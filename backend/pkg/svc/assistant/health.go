package assistant

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"syscall"
	"time"
)

// The model server and its daemon are separate: `lms daemon up` can be running
// while `lms server start` has never been called or has stopped. When that
// happens every request fails and the assistant looks broken for no visible
// reason -- observed live on 2026-09-10, where a stopped server silently
// swallowed embeddings and would have failed a voice turn with a generic error.
//
// So health is tracked explicitly, surfaced in state, and repaired once per turn
// rather than left for the user to diagnose.

type health struct {
	mu        sync.Mutex
	reachable bool
	checkedAt time.Time
	lastErr   string
	starting  bool
}

func (s *Service) healthSnapshot() (bool, string) {
	s.health.mu.Lock()
	defer s.health.mu.Unlock()
	return s.health.reachable, s.health.lastErr
}

// refreshHealth probes the model server, caching the result briefly so a burst
// of calls does not become a burst of HTTP requests.
func (s *Service) refreshHealth(force bool) bool {
	s.health.mu.Lock()
	if !force && time.Since(s.health.checkedAt) < 5*time.Second {
		ok := s.health.reachable
		s.health.mu.Unlock()
		return ok
	}
	s.health.mu.Unlock()

	s.mu.Lock()
	endpoint := s.cfg.Endpoint
	s.mu.Unlock()

	err := probeLLM(endpoint)

	s.health.mu.Lock()
	was := s.health.reachable
	s.health.reachable = err == nil
	s.health.checkedAt = time.Now()
	if err != nil {
		s.health.lastErr = err.Error()
	} else {
		s.health.lastErr = ""
	}
	changed := was != s.health.reachable
	ok := s.health.reachable
	s.health.mu.Unlock()

	if changed {
		s.mu.Lock()
		s.seq++
		s.mu.Unlock()
		s.broadcast()
	}
	return ok
}

// ensureServer brings the model server up if it is down.
//
// Deliberately narrow: it runs the `lms` binary from the configured stack with a
// fixed argument vector, never a shell, and only ever the one subcommand. It is
// attempted at most once at a time, and a failure is reported rather than
// retried in a loop.
func (s *Service) ensureServer(ctx context.Context) bool {
	if s.refreshHealth(true) {
		return true
	}

	s.health.mu.Lock()
	if s.health.starting {
		s.health.mu.Unlock()
		return false
	}
	s.health.starting = true
	s.health.mu.Unlock()
	defer func() {
		s.health.mu.Lock()
		s.health.starting = false
		s.health.mu.Unlock()
	}()

	lms := lmsPath()
	if lms == "" {
		return false
	}

	s.setState(StateStarting, nil)

	cmd := exec.CommandContext(ctx, lms, "server", "start")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Run(); err != nil {
		s.health.mu.Lock()
		s.health.lastErr = "could not start the model server: " + err.Error()
		s.health.mu.Unlock()
		return false
	}

	// The server needs a moment to bind before it answers.
	deadline := time.Now().Add(15 * time.Second)
	for time.Now().Before(deadline) {
		select {
		case <-ctx.Done():
			return false
		case <-time.After(500 * time.Millisecond):
		}
		if s.refreshHealth(true) {
			return true
		}
	}
	return false
}

// lmsPath finds the LM Studio CLI without requiring it on PATH: the daemon does
// not inherit an interactive shell's environment.
func lmsPath() string {
	if p, err := exeLookPath("lms"); err == nil {
		return p
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	p := filepath.Join(home, ".lmstudio", "bin", "lms")
	if fi, err := os.Stat(p); err == nil && !fi.IsDir() {
		return p
	}
	return ""
}

// startHealthLoop probes reachability in the background.
//
// Without this, `reachable` stays false until something happens to ask, so a
// perfectly healthy server is reported as down on a fresh daemon -- which is
// exactly what the settings panel showed on first load. The interval is long
// because this is a local HTTP GET against a server that is either up or not.
func (s *Service) startHealthLoop() {
	go func() {
		s.refreshHealth(true)
		t := time.NewTicker(30 * time.Second)
		defer t.Stop()
		for range t.C {
			s.refreshHealth(true)
		}
	}()
}
