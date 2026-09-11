package sessionlock

import (
	"encoding/json"
	"testing"
)

// The guard that failed read a signal nothing ever set. This asserts the
// service actually reports what it was told -- the property the previous guard
// was never checked for.
func TestReportsWhatTheShellSet(t *testing.T) {
	s := NewService()

	if s.Locked() {
		t.Error("a fresh service must not claim the session is locked")
	}

	if _, err := s.set(json.RawMessage(`{"locked":true}`)); err != nil {
		t.Fatal(err)
	}
	if !s.Locked() {
		t.Fatal("the service must report locked after the shell says so")
	}

	res, err := s.state(nil)
	if err != nil {
		t.Fatal(err)
	}
	m, ok := res.(map[string]any)
	if !ok || m["locked"] != true {
		t.Errorf("state() = %#v, want locked true", res)
	}

	if _, err := s.set(json.RawMessage(`{"locked":false}`)); err != nil {
		t.Fatal(err)
	}
	if s.Locked() {
		t.Error("unlocking must be reported too")
	}
}

// An unlock report that never arrives would leave reload refused forever, so a
// malformed payload must not change the state.
func TestMalformedPayloadLeavesStateAlone(t *testing.T) {
	s := NewService()
	if _, err := s.set(json.RawMessage(`{"locked":true}`)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.set(json.RawMessage(`not json`)); err == nil {
		t.Error("a malformed payload must be rejected")
	}
	if !s.Locked() {
		t.Error("a rejected payload must not silently unlock the guard")
	}
}

// The guard's combination rule, which is the part that decides whether a reload
// proceeds while the screen is locked.
//
// This is here because the first version of that rule was wrong in a way the
// existing tests could not see: it returned the daemon's answer whenever the
// daemon answered, so a daemon that had just restarted -- starting at false --
// silently overrode a logind hint that still said locked. Either source saying
// locked has to win.
func TestEitherSourceLockedRefuses(t *testing.T) {
	cases := []struct {
		shell, shellKnown, logind bool
		wantLocked                bool
		why                       string
	}{
		{shell: true, shellKnown: true, logind: false, wantLocked: true,
			why: "the shell is showing a lock surface; logind not knowing is not a reason to proceed"},
		{shell: false, shellKnown: true, logind: true, wantLocked: true,
			why: "a restarted daemon starts at false; logind still says locked"},
		{shell: false, shellKnown: false, logind: true, wantLocked: true,
			why: "no daemon to ask, so logind is all there is"},
		{shell: false, shellKnown: true, logind: false, wantLocked: false,
			why: "both agree it is unlocked"},
		{shell: false, shellKnown: false, logind: false, wantLocked: false,
			why: "nothing known; the guard fails open by design"},
	}
	for _, c := range cases {
		got := CombineLockSignals(c.shell, c.shellKnown, c.logind)
		if got != c.wantLocked {
			t.Errorf("shell=%v known=%v logind=%v -> %v, want %v: %s",
				c.shell, c.shellKnown, c.logind, got, c.wantLocked, c.why)
		}
	}
}
