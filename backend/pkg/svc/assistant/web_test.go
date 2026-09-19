package assistant

import (
	"net"
	"strings"
	"testing"
)

// The whole point of this client is that a web page cannot steer the assistant
// into the local network. These are the addresses an SSRF attempt reaches for.
func TestWebClientRefusesInternalAddresses(t *testing.T) {
	blocked := []string{
		"http://127.0.0.1/",
		"http://localhost/",
		"http://[::1]/",
		"http://10.0.0.5/",
		"http://192.168.1.1/",
		"http://172.16.0.1/",
		"http://169.254.169.254/latest/meta-data/", // cloud metadata
		"http://100.64.0.1/",                       // carrier NAT
		"http://0.0.0.0/",
		"http://[::ffff:127.0.0.1]/", // IPv4-mapped loopback
	}
	for _, raw := range blocked {
		// "localhost" is a name, so it is refused at dial time rather than by
		// the URL check; everything else is a literal and must fail here.
		if strings.Contains(raw, "localhost") {
			continue
		}
		if err := checkWebURL(raw); err == nil {
			t.Errorf("%s was allowed; it must be refused", raw)
		}
	}
}

// A name that resolves to a private address must be refused at dial time, not
// merely at URL-check time. This is the DNS-rebinding case.
func TestPublicIPRejectsResolvedPrivateAddresses(t *testing.T) {
	for _, s := range []string{"127.0.0.1", "::1", "10.1.2.3", "192.168.0.7", "169.254.1.1", "100.100.0.1", "224.0.0.1"} {
		if err := publicIP(net.ParseIP(s)); err == nil {
			t.Errorf("publicIP(%s) allowed an internal address", s)
		}
	}
	// A genuinely public address must still be allowed, or the tools are
	// useless rather than safe.
	for _, s := range []string{"1.1.1.1", "93.184.216.34", "2606:4700:4700::1111"} {
		if err := publicIP(net.ParseIP(s)); err != nil {
			t.Errorf("publicIP(%s) refused a public address: %v", s, err)
		}
	}
}

// Credentials and odd schemes are refused: file:// and gopher:// are classic
// ways to turn a fetcher into something else.
func TestWebURLPolicy(t *testing.T) {
	for _, raw := range []string{
		"file:///etc/passwd",
		"gopher://example.com/",
		"ftp://example.com/",
		"http://user:pass@example.com/",
		"http:///nohost",
		"not a url",
	} {
		if err := checkWebURL(raw); err == nil {
			t.Errorf("%q was allowed; it must be refused", raw)
		}
	}
	for _, raw := range []string{"https://en.wikipedia.org/wiki/France", "http://example.com/x?y=1"} {
		if err := checkWebURL(raw); err != nil {
			t.Errorf("%q was refused: %v", raw, err)
		}
	}
}

// Wikipedia's full-text search ranks by term frequency, so asking about a
// subject regularly puts a side article above the subject's own. Asking for
// the current version of a game returned a character article first, whose
// snippet named a 2023 update, and that was the answer the assistant gave.
func TestTitleClosenessRanksTheSubjectArticleFirst(t *testing.T) {
	query := "latest Genshin Impact update version"
	subject := titleCloseness(query, "Genshin Impact")
	for _, side := range []string{
		"Furina (Genshin Impact)",
		"Inazuma (Genshin Impact)",
		"List of Genshin Impact characters",
		"Bennett (Genshin Impact)",
	} {
		if titleCloseness(query, side) >= subject {
			t.Errorf("%q must not outrank the subject's own article", side)
		}
	}
	// An exact title match is the strongest signal there is.
	if titleCloseness("Genshin Impact", "Genshin Impact") <= subject {
		t.Error("an exact title match must score highest")
	}
}

// A Wikipedia article URL must be read through the extract API. Reading it as
// HTML returned 6000 characters of navigation and no article text at all.
func TestWikipediaURLsUseTheExtractAPI(t *testing.T) {
	api, ok := wikipediaPlainTextAPI("https://en.wikipedia.org/wiki/Genshin_Impact")
	if !ok {
		t.Fatal("a wikipedia article URL must be recognised")
	}
	for _, want := range []string{"action=query", "prop=extracts", "explaintext=1", "Genshin_Impact"} {
		if !strings.Contains(api, want) {
			t.Errorf("extract API URL is missing %q: %s", want, api)
		}
	}
	// Anything else is fetched normally.
	if _, ok := wikipediaPlainTextAPI("https://example.com/wiki/Thing"); ok {
		t.Error("a non-wikipedia host must not be routed to the extract API")
	}
}
