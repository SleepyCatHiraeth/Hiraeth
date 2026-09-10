package main

import (
	"os"
	"time"

	"github.com/godbus/dbus/v5"
)

// Restarting the shell while the session is locked strands the user.
//
// The lockscreen is an ext-session-lock surface, and that protocol deliberately
// keeps the session locked if the locking client dies -- otherwise crashing the
// lock screen would be a trivial bypass. So killing Quickshell mid-lock destroys
// the only surface that can accept a password while the compositor correctly
// refuses to unlock, and the only way back in is a TTY.
//
// This is easy to trigger by accident: `ambxst reload` from an SSH session, from
// a script, or from an agent doing iterative development. It cost a real lockout
// on 2026-09-10.

// sessionLocked reports whether logind considers this session locked.
//
// It fails OPEN (returns false) on any error. A reload must not become
// impossible because D-Bus is unavailable -- the guard exists to catch an
// obvious mistake, not to be an authority on session state.
func sessionLocked() bool {
	conn, err := dbus.SystemBus()
	if err != nil {
		return false
	}

	obj := conn.Object("org.freedesktop.login1", dbus.ObjectPath("/org/freedesktop/login1"))

	// Prefer the session named by the environment; fall back to logind's idea of
	// this process's session.
	var sessionPath dbus.ObjectPath
	if id := os.Getenv("XDG_SESSION_ID"); id != "" {
		if err := obj.Call("org.freedesktop.login1.Manager.GetSession", 0, id).
			Store(&sessionPath); err != nil {
			sessionPath = ""
		}
	}
	if sessionPath == "" {
		if err := obj.Call("org.freedesktop.login1.Manager.GetSessionByPID", 0,
			uint32(os.Getpid())).Store(&sessionPath); err != nil {
			return false
		}
	}

	sess := conn.Object("org.freedesktop.login1", sessionPath)
	v, err := sess.GetProperty("org.freedesktop.login1.Session.LockedHint")
	if err != nil {
		return false
	}
	locked, ok := v.Value().(bool)
	return ok && locked
}

// waitForUnlock blocks until the session unlocks or the timeout expires.
// Returns true if it is safe to proceed.
func waitForUnlock(timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if !sessionLocked() {
			return true
		}
		time.Sleep(500 * time.Millisecond)
	}
	return !sessionLocked()
}
