package screenshot

import (
	"os"
	"path/filepath"
	"testing"

	internal "ambxst/backend/internal/screenshot"
	"ambxst/backend/pkg/capture"
)

func TestWriteTempPNGIsPrivate(t *testing.T) {
	buffer, err := internal.CreateShmBuffer(2, 2, 8)
	if err != nil {
		t.Fatal(err)
	}
	defer buffer.Close()
	buffer.Format = internal.FormatARGB8888

	path, err := writeTempPNG(t.TempDir(), &internal.CaptureResult{Buffer: buffer, Format: uint32(buffer.Format)})
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(path)

	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if mode := info.Mode().Perm(); mode != 0o600 {
		t.Fatalf("temporary frame mode = %o, want 600", mode)
	}
}

func TestCloseRemovesFrozenFrame(t *testing.T) {
	buffer, err := internal.CreateShmBuffer(2, 2, 8)
	if err != nil {
		t.Fatal(err)
	}
	buffer.Format = internal.FormatARGB8888
	result := &internal.CaptureResult{Buffer: buffer, Format: uint32(buffer.Format)}
	path, err := writeTempPNG(t.TempDir(), result)
	if err != nil {
		buffer.Close()
		t.Fatal(err)
	}

	capture.StoreSessionFrame("test", result, func() {
		buffer.Close()
		_ = os.Remove(path)
	})
	NewService(nil).Close()
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("temporary frame survived service close: %v", err)
	}
}

func TestFrameDirIsPrivateAndUnderRuntimeDir(t *testing.T) {
	runtime := t.TempDir()
	t.Setenv("XDG_RUNTIME_DIR", runtime)

	dir := NewService(nil).frameDir()
	want := filepath.Join(runtime, "ambxst", "frames")
	if dir != want {
		t.Fatalf("frameDir = %q, want %q", dir, want)
	}
	info, err := os.Stat(dir)
	if err != nil {
		t.Fatal(err)
	}
	if mode := info.Mode().Perm(); mode != 0o700 {
		t.Fatalf("frame dir mode = %o, want 700", mode)
	}
}

func TestFrameDirFallsBackWhenRuntimeDirUnset(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", "")
	if dir := NewService(nil).frameDir(); dir != "" {
		t.Fatalf("frameDir = %q, want empty so os.CreateTemp falls back", dir)
	}
}
