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

// sessionLocked must fail open: a reload becoming impossible because D-Bus is
// unreachable would be worse than the hazard the guard prevents.
func TestSessionLockedFailsOpen(t *testing.T) {
	t.Setenv("DBUS_SYSTEM_BUS_ADDRESS", "unix:path=/nonexistent-for-test")
	if sessionLocked() {
		t.Error("sessionLocked must return false when the bus is unreachable")
	}
}
