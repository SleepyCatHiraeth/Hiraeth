package assistant

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// fakeStack builds a stack directory whose "python" is the given shell script,
// so the worker protocol can be exercised without faster-whisper.
func fakeStack(t *testing.T, script string) string {
	t.Helper()
	dir := t.TempDir()
	bin := filepath.Join(dir, ".venv", "bin")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "stt.py"), []byte("# fake\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "python"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return dir
}

// A dependency printing a banner to stdout used to be read as readiness, after
// which the real {"ready":true} was consumed as the first transcription's
// result -- leaving every later turn one answer behind.
func TestWarmWorkerIgnoresNoiseBeforeReady(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig()
	s.cfg.StackDir = fakeStack(t, `#!/bin/sh
echo "Some dependency banner"
echo '{"ready": true}'
while read -r line; do
  printf '{"text": "heard %s"}\n' "$(basename "$line")"
done
`)
	defer s.stt.stop()

	got, err := s.transcribeWarm(context.Background(), "/tmp/first.wav")
	if err != nil {
		t.Fatalf("transcribe: %v", err)
	}
	if got != "heard first.wav" {
		t.Fatalf("got %q; a banner was mistaken for the ready line", got)
	}

	// The decisive part: the second turn must not receive the first turn's text.
	got2, err := s.transcribeWarm(context.Background(), "/tmp/second.wav")
	if err != nil {
		t.Fatalf("second transcribe: %v", err)
	}
	if got2 != "heard second.wav" {
		t.Errorf("second turn got %q: the worker is one answer behind", got2)
	}
}

// A worker that never reports readiness must not hold the turn past its budget.
func TestWarmWorkerStartupHonoursTheCallersDeadline(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig()
	s.cfg.StackDir = fakeStack(t, "#!/bin/sh\nsleep 60\n")
	defer s.stt.stop()

	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer cancel()

	start := time.Now()
	if _, err := s.transcribeWarm(ctx, "/tmp/a.wav"); err == nil {
		t.Fatal("a worker that never becomes ready must fail")
	}
	if elapsed := time.Since(start); elapsed > 5*time.Second {
		t.Errorf("waited %s; startup must be bounded by the caller's context", elapsed)
	}
}

// The transcriber holds a loaded model, so "off" has to release it.
func TestReleaseStopsTheWarmWorker(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig()
	s.cfg.StackDir = fakeStack(t, `#!/bin/sh
echo '{"ready": true}'
while read -r line; do echo '{"text": "x"}'; done
`)
	if _, err := s.transcribeWarm(context.Background(), "/tmp/a.wav"); err != nil {
		t.Fatalf("transcribe: %v", err)
	}
	s.stt.mu.Lock()
	running := s.stt.cmd != nil
	s.stt.mu.Unlock()
	if !running {
		t.Fatal("expected a warm worker to be running")
	}

	s.release()

	s.stt.mu.Lock()
	stillRunning := s.stt.cmd != nil
	s.stt.mu.Unlock()
	if stillRunning {
		t.Error("release must stop the warm transcriber: it holds a loaded model")
	}
}
