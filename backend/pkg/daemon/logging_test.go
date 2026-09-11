package daemon

import (
	"ambxst/backend/pkg/paths"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The size was checked once at startup, so a daemon left running for weeks —
// the normal case for a desktop shell — grew without limit.
func TestCappedLogTruncatesAtTheCeiling(t *testing.T) {
	path := filepath.Join(t.TempDir(), "daemon.log")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	c := &cappedLog{f: f, max: 1024}
	line := []byte(strings.Repeat("x", 128) + "\n")
	for i := 0; i < 40; i++ { // ~5KB through a 1KB cap
		if _, err := c.Write(line); err != nil {
			t.Fatal(err)
		}
	}

	fi, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if fi.Size() > 1024 {
		t.Errorf("log grew to %d bytes past its %d ceiling", fi.Size(), 1024)
	}
	if fi.Size() == 0 {
		t.Error("truncation must not leave the log empty of recent lines")
	}
}

// A log written by an earlier build kept the process umask, so it stayed
// world-readable: O_CREATE's mode applies only when the file is created.
func TestStartLoggingRepairsAnExistingModeS(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_STATE_HOME", dir)

	path := filepath.Join(dir, "ambxst", "daemon.log")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("old\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	startLogging(paths.New())

	fi, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if mode := fi.Mode().Perm(); mode != 0o600 {
		t.Errorf("log mode is %o, want 600: an old world-readable log must be repaired", mode)
	}
}
