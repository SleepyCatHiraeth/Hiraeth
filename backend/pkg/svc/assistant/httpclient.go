package assistant

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"time"
)

// One HTTP policy for every request this assistant makes.
//
// Validating the configured endpoint is not enough on its own. Go's default
// client follows redirects, so a local server -- compromised, misconfigured, or
// simply not the one the user thinks is listening -- can answer with a 302 and
// send the prompt, the transcript, or an embedding off the machine. The address
// being loopback said nothing about where the bytes ended up.
//
// So the check moves from "the URL you configured" to "every destination this
// request actually reaches", and lives in one place rather than being repeated
// at four call sites.

// LocalOnlyError reports a destination that would have left the machine.
type LocalOnlyError struct {
	URL    string
	Reason string
}

func (e *LocalOnlyError) Error() string {
	return fmt.Sprintf("refusing non-local destination %q: %s (local-only mode)", e.URL, e.Reason)
}

// checkURL enforces the local-only invariant for one URL.
//
// Exported behaviour is deliberately strict: loopback literal or "localhost",
// http scheme only, and no embedded credentials. A hostname that merely
// *resolves* to loopback today is refused, because resolution can change
// between the check and the connection.
func checkURL(raw string) error {
	u, err := url.Parse(raw)
	if err != nil {
		return &LocalOnlyError{URL: raw, Reason: "unparseable"}
	}
	if u.Scheme != "http" {
		// https to loopback is pointless and would mask a proxy; anything else
		// is not a model endpoint.
		return &LocalOnlyError{URL: raw, Reason: "scheme must be http"}
	}
	if u.User != nil {
		return &LocalOnlyError{URL: raw, Reason: "embedded credentials"}
	}
	host := u.Hostname()
	if host == "localhost" {
		return nil
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return &LocalOnlyError{URL: raw, Reason: "host is not a literal IP address"}
	}
	if !ip.IsLoopback() {
		return &LocalOnlyError{URL: raw, Reason: "address is not loopback"}
	}
	return nil
}

// localOnlyTransport refuses to dial any address that is not loopback.
//
// This is the backstop: even if a redirect slipped past the URL check, or a
// hostname resolved somewhere unexpected, the connection itself is refused at
// dial time. Belt and braces, because this is the guarantee the whole design
// rests on.
func localOnlyDial(network, addr string) error {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return &LocalOnlyError{URL: addr, Reason: "unparseable address"}
	}
	ip := net.ParseIP(host)
	if ip == nil || !ip.IsLoopback() {
		return &LocalOnlyError{URL: addr, Reason: "dialled address is not loopback"}
	}
	return nil
}

// newLocalClient builds the only HTTP client this package uses.
func newLocalClient(timeout time.Duration) *http.Client {
	dialer := &net.Dialer{Timeout: 10 * time.Second, KeepAlive: 30 * time.Second}

	return &http.Client{
		Timeout: timeout,
		// Redirects are refused outright rather than re-validated. A model
		// server has no legitimate reason to redirect, so accepting any
		// redirect would only widen the attack surface for no feature.
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			return &LocalOnlyError{URL: req.URL.String(), Reason: "redirects are not followed"}
		},
		Transport: &http.Transport{
			Proxy: nil, // never honour HTTP_PROXY: that is an off-machine hop
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				if err := localOnlyDial(network, addr); err != nil {
					return nil, err
				}
				return dialer.DialContext(ctx, network, addr)
			},
			ForceAttemptHTTP2:     false,
			MaxIdleConns:          4,
			IdleConnTimeout:       60 * time.Second,
			TLSHandshakeTimeout:   5 * time.Second,
			ExpectContinueTimeout: 1 * time.Second,
		},
	}
}

// httpClient returns the shared local-only client for auxiliary calls
// (embeddings, extraction). Built per call rather than cached because these are
// infrequent and a fresh client carries no cross-request state.
func (s *Service) httpClient() *http.Client {
	return newLocalClient(60 * time.Second)
}
