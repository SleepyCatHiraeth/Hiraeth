package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestFailedThumbnailIsRetriedOnlyAfterSourceChanges(t *testing.T) {
	dir := t.TempDir()
	source := filepath.Join(dir, "wallpaper.jpg")
	thumb := filepath.Join(dir, "wallpaper.jpg.jpg")
	marker := thumb + ".failed"
	if err := os.WriteFile(source, []byte("broken"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(marker, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if needsThumbnail(source, thumb) {
		t.Fatal("unchanged failed source should be skipped")
	}
	future := time.Now().Add(time.Second)
	if err := os.Chtimes(source, future, future); err != nil {
		t.Fatal(err)
	}
	if !needsThumbnail(source, thumb) {
		t.Fatal("changed failed source should be retried")
	}
}
