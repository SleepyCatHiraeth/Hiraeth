package assistant

import (
	"bufio"
	"context"
	"encoding/json"
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

// turn is one voice interaction. It owns every child process it starts and
// guarantees two things on exit, however it exits: the microphone is closed and
// no child survives.
type turn struct {
	svc    *Service
	ctx    context.Context
	cancel context.CancelFunc

	mu       sync.Mutex
	rec      *exec.Cmd
	wavPath  string
	stopOnce sync.Once
	recDone  chan struct{}
}

func (s *Service) startTurn() error {
	venv := filepath.Join(s.cfg.StackDir, ".venv", "bin", "python")
	if _, err := os.Stat(venv); err != nil {
		return fmt.Errorf("%w: %s missing", errNoStack, venv)
	}
	if err := checkEndpoint(s.cfg.Endpoint); err != nil {
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

	ctx, cancel := context.WithCancel(context.Background())
	t := &turn{
		svc:     s,
		ctx:     ctx,
		cancel:  cancel,
		wavPath: filepath.Join(dir, fmt.Sprintf("turn-%d.wav", time.Now().UnixNano())),
		recDone: make(chan struct{}),
	}

	// 16 kHz mono is what Whisper wants; recording anything richer just costs
	// disk and resampling.
	args := []string{"--channels=1", "--rate=16000", "--format=s16"}
	if target := pickCaptureTarget(ctx, s.cfg.CaptureTarget); target != "" {
		args = append(args, "--target="+target)
	}
	args = append(args, t.wavPath)
	rec := exec.CommandContext(ctx, "pw-record", args...)
	rec.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := rec.Start(); err != nil {
		cancel()
		return fmt.Errorf("microphone: %w", err)
	}
	t.rec = rec

	s.mu.Lock()
	s.turn = t
	s.transcript = ""
	s.response = ""
	s.lastErr = ""
	s.mu.Unlock()
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
	select {
	case <-t.recDone:
	case <-t.ctx.Done():
		t.endCapture()
		t.finish(StateCancelled, nil)
		return
	case <-time.After(60 * time.Second):
		t.endCapture()
	}

	_ = t.rec.Wait() // reap; a non-zero code here is expected after SIGINT

	if t.aborted() {
		t.finish(StateCancelled, nil)
		return
	}
	if fi, err := os.Stat(t.wavPath); err != nil || fi.Size() < 4096 {
		t.finish(StateError, func() { s.lastErr = "no audio captured" })
		return
	}

	s.setState(StateTranscribing, nil)
	text, err := t.transcribe()
	if t.aborted() {
		t.finish(StateCancelled, nil)
		return
	}
	if err != nil {
		t.finish(StateError, func() { s.lastErr = "speech recognition: " + err.Error() })
		return
	}
	if strings.TrimSpace(text) == "" {
		t.finish(StateIdle, func() { s.lastErr = "nothing heard" })
		return
	}
	s.setState(StateThinking, func() { s.transcript = text })

	if err := t.answer(text); err != nil {
		if t.aborted() {
			t.finish(StateCancelled, nil)
			return
		}
		t.finish(StateError, func() { s.lastErr = err.Error() })
		return
	}
	t.finish(StateIdle, nil)
}

func (t *turn) transcribe() (string, error) {
	cfg := t.svc.cfg
	cmd := exec.CommandContext(t.ctx,
		filepath.Join(cfg.StackDir, ".venv", "bin", "python"),
		filepath.Join(cfg.StackDir, "stt.py"),
		t.wavPath,
		"--model", cfg.STTModel,
		"--threads", fmt.Sprint(cfg.STTThreads),
	)
	cmd.Dir = cfg.StackDir
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Env = append(os.Environ(),
		"HF_HOME="+filepath.Join(cfg.StackDir, "models", "hf"),
		"HF_HUB_OFFLINE=1",
	)
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

// answer streams the model's reply and speaks it sentence by sentence, so
// playback begins while the rest is still being generated.
func (t *turn) answer(prompt string) error {
	s := t.svc

	speaker, err := t.startSpeaker()
	if err != nil {
		return fmt.Errorf("speech output: %w", err)
	}
	defer speaker.close()

	spoke := false
	var full strings.Builder

	err = streamChat(t.ctx, s.cfg, prompt, func(sentence string) {
		if !spoke {
			spoke = true
			s.setState(StateSpeaking, nil)
		}
		full.WriteString(sentence)
		full.WriteString(" ")
		s.mu.Lock()
		s.response = strings.TrimSpace(full.String())
		s.seq++
		s.mu.Unlock()
		s.broadcast()
		speaker.say(sentence)
	})
	if err != nil {
		return err
	}
	speaker.finish()
	return nil
}

// speaker pipes sentences into Piper and Piper's PCM into PipeWire. Both live in
// one process group so an interrupt kills synthesis and playback together
// instead of leaving a sentence to finish playing after the user said stop.
type speaker struct {
	tts  *exec.Cmd
	play *exec.Cmd
	in   io.WriteCloser
	once sync.Once
}

func (t *turn) startSpeaker() (*speaker, error) {
	cfg := t.svc.cfg
	ttsArgs := []string{
		filepath.Join(cfg.StackDir, "tts.py"),
		"--engine", cfg.TTSEngine,
		"--model", t.svc.voiceModelPath(),
	}
	if cfg.TTSEngine == "kokoro" {
		ttsArgs = append(ttsArgs,
			"--voices-bin", filepath.Join(cfg.StackDir, "models", "kokoro", "voices-v1.0.bin"),
			"--voice", cfg.TTSVoice,
			"--speed", strconv.FormatFloat(cfg.Speed, 'f', 2, 64),
		)
	}
	tts := exec.CommandContext(t.ctx,
		filepath.Join(cfg.StackDir, ".venv", "bin", "python"),
		ttsArgs...,
	)
	tts.Dir = cfg.StackDir
	tts.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

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
		_ = tts.Process.Kill()
		return nil, err
	}
	return &speaker{tts: tts, play: play, in: in}, nil
}

func (s *speaker) say(sentence string) {
	_, _ = io.WriteString(s.in, strings.ReplaceAll(sentence, "\n", " ")+"\n")
}

func (s *speaker) finish() {
	s.once.Do(func() { _ = s.in.Close() })
	_ = s.tts.Wait()
	_ = s.play.Wait()
}

func (s *speaker) close() {
	s.once.Do(func() { _ = s.in.Close() })
	for _, c := range []*exec.Cmd{s.tts, s.play} {
		if c != nil && c.Process != nil {
			_ = syscall.Kill(-c.Process.Pid, syscall.SIGKILL)
		}
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
