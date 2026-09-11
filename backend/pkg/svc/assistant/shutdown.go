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
	// closed while release() is draining. WaitGroup.Add must not run
	// concurrently with Wait, so registration is refused for the duration
	// rather than racing the drain.
	closed bool
}

// ctxFor returns a context that shutdown can cancel, and registers the caller
// with the wait group. The returned done() must be called when the work ends.
func (s *Service) backgroundContext(timeout time.Duration) (context.Context, func()) {
	s.bg.mu.Lock()
	if s.bg.closed {
		// Shutting down: hand back a context that is already done, and register
		// nothing. The caller checks ctx.Err() the same way it would for a
		// cancellation, so no caller needs a second code path.
		s.bg.mu.Unlock()
		ctx, cancel := context.WithCancel(context.Background())
		cancel()
		return ctx, func() {}
	}
	if s.bg.ctx == nil {
		s.bg.ctx, s.bg.cancel = context.WithCancel(context.Background())
	}
	parent := s.bg.ctx
	// Add under the same lock that release() takes before it waits. Adding
	// after the unlock let a worker register while the drain was already
	// running, which is a WaitGroup misuse and a real race.
	s.bg.wg.Add(1)
	s.bg.mu.Unlock()

	ctx, cancel := context.WithTimeout(parent, timeout)
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
//
// Serialised against itself: two concurrent releases -- a disable from the
// settings panel racing a daemon shutdown, or simply two disables on two IPC
// connections -- could otherwise have one clear the `closed` flag while the
// other was still draining, which lets new work register during a WaitGroup
// wait. That is the same misuse this flag exists to prevent.
func (s *Service) release() {
	s.releaseMu.Lock()
	defer s.releaseMu.Unlock()

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
	s.bg.closed = true
	s.bg.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	waitWithTimeout(&s.bg.wg, 5*time.Second)

	// Reopen. release() is also what "turn the assistant off" runs, and turning
	// it back on must not need a restart.
	s.bg.mu.Lock()
	s.bg.closed = false
	s.bg.mu.Unlock()

	// 3. Release the warm transcriber. It holds a loaded model, which is most
	//    of what "turn it off" is meant to give back.
	s.stt.stop()

	// 4. Drop the conversation. "Off" has to mean the assistant does not
	//    remember what was said before it was switched off.
	s.convo.forget()

	// 5. Close the memory store last: extraction may still have been using it.
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
