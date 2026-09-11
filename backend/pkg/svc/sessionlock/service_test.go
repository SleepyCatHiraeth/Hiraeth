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
