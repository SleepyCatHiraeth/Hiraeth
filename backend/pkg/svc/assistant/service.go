// Package assistant implements the turret voice assistant's backend service.
//
// The design rule that shapes everything here: the language model proposes,
// this package disposes. Stage 1 has no tools at all, so the model's output is
// only ever spoken or displayed -- but the process boundaries, argv-only
// execution and loopback-only networking are established now, because retrofitting
// them after a tool layer exists is how the existing `run_shell_command` path in
// modules/services/Ai.qml ended up executing model output through `bash -c`.
package assistant

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"ambxst/backend/pkg/ipc"
)

// State names mirror the documented assistant state machine. Stage 1 reaches
// only this subset; the rest arrive with the memory and tool stages.
const (
	StateIdle         = "idle"
	StateListening    = "listening"
	StateTranscribing = "transcribing"
	StateThinking     = "thinking"
	StateSpeaking     = "speaking"
	StateCancelled    = "cancelled"
	StateError        = "error"
)

// Config carries the resolved locations of the local stack. Nothing here is a
// network address except Endpoint, which is validated as loopback before use.
type Config struct {
	StackDir   string `json:"stack_dir"`
	Endpoint   string `json:"endpoint"`
	Model      string `json:"model"`
	Voice      string `json:"voice"`
	STTModel   string `json:"stt_model"`
	STTThreads int    `json:"stt_threads"`
	MaxTokens  int    `json:"max_tokens"`
	Volume     string `json:"volume"`
	// Empty means "auto-detect"; see pickCaptureTarget for why the PipeWire
	// default is not trusted.
	CaptureTarget string `json:"capture_target"`
	// Empty means "use the PipeWire default sink". Unlike capture, no guess is
	// made here: which output the user can actually hear is not inferable, and
	// guessing wrong sends speech to a device they are not listening to.
	PlaybackTarget string `json:"playback_target"`
}

func defaultConfig() Config {
	home, _ := os.UserHomeDir()
	stack := filepath.Join(home, "Project", "Tools", "turret-stack")
	return Config{
		StackDir: stack,
		// Loopback only. checkEndpoint refuses anything else, so a config edit
		// cannot quietly turn this into a cloud assistant.
		Endpoint:   "http://127.0.0.1:1234/v1",
		Model:      "qwen/qwen3-14b",
		Voice:      filepath.Join(stack, "models", "piper", "en_US-lessac-medium.onnx"),
		STTModel:   "small.en",
		STTThreads: 8,
		MaxTokens:  300,
		Volume:     "0.6",
	}
}

// Service owns the assistant's state and the single in-flight turn.
type Service struct {
	cfg Config

	mu         sync.Mutex
	state      string
	transcript string
	response   string
	lastErr    string
	seq        uint64
	turn       *turn // non-nil while a turn is active

	subsMu sync.Mutex
	subs   []*ipc.Subscriber
}

func NewService() *Service {
	return &Service{cfg: defaultConfig(), state: StateIdle}
}

func (s *Service) Register(srv *ipc.Server) {
	srv.Register(&ipc.Service{
		Name: "assistant",
		Methods: map[string]ipc.HandlerFunc{
			"toggle": s.toggle,
			"cancel": s.cancel,
			"state":  s.stateMethod,
			"check":  s.check,
		},
		Subscribe: s.subscribe,
	})
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
		"state":      s.state,
		"transcript": s.transcript,
		"response":   s.response,
		"error":      s.lastErr,
		"seq":        s.seq,
	}
}

func (s *Service) setState(state string, mutate func()) {
	s.mu.Lock()
	s.state = state
	s.seq++
	if mutate != nil {
		mutate()
	}
	s.mu.Unlock()
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
func (s *Service) toggle(_ json.RawMessage) (any, error) {
	s.mu.Lock()
	active := s.turn
	state := s.state
	s.mu.Unlock()

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

func (s *Service) fail(err error) {
	s.setState(StateError, func() { s.lastErr = err.Error() })
}

// check reports whether every local dependency is actually present, so the UI
// can explain a missing piece instead of failing mid-turn. It deliberately does
// not start anything.
func (s *Service) check(_ json.RawMessage) (any, error) {
	res := map[string]any{}
	venv := filepath.Join(s.cfg.StackDir, ".venv", "bin", "python")

	for label, path := range map[string]string{
		"venv":  venv,
		"stt":   filepath.Join(s.cfg.StackDir, "stt.py"),
		"tts":   filepath.Join(s.cfg.StackDir, "tts.py"),
		"voice": s.cfg.Voice,
	} {
		_, err := os.Stat(path)
		res[label] = err == nil
	}
	for _, bin := range []string{"pw-record", "pw-play", "pw-dump"} {
		res[bin] = lookPathOK(bin)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	res["capture_target"] = pickCaptureTarget(ctx, s.cfg.CaptureTarget)
	if srcs, err := listSources(ctx); err == nil {
		res["sources"] = srcs
	}
	res["playback_target"] = s.cfg.PlaybackTarget
	if sinks, err := listSinks(ctx); err == nil {
		res["sinks"] = sinks
	}
	if err := checkEndpoint(s.cfg.Endpoint); err != nil {
		res["endpoint"] = false
		res["endpoint_error"] = err.Error()
	} else {
		res["endpoint"] = true
	}
	res["llm_reachable"] = probeLLM(s.cfg.Endpoint) == nil
	if err := probeLLM(s.cfg.Endpoint); err != nil {
		res["llm_error"] = err.Error()
	}
	return res, nil
}

func lookPathOK(bin string) bool {
	_, err := exeLookPath(bin)
	return err == nil
}

var errNoStack = fmt.Errorf("turret stack not installed")
