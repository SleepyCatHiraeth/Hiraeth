package assistant

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"sync"
	"syscall"
	"time"
)

// A warm transcriber.
//
// stt.py has had a `--serve` mode since the first version and nothing ever
// called it: every turn started Python, imported faster-whisper and loaded the
// model again. Measured on this machine that is ~0.7s of the ~1.55s a turn
// takes before the assistant says anything, spent re-doing work that was done
// the turn before.
//
// The worker is therefore kept between turns, and given up again when the
// assistant is switched off or has been idle long enough that the ~250MB it
// holds is worth more than the second it saves.

const sttIdleTimeout = 10 * time.Minute

type sttWorker struct {
	mu       sync.Mutex
	cmd      *exec.Cmd
	in       io.WriteCloser
	out      *bufio.Scanner
	stderr   *capped
	lastUsed time.Time
}

// transcribe sends one WAV path to the warm worker and waits for its answer.
//
// Any failure -- a worker that would not start, a dead pipe, an abandoned read
// -- stops the worker and returns an error, so the caller can fall back to a
// one-shot run. A half-consumed worker is never reused: the next turn would
// read this turn's answer.
func (s *Service) transcribeWarm(ctx context.Context, wav string) (string, error) {
	w := &s.stt
	w.mu.Lock()
	defer w.mu.Unlock()

	if err := w.ensure(s.cfg); err != nil {
		return "", err
	}

	if _, err := io.WriteString(w.in, wav+"\n"); err != nil {
		w.stopLocked()
		return "", fmt.Errorf("transcriber pipe closed: %w", err)
	}

	type result struct {
		text string
		err  error
	}
	// Read through a local, not through w.out. On the timeout path below,
	// stopLocked sets w.out to nil while this goroutine is still scanning: a
	// cancelled turn would have dereferenced nil and taken the whole daemon
	// down with it. The buffered channel is what lets the goroutine finish and
	// exit after nobody is listening.
	out := w.out
	done := make(chan result, 1)
	go func() {
		if !out.Scan() {
			err := out.Err()
			if err == nil {
				err = fmt.Errorf("transcriber exited")
			}
			done <- result{err: err}
			return
		}
		var msg struct {
			Text  string `json:"text"`
			Error string `json:"error"`
		}
		if err := json.Unmarshal(out.Bytes(), &msg); err != nil {
			done <- result{err: fmt.Errorf("transcriber returned malformed output")}
			return
		}
		if msg.Error != "" {
			done <- result{err: fmt.Errorf("transcription failed: %s", msg.Error)}
			return
		}
		done <- result{text: msg.Text}
	}()

	select {
	case r := <-done:
		if r.err != nil {
			w.stopLocked()
			return "", r.err
		}
		w.lastUsed = time.Now()
		return r.text, nil
	case <-ctx.Done():
		// The answer to this WAV is still coming and would be read as the
		// answer to the next one. Cheaper to pay one model load than to risk
		// transcribing the wrong recording.
		w.stopLocked()
		return "", ctx.Err()
	}
}

// ensure starts the worker if it is not running, and waits for it to report
// that the model is loaded. Caller holds the lock.
func (w *sttWorker) ensure(cfg Config) error {
	if w.cmd != nil {
		return nil
	}
	python := filepath.Join(cfg.StackDir, ".venv", "bin", "python")
	if _, err := os.Stat(python); err != nil {
		return fmt.Errorf("%w: %s missing", errNoStack, python)
	}

	cmd := exec.Command(python,
		filepath.Join(cfg.StackDir, "stt.py"),
		"--serve",
		"--model", cfg.STTModel,
		"--threads", strconv.Itoa(cfg.STTThreads),
		"--vocab", cfg.STTVocab,
	)
	cmd.Dir = cfg.StackDir
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Env = append(os.Environ(),
		"HF_HOME="+filepath.Join(cfg.StackDir, "models", "hf"),
		"HF_HUB_OFFLINE=1",
	)
	stderr := newCapped(4096)
	cmd.Stderr = stderr

	in, err := cmd.StdinPipe()
	if err != nil {
		return err
	}
	out, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("transcriber: %w", err)
	}

	w.cmd, w.in, w.stderr = cmd, in, stderr
	w.out = bufio.NewScanner(out)
	w.out.Buffer(make([]byte, 0, 64*1024), 1<<20)

	// Wait for the ready line. Model load is the whole point of this worker, so
	// the first turn still pays for it -- but only the first.
	ready := make(chan error, 1)
	scanner := w.out // local, for the same reason as in transcribeWarm
	go func() {
		if !scanner.Scan() {
			ready <- fmt.Errorf("transcriber failed to start: %s", oneLine(stderr.String()))
			return
		}
		ready <- nil
	}()
	select {
	case err := <-ready:
		if err != nil {
			w.stopLocked()
			return err
		}
	case <-time.After(60 * time.Second):
		w.stopLocked()
		return fmt.Errorf("transcriber did not become ready")
	}

	w.lastUsed = time.Now()
	logEvent("transcriber warm (model %s)", cfg.STTModel)
	return nil
}

// stopLocked kills the worker and its process group. Caller holds the lock.
func (w *sttWorker) stopLocked() {
	if w.cmd == nil {
		return
	}
	if w.in != nil {
		_ = w.in.Close()
	}
	if w.cmd.Process != nil {
		_ = syscall.Kill(-w.cmd.Process.Pid, syscall.SIGKILL)
		// Reaped on its own goroutine: os/exec closes the stdout pipe inside
		// Wait, and calling it while a reader is still draining that pipe is
		// exactly the race os/exec documents. The process is already killed, so
		// the reader ends in microseconds and Wait returns straight after.
		cmd := w.cmd
		go func() { _ = cmd.Wait() }()
	}
	w.cmd, w.in, w.out, w.stderr = nil, nil, nil, nil
}

func (w *sttWorker) stop() {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.stopLocked()
}

// reapIfIdle gives the model's memory back when it has not been used in a
// while. Called from the health loop, which only runs while the assistant is on.
func (w *sttWorker) reapIfIdle() {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.cmd == nil || time.Since(w.lastUsed) < sttIdleTimeout {
		return
	}
	logEvent("transcriber idle for %s, releasing it", sttIdleTimeout)
	w.stopLocked()
}
