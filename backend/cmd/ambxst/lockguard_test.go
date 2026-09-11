package main

import "testing"

func TestHasFlag(t *testing.T) {
	args := []string{"--wait", "other"}
	if !hasFlag(args, "--wait") {
		t.Error("--wait not detected")
	}
	if !hasFlag([]string{"-f"}, "--force", "-f") {
		t.Error("alias not detected")
	}
	if hasFlag([]string{"--forcefully"}, "--force") {
		t.Error("prefix wrongly matched as exact flag")
	}
	if hasFlag(nil, "--force") {
		t.Error("empty args matched")
	}
}

// The logind reader must fail open: a reload becoming impossible because D-Bus
// is unreachable would be worse than the hazard the guard prevents.
//
// This tests logindReportsLocked rather than sessionLocked, because
// sessionLocked also asks the running daemon and so depends on whether this
// machine happens to be locked while the suite runs -- which made it flake. The
// combination rule the two feed is tested in the sessionlock package, where it
// can be exercised without a live system.
func TestLogindReadFailsOpen(t *testing.T) {
	t.Setenv("DBUS_SYSTEM_BUS_ADDRESS", "unix:path=/nonexistent-for-test")
	if logindReportsLocked() {
		t.Error("the logind read must return false when the bus is unreachable")
	}
}
