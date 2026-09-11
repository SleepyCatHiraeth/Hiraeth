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
		// Accepted here and checked again at dial time, where it is resolved
		// and every answer must be loopback. See localOnlyDial.
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
	_, err := resolveLoopback(context.Background(), addr)
	return err
}

// resolveLoopback checks an address and returns the exact address that must be
// dialled.
//
// Returning the resolved address is the point. An earlier version validated a
// name's DNS answers and then handed the NAME to the dialler, which resolved it
// a second time -- so a resolver that answered loopback to the check and
// something else to the dialler would have sent the transcript off the machine.
// Validating one answer and connecting to another is not a check at all.
func resolveLoopback(ctx context.Context, addr string) ([]string, error) {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return nil, &LocalOnlyError{URL: addr, Reason: "unparseable address"}
	}
	if ip := net.ParseIP(host); ip != nil {
		if !ip.IsLoopback() {
			return nil, &LocalOnlyError{URL: addr, Reason: "dialled address is not loopback"}
		}
		return []string{addr}, nil
	}

	// A name reaches here unresolved, so "localhost" -- which checkURL accepts
	// and the settings panel documents -- was refused at dial time and could
	// never connect. Resolve it under the request's own context, so a wedged
	// resolver cannot outlive the request that needed it.
	addrs, err := net.DefaultResolver.LookupIPAddr(ctx, host)
	if err != nil {
		return nil, &LocalOnlyError{URL: addr, Reason: "host does not resolve"}
	}
	if len(addrs) == 0 {
		return nil, &LocalOnlyError{URL: addr, Reason: "host resolves to nothing"}
	}
	// Every answer must be loopback: one non-loopback record is enough to make
	// the destination unsafe, and which record a dialler would pick is not ours
	// to predict.
	//
	// All of them are returned, not just the first. "localhost" commonly
	// resolves to both ::1 and 127.0.0.1 while a server listens on only one, so
	// pinning to one answer turns a working endpoint into a refused connection
	// -- which is exactly the bug this whole path exists to fix.
	out := make([]string, 0, len(addrs))
	for _, a := range addrs {
		if !a.IP.IsLoopback() {
			return nil, &LocalOnlyError{URL: addr, Reason: "host resolves to a non-loopback address"}
		}
		out = append(out, net.JoinHostPort(a.IP.String(), port))
	}
	return out, nil
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
				// Resolve and validate once, then connect to the literal that
				// was validated. Handing the name back to the dialler would let
				// it resolve again and reach somewhere else.
				checked, err := resolveLoopback(ctx, addr)
				if err != nil {
					return nil, err
				}
				// Try each validated literal in turn, as the standard dialler
				// would for a name -- but only ever the literals this policy
				// approved.
				var lastErr error
				for _, target := range checked {
					conn, err := dialer.DialContext(ctx, network, target)
					if err == nil {
						return conn, nil
					}
					lastErr = err
				}
				return nil, lastErr
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
