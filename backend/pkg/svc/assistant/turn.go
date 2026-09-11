package assistant

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

var exeLookPath = exec.LookPath

// turnBudget caps one whole interaction: listening, transcription, generation
// and speech. Generous, because a long answer spoken slowly is legitimate; it
// exists to end a turn that is never going to finish, not to hurry a real one.
const turnBudget = 5 * time.Minute

// turn is one voice interaction. It owns every child process it starts and
// guarantees two things on exit, however it exits: the microphone is closed and
// no child survives.
type turn struct {
	svc    *Service
	ctx    context.Context
	cancel context.CancelFunc

	// A snapshot taken under the service lock when the turn is claimed.
	//
	// The pipeline read s.cfg directly at four points, unsynchronised, while
	// another IPC connection could be writing it. That is a data race in the
	// strict sense, and a behavioural one too: a settings change landing
	// mid-turn could transcribe with one stack directory and synthesise with
	// another. A turn now runs entirely on the settings it started with.
	cfg Config

	mu       sync.Mutex
	rec      *exec.Cmd
	wavPath  string
	stopOnce sync.Once
	recDone  chan struct{}
}

func (s *Service) startTurn() error {
	// One snapshot for the whole of startup, and the same one the turn keeps.
	// Reading s.cfg field by field, unlocked, raced every settings change.
	s.mu.Lock()
	cfg := s.cfg
	s.mu.Unlock()

	venv := filepath.Join(cfg.StackDir, ".venv", "bin", "python")
	if _, err := os.Stat(venv); err != nil {
		return fmt.Errorf("%w: %s missing", errNoStack, venv)
	}
	if err := checkEndpoint(cfg.Endpoint); err != nil {
		return err
	}

	runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
	if runtimeDir == "" {
		runtimeDir = os.TempDir()
	}
	dir := filepath.Join(runtimeDir, "ambxst", "assistant")
	// 0700: captured speech is as private as it gets, and it lives on tmpfs.
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}

	// C9: every stage had its own timeout and the turn as a whole had none, so
	// a wedged synthesiser or a model that never finished left the assistant
	// occupied indefinitely with no way back except a keypress.
	ctx, cancel := context.WithTimeout(context.Background(), turnBudget)
	t := &turn{
		svc:     s,
		ctx:     ctx,
		cancel:  cancel,
		wavPath: filepath.Join(dir, fmt.Sprintf("turn-%d.wav", time.Now().UnixNano())),
		recDone: make(chan struct{}),
	}

	// 16 kHz mono is what Whisper wants; recording anything richer just costs
	// disk and resampling. Device selection runs a subprocess, so it happens
	// before the slot is claimed and while no lock is held.
	args := []string{"--channels=1", "--rate=16000", "--format=s16"}
	if target := pickCaptureTarget(ctx, cfg.CaptureTarget); target != "" {
		args = append(args, "--target="+target)
	}
	args = append(args, t.wavPath)

	// Claim the single-operation slot before starting anything.
	//
	// Two defects here. `toggle` read `s.turn` and then called this, so two
	// presses close together could both pass the check and start two
	// recorders. And nothing checked `speaking` at all, so pressing the key
	// during a voice test opened a second synthesiser on the same sink.
	s.mu.Lock()
	if s.turn != nil || s.speaking {
		s.mu.Unlock()
		cancel()
		return fmt.Errorf("busy")
	}
	// Re-check the master switch at the moment of claiming, not only at the
	// start of preflight. Capture-target discovery runs a subprocess, so a
	// disable can complete inside that window -- releasing resources and
	// stopping the model server -- after which this turn would have started the
	// microphone and had ensureServer bring the server straight back up, with
	// the UI still showing "off".
	if !s.cfg.Enabled {
		s.mu.Unlock()
		cancel()
		return fmt.Errorf("the turret assistant is off; turn it on in Settings")
	}
	t.cfg = cfg
	s.turn = t
	s.transcript = ""
	s.response = ""
	s.lastErr = ""
	s.lastErrKind = ""
	s.mu.Unlock()

	rec := exec.CommandContext(ctx, "pw-record", args...)
	rec.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := rec.Start(); err != nil {
		// Release the slot: a turn that never started must not leave the
		// assistant permanently busy.
		s.mu.Lock()
		if s.turn == t {
			s.turn = nil
		}
		s.mu.Unlock()
		cancel()
		return fmt.Errorf("microphone: %w", err)
	}
	t.mu.Lock()
	t.rec = rec
	t.mu.Unlock()

	s.setState(StateListening, nil)

	go t.run()
	return nil
}

// endCapture stops recording and lets run() proceed to transcription.
func (t *turn) endCapture() {
	t.stopOnce.Do(func() {
		t.mu.Lock()
		rec := t.rec
		t.mu.Unlock()
		if rec != nil && rec.Process != nil {
			// SIGINT so pw-record finalises the WAV header. A SIGKILL here
			// leaves a truncated file that Whisper cannot read.
			_ = syscall.Kill(-rec.Process.Pid, syscall.SIGINT)
		}
		close(t.recDone)
	})
}

// abort tears the whole turn down now. Safe to call from any state, any number
// of times.
func (t *turn) abort() {
	t.endCapture()
	t.cancel()
}

func (t *turn) finish(state string, mutate func()) {
	t.cancel()
	_ = os.Remove(t.wavPath) // audio is never retained by default
	t.svc.mu.Lock()
	if t.svc.turn == t {
		t.svc.turn = nil
	}
	t.svc.mu.Unlock()
	t.svc.setState(state, mutate)
}

// failWith ends the turn in an error state carrying the kind of failure.
func (t *turn) failWith(kind, msg string) {
	logEvent("turn failed (%s)", kind)
	t.finish(StateError, func() {
		t.svc.lastErr = msg
		t.svc.lastErrKind = kind
	})
}

// expired ends a turn whose context is done. A user cancellation and a blown
// budget both land here, and they are reported differently: one is a decision,
// the other is a fault.
func (t *turn) expired() {
	if errors.Is(t.ctx.Err(), context.DeadlineExceeded) {
		t.failWith(ErrTimeout, "the turn ran past its time budget and was ended")
		return
	}
	t.finish(StateCancelled, nil)
}

func (t *turn) aborted() bool {
	select {
	case <-t.ctx.Done():
		return true
	default:
		return false
	}
}

func (t *turn) run() {
	s := t.svc

	// Wait for the user to end the utterance, or for a hard cap that stops the
	// microphone even if the second keypress never arrives.
	// Timer rather than time.After: the discarded timer stayed armed for the
	// full minute after a normal turn ended, holding the turn and its closure
	// live in the runtime heap once per interaction.
	cap := time.NewTimer(60 * time.Second)
	select {
	case <-t.recDone:
		cap.Stop()
	case <-t.ctx.Done():
		cap.Stop()
		t.endCapture()
		t.expired()
		return
	case <-cap.C:
		t.endCapture()
	}

	// Reap. A non-zero code is expected after SIGINT, but a failure to even
	// start recording is not, and used to be invisible.
	if werr := t.rec.Wait(); werr != nil {
		logEventEvery("rec-exit", time.Minute, "recorder exited: %v", werr)
	}

	if t.aborted() {
		t.expired()
		return
	}
	if fi, err := os.Stat(t.wavPath); err != nil || fi.Size() < 4096 {
		t.failWith(ErrMicrophone, "no audio was captured; check the input device in Settings")
		return
	}

	s.setState(StateTranscribing, nil)
	text, err := t.transcribe()
	if t.aborted() {
		t.expired()
		return
	}
	if err != nil {
		t.failWith(ErrSTT, "speech recognition: "+err.Error())
		return
	}
	if strings.TrimSpace(text) == "" {
		t.finish(StateIdle, func() { s.lastErr = "nothing heard" })
		return
	}
	s.setState(StateThinking, func() { s.transcript = text })

	// A stopped model server is the most likely reason a turn fails, and it is
	// repairable. Try once, and if it stays down say so plainly instead of
	// producing a generic provider error.
	if !s.ensureServer(t.ctx) {
		_, why := s.healthSnapshot()
		if why == "" {
			why = "the local model server is not running"
		}
		t.failWith(ErrProvider, "model server unreachable: "+why+" (try: lms server start)")
		return
	}

	// Retrieval is best-effort and never blocks the answer. An empty string
	// means the model simply gets no stored context this turn.
	recallStart := time.Now()
	memCtx, _ := s.recall(t.ctx, t.cfg, text)
	logWorker("recall", time.Since(recallStart), nil, "")

	if err := t.answer(text, memCtx); err != nil {
		if t.aborted() {
			t.expired()
			return
		}
		t.failWith(classifyError(err), err.Error())
		return
	}
	t.finish(StateIdle, nil)

	// Capture runs after the turn is finished and the user has their answer, so
	// extraction latency is never on the critical path of a conversation.
	s.mu.Lock()
	reply := s.response
	s.mu.Unlock()
	// Only while still enabled. `finish` publishes idle before this runs, so a
	// disable landing in that window would call convo.forget and then have this
	// exchange appended behind it -- re-enabling would expose conversation that
	// "off" promised to discard.
	//
	// The check and the append happen under the service lock together. Reading
	// `enabled`, releasing, then recording left the same window open, just
	// narrower.
	s.mu.Lock()
	enabled := s.cfg.Enabled
	if reply != "" && enabled {
		// In memory only, and only for a complete exchange: an interrupted
		// half-answer is not something to refer back to.
		s.convo.record(text, reply)
	}
	s.mu.Unlock()

	if reply != "" && enabled {
		// Registered on this stack, not inside the goroutine: a disable landing
		// between the two would otherwise see nothing to wait for.
		s.goBackground(90*time.Second, func(context.Context) { s.capture(t.cfg, text, reply) })
	}
}

func (t *turn) transcribe() (string, error) {
	// Warm worker first: it saves the ~0.7s model load that dominated cold
	// start. A one-shot run is kept as the fallback, because a transcriber that
	// will not stay up must not mean an assistant that cannot hear.
	started := time.Now()
	text, err := t.svc.transcribeWarm(t.ctx, t.cfg, t.wavPath)
	if err == nil {
		logWorker("stt", time.Since(started), nil, "")
		return strings.TrimSpace(text), nil
	}
	if t.aborted() {
		return "", err
	}
	logEventEvery("stt-warm", time.Minute, "warm transcriber unavailable (%v), falling back", err)

	cfg := t.cfg
	cmd := exec.CommandContext(t.ctx,
		filepath.Join(cfg.StackDir, ".venv", "bin", "python"),
		filepath.Join(cfg.StackDir, "stt.py"),
		t.wavPath,
		"--model", cfg.STTModel,
		"--threads", fmt.Sprint(cfg.STTThreads),
		"--vocab", cfg.STTVocab,
	)
	cmd.Dir = cfg.StackDir
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Env = append(os.Environ(),
		"HF_HOME="+filepath.Join(cfg.StackDir, "models", "hf"),
		"HF_HUB_OFFLINE=1",
	)
	// Capture stderr: a Python traceback used to be discarded entirely, so an
	// STT failure surfaced as an empty transcript with no explanation anywhere.
	errBuf := newCapped(4096)
	cmd.Stderr = errBuf
	started = time.Now()
	out, err := cmd.Output()
	logWorker("stt-oneshot", time.Since(started), err, errBuf.String())
	if err != nil {
		return "", fmt.Errorf("speech recognition failed: %w", err)
	}
	return strings.TrimSpace(string(out)), nil
}

// answer streams the model's reply and speaks it sentence by sentence, so
// playback begins while the rest is still being generated.
func (t *turn) answer(prompt, memCtx string) error {
	s := t.svc

	speaker, err := t.startSpeaker()
	if err != nil {
		return fmt.Errorf("speech output: %w", err)
	}
	defer speaker.close()

	spoke := false
	var sayErr error
	var full strings.Builder
	// Time to first audio is the number the user actually feels. It was not
	// recorded anywhere, so the live test had to be reconstructed from state
	// transitions.
	answerStart := time.Now()

	err = streamChat(t.ctx, t.cfg, prompt, memCtx, s.convo.messages(), func(sentence string) {
		if !spoke {
			spoke = true
			logWorker("llm-first-speech", time.Since(answerStart), nil, "")
			s.setState(StateSpeaking, nil)
		}
		full.WriteString(sentence)
		full.WriteString(" ")
		s.mu.Lock()
		s.response = strings.TrimSpace(full.String())
		s.seq++
		s.mu.Unlock()
		s.broadcast()
		if sayErr == nil {
			sayErr = speaker.say(sentence)
		}
	})
	if err != nil {
		return err
	}
	if sayErr != nil {
		return sayErr
	}
	speaker.finish()
	// A synthesiser or playback process that died mid-answer means the user
	// heard part of a reply, or none of it. Reporting that turn as a success
	// let the exchange into conversation history and into memory extraction as
	// though it had been spoken.
	if err := speaker.err(); err != nil {
		return err
	}
	return nil
}

// speaker pipes sentences into the TTS engine and its PCM into PipeWire.
//
// Each child gets its OWN process group (both set Setpgid), and close() signals
// both groups, so an interrupt takes synthesis and playback down together
// rather than leaving a sentence playing after the user said stop. An earlier
// comment here claimed they shared one group; they never did.
type speaker struct {
	tts  *exec.Cmd
	play *exec.Cmd
	in   io.WriteCloser
	once sync.Once

	// reaped is set once Wait() has returned for both children. After that
	// their PIDs belong to the kernel again, and signalling them could hit an
	// unrelated process group that happened to inherit the number.
	mu      sync.Mutex
	reaped  bool
	exitErr error
	stderr  *capped
}

// diagnostic returns the synthesiser's last words, for logging only. Never user
// content: tts.py writes progress and errors here, not text.
func (s *speaker) diagnostic() string {
	if s.stderr == nil {
		return ""
	}
	return s.stderr.String()
}

func (t *turn) startSpeaker() (*speaker, error) {
	cfg := t.cfg
	ttsArgs := []string{
		filepath.Join(cfg.StackDir, "tts.py"),
		"--engine", cfg.TTSEngine,
		"--model", voiceModelPath(cfg),
	}
	if cfg.TTSEngine == "kokoro" {
		ttsArgs = append(ttsArgs,
			"--voices-bin", filepath.Join(cfg.StackDir, "models", "kokoro", "voices-v1.0.bin"),
			"--voice", cfg.TTSVoice,
			"--speed", strconv.FormatFloat(cfg.Speed, 'f', 2, 64),
		)
	} else if cfg.Speed > 0 && cfg.Speed != 1.0 {
		// Piper measures duration, not rate, so the setting inverts: 1.25x speed
		// is a length scale of 0.8. Passing --speed here did nothing at all, so
		// the speed slider silently had no effect on the fallback engine.
		ttsArgs = append(ttsArgs,
			"--length-scale", strconv.FormatFloat(1.0/cfg.Speed, 'f', 3, 64))
	}
	tts := exec.CommandContext(t.ctx,
		filepath.Join(cfg.StackDir, ".venv", "bin", "python"),
		ttsArgs...,
	)
	tts.Dir = cfg.StackDir
	tts.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	// The synthesiser's stderr was discarded, so "no sound" and "the model file
	// is missing" looked identical from the outside.
	ttsErr := newCapped(4096)
	tts.Stderr = ttsErr

	in, err := tts.StdinPipe()
	if err != nil {
		return nil, err
	}
	pcm, err := tts.StdoutPipe()
	if err != nil {
		return nil, err
	}

	// --raw is required: without it pw-play tries to parse a container header
	// and rejects the stream outright.
	// Rate follows the engine: Kokoro emits 24 kHz, Piper 22.05 kHz. A mismatch
	// here does not error, it just plays back at the wrong pitch.
	playArgs := []string{"--raw", "--format=s16",
		"--rate=" + sampleRateFor(cfg.TTSEngine), "--channels=1",
		"--volume=" + cfg.Volume}
	if cfg.PlaybackTarget != "" {
		playArgs = append(playArgs, "--target="+cfg.PlaybackTarget)
	}
	playArgs = append(playArgs, "-")
	play := exec.CommandContext(t.ctx, "pw-play", playArgs...)
	play.Stdin = pcm
	play.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	if err := tts.Start(); err != nil {
		return nil, err
	}
	if err := play.Start(); err != nil {
		_ = in.Close()
		_ = syscall.Kill(-tts.Process.Pid, syscall.SIGKILL)
		go func() { _ = tts.Wait() }() // reap, or it lingers as a zombie
		return nil, fmt.Errorf("audio playback: %w", err)
	}
	return &speaker{tts: tts, play: play, in: in, stderr: ttsErr}, nil
}

// say queues one sentence. A write failure means the synthesiser has gone --
// the pipe is closed or the process died -- and it used to be discarded, so a
// turn in which nothing was ever spoken finished as a success, recorded the
// exchange and extracted memories from it.
func (s *speaker) say(sentence string) error {
	if _, err := io.WriteString(s.in, strings.ReplaceAll(sentence, "\n", " ")+"\n"); err != nil {
		return fmt.Errorf("speech output stopped accepting text: %w", err)
	}
	return nil
}

// err reports a child that exited badly, for the caller to surface. Populated
// by finish; nil until then.
func (s *speaker) err() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.exitErr
}

func (s *speaker) finish() {
	s.once.Do(func() { _ = s.in.Close() })
	ttsErr := s.tts.Wait()
	if ttsErr != nil {
		logWorker("tts", 0, ttsErr, s.diagnostic())
	}
	playErr := s.play.Wait()
	if playErr != nil {
		logWorker("playback", 0, playErr, "")
	}
	s.mu.Lock()
	switch {
	case ttsErr != nil:
		s.exitErr = fmt.Errorf("speech synthesis failed: %w", ttsErr)
	case playErr != nil:
		s.exitErr = fmt.Errorf("audio playback failed: %w", playErr)
	}
	s.mu.Unlock()
	s.mu.Lock()
	s.reaped = true
	s.mu.Unlock()
}

func (s *speaker) close() {
	s.once.Do(func() { _ = s.in.Close() })
	s.mu.Lock()
	done := s.reaped
	s.reaped = true
	s.mu.Unlock()
	if done {
		return // already waited for; their PIDs are no longer ours to signal
	}
	for _, c := range []*exec.Cmd{s.tts, s.play} {
		if c == nil || c.Process == nil {
			continue
		}
		_ = syscall.Kill(-c.Process.Pid, syscall.SIGKILL)
		// Reap. Killing without waiting left one zombie Python and one zombie
		// pw-play behind every cancelled turn, accumulating until the daemon
		// exited. On its own goroutine because a kill signal is not instant and
		// this is on the cancellation path, which must stay immediate.
		cmd := c
		go func() { _ = cmd.Wait() }()
	}
}

// scanJSONLines is a small helper so the LLM client can read SSE without
// pulling in a dependency.
func newLineScanner(r io.Reader) *bufio.Scanner {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	return sc
}

var _ = json.Marshal
