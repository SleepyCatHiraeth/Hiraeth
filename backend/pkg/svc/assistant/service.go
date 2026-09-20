// Package assistant implements the turret voice assistant's backend service.
//
// The design rule that shapes everything here: the language model proposes,
// this package disposes. The process boundaries, argv-only execution and
// loopback-only networking were established before any tool existed, because
// retrofitting them afterwards is how the old `run_shell_command` path in
// modules/services/Ai.qml came to execute model output through `bash -c`.
//
// There is a tool loop now (tool_loop.go), bounded to three rounds, and tools
// that would require approval are withheld because no consent-token path
// exists yet. The QML side no longer has a shell tool either: it proposes
// against a fixed argv allow-list in modules/services/ai/ToolCatalog.js.
package assistant

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"ambxst/backend/pkg/ipc"
	"ambxst/backend/pkg/svc/assistant/memory"
)

// State names mirror the documented assistant state machine. Stage 1 reaches
// only this subset; the rest arrive with the memory and tool stages.
const (
	StateIdle         = "idle"
	StateListening    = "listening"
	StateTranscribing = "transcribing"
	StateThinking     = "thinking"
	StateSpeaking     = "speaking"
	StateStarting     = "starting"
	StateCancelled    = "cancelled"
	StateError        = "error"
)

// Error kinds accompany StateError. One state with a kind, rather than six
// error states: the UI shows an error the same way whatever failed, and the
// only thing it needs to vary is what it tells the user to check. Adding six
// states would have meant six entries in every style map for no visible gain.
const (
	ErrMicrophone = "microphone" // capture device missing, busy, or silent
	ErrSTT        = "stt"        // transcription worker failed
	ErrTTS        = "tts"        // synthesis worker failed to start or died
	ErrAudio      = "audio"      // playback failed
	ErrMemory     = "memory"     // store or embedding failed
	ErrProvider   = "provider"   // model server unreachable, refused, or truncated
	ErrTimeout    = "timeout"    // the turn ran past its budget
	ErrConfig     = "config"     // the stack or endpoint is not usable
)

// Config carries the resolved locations of the local stack. Nothing here is a
// network address except Endpoint, which is validated as loopback before use.
type Config struct {
	// Master switch. Off by default and off after a reboot: with this false
	// nothing polls, no database is opened, no process is started, and a turn
	// is refused. The assistant costs exactly nothing until it is turned on.
	Enabled bool `json:"enabled"`

	StackDir  string  `json:"stack_dir"`
	Endpoint  string  `json:"endpoint"`
	Model     string  `json:"model"`
	Voice     string  `json:"voice"`
	TTSEngine string  `json:"tts_engine"`
	TTSVoice  string  `json:"tts_voice"`
	Speed     float64 `json:"speed"`
	STTModel  string  `json:"stt_model"`
	// Domain words Whisper should expect. Without this it guesses unfamiliar
	// proper nouns phonetically: "Hiraeth" came back as "Marcos" and "Hiraiz"
	// on separate real attempts. Measured fix, no latency cost.
	STTVocab   string `json:"stt_vocab"`
	STTThreads int    `json:"stt_threads"`
	MaxTokens  int    `json:"max_tokens"`
	Volume     string `json:"volume"`
	// Empty means "auto-detect"; see pickCaptureTarget for why the PipeWire
	// default is not trusted.
	CaptureTarget string `json:"capture_target"`

	// Memory is opt-in: at defaults the assistant writes nothing durable.
	MemoryEnabled       bool            `json:"memory_enabled"`
	MemoryCategories    map[string]bool `json:"memory_categories"`
	MemoryLimit         int             `json:"memory_limit"`
	MemoryMinConfidence float64         `json:"memory_min_confidence"`
	EmbedModel          string          `json:"embed_model"`
	// Empty means "use the PipeWire default sink". Unlike capture, no guess is
	// made here: which output the user can actually hear is not inferable, and
	// guessing wrong sends speech to a device they are not listening to.
	PlaybackTarget string `json:"playback_target"`

	// Web access for the research tools. Off at defaults, and it is the one
	// setting that changes what leaves this machine: with it on, a search
	// query and the pages chosen from the results are fetched from the public
	// internet. The MODEL endpoint stays loopback either way -- httpclient.go
	// enforces that and is unaffected by this flag.
	WebEnabled bool `json:"web_enabled"`
}

func defaultConfig() Config {
	home, _ := os.UserHomeDir()
	stack := filepath.Join(home, "Project", "Tools", "turret-stack")
	return Config{
		Enabled:  false,
		StackDir: stack,
		// Loopback only. checkEndpoint refuses anything else, so a config edit
		// cannot quietly turn this into a cloud assistant.
		Endpoint: "http://127.0.0.1:1234/v1",
		Model:    "qwen3-4b-instruct-2507",
		// Chosen by the user on 2026-09-10 after listening to eight candidates.
		// am_onyx is the other pick and is one setting away.
		TTSEngine:  "kokoro",
		TTSVoice:   "af_heart",
		Speed:      1.0,
		Voice:      filepath.Join(stack, "models", "piper", "en_US-lessac-medium.onnx"),
		STTModel:   "small.en",
		STTVocab:   "Hiraeth,AMBXST,Hyprland,Quickshell,CachyOS,turret,notch,SideNotch,Kokoro,Piper",
		STTThreads: 8,
		MaxTokens:  300,
		Volume:     "0.6",

		MemoryEnabled:       false,
		MemoryLimit:         6,
		MemoryMinConfidence: 0.5,
		EmbedModel:          "text-embedding-nomic-embed-text-v1.5",
	}
}

// Service owns the assistant's state and the single in-flight turn.
type Service struct {
	cfg Config

	mu          sync.Mutex
	state       string
	transcript  string
	response    string
	lastErr     string
	lastErrKind string
	seq         uint64
	turn        *turn // non-nil while a turn is active

	// Recent exchanges, in memory only and never written to disk. See
	// history.go for why it expires.
	convo conversation

	// Warm transcriber, kept between turns. See stt.go.
	stt sttWorker

	// When the expiry sweep last ran. Guarded by mu.
	lastSweep time.Time

	// Serialises release(); see shutdown.go.
	releaseMu sync.Mutex

	mem             *memory.Store
	pendingMemories int
	speaking        bool
	bg              background
	closeOnce       sync.Once
	health          health
	embedErr        string

	// buffered so a wake never blocks the setter; see startHealthLoop.
	healthWake chan struct{}
	// closed once, by Close, to end the health loop. Without it the loop could
	// park on healthWake forever and outlive the service that owns it.
	stopHealth chan struct{}
	// closed by the loop itself when it leaves, so Close can wait for it rather
	// than merely signal it. Signalling and returning let a probe still be in
	// flight, mutating health state after shutdown had begun.
	healthDone chan struct{}

	subsMu sync.Mutex
	subs   []*ipc.Subscriber
}

func NewService() *Service {
	cfg, err := loadConfig()
	s := &Service{
		cfg:        cfg,
		state:      StateIdle,
		healthWake: make(chan struct{}, 1),
		stopHealth: make(chan struct{}),
	}
	if err != nil {
		// Surfaced rather than swallowed: the user gets defaults this session
		// and their file is left untouched for inspection.
		s.lastErr = "assistant config unreadable, using defaults: " + err.Error()
	}
	return s
}

func (s *Service) Register(srv *ipc.Server) {
	srv.Register(&ipc.Service{
		Name: "assistant",
		Methods: map[string]ipc.HandlerFunc{
			"toggle":  s.toggle,
			"ask":     s.ask,
			"release": s.keyReleased,
			"cancel":  s.cancel,
			"state":   s.stateMethod,
			"check":   s.check,
			"config":  s.getConfig,
			"set":     s.setConfig,
			"voices":  s.listVoices,
			"say":     s.say,
			"health":  s.healthMethod,

			"memory.list":    s.memoryList,
			"memory.pending": s.memoryPending,
			"memory.confirm": s.memoryConfirm,
			"memory.correct": s.memoryCorrect,
			"memory.forget":  s.memoryForget,
			"memory.stats":   s.memoryStats,
			"memory.audit":   s.memoryAudit,
			"memory.compact": s.memoryCompact,

			"draft.email": s.draftEmail,

			"tools.list":    s.toolsList,
			"tools.invoke":  s.toolsInvoke,
			"memory.export": s.memoryExport,
			"memory.import": s.memoryImport,
		},
		Subscribe: s.subscribe,
	})
	s.startHealthLoop()
}

func (s *Service) subscribe(sub *ipc.Subscriber) {
	s.subsMu.Lock()
	s.subs = append(s.subs, sub)
	s.subsMu.Unlock()

	sub.Send("assistant.state", s.snapshot())

	go func() {
		<-sub.StopCh()
		s.subsMu.Lock()
		defer s.subsMu.Unlock()
		for i, x := range s.subs {
			if x == sub {
				s.subs = append(s.subs[:i], s.subs[i+1:]...)
				return
			}
		}
	}()
}

// snapshot is the whole observable state in one object. Subscription events can
// be dropped when a subscriber's queue is full (see pkg/ipc/server.go's Push),
// so every event carries the complete state and a sequence number rather than a
// delta -- a client that misses one is still correct after the next.
func (s *Service) snapshot() map[string]any {
	s.mu.Lock()
	defer s.mu.Unlock()
	return map[string]any{
		"state":            s.state,
		"transcript":       s.transcript,
		"response":         s.response,
		"error":            s.lastErr,
		"error_kind":       s.lastErrKind,
		"seq":              s.seq,
		"enabled":          s.cfg.Enabled,
		"memory_enabled":   s.cfg.MemoryEnabled,
		"web_enabled":      s.cfg.WebEnabled,
		"pending_memories": s.pendingMemories,
		"llm_reachable":    s.healthReachableLocked(),
		"llm_error":        s.healthErrLocked(),
		"embed_error":      s.embedErr,
	}
}

// These read health under its own lock, never the service lock, so snapshot()
// cannot deadlock against a concurrent probe.
func (s *Service) healthReachableLocked() bool {
	s.health.mu.Lock()
	defer s.health.mu.Unlock()
	return s.health.reachable
}

func (s *Service) healthErrLocked() string {
	s.health.mu.Lock()
	defer s.health.mu.Unlock()
	return s.health.lastErr
}

func (s *Service) setState(state string, mutate func()) {
	s.mu.Lock()
	from := s.state
	s.state = state
	s.seq++
	if state != StateError {
		s.lastErrKind = ""
	}
	if mutate != nil {
		mutate()
	}
	s.mu.Unlock()
	logState(from, state, state == StateListening)
	s.broadcast()
}

func (s *Service) broadcast() {
	snap := s.snapshot()
	s.subsMu.Lock()
	subs := append([]*ipc.Subscriber(nil), s.subs...)
	s.subsMu.Unlock()
	for _, sub := range subs {
		sub.Send("assistant.state", snap)
	}
}

// toggle is the single entry point the keybind drives. Press once to listen,
// press again to stop listening and answer; press during an answer to interrupt.
// ask runs a turn from typed text instead of the microphone.
//
// `speak` defaults to false: the panel's chat is read, not heard, and a reply
// spoken aloud for every typed message would be the wrong default in a room
// with other people in it. Callers that want the voice pass it explicitly.
func (s *Service) ask(params json.RawMessage) (any, error) {
	var p struct {
		Text  string `json:"text"`
		Speak bool   `json:"speak"`
	}
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, err
	}
	if err := s.startTextTurn(p.Text, p.Speak); err != nil {
		return nil, err
	}
	// The reply itself arrives over the state broadcast as it streams, the
	// same way a spoken turn's does. Nothing is returned here but the
	// acknowledgement that a turn was claimed.
	return map[string]any{"accepted": true}, nil
}

func (s *Service) toggle(_ json.RawMessage) (any, error) {
	s.mu.Lock()
	active := s.turn
	state := s.state
	enabled := s.cfg.Enabled
	s.mu.Unlock()

	if !enabled && active == nil {
		return nil, fmt.Errorf("the turret assistant is off; turn it on in Settings")
	}

	switch {
	case active != nil && state == StateListening:
		active.endCapture()
		return map[string]any{"action": "stopped_listening"}, nil
	case active != nil:
		// Speaking or thinking: a second press is an interrupt, never a queue.
		active.abort()
		return map[string]any{"action": "interrupted"}, nil
	default:
		if err := s.startTurn(); err != nil {
			s.fail(err)
			return nil, err
		}
		return map[string]any{"action": "listening"}, nil
	}
}

// release is the key-up half of push-to-talk.
//
// Hold to talk, release to send. A quick tap instead latches: releasing within
// the threshold leaves the microphone open so the key behaves as a toggle, and
// a second press ends it. Without that, a tap would open and immediately close
// the microphone and the turn would die with "no audio was captured" -- which
// is what a pure press-and-hold binding does to anyone who taps the key out of
// habit. Both gestures reach the same state machine.
const pushToTalkLatch = 400 * time.Millisecond

func (s *Service) keyReleased(_ json.RawMessage) (any, error) {
	s.mu.Lock()
	active := s.turn
	state := s.state
	s.mu.Unlock()

	if active == nil || state != StateListening {
		// Nothing is listening: the release belongs to a press that started
		// something else, or to an interrupt. Not an error.
		return map[string]any{"action": "ignored"}, nil
	}
	if time.Since(active.startedAt) < pushToTalkLatch {
		return map[string]any{"action": "latched"}, nil
	}
	active.endCapture()
	return map[string]any{"action": "stopped_listening"}, nil
}

func (s *Service) cancel(_ json.RawMessage) (any, error) {
	s.mu.Lock()
	active := s.turn
	s.mu.Unlock()
	if active != nil {
		active.abort()
	}
	return map[string]any{"cancelled": active != nil}, nil
}

func (s *Service) stateMethod(_ json.RawMessage) (any, error) {
	return s.snapshot(), nil
}

// fail records an error state with the kind of failure it was, so the UI can
// say "check your microphone" rather than "something went wrong".
func (s *Service) failKind(kind, msg string) {
	s.setState(StateError, func() {
		s.lastErr = msg
		s.lastErrKind = kind
	})
}

func (s *Service) fail(err error) {
	s.failKind(classifyError(err), err.Error())
}

// classifyError maps the errors startTurn can return onto a kind.
func classifyError(err error) string {
	switch {
	case err == nil:
		return ""
	case errors.Is(err, errNoStack):
		return ErrConfig
	case errors.Is(err, context.DeadlineExceeded):
		return ErrTimeout
	}
	var local *LocalOnlyError
	if errors.As(err, &local) {
		return ErrConfig
	}
	if strings.Contains(err.Error(), "microphone") {
		return ErrMicrophone
	}
	return ErrProvider
}

// check reports whether every local dependency is actually present, so the UI
// can explain a missing piece instead of failing mid-turn. It deliberately does
// not start anything.
func (s *Service) check(_ json.RawMessage) (any, error) {
	// One snapshot for the whole answer. This read s.cfg a dozen times without
	// the lock, including from three goroutines, while setConfig writes it
	// under one -- a data race, and a report that could describe files from the
	// old stack directory beside a probe of the new endpoint.
	s.mu.Lock()
	cfg := s.cfg
	s.mu.Unlock()

	res := map[string]any{}
	venv := filepath.Join(cfg.StackDir, ".venv", "bin", "python")

	for label, path := range map[string]string{
		"venv":  venv,
		"stt":   filepath.Join(cfg.StackDir, "stt.py"),
		"tts":   filepath.Join(cfg.StackDir, "tts.py"),
		"voice": voiceModelPath(cfg),
	} {
		_, err := os.Stat(path)
		res[label] = err == nil
	}
	for _, bin := range []string{"pw-record", "pw-play", "pw-dump"} {
		res[bin] = lookPathOK(bin)
	}

	// Device enumeration and the model-server probe are the slow parts, and
	// they used to run one after another: two `pw-dump` invocations plus an
	// HTTP request, each with its own timeout, all inside the handler that
	// every other shell module is queued behind. They run together now, under
	// one short deadline, so the worst case is the slowest of them rather than
	// the sum.
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	var (
		mu      sync.Mutex
		wg      sync.WaitGroup
		target  string
		sources []audioSource
		sinks   []audioNode
		llmErr  error
	)
	wg.Add(3)
	go func() {
		defer wg.Done()
		t := pickCaptureTarget(ctx, cfg.CaptureTarget)
		mu.Lock()
		target = t
		mu.Unlock()
	}()
	go func() {
		defer wg.Done()
		src, err := listSources(ctx)
		snk, err2 := listSinks(ctx)
		mu.Lock()
		if err == nil {
			sources = src
		}
		if err2 == nil {
			sinks = snk
		}
		mu.Unlock()
	}()
	go func() {
		defer wg.Done()
		err := probeLLM(ctx, cfg.Endpoint)
		mu.Lock()
		llmErr = err
		mu.Unlock()
	}()
	wg.Wait()

	res["capture_target"] = target
	if sources != nil {
		res["sources"] = sources
	}
	res["playback_target"] = cfg.PlaybackTarget
	if sinks != nil {
		res["sinks"] = sinks
	}
	if err := checkEndpoint(cfg.Endpoint); err != nil {
		res["endpoint"] = false
		res["endpoint_error"] = err.Error()
	} else {
		res["endpoint"] = true
	}
	res["llm_reachable"] = llmErr == nil
	if llmErr != nil {
		res["llm_error"] = llmErr.Error()
	}
	return res, nil
}

// say speaks a line through the configured engine, using the same code path a
// real turn uses. This is what a Settings "Test voice" button drives, and it is
// the only way to verify speech output without a microphone.
func (s *Service) say(params json.RawMessage) (any, error) {
	var p struct {
		Text string `json:"text"`
	}
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, err
	}
	if p.Text == "" {
		p.Text = "Turret assistant voice test."
	}

	// The master switch governs this too. It did not, so any IPC client could
	// start the synthesiser and playback while the UI said the assistant was
	// off -- and the settings panel only offers the voice test when it is on,
	// so nothing legitimate is lost by refusing.
	s.mu.Lock()
	enabled := s.cfg.Enabled
	s.mu.Unlock()
	if !enabled {
		return nil, fmt.Errorf("the turret assistant is off; turn it on in Settings")
	}

	// Claim the single-operation slot, exactly as a real turn does. Checking
	// `turn == nil` without reserving anything let two voice tests -- or a
	// voice test and a turn -- synthesise and play over each other.
	s.mu.Lock()
	if s.turn != nil || s.speaking {
		s.mu.Unlock()
		return nil, fmt.Errorf("busy")
	}
	s.speaking = true
	s.mu.Unlock()

	// Returns immediately: speaking took up to 60s inside the handler, freezing
	// every other shell module for the duration.
	started := s.goBackground(60*time.Second, func(ctx context.Context) {
		defer func() {
			s.mu.Lock()
			s.speaking = false
			failed := s.state == StateError
			s.mu.Unlock()
			// Do not overwrite an error the test just reported: an
			// unconditional return to idle erased the one thing the voice test
			// exists to tell the user.
			if !failed {
				s.setState(StateIdle, nil)
			}
		}()

		s.mu.Lock()
		cfg := s.cfg
		s.mu.Unlock()
		t := &turn{svc: s, ctx: ctx, cancel: func() {}, cfg: cfg}
		sp, err := t.startSpeaker()
		if err != nil {
			logWorker("voice-test", 0, err, "")
			s.failKind(ErrTTS, "speech output: "+err.Error())
			return
		}
		defer sp.close()

		began := time.Now()
		s.setState(StateSpeaking, nil)
		if err := sp.say(p.Text); err != nil {
			if ctx.Err() != nil {
				return // cancelled, not broken: disable kills these workers
			}
			logWorker("voice-test", time.Since(began), err, sp.diagnostic())
			s.failKind(ErrTTS, err.Error())
			return
		}
		sp.finish()
		// A voice test that produced no sound must not report success: it is
		// the one thing the test exists to tell the user.
		if err := sp.err(); err != nil {
			// A cancelled voice test kills its own workers, so their non-zero
			// exits are expected. Reporting them as a speech-output failure
			// left Settings showing a fault after the user simply switched the
			// assistant off -- and the state is deliberately preserved, so it
			// stayed on screen.
			if ctx.Err() != nil {
				return
			}
			logWorker("voice-test", time.Since(began), err, sp.diagnostic())
			s.failKind(ErrTTS, err.Error())
			return
		}
		logWorker("voice-test", time.Since(began), nil, "")
	})
	if !started {
		s.mu.Lock()
		s.speaking = false
		s.mu.Unlock()
		return nil, fmt.Errorf("the assistant is shutting down")
	}

	return map[string]any{"accepted": true, "async": true}, nil
}

// healthMethod reports model-server reachability, and optionally repairs or
// stops the server.
//
// Repair and stop run subprocesses that take tens of seconds. They used to run
// inside the handler, which stalled every other shell request: the IPC server
// handles one request at a time per connection and QML shares a single request
// socket across all modules. So both are dispatched to a background worker and
// the caller is told the work was accepted; progress arrives over the normal
// state broadcast.
func (s *Service) healthMethod(params json.RawMessage) (any, error) {
	var p struct {
		Repair bool `json:"repair"`
		Stop   bool `json:"stop"`
	}
	_ = json.Unmarshal(params, &p)

	if p.Repair {
		// The master switch means nothing starts while the assistant is off.
		// Repair used to start the model server regardless, which is exactly
		// the VRAM the switch exists to not spend.
		s.mu.Lock()
		enabled := s.cfg.Enabled
		s.mu.Unlock()
		if !enabled {
			return nil, fmt.Errorf("the turret assistant is off; turn it on in Settings first")
		}
	}

	if p.Stop || p.Repair {
		stop := p.Stop
		started := s.goBackground(45*time.Second, func(ctx context.Context) {
			if stop {
				if err := s.stopRuntime(ctx); err != nil {
					logEvent("assistant runtime stop failed: %v", err)
				} else {
					logEvent("assistant runtime stopped: model server and transcriber released")
				}
				return
			}
			if err := s.startRuntime(ctx); err != nil {
				logEvent("assistant runtime failed to start: %v", err)
			} else {
				logEvent("assistant runtime started: model server and transcriber warm")
			}
			s.setState(StateIdle, nil)
		})
		// Reporting "accepted" for work that was never admitted is a lie the
		// caller cannot detect. A concurrent disable closes the background
		// group, and the dispatch is refused.
		if !started {
			return nil, fmt.Errorf("the assistant is shutting down")
		}
		ok, lastErr := s.healthSnapshot()
		return map[string]any{
			"accepted": true, "async": true,
			"reachable": ok, "error": lastErr,
			"lms": lmsPath(), "endpoint": s.cfg.Endpoint,
		}, nil
	}

	s.refreshHealth(true)
	ok, lastErr := s.healthSnapshot()
	return map[string]any{
		"reachable": ok, "error": lastErr,
		"lms": lmsPath(), "endpoint": s.cfg.Endpoint,
	}, nil
}

// getConfig returns the live settings.
func (s *Service) getConfig(_ json.RawMessage) (any, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.cfg, nil
}

// listVoices reports the selectable voices, so a settings UI does not have to
// hardcode a list that would drift from what is on disk.
func (s *Service) listVoices(_ json.RawMessage) (any, error) {
	return KnownVoices, nil
}

// setConfig applies a partial update and persists it. Refused mid-turn, because
// changing the voice or endpoint under a running pipeline would apply to half of
// it. The endpoint is re-validated here so local-only cannot be disabled by
// writing to the config file through this path.
func (s *Service) setConfig(params json.RawMessage) (any, error) {
	s.mu.Lock()
	// `speaking` counts as busy too. It did not, so a settings change could
	// land in the middle of a voice test, which reads the same fields.
	if s.turn != nil || s.speaking {
		s.mu.Unlock()
		return nil, fmt.Errorf("busy: finish or cancel the current turn first")
	}
	next := s.cfg
	// Captured before the patch is applied, so an off-to-on transition can be
	// told apart from a settings change made while already on. Every setConfig
	// with the assistant on reaches the same branch below, and starting the
	// runtime there unconditionally would launch the model server every time
	// the user nudged the voice or the speed.
	wasEnabled := next.Enabled
	s.mu.Unlock()

	if err := json.Unmarshal(params, &next); err != nil {
		return nil, err
	}
	if err := checkEndpoint(next.Endpoint); err != nil {
		return nil, err
	}
	if next.TTSEngine != "kokoro" && next.TTSEngine != "piper" {
		return nil, fmt.Errorf("unknown tts engine %q", next.TTSEngine)
	}
	if next.Speed <= 0 {
		next.Speed = 1.0
	}
	if err := saveConfig(next); err != nil {
		return nil, err
	}

	s.mu.Lock()
	// Rechecked under the same lock that installs it. The busy test above
	// happens before decoding and a disk write, and a turn can claim the slot
	// inside that window -- so "settings are refused mid-turn" was true of the
	// check and not of the write.
	if s.turn != nil || s.speaking {
		s.mu.Unlock()
		return nil, fmt.Errorf("busy: finish or cancel the current turn first")
	}
	s.cfg = next
	s.mu.Unlock()
	// Turning the assistant off must actually stop things, not just refuse new
	// work: close the memory database and let the health loop idle.
	if !next.Enabled {
		// Disabling must actually stop things, not merely refuse new work: the
		// settings panel tells the user resources are released, and the user's
		// stated reason for the master switch is VRAM.
		//
		// `release` deliberately leaves the model server alone, because it is
		// also the reload path and a reload should not unload a model. Disable
		// is different: the user asked for the resources back. A server they
		// started themselves is still theirs and is left running.
		// Local resources go synchronously: the caller is told the assistant is
		// off, and that has to be true when it is told. This is bounded --
		// aborting a turn is immediate and the background drain gives up after
		// five seconds.
		s.release()

		// Stopping the model server is a subprocess that takes tens of seconds,
		// so it goes to the background like every other long operation. A
		// server the user started themselves is theirs and is left alone.
		s.health.mu.Lock()
		ours := s.health.startedByUs
		s.health.mu.Unlock()
		if ours {
			s.goBackground(45*time.Second, func(ctx context.Context) {
				if err := s.stopServerForce(ctx); err != nil {
					logEvent("could not stop the model server on disable: %v", err)
					return
				}
				logEvent("model server stopped: assistant disabled")
			})
		}
	} else {
		// Wake the parked health loop and probe immediately, or the panel
		// reports "server not running" until the first tick after switch-on.
		s.wakeHealth()
		go s.refreshHealth(true)

		// Switching the master switch on is a deliberate act, so it brings the
		// runtime up the same way the panel's "Start everything" does. Nothing
		// autostarts: `enabled` is still false after a reboot, and the server
		// and transcriber come up only because the user just asked for them.
		//
		// Backgrounded for the same reason the panel's button is: starting the
		// model server takes tens of seconds and must not hold the IPC socket.
		if !wasEnabled {
			s.goBackground(45*time.Second, func(ctx context.Context) {
				if err := s.startRuntime(ctx); err != nil {
					logEvent("assistant runtime failed to start on switch-on: %v", err)
					return
				}
				logEvent("assistant runtime started on switch-on: model server and transcriber warm")
				s.setState(StateIdle, nil)
			})
		}
		if next.MemoryEnabled {
			// Enabling must surface anything already waiting, not just what
			// arrives afterwards.
			s.refreshPending()
		}
	}
	s.broadcast()
	return next, nil
}

func lookPathOK(bin string) bool {
	_, err := exeLookPath(bin)
	return err == nil
}

var errNoStack = fmt.Errorf("turret stack not installed")
