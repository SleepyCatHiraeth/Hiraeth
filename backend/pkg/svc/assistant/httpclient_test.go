package assistant

import (
	"context"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestCheckURLRefusesEverythingNonLocal(t *testing.T) {
	ok := []string{
		"http://127.0.0.1:1234/v1",
		"http://localhost:1234/v1",
		"http://[::1]:1234/v1",
		"http://127.0.0.53:8080/v1",
	}
	for _, u := range ok {
		if err := checkURL(u); err != nil {
			t.Errorf("expected %q allowed, got %v", u, err)
		}
	}

	bad := map[string]string{
		"https://127.0.0.1:1234/v1":   "https should be refused: it hides a proxy and buys nothing on loopback",
		"http://192.168.1.50:1234/v1": "LAN address",
		"http://api.openai.com/v1":    "remote host",
		"http://0.0.0.0:1234/v1":      "wildcard is not loopback",
		"http://user:pw@127.0.0.1/v1": "embedded credentials",
		"http://evil.test:1234/v1":    "hostname that is not a loopback literal",
		"ftp://127.0.0.1/v1":          "non-http scheme",
		"://nonsense":                 "unparseable",
	}
	for u, why := range bad {
		if err := checkURL(u); err == nil {
			t.Errorf("expected %q refused (%s), but it was allowed", u, why)
		}
	}
}

// The defect this guards: validating the configured URL said nothing about
// where the bytes actually went, because the default client follows redirects.
func TestClientRefusesRedirectOffMachine(t *testing.T) {
	remote := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("request reached the redirect target; local-only was bypassed")
		w.WriteHeader(http.StatusOK)
	}))
	defer remote.Close()

	redirector := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, remote.URL+"/v1/models", http.StatusFound)
	}))
	defer redirector.Close()

	req, err := http.NewRequest(http.MethodGet, redirector.URL+"/v1/models", nil)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := newLocalClient(5 * time.Second).Do(req)
	if err == nil {
		resp.Body.Close()
		t.Fatal("redirect was followed; it must be refused")
	}
	if !strings.Contains(err.Error(), "redirects are not followed") {
		t.Errorf("wrong refusal reason: %v", err)
	}
}

// Backstop: even if a URL check were bypassed, the dial itself must refuse a
// non-loopback address.
func TestDialRefusesNonLoopback(t *testing.T) {
	if err := localOnlyDial("tcp", "93.184.216.34:80"); err == nil {
		t.Error("non-loopback dial should be refused")
	}
	if err := localOnlyDial("tcp", "127.0.0.1:1234"); err != nil {
		t.Errorf("loopback dial should be allowed, got %v", err)
	}
	if err := localOnlyDial("tcp", "[::1]:1234"); err != nil {
		t.Errorf("IPv6 loopback should be allowed, got %v", err)
	}
}

// A proxy would be an off-machine hop even for a loopback URL.
func TestClientIgnoresProxyEnvironment(t *testing.T) {
	t.Setenv("HTTP_PROXY", "http://192.168.1.99:3128")
	t.Setenv("http_proxy", "http://192.168.1.99:3128")

	local := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer local.Close()

	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, local.URL, nil)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := newLocalClient(5 * time.Second).Do(req)
	if err != nil {
		t.Fatalf("loopback request should succeed while a proxy is set: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Errorf("status %d", resp.StatusCode)
	}
}

// The repair for "localhost could never connect" introduced a worse bug: it
// validated a name's DNS answers and then handed the NAME to the dialler, which
// resolved it again. Validating one answer and connecting to another is not a
// check. The dial target must be the literal that was validated.
func TestResolveReturnsTheValidatedLiteral(t *testing.T) {
	got, err := resolveLoopback(context.Background(), "localhost:1234")
	if err != nil {
		t.Fatalf("localhost must resolve: %v", err)
	}
	if len(got) == 0 {
		t.Fatal("no dial targets returned")
	}
	// Every answer is kept: localhost commonly resolves to both ::1 and
	// 127.0.0.1 while a server listens on only one of them.
	for _, target := range got {
		host, port, err := net.SplitHostPort(target)
		if err != nil {
			t.Fatalf("bad address %q: %v", target, err)
		}
		if port != "1234" {
			t.Errorf("port %q, want 1234", port)
		}
		ip := net.ParseIP(host)
		if ip == nil {
			t.Fatalf("dial target %q is still a name; it must be a validated literal", host)
		}
		if !ip.IsLoopback() {
			t.Errorf("dial target %q is not loopback", host)
		}
	}
}

func TestResolveKeepsLiteralsUntouched(t *testing.T) {
	for _, addr := range []string{"127.0.0.1:1234", "[::1]:1234"} {
		got, err := resolveLoopback(context.Background(), addr)
		if err != nil {
			t.Errorf("%s should be allowed: %v", addr, err)
			continue
		}
		if len(got) != 1 || got[0] != addr {
			t.Errorf("literal rewritten: %q -> %v", addr, got)
		}
	}
	if _, err := resolveLoopback(context.Background(), "10.0.0.5:1234"); err == nil {
		t.Error("a non-loopback literal must be refused")
	}
}

// A wedged resolver must not outlive the request that needed it.
func TestResolveHonoursTheContext(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := resolveLoopback(ctx, "some-name-that-needs-dns.invalid:80"); err == nil {
		t.Error("a cancelled context must abort resolution")
	}
}
