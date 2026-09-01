package main

import (
	"bufio"
	"net"
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

func TestSendMpvIpc(t *testing.T) {
	socket := filepath.Join(t.TempDir(), "mpv.sock")
	listener, err := net.Listen("unix", socket)
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	received := make(chan string, 1)
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		line, _ := bufio.NewReader(conn).ReadString('\n')
		received <- line
	}()

	const payload = `{"command":["set_property","time-pos",0]}`
	if err := sendMpvIpc(socket, payload); err != nil {
		t.Fatal(err)
	}
	if got := <-received; got != payload+"\n" {
		t.Fatalf("unexpected payload %q", got)
	}
}
