package assistant

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

// say used to synthesise and play inline, holding the IPC handler for as long
// as the speech took. QML shares one request socket across every module, and
// the IPC server processes a connection's requests serially, so a ten-second
// reply froze the clock, the workspaces and the tray with it.
func TestSayReturnsWithoutWaitingForSpeech(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig()
	s.cfg.StackDir = t.TempDir() // no python here: the worker fails, off the handler's path

	start := time.Now()
	res, err := s.say(json.RawMessage(`{"text":"hello"}`))
	if err != nil {
		t.Fatalf("say: %v", err)
	}
	if elapsed := time.Since(start); elapsed > 2*time.Second {
		t.Errorf("handler blocked for %s; it must return immediately", elapsed)
	}
	m, ok := res.(map[string]any)
	if !ok || m["accepted"] != true {
		t.Fatalf("expected an accepted acknowledgement, got %#v", res)
	}
}

// Checking `turn == nil` without reserving anything let two voice tests overlap,
// producing two synthesisers and two playback streams on the same sink.
func TestSayRefusesToOverlapItself(t *testing.T) {
	s := &Service{state: StateIdle, speaking: true}
	s.cfg = defaultConfig()
	if _, err := s.say(json.RawMessage(`{"text":"hello"}`)); err == nil {
		t.Fatal("a second say must be refused while one is already speaking")
	}
}

// The same slot a turn claims, so a voice test cannot talk over a real reply.
func TestSayRefusesDuringATurn(t *testing.T) {
	s := &Service{state: StateSpeaking}
	s.cfg = defaultConfig()
	s.turn = &turn{svc: s}
	if _, err := s.say(json.RawMessage(`{"text":"hello"}`)); err == nil {
		t.Fatal("say must be refused while a turn is active")
	}
}

// Repair and stop shell out to `lms`, which takes tens of seconds. Stop is used
// here because it refuses immediately when the server is not ours, so the test
// exercises the handler's asynchrony without starting anything.
func TestHealthStopIsNotSynchronous(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig()

	start := time.Now()
	res, err := s.healthMethod(json.RawMessage(`{"stop":true}`))
	if err != nil {
		t.Fatalf("health stop: %v", err)
	}
	if elapsed := time.Since(start); elapsed > 2*time.Second {
		t.Errorf("handler blocked for %s; it must run in the background", elapsed)
	}
	if m, ok := res.(map[string]any); !ok || m["accepted"] != true {
		t.Fatalf("expected an accepted acknowledgement, got %#v", res)
	}
	s.release()
}

// A stream that ends without [DONE] or a finish_reason means the connection
// dropped mid-answer. Accepting it made a half-answer look like a whole one.
func TestStreamChatReportsATruncatedReply(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		io.WriteString(w, "data: {\"choices\":[{\"delta\":{\"content\":\"Half a thought. \"}}]}\n\n")
		// and then nothing: no [DONE], no finish_reason
	}))
	defer srv.Close()

	cfg := defaultConfig()
	cfg.Endpoint = srv.URL

	var spoken []string
	err := streamChat(context.Background(), cfg, "hello", "", nil, func(s string) {
		spoken = append(spoken, s)
	})
	if !errors.Is(err, errTruncated) {
		t.Fatalf("expected a truncation error, got %v", err)
	}
	if len(spoken) != 1 || spoken[0] != "Half a thought." {
		t.Errorf("what did arrive must still be spoken, got %q", spoken)
	}
}

func TestStreamChatAcceptsAFinishedReply(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, "data: {\"choices\":[{\"delta\":{\"content\":\"All done. \"}}]}\n\n")
		io.WriteString(w, "data: [DONE]\n\n")
	}))
	defer srv.Close()

	cfg := defaultConfig()
	cfg.Endpoint = srv.URL
	if err := streamChat(context.Background(), cfg, "hello", "", nil, func(string) {}); err != nil {
		t.Fatalf("a completed stream must not error: %v", err)
	}
}

// The kind is what lets the UI say which part failed.
func TestErrorKindIsClearedOnRecovery(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig()

	s.failKind(ErrMicrophone, "no audio was captured")
	if got := s.snapshot()["error_kind"]; got != ErrMicrophone {
		t.Fatalf("error_kind = %v, want %q", got, ErrMicrophone)
	}
	s.setState(StateIdle, nil)
	if got := s.snapshot()["error_kind"]; got != "" {
		t.Errorf("error_kind must clear when the state leaves error, got %v", got)
	}
}

// The master switch has to mean it: repair used to start the model server, and
// its model, while the assistant was switched off.
func TestHealthRepairRefusedWhileDisabled(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig() // Enabled is false by default
	if _, err := s.healthMethod(json.RawMessage(`{"repair":true}`)); err == nil {
		t.Fatal("repair must be refused while the assistant is off")
	}
}

// The health loop used to wake every 30 seconds whether or not the assistant
// was on -- 2,880 probes a day for a service the user had switched off.
func TestHealthLoopParksWhileDisabled(t *testing.T) {
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"data":[]}`))
	}))
	defer srv.Close()

	s := &Service{state: StateIdle, healthWake: make(chan struct{}, 1)}
	s.cfg = defaultConfig()
	s.cfg.Endpoint = srv.URL
	s.cfg.Enabled = false

	s.startHealthLoop()
	time.Sleep(300 * time.Millisecond)
	if n := hits.Load(); n != 0 {
		t.Fatalf("probed %d times while disabled; the loop must park", n)
	}

	// Enabling must probe at once, not at the next tick: the settings panel
	// otherwise reports "server not running" for half a minute after switch-on.
	s.mu.Lock()
	s.cfg.Enabled = true
	s.mu.Unlock()
	s.wakeHealth()

	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if hits.Load() > 0 {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Error("enabling the assistant did not wake the health loop")
}

// Turning one category off must not disable the other eight. The map used to be
// returned verbatim when non-empty, so "absent" meant "disabled" -- which would
// have made the per-category switches in Settings quietly destructive.
func TestEnabledCategoriesMergesOntoDefaults(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig()
	s.cfg.MemoryCategories = map[string]bool{"projects": false}

	cats := s.enabledCategories()
	if cats["projects"] {
		t.Error("an explicitly disabled category must stay disabled")
	}
	for _, k := range []string{"user_profile", "preferences", "environment", "routines", "instructions", "important_facts"} {
		if !cats[k] {
			t.Errorf("category %q was silently disabled by an unrelated choice", k)
		}
	}
	if len(cats) != len(defaultCategories()) {
		t.Errorf("got %d categories, want the full set of %d", len(cats), len(defaultCategories()))
	}
}

// Pressing the activation key during a voice test used to start a turn anyway,
// putting a second synthesiser on the same sink. Nothing checked `speaking`.
func TestStartTurnRefusedWhileSpeaking(t *testing.T) {
	s := &Service{state: StateIdle, speaking: true}
	s.cfg = defaultConfig()
	s.cfg.Enabled = true
	s.cfg.StackDir = t.TempDir()

	if err := s.startTurn(); err == nil {
		t.Fatal("a turn must be refused while a voice test is speaking")
	}
	s.mu.Lock()
	active := s.turn
	s.mu.Unlock()
	if active != nil {
		t.Error("a refused turn must not be installed")
	}
}

// A turn that fails to start must release the slot, or the assistant is busy
// forever with nothing running.
func TestStartTurnReleasesTheSlotWhenItFails(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig()
	s.cfg.Enabled = true
	s.cfg.StackDir = t.TempDir() // no .venv here: startTurn fails its pre-flight

	if err := s.startTurn(); err == nil {
		t.Fatal("expected the missing stack to fail the turn")
	}
	s.mu.Lock()
	active := s.turn
	s.mu.Unlock()
	if active != nil {
		t.Error("the slot must be free after a failed start")
	}
}
