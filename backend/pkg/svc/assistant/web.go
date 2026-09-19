package assistant

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Outbound web access for the research tools.
//
// This is the exact inverse of httpclient.go, and the two must be read
// together. That file guarantees the MODEL endpoint never leaves this machine;
// this one guarantees the tools never reach BACK INTO it. A tool that could
// fetch 127.0.0.1 or 192.168.x.x would hand a language model -- steered by
// whatever a web page says -- a probe into the local network, which is the
// SSRF shape the 2026-09-12 audit found in the link-preview service. That
// service is deliberately NOT reused here for that reason.
//
// Nothing below is shared with the link-preview client.

const (
	// A page is read for its text. Anything larger is a download, not a
	// document, and is cut off rather than buffered.
	maxFetchBytes = 512 * 1024
	// Redirects are followed, but each hop is re-validated. Three is enough
	// for canonicalisation and http->https without becoming a chain to follow
	// somewhere unexpected.
	maxRedirects = 3
	// Identifies the client honestly. A tool that lies about being a browser
	// is a tool whose traffic its operator cannot reason about.
	webUserAgent = "ambxst-turret/1.0 (local assistant; +https://ambxst.local)"
)

// errBlockedAddress reports a host the tools must not reach.
type errBlockedAddress struct {
	Host   string
	Reason string
}

func (e *errBlockedAddress) Error() string {
	return fmt.Sprintf("refusing to fetch %s: %s", e.Host, e.Reason)
}

// publicIP reports whether an address may be fetched.
//
// Everything that is not plainly public is refused: loopback, RFC1918,
// link-local, unique-local, carrier NAT, multicast and the unspecified
// address. The default is deny -- a new address class that Go does not yet
// classify should be refused, not allowed through by omission.
func publicIP(ip net.IP) error {
	switch {
	case ip == nil:
		return &errBlockedAddress{Host: "?", Reason: "unparseable address"}
	case ip.IsLoopback():
		return &errBlockedAddress{Host: ip.String(), Reason: "loopback"}
	case ip.IsPrivate():
		return &errBlockedAddress{Host: ip.String(), Reason: "private network"}
	case ip.IsLinkLocalUnicast(), ip.IsLinkLocalMulticast():
		return &errBlockedAddress{Host: ip.String(), Reason: "link-local"}
	case ip.IsMulticast():
		return &errBlockedAddress{Host: ip.String(), Reason: "multicast"}
	case ip.IsUnspecified():
		return &errBlockedAddress{Host: ip.String(), Reason: "unspecified address"}
	case ip.IsInterfaceLocalMulticast():
		return &errBlockedAddress{Host: ip.String(), Reason: "interface-local"}
	}
	// 100.64.0.0/10, carrier-grade NAT. Go has no helper for it, and it is
	// routable enough to reach a router's admin interface.
	if v4 := ip.To4(); v4 != nil && v4[0] == 100 && v4[1] >= 64 && v4[1] <= 127 {
		return &errBlockedAddress{Host: ip.String(), Reason: "carrier-grade NAT range"}
	}
	// IPv4-mapped IPv6 (::ffff:127.0.0.1) is checked above via To4(), which
	// unwraps it -- but an explicit note, because getting this wrong is the
	// classic bypass.
	return nil
}

// checkWebURL validates a URL before it is fetched. Applied to the first URL
// and again to every redirect target.
func checkWebURL(raw string) error {
	u, err := url.Parse(raw)
	if err != nil {
		return &errBlockedAddress{Host: raw, Reason: "unparseable URL"}
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return &errBlockedAddress{Host: raw, Reason: "scheme must be http or https"}
	}
	if u.User != nil {
		return &errBlockedAddress{Host: raw, Reason: "embedded credentials"}
	}
	if u.Hostname() == "" {
		return &errBlockedAddress{Host: raw, Reason: "no host"}
	}
	// A literal IP is decided here. A name is decided at dial time, where its
	// resolved answer is what gets checked -- validating a name here would be
	// checking one thing and connecting to another.
	if ip := net.ParseIP(u.Hostname()); ip != nil {
		return publicIP(ip)
	}
	return nil
}

// publicOnlyDial resolves an address, refuses every non-public answer, and
// returns the exact address to dial.
//
// Returning the resolved address is the whole point, for the same reason
// resolveLoopback does it: a resolver that answers public to the check and
// private to the dialler would defeat a check that validated a name and then
// handed the name on. DNS rebinding is exactly that attack.
func publicOnlyDial(ctx context.Context, network, addr string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return nil, &errBlockedAddress{Host: addr, Reason: "unparseable address"}
	}

	if ip := net.ParseIP(host); ip != nil {
		if err := publicIP(ip); err != nil {
			return nil, err
		}
		d := net.Dialer{Timeout: 10 * time.Second}
		return d.DialContext(ctx, network, net.JoinHostPort(ip.String(), port))
	}

	ips, err := net.DefaultResolver.LookupIPAddr(ctx, host)
	if err != nil {
		return nil, fmt.Errorf("resolving %s: %w", host, err)
	}
	if len(ips) == 0 {
		return nil, &errBlockedAddress{Host: host, Reason: "no addresses"}
	}
	// Every answer must be acceptable. Dialling the first public answer of a
	// set that also contains private ones would let a hostile resolver pick
	// which one the connection actually used.
	for _, a := range ips {
		if err := publicIP(a.IP); err != nil {
			return nil, err
		}
	}
	d := net.Dialer{Timeout: 10 * time.Second}
	return d.DialContext(ctx, network, net.JoinHostPort(ips[0].IP.String(), port))
}

// webClient builds the one client every web tool uses.
func webClient(timeout time.Duration) *http.Client {
	return &http.Client{
		Timeout: timeout,
		Transport: &http.Transport{
			DialContext:           publicOnlyDial,
			TLSHandshakeTimeout:   10 * time.Second,
			ResponseHeaderTimeout: 15 * time.Second,
			DisableKeepAlives:     true,
			Proxy:                 nil, // never inherit a proxy from the environment
		},
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= maxRedirects {
				return fmt.Errorf("too many redirects")
			}
			return checkWebURL(req.URL.String())
		},
	}
}

// fetchBody GETs a URL and returns at most maxFetchBytes of its body.
//
// The content type is checked before the body is read: a tool that asks for a
// document and is handed a 2 GB video should not discover that by buffering it.
func fetchBody(ctx context.Context, rawurl string, timeout time.Duration) (string, string, error) {
	if err := checkWebURL(rawurl); err != nil {
		return "", "", err
	}
	req, err := http.NewRequestWithContext(ctx, "GET", rawurl, nil)
	if err != nil {
		return "", "", err
	}
	req.Header.Set("User-Agent", webUserAgent)
	req.Header.Set("Accept", "text/html,application/xhtml+xml,text/plain,application/json;q=0.9")
	req.Header.Set("Accept-Language", "en")

	resp, err := webClient(timeout).Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return "", "", fmt.Errorf("http %d", resp.StatusCode)
	}
	ct := strings.ToLower(resp.Header.Get("Content-Type"))
	switch {
	case strings.Contains(ct, "text/html"),
		strings.Contains(ct, "application/xhtml"),
		strings.Contains(ct, "text/plain"),
		strings.Contains(ct, "application/json"):
	default:
		return "", "", fmt.Errorf("refusing content type %q", ct)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, maxFetchBytes))
	if err != nil {
		return "", "", err
	}
	return string(body), ct, nil
}
