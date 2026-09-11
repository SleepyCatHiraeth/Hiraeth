package assistant

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
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
	// Set once the chat and embedding models have been explicitly loaded, so
	// the check is not a subprocess on every turn. Cleared when the server
	// stops, because a new server has loaded nothing.
	modelsReady bool
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
	return s.refreshHealthCtx(context.Background(), force)
}

// refreshHealthCtx is refreshHealth under a caller's context, so a turn's
// deadline reaches the probe.
func (s *Service) refreshHealthCtx(ctx context.Context, force bool) bool {
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

	err := probeLLM(ctx, endpoint)

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
	// Nothing starts a model server while the assistant is off. Without this,
	// a turn that began just before a disable could bring the server back up
	// behind the switch -- the exact VRAM surprise the switch exists to stop.
	s.mu.Lock()
	enabled := s.cfg.Enabled
	s.mu.Unlock()
	if !enabled {
		return false
	}

	if s.refreshHealthCtx(ctx, true) {
		// Reachable, but the models may still be absent or JIT-loaded: a server
		// the user started themselves has loaded nothing in particular.
		s.mu.Lock()
		cfg := s.cfg
		s.mu.Unlock()
		s.ensureModelsLoaded(ctx, cfg)
		return true
	}

	s.health.mu.Lock()
	if s.health.starting {
		// Someone else is already starting it. That is not a failure, and
		// reporting it as one put "model server failed to start" in the log
		// twice in the same second while a perfectly good start was in
		// progress. Wait for it instead of racing it -- two concurrent
		// `lms daemon up` invocations rewrite the CLI passkey file and orphan
		// whichever daemon got there first, which is exactly how this machine
		// ended up with a running llmster that its own CLI could not
		// authenticate to.
		s.health.mu.Unlock()
		return s.waitForStart(ctx)
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
	if out, err := up.CombinedOutput(); err != nil && recoverOrphanedDaemon(string(out)) {
		retry := exec.CommandContext(ctx, lms, "daemon", "up")
		retry.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
		_ = retry.Run()
	}

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
		if s.refreshHealthCtx(ctx, true) {
			s.mu.Lock()
			cfg := s.cfg
			s.mu.Unlock()
			s.ensureModelsLoaded(ctx, cfg)
			return true
		}
	}
	return false
}

// loadedModels returns the model keys currently resident, via `lms ps --json`.
func loadedModels(ctx context.Context, lms string) map[string]bool {
	out, err := exec.CommandContext(ctx, lms, "ps", "--json").Output()
	if err != nil {
		return nil
	}
	var entries []struct {
		Identifier string `json:"identifier"`
		ModelKey   string `json:"modelKey"`
	}
	if err := json.Unmarshal(out, &entries); err != nil {
		return nil
	}
	loaded := make(map[string]bool, len(entries)*2)
	for _, e := range entries {
		loaded[e.Identifier] = true
		loaded[e.ModelKey] = true
	}
	return loaded
}

// ensureModelsLoaded loads the chat and embedding models explicitly.
//
// This is the single biggest latency win measured on this machine, and it is
// not an optimisation so much as a workaround for a specific behaviour:
// LM Studio's `unloadPreviousJITModelOnLoad` is true by default, and a model
// pulled in on demand by an API request is JIT-loaded. So a turn with memory
// enabled did this, every time:
//
//	recall   -> embedding request -> loads the 84MB embedder, EVICTING the 9GB chat model
//	answer   -> chat request      -> reloads the 9GB chat model
//
// Measured 2026-09-11 on the live server: a chat request immediately after an
// embedding took 3.70s to its first token, against 0.118s with both models
// resident. That 3.6s was the whole of the gap between the user finishing
// speaking and the assistant starting to answer.
//
// Models loaded explicitly are not JIT models, so they are not subject to that
// eviction. Loading is skipped when a model is already resident, because
// `lms load` would otherwise start a second copy of it.
func (s *Service) ensureModelsLoaded(ctx context.Context, cfg Config) {
	s.health.mu.Lock()
	done := s.health.modelsReady
	s.health.mu.Unlock()
	if done {
		return
	}

	lms := lmsPath()
	if lms == "" {
		return
	}
	loaded := loadedModels(ctx, lms)
	if loaded == nil {
		return // could not tell; loading blind risks duplicate instances
	}

	want := []string{cfg.Model}
	if cfg.MemoryEnabled && cfg.EmbedModel != "" {
		want = append(want, cfg.EmbedModel)
	}
	for _, key := range want {
		if key == "" || loaded[key] {
			continue
		}
		started := time.Now()
		cmd := exec.CommandContext(ctx, lms, "load", key, "-y")
		cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
		if err := cmd.Run(); err != nil {
			logEvent("could not preload %s: %v", key, err)
			continue
		}
		logEvent("preloaded %s in %s", key, time.Since(started).Round(time.Millisecond))
	}

	s.health.mu.Lock()
	s.health.modelsReady = true
	s.health.mu.Unlock()
}

// waitForStart blocks while another caller brings the server up.
func (s *Service) waitForStart(ctx context.Context) bool {
	for {
		select {
		case <-ctx.Done():
			return false
		case <-time.After(500 * time.Millisecond):
		}
		s.health.mu.Lock()
		starting := s.health.starting
		s.health.mu.Unlock()
		if !starting {
			return s.refreshHealthCtx(ctx, true)
		}
	}
}

// recoverOrphanedDaemon deals with an llmster the CLI cannot talk to.
//
// `lms daemon up` rewrites ~/.lmstudio/.internal/lms-key-2 on every run, so a
// second invocation orphans the daemon the first one started: the process keeps
// running and every CLI call then fails with "Invalid passkey for lms CLI
// client". Nothing recovers from that on its own, and the assistant reports only
// that the server would not start -- which is true and useless.
//
// The orphan is useless to everyone, including whoever started it, because no
// CLI can reach it any more. So it is killed and the caller retries once.
func recoverOrphanedDaemon(out string) bool {
	if !strings.Contains(out, "Invalid passkey") {
		return false
	}
	logEvent("llmster is running with a passkey its CLI cannot use; restarting it")
	cmd := exec.Command("pkill", "-x", "llmster")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	_ = cmd.Run()
	time.Sleep(2 * time.Second)
	return true
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
// healthLoopsRunning counts live health loops, so a test can prove the loop
// actually exited rather than merely that Close signalled it.
var healthLoopsRunning int32

func (s *Service) startHealthLoop() {
	atomic.AddInt32(&healthLoopsRunning, 1)
	s.healthDone = make(chan struct{})
	go func() {
		defer atomic.AddInt32(&healthLoopsRunning, -1)
		defer close(s.healthDone)
		idle := time.NewTimer(time.Hour)
		defer idle.Stop()
		for {
			// Shutdown first, so a daemon exit is not held up by a parked loop
			// and a test does not leak one goroutine per constructed service.
			select {
			case <-s.stopHealth:
				return
			default:
			}

			s.mu.Lock()
			enabled := s.cfg.Enabled
			s.mu.Unlock()

			if !enabled {
				// Park completely. The old loop woke every 30 seconds to
				// discover the assistant was still off -- 2,880 wakeups a day
				// on a laptop, for a service the user had deliberately
				// disabled. Turning it on signals this channel, so nothing is
				// lost by sleeping indefinitely.
				select {
				case <-s.healthWake:
				case <-s.stopHealth:
					return
				}
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
			case <-s.stopHealth:
				return
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
	s.health.modelsReady = false
	s.health.mu.Unlock()
	s.refreshHealth(true)
	return nil
}
