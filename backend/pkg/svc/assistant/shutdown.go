package assistant

import (
	"context"
	"sync"
	"time"
)

// Shutdown and disable share one teardown path.
//
// Two separate defects motivated this. The daemon never called anything on the
// assistant at shutdown, and workers run in their own process groups, so a
// reload during capture or speech could leave pw-record holding the microphone
// after the shell that started it had gone. Separately, "disable" closed the
// memory store but left an in-flight turn and any background extraction running,
// while the UI claimed resources had been released.
//
// Both are the same operation: stop owning things. So there is one
// implementation, and `Close` is just `release` with the extra step of stopping
// a server we started.

// tracked background work, so shutdown can wait for it rather than racing it.
type background struct {
	mu     sync.Mutex
	wg     sync.WaitGroup
	cancel context.CancelFunc
	ctx    context.Context
}

// ctxFor returns a context that shutdown can cancel, and registers the caller
// with the wait group. The returned done() must be called when the work ends.
func (s *Service) backgroundContext(timeout time.Duration) (context.Context, func()) {
	s.bg.mu.Lock()
	if s.bg.ctx == nil {
		s.bg.ctx, s.bg.cancel = context.WithCancel(context.Background())
	}
	parent := s.bg.ctx
	s.bg.mu.Unlock()

	ctx, cancel := context.WithTimeout(parent, timeout)
	s.bg.wg.Add(1)
	return ctx, func() {
		cancel()
		s.bg.wg.Done()
	}
}

// release stops everything this service owns except the model server.
//
// Idempotent, and safe to call from any state. Returns once workers are gone
// rather than merely signalled, because the caller's whole purpose is to be able
// to say truthfully that nothing is running.
func (s *Service) release() {
	// 1. Abort any in-flight turn. This closes the microphone and kills the
	//    recorder, transcriber, synthesiser and playback process groups.
	s.mu.Lock()
	active := s.turn
	s.mu.Unlock()
	if active != nil {
		active.abort()
	}

	// 2. Cancel background extraction and wait for it. Without the wait, a
	//    reload could still have an extraction mid-HTTP-request.
	s.bg.mu.Lock()
	cancel := s.bg.cancel
	s.bg.cancel = nil
	s.bg.ctx = nil
	s.bg.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	waitWithTimeout(&s.bg.wg, 5*time.Second)

	// 3. Close the memory store last: extraction may still have been using it.
	s.mu.Lock()
	mem := s.mem
	s.mem = nil
	s.pendingMemories = 0
	s.mu.Unlock()
	if mem != nil {
		_ = mem.Close()
	}
}

// Close is the daemon shutdown hook. Registered by the daemon so a reload or an
// exit cannot orphan the microphone.
func (s *Service) Close() error {
	s.closeOnce.Do(func() {
		s.release()

		// Only stop a server we started. One the user launched is theirs.
		s.health.mu.Lock()
		ours := s.health.startedByUs
		s.health.mu.Unlock()
		if ours {
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			_ = s.stopServerForce(ctx)
		}

		s.setState(StateIdle, nil)
	})
	return nil
}

// waitWithTimeout waits for wg, giving up after d. Shutdown must not hang
// forever on a wedged worker; the process groups are killed regardless.
func waitWithTimeout(wg *sync.WaitGroup, d time.Duration) {
	done := make(chan struct{})
	go func() {
		wg.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(d):
	}
}
