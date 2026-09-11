package assistant

import (
	"encoding/json"
	"fmt"
	"mime"
	"net/mail"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func draftService(t *testing.T) *Service {
	t.Helper()
	t.Setenv("XDG_DATA_HOME", t.TempDir())
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig()
	s.cfg.Enabled = true // drafting is an action, so the master switch gates it
	return s
}

func draft(t *testing.T, s *Service, to, subject, body string) (map[string]any, error) {
	t.Helper()
	params, err := json.Marshal(map[string]string{"to": to, "subject": subject, "body": body})
	if err != nil {
		t.Fatal(err)
	}
	res, err := s.draftEmail(params)
	if err != nil {
		return nil, err
	}
	return res.(map[string]any), nil
}

func TestDraftRoundTripsAsRealMail(t *testing.T) {
	s := draftService(t)
	res, err := draft(t, s, "someone@example.com", "About the water filter", "It is due this month.\nSecond line.")
	if err != nil {
		t.Fatal(err)
	}

	path := res["path"].(string)
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	msg, err := mail.ReadMessage(f)
	if err != nil {
		t.Fatalf("the draft is not parseable as mail: %v", err)
	}
	if got := msg.Header.Get("To"); got != "someone@example.com" {
		t.Errorf("To = %q", got)
	}
	if got := msg.Header.Get("Subject"); !strings.Contains(got, "water filter") {
		t.Errorf("Subject = %q", got)
	}
}

// The real risk: `to` and `subject` come from a language model, and headers are
// newline-delimited. A newline lets the model invent headers the user never
// sees -- a Bcc elsewhere, a Reply-To, or a blank line that turns the rest of
// the subject into the body.
func TestDraftRefusesHeaderInjection(t *testing.T) {
	s := draftService(t)

	injections := []string{
		"a@b.com\r\nBcc: attacker@elsewhere.test",
		"a@b.com\nBcc: attacker@elsewhere.test",
		"a@b.com\rReply-To: attacker@elsewhere.test",
		"a@b.com\x00",
		"a@b.com\u0085X-Injected: yes", // NEL: a line break to Unicode-aware readers
		"a@b.com\u2028X-Injected: yes",
		"a@b.com\r\n", // trailing, and must be refused not trimmed
		"a@b.com Bcc: attacker@elsewhere.test",
	}
	for _, to := range injections {
		if _, err := draft(t, s, to, "Subject", "body"); err == nil {
			t.Errorf("recipient injection accepted: %q", to)
		}
	}
	for _, subject := range injections {
		if _, err := draft(t, s, "someone@example.com", subject, "body"); err == nil {
			t.Errorf("subject injection accepted: %q", subject)
		}
	}

	// And nothing was written while refusing.
	entries, err := os.ReadDir(s.draftsDir())
	if err == nil && len(entries) != 0 {
		t.Errorf("a refused draft still wrote %d file(s)", len(entries))
	}
}

// A comma in a dictated name must not quietly become a second recipient.
func TestDraftRefusesAnythingButOnePlainAddress(t *testing.T) {
	s := draftService(t)
	for _, to := range []string{
		"a@b.com, c@d.com",
		"Someone <a@b.com>",
		"not-an-address",
		"a@b",
		"",
	} {
		if _, err := draft(t, s, to, "Subject", "body"); err == nil {
			t.Errorf("accepted %q as a single address", to)
		}
	}
}

// A draft that mangles the user's own name is worse than no draft.
func TestDraftKeepsNonASCIIIntact(t *testing.T) {
	s := draftService(t)
	res, err := draft(t, s, "someone@example.com", "Grüße von Hiraeth — 日本語", "Körper mit Umlauten: äöü\n")
	if err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(res["path"].(string))
	if err != nil {
		t.Fatal(err)
	}
	f, err := os.Open(res["path"].(string))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	msg, err := mail.ReadMessage(f)
	if err != nil {
		t.Fatal(err)
	}
	dec := new(mime.WordDecoder)
	subject, err := dec.DecodeHeader(msg.Header.Get("Subject"))
	if err != nil {
		t.Fatal(err)
	}
	if subject != "Grüße von Hiraeth — 日本語" {
		t.Errorf("subject did not survive: %q", subject)
	}
	if !strings.Contains(string(raw), "äöü") {
		t.Error("body lost its non-ASCII characters")
	}
	if !strings.Contains(string(raw), "charset=utf-8") {
		t.Error("no charset declared, so whatever opens this may guess wrong")
	}
}

func TestDraftRefusesAnOversizedBody(t *testing.T) {
	s := draftService(t)
	_, err := draft(t, s, "someone@example.com", "Long", strings.Repeat("x", maxDraftBody+1))
	if err == nil {
		t.Fatal("an oversized body must be refused")
	}
	if !strings.Contains(err.Error(), "limit") {
		t.Errorf("the error should say what the limit is: %v", err)
	}
}

// The subject reaches the filename, so it must not reach the path.
func TestDraftSubjectCannotEscapeTheDirectory(t *testing.T) {
	s := draftService(t)
	res, err := draft(t, s, "someone@example.com", "../../../../etc/passwd", "body")
	if err != nil {
		t.Fatal(err)
	}
	path := res["path"].(string)
	dir := s.draftsDir()
	if filepath.Dir(path) != dir {
		t.Fatalf("draft escaped to %q, outside %q", path, dir)
	}
	if strings.Contains(filepath.Base(path), "/") || strings.Contains(filepath.Base(path), "..") {
		t.Errorf("filename carries path syntax: %q", filepath.Base(path))
	}
}

// Correspondence, in the user's data directory.
func TestDraftFilePermissions(t *testing.T) {
	s := draftService(t)
	res, err := draft(t, s, "someone@example.com", "Modes", "body")
	if err != nil {
		t.Fatal(err)
	}
	fi, err := os.Stat(res["path"].(string))
	if err != nil {
		t.Fatal(err)
	}
	if mode := fi.Mode().Perm(); mode != 0o600 {
		t.Errorf("draft mode %o, want 600", mode)
	}
	di, err := os.Stat(s.draftsDir())
	if err != nil {
		t.Fatal(err)
	}
	if mode := di.Mode().Perm(); mode != 0o700 {
		t.Errorf("drafts directory mode %o, want 700", mode)
	}
}

// Nothing here may send or launch anything; the whole output is a file.
func TestDraftReturnsOnlyAPath(t *testing.T) {
	s := draftService(t)
	res, err := draft(t, s, "someone@example.com", "Quiet", "body")
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := res["path"].(string); !ok {
		t.Fatal("no path returned")
	}
	if len(res) != 2 {
		t.Errorf("unexpected extra fields in the result: %v", res)
	}
	_ = fmt.Sprint(res)
}
