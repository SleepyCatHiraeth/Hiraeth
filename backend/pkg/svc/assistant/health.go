package assistant

import (
	"context"
	"fmt"
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
	// Ownership: only a server this assistant started may be stopped by it.
	startedByUs bool
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

	// The daemon may be down as well as the server; `daemon up` is a no-op when
	// it is already running, so this is unconditional rather than conditional
	// on a status check that could race.
	up := exec.CommandContext(ctx, lms, "daemon", "up")
	up.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	_ = up.Run()

	cmd := exec.CommandContext(ctx, lms, "server", "start")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Run(); err != nil {
		s.health.mu.Lock()
		s.health.lastErr = "could not start the model server: " + err.Error()
		s.health.mu.Unlock()
		return false
	}

	s.health.mu.Lock()
	s.health.startedByUs = true
	s.health.mu.Unlock()

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
		idle := time.NewTimer(time.Hour)
		defer idle.Stop()
		for {
			s.mu.Lock()
			enabled := s.cfg.Enabled
			s.mu.Unlock()

			if !enabled {
				// Park completely. The old loop woke every 30 seconds to
				// discover the assistant was still off -- 2,880 wakeups a day
				// on a laptop, for a service the user had deliberately
				// disabled. Turning it on signals this channel, so nothing is
				// lost by sleeping indefinitely.
				<-s.healthWake
				continue
			}

			s.refreshHealth(true)
			s.stt.reapIfIdle()
			s.sweepExpired()

			if !idle.Stop() {
				select {
				case <-idle.C:
				default:
				}
			}
			idle.Reset(30 * time.Second)
			select {
			case <-idle.C:
			case <-s.healthWake:
			}
		}
	}()
}

// wakeHealth nudges the health loop, so enabling the assistant probes at once
// instead of at the next tick.
func (s *Service) wakeHealth() {
	select {
	case s.healthWake <- struct{}{}:
	default: // already pending: one wakeup is as good as two
	}
}

// stopServer shuts the model server down and unloads whatever it is holding.
//
// The daemon idles at a few hundred MB of RAM and keeps any loaded model
// resident until its TTL expires, which matters on a machine that also plays
// games. Turning the assistant off should be able to actually give that back,
// so this is offered explicitly rather than left to the TTL.
// startedServer records whether WE started llmster. Stopping a server the user
// started themselves would be taking something that is not ours.
func (s *Service) stopServer(ctx context.Context) error {
	s.health.mu.Lock()
	ours := s.health.startedByUs
	s.health.mu.Unlock()
	if !ours {
		return fmt.Errorf("the model server was not started by the assistant; stop it yourself with `lms server stop`")
	}
	return s.stopServerForce(ctx)
}

func (s *Service) stopServerForce(ctx context.Context) error {
	lms := lmsPath()
	if lms == "" {
		return fmt.Errorf("lms not found")
	}
	// Unload first so VRAM is released even if the server lingers.
	unload := exec.CommandContext(ctx, lms, "unload", "--all")
	unload.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	_ = unload.Run()

	stop := exec.CommandContext(ctx, lms, "server", "stop")
	stop.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := stop.Run(); err != nil {
		return err
	}

	// Stopping the server leaves the daemon resident at a few hundred MB, which
	// is most of what "turn it off" is meant to reclaim. `ensureServer` brings
	// both back, so taking the daemon down too costs nothing but a slower first
	// turn.
	down := exec.CommandContext(ctx, lms, "daemon", "down")
	down.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	_ = down.Run()

	s.health.mu.Lock()
	s.health.startedByUs = false
	s.health.mu.Unlock()
	s.refreshHealth(true)
	return nil
}
