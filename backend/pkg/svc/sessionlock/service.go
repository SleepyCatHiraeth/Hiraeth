// Package sessionlock tracks whether the shell's lockscreen is up.
//
// This exists because of two real incidents, on 2026-09-10 and 2026-09-11.
//
// The lockscreen is an ext-session-lock surface. That protocol deliberately
// keeps the session locked if the locking client dies, so that crashing the lock
// screen is not a bypass. Restarting Quickshell while it is up therefore
// destroys the only surface that can accept a password, and the way back in is a
// TTY.
//
// A guard was added after the first incident. It read logind's `LockedHint` --
// and AMBXST's lockscreen never sets it, because locking is a QML property in
// LockscreenService.qml and nothing told the rest of the system. The guard read
// a signal that was always false, failed open by design, and waved through the
// reload that caused the second one. Checking that a mechanism works is not the
// same as checking it ever reports the condition you care about.
//
// So the shell reports lock state here, and this package does two things with
// it: answers the reload guard, and tells logind, so every other tool on the
// machine that reads LockedHint sees the truth as well.
package sessionlock

import (
	"encoding/json"
	"log"
	"os"
	"sync"

	"github.com/godbus/dbus/v5"

	"ambxst/backend/pkg/ipc"
)

type Service struct {
	mu     sync.RWMutex
	locked bool
}

func NewService() *Service { return &Service{} }

func (s *Service) Register(srv *ipc.Server) {
	srv.Register(&ipc.Service{
		Name: "lock",
		Methods: map[string]ipc.HandlerFunc{
			"set":   s.set,
			"state": s.state,
		},
	})
}

// set records the shell's lock state. Called by LockscreenService.qml whenever
// the lockscreen appears or goes away.
func (s *Service) set(params json.RawMessage) (any, error) {
	var p struct {
		Locked bool `json:"locked"`
	}
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, err
	}

	s.mu.Lock()
	changed := s.locked != p.Locked
	s.locked = p.Locked
	s.mu.Unlock()

	if changed {
		state := "released"
		if p.Locked {
			state = "engaged"
		}
		log.Printf("[ambxst] lockscreen %s", state)
	}

	// Published every time, not only on a change. The shell reports its state at
	// startup precisely to correct a stale hint, and a "changed" gate throws
	// that report away: the service starts false, the shell says false, nothing
	// is sent, and logind keeps whatever wrong value it had. Observed exactly
	// that on 2026-09-11 with LockedHint stuck at yes across a reboot. The call
	// is cheap and happens only on lock, unlock, or shell start.
	setLoginHint(p.Locked)
	return map[string]any{"locked": p.Locked}, nil
}

func (s *Service) state(json.RawMessage) (any, error) {
	return map[string]any{"locked": s.Locked()}, nil
}

func (s *Service) Locked() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.locked
}

// setLoginHint publishes the state to logind.
//
// Best-effort: a shell that cannot reach the system bus must still be able to
// lock. The value of doing it at all is that everything else on the machine
// reads LockedHint, and until now it was simply wrong whenever the screen was
// locked.
func setLoginHint(locked bool) {
	conn, err := dbus.SystemBus()
	if err != nil {
		return
	}
	mgr := conn.Object("org.freedesktop.login1", dbus.ObjectPath("/org/freedesktop/login1"))

	var sessionPath dbus.ObjectPath
	if id := os.Getenv("XDG_SESSION_ID"); id != "" {
		if err := mgr.Call("org.freedesktop.login1.Manager.GetSession", 0, id).Store(&sessionPath); err != nil {
			sessionPath = ""
		}
	}
	if sessionPath == "" {
		if err := mgr.Call("org.freedesktop.login1.Manager.GetSessionByPID", 0,
			uint32(os.Getpid())).Store(&sessionPath); err != nil {
			return
		}
	}

	sess := conn.Object("org.freedesktop.login1", sessionPath)
	if call := sess.Call("org.freedesktop.login1.Session.SetLockedHint", 0, locked); call.Err != nil {
		log.Printf("[ambxst] could not publish lock state to logind: %v", call.Err)
	}
}
