package assistant

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"
)

// The two tests below reach the real internet. They are opt-in so that
// `go test ./...` stays offline, deterministic and fast; the SSRF refusal test
// needs no network and always runs, because it is the one guarding a
// security property.
func requireLiveWeb(t *testing.T) {
	t.Helper()
	if os.Getenv("AMBXST_LIVE_WEB") == "" {
		t.Skip("set AMBXST_LIVE_WEB=1 to run tests that reach the internet")
	}
}

func TestLiveWebSearch(t *testing.T) {
	requireLiveWeb(t)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	out, err := runWebSearch(ctx, map[string]any{"query": "capital of France"})
	if err != nil {
		t.Fatalf("web_search: %v", err)
	}
	t.Logf("RESULT:\n%s", out)
	if !strings.Contains(out, "Wikipedia") {
		t.Error("expected a Wikipedia hit")
	}
}

func TestLiveFetchURL(t *testing.T) {
	requireLiveWeb(t)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	out, err := runFetchURL(ctx, map[string]any{"url": "https://en.wikipedia.org/wiki/France"})
	if err != nil {
		t.Fatalf("fetch_url: %v", err)
	}
	t.Logf("first 300 chars:\n%s", out[:min(300, len(out))])
}

func TestLiveFetchRefusesInternal(t *testing.T) {
	ctx := context.Background()
	if _, err := runFetchURL(ctx, map[string]any{"url": "http://127.0.0.1:1234/v1/models"}); err == nil {
		t.Fatal("fetch_url reached the local model server; it must be refused")
	} else {
		t.Logf("correctly refused: %v", err)
	}
}
