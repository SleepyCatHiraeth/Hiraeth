package assistant

import "testing"

// A typed turn must never open the microphone. The whole point of the split is
// that startTextTurn skips the audio half, so the cheapest proof is that it
// starts no recorder and installs a turn that owns none.
func TestTextTurnStartsNoRecorder(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig()
	s.cfg.Enabled = true
	// Deliberately NOT a real stack: a silent turn must not need the venv.
	s.cfg.StackDir = t.TempDir()

	if err := s.startTextTurn("what time is it", false); err != nil {
		t.Fatalf("startTextTurn: %v", err)
	}

	s.mu.Lock()
	active := s.turn
	s.mu.Unlock()
	if active == nil {
		t.Fatal("no turn was installed")
	}
	if !active.silent {
		t.Error("a turn started with speak=false must be silent")
	}
	active.mu.Lock()
	rec, wav := active.rec, active.wavPath
	active.mu.Unlock()
	if rec != nil {
		t.Error("a typed turn must not start a recorder")
	}
	if wav != "" {
		t.Error("a typed turn must not claim a WAV path")
	}
	active.abort()
}

// The master switch governs typed turns exactly as it governs spoken ones.
func TestTextTurnRefusedWhileDisabled(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig() // disabled
	if err := s.startTextTurn("hello", false); err == nil {
		t.Fatal("a typed turn must be refused while the assistant is off")
	}
}

// Local-only is a property of every path that reaches the model, not just the
// spoken one.
func TestTextTurnRejectsRemoteEndpoint(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig()
	s.cfg.Enabled = true
	s.cfg.Endpoint = "https://api.openai.com/v1"

	if err := s.startTextTurn("hello", false); err == nil {
		t.Fatal("a typed turn must not be allowed to reach a remote endpoint")
	}
}

// One slot, whatever claimed it. A typed message arriving mid-turn is refused
// rather than interleaved into the running exchange.
func TestTextTurnRefusedWhileATurnIsActive(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig()
	s.cfg.Enabled = true
	s.cfg.StackDir = t.TempDir()

	if err := s.startTextTurn("first", false); err != nil {
		t.Fatalf("first turn: %v", err)
	}
	defer func() {
		s.mu.Lock()
		active := s.turn
		s.mu.Unlock()
		if active != nil {
			active.abort()
		}
	}()

	if err := s.startTextTurn("second", false); err == nil {
		t.Error("a second turn must not claim the slot while one is active")
	}
}

// An empty message is not a turn.
func TestTextTurnRejectsEmptyPrompt(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig()
	s.cfg.Enabled = true
	s.cfg.StackDir = t.TempDir()

	if err := s.startTextTurn("   \n\t ", false); err == nil {
		t.Error("whitespace is not a prompt")
	}
	s.mu.Lock()
	active := s.turn
	s.mu.Unlock()
	if active != nil {
		t.Error("no turn should have been installed")
	}
}
