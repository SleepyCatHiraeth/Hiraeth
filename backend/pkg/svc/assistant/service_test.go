package assistant

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
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
	s.cfg.Enabled = true
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
	s.cfg.Enabled = true
	if _, err := s.say(json.RawMessage(`{"text":"hello"}`)); err == nil {
		t.Fatal("a second say must be refused while one is already speaking")
	}
}

// The same slot a turn claims, so a voice test cannot talk over a real reply.
func TestSayRefusesDuringATurn(t *testing.T) {
	s := &Service{state: StateSpeaking}
	s.cfg = defaultConfig()
	s.cfg.Enabled = true
	s.turn = &turn{svc: s}
	if _, err := s.say(json.RawMessage(`{"text":"hello"}`)); err == nil {
		t.Fatal("say must be refused while a turn is active")
	}
}

// Repair and stop shell out to `lms`, which takes tens of seconds.
//
// The first version of this test used a service with startedByUs=false -- the
// fast refusal path -- so it would have stayed green if the OWNED-server stop
// became synchronous again, which is the case that actually blocks the shell.
// It now stubs `lms` with a script that sleeps, and asserts the handler returns
// while that script is still running.
func TestHealthStopIsNotSynchronous(t *testing.T) {
	slow := filepath.Join(t.TempDir(), "lms")
	if err := os.WriteFile(slow, []byte("#!/bin/sh\nsleep 10\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	old := exeLookPath
	exeLookPath = func(string) (string, error) { return slow, nil }
	// Restored after the background stop has been drained, not on defer: the
	// worker reads this package variable, so putting it back while that
	// goroutine still runs is itself a race.
	restore := func() { exeLookPath = old }

	s := &Service{state: StateIdle, stopHealth: make(chan struct{})}
	s.cfg = defaultConfig()
	// Ours, so the stop is really attempted rather than refused outright.
	s.health.startedByUs = true

	start := time.Now()
	res, err := s.healthMethod(json.RawMessage(`{"stop":true}`))
	elapsed := time.Since(start)
	if err != nil {
		t.Fatalf("health stop: %v", err)
	}
	if elapsed > 2*time.Second {
		t.Errorf("handler blocked for %s while `lms` ran; it must return immediately", elapsed)
	}
	if m, ok := res.(map[string]any); !ok || m["accepted"] != true {
		t.Fatalf("expected an accepted acknowledgement, got %#v", res)
	}

	// The work really is in flight: release waits for it rather than finding
	// nothing registered.
	s.release()
	restore()
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

// Two disables on two IPC connections, or a disable racing daemon shutdown.
// Without serialisation one release could clear the draining flag while the
// other was still waiting, which readmits work during a WaitGroup wait.
func TestConcurrentReleaseIsSafe(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig()

	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			ctx, done := s.backgroundContext(time.Second)
			<-ctx.Done()
			done()
		}()
		wg.Add(1)
		go func() {
			defer wg.Done()
			s.release()
		}()
	}
	wg.Wait()

	// Still usable afterwards: release is also "turn it off", and turning it
	// back on must not need a restart.
	ctx, done := s.backgroundContext(time.Second)
	defer done()
	if ctx.Err() != nil {
		t.Error("the service must accept background work again after a release")
	}
}

// The master switch governs the voice test too. It did not: any IPC client
// could start the synthesiser and playback while the UI said "off".
func TestSayRefusedWhileDisabled(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig() // Enabled is false by default
	if _, err := s.say(json.RawMessage(`{"text":"hello"}`)); err == nil {
		t.Fatal("the voice test must be refused while the assistant is off")
	}
}

// A voice test that cannot start the synthesiser must leave the error visible.
// The deferred return to idle used to erase it immediately.
func TestVoiceTestLeavesItsErrorVisible(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig()
	s.cfg.Enabled = true
	s.cfg.StackDir = t.TempDir() // no python: startSpeaker fails

	if _, err := s.say(json.RawMessage(`{"text":"hello"}`)); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		snap := s.snapshot()
		if snap["state"] == StateError {
			if snap["error_kind"] != ErrTTS {
				t.Errorf("error_kind = %v, want %q", snap["error_kind"], ErrTTS)
			}
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Errorf("a failed voice test must end in an error state, got %v", s.snapshot()["state"])
}

// The health loop parks on a channel while the assistant is off, so without a
// shutdown signal it outlived the service: one leaked goroutine per instance.
func TestCloseStopsTheHealthLoop(t *testing.T) {
	s := &Service{
		state:      StateIdle,
		healthWake: make(chan struct{}, 1),
		stopHealth: make(chan struct{}),
	}
	s.cfg = defaultConfig() // disabled: the loop parks immediately

	done := make(chan struct{})
	go func() {
		s.startHealthLoop()
		close(done)
	}()
	<-done
	time.Sleep(50 * time.Millisecond) // let the loop reach its park

	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	select {
	case <-s.stopHealth:
	default:
		t.Error("Close must signal the health loop to stop")
	}
}

// Only work started through backgroundContext was visible to shutdown, so a
// disable on one IPC connection could close the memory database underneath a
// synchronous handler running on another.
func TestReleaseWaitsForMemoryHandlers(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", dir)
	t.Setenv("XDG_DATA_HOME", dir)

	s := &Service{state: StateIdle}
	s.cfg = defaultConfig()
	s.cfg.Enabled = true
	s.cfg.MemoryEnabled = true

	st, release := s.useStore()
	if st == nil {
		t.Fatal("expected a store")
	}

	released := make(chan struct{})
	go func() {
		s.release()
		close(released)
	}()

	select {
	case <-released:
		t.Fatal("release returned while a memory handler still held the store")
	case <-time.After(150 * time.Millisecond):
	}

	release()
	select {
	case <-released:
	case <-time.After(5 * time.Second):
		t.Fatal("release did not finish after the handler let go")
	}

	// And afterwards the store is refused rather than handed out closed.
	s.mu.Lock()
	mem := s.mem
	s.mu.Unlock()
	if mem != nil {
		t.Error("release must close the store once nothing is using it")
	}
}
