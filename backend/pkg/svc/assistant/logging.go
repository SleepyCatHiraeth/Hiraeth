package assistant

import (
	"log"
	"strings"
	"sync"
	"time"
)

// Diagnostics.
//
// The package previously had no logging at all. When the model server was
// silently stopped, every request failed and nothing recorded why; the cause was
// found by running `ss` by hand. A voice assistant fails in the background, out
// of sight, so the absence of evidence was the real defect.
//
// Two rules shape what is written:
//
//   - Never log content. No transcript, no reply, no memory text, no prompt. The
//     whole point of a local assistant is that what you say stays yours, and a
//     log is the easiest place for that to leak.
//   - Log transitions and lifecycle, not activity. One line when state changes,
//     one when a worker starts, ends or fails. Enough to reconstruct a turn.

const logPrefix = "[assistant] "

// rate limits identical repeated messages so a flapping worker cannot fill the
// journal.
var logLimiter = struct {
	mu   sync.Mutex
	last map[string]time.Time
}{last: map[string]time.Time{}}

func shouldLog(key string, every time.Duration) bool {
	logLimiter.mu.Lock()
	defer logLimiter.mu.Unlock()
	if t, ok := logLimiter.last[key]; ok && time.Since(t) < every {
		return false
	}
	logLimiter.last[key] = time.Now()
	return true
}

// logState records a state transition, including whether the microphone is open
// — the single most important fact when reconstructing what the assistant was
// doing.
func logState(from, to string, micOpen bool) {
	if from == to {
		return
	}
	mic := ""
	if micOpen {
		mic = " mic=OPEN"
	}
	log.Printf("%sstate %s -> %s%s", logPrefix, from, to, mic)
}

// logWorker records a worker's outcome. `detail` must never contain user
// content; callers pass exit codes and truncated stderr only.
func logWorker(stage string, dur time.Duration, err error, detail string) {
	if err == nil {
		log.Printf("%s%s ok in %s", logPrefix, stage, dur.Round(time.Millisecond))
		return
	}
	if detail != "" {
		detail = " detail=" + truncate(oneLine(detail), 200)
	}
	log.Printf("%s%s FAILED after %s: %v%s", logPrefix, stage, dur.Round(time.Millisecond), err, detail)
}

// logEvent records something noteworthy that is not a state change.
func logEvent(format string, args ...any) {
	log.Printf(logPrefix+format, args...)
}

// logEventEvery is logEvent with rate limiting, for anything that can repeat.
func logEventEvery(key string, every time.Duration, format string, args ...any) {
	if shouldLog(key, every) {
		log.Printf(logPrefix+format, args...)
	}
}

// capped is an io.Writer that keeps the first n bytes of a worker's stderr and
// discards the rest. A wedged Python worker can write for as long as the turn's
// budget allows, and only the first few lines ever say anything useful.
type capped struct {
	mu  sync.Mutex
	buf []byte
	n   int
}

func newCapped(n int) *capped { return &capped{n: n} }

func (c *capped) Write(p []byte) (int, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if room := c.n - len(c.buf); room > 0 {
		if len(p) < room {
			room = len(p)
		}
		c.buf = append(c.buf, p[:room]...)
	}
	return len(p), nil // always report success: dropping is not the worker's problem
}

func (c *capped) String() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return string(c.buf)
}

func oneLine(s string) string {
	return strings.Join(strings.Fields(s), " ")
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}
