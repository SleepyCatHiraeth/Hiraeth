package main

import (
	"encoding/json"
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

// sessionLocked reports whether the session is locked, asking the shell first.
//
// The first version of this asked ONLY logind, and AMBXST's lockscreen never
// set logind's LockedHint -- locking was a QML property and nothing published
// it. So the guard read a signal that was permanently false and waved through
// the reload that caused a second lockout on 2026-09-11.
//
// The running daemon now holds the shell's own answer, which is authoritative
// for this lockscreen, and publishes it to logind as well. Both are consulted:
// the daemon because it is the truth, logind because it still covers a lock
// engaged by anything else on the system.
func sessionLocked() bool {
	if locked, ok := shellReportsLocked(); ok {
		return locked
	}
	return logindReportsLocked()
}

// shellReportsLocked asks the running daemon. The second return is false when
// the daemon cannot be reached or does not know, in which case the caller falls
// back to logind.
func shellReportsLocked() (locked bool, known bool) {
	if !isAlive() {
		return false, false
	}
	resp, err := newClient().Call("lock.state", map[string]any{})
	if err != nil {
		return false, false
	}
	var out struct {
		Locked bool `json:"locked"`
	}
	if err := json.Unmarshal(resp, &out); err != nil {
		return false, false
	}
	return out.Locked, true
}

// logindReportsLocked reports whether logind considers this session locked.
//
// It fails OPEN (returns false) on any error. A reload must not become
// impossible because D-Bus is unavailable -- the guard exists to catch an
// obvious mistake, not to be an authority on session state.
func logindReportsLocked() bool {
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
