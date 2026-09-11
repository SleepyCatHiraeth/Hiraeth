package assistant

import (
	"encoding/json"
	"fmt"
	"mime"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
	"unicode"
)

// Email drafting. Stage 4, and deliberately only half of it.
//
// The assistant writes a draft to disk and returns the path. It does not send,
// and it does not open anything: no mail client, no xdg-email, no browser.
// Sending needs a Secret Service provider this machine does not have, and the
// user's decision on 2026-09-10 was drafting now and sending in a later patch.
// So the entire output of this feature is a file, which the user opens
// themselves, having read it.
//
// The interesting risk here is not formatting. `to` and `subject` arrive from a
// language model's output, and headers are newline-delimited: a newline inside
// either lets the model invent headers the user never sees -- a Bcc to somewhere
// else, a Reply-To, or an early blank line that turns the rest of the "subject"
// into the body. That is the email equivalent of the `bash -c` defect this
// assistant was built to avoid.
//
// The rule is therefore to REFUSE a header containing a control character
// rather than escape it. An escaped draft is a guess about what was meant; a
// refused one is recoverable, and the user finds out.

const maxDraftBody = 64 << 10

// headerSafe rejects any control character in a header value.
//
// Not just \r and \n: a bare NUL or an escape can confuse whatever the user
// eventually opens the file with, and nothing legitimate in a subject line needs
// one. Unicode line separators count too, because some parsers treat them as
// line breaks.
func headerSafe(field, value string) error {
	for _, r := range value {
		// unicode.IsControl covers C0 AND C1 -- the first version missed
		// U+0080..U+009F, and U+0085 NEL in particular is treated as a line
		// break by Unicode-aware consumers, so it reopened header injection
		// against anything that is not byte-oriented.
		if unicode.IsControl(r) && r != '\t' || r == 0x2028 || r == 0x2029 {
			return fmt.Errorf("%s contains a control character (%U); refusing rather than guessing what was meant", field, r)
		}
	}
	return nil
}

// A single address, conservatively. Multiple recipients are a decision for the
// user's mail client, not something to extract from speech: a comma in a
// dictated name should not quietly become a second recipient.
var addressPattern = regexp.MustCompile(`^[^\s@,<>"]+@[^\s@,<>".]+\.[^\s@,<>"]+$`)

var slugUnsafe = regexp.MustCompile(`[^a-z0-9]+`)

// slug builds the filename portion from the subject.
//
// Everything outside [a-z0-9-] goes, so a subject of "../../etc/passwd" cannot
// contribute a path separator. The result is still checked against the drafts
// directory afterwards, because a filename rule that is only enforced by a
// regular expression is one refactor away from not being enforced at all.
func slug(subject string) string {
	s := slugUnsafe.ReplaceAllString(strings.ToLower(subject), "-")
	s = strings.Trim(s, "-")
	if len(s) > 60 {
		s = s[:60]
		s = strings.Trim(s, "-")
	}
	if s == "" {
		return "untitled"
	}
	return s
}

func (s *Service) draftsDir() string {
	data := os.Getenv("XDG_DATA_HOME")
	if data == "" {
		home, _ := os.UserHomeDir()
		data = filepath.Join(home, ".local", "share")
	}
	return filepath.Join(data, "ambxst", "assistant", "drafts")
}

// draftEmail writes an RFC 5322 message and returns where it went.
func (s *Service) draftEmail(params json.RawMessage) (any, error) {
	// Drafting is something the assistant DOES, so the master switch governs it.
	s.mu.Lock()
	enabled := s.cfg.Enabled
	s.mu.Unlock()
	if !enabled {
		return nil, fmt.Errorf("the turret assistant is off; turn it on in Settings")
	}

	var p struct {
		To      string `json:"to"`
		Subject string `json:"subject"`
		Body    string `json:"body"`
	}
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, err
	}

	// Validated BEFORE trimming. Trimming first silently removed a trailing
	// CRLF or NEL instead of refusing it, which turns a refusal rule into a
	// cleanup rule -- and the whole point is that the user finds out.
	if err := headerSafe("recipient", p.To); err != nil {
		return nil, err
	}
	if err := headerSafe("subject", p.Subject); err != nil {
		return nil, err
	}

	p.To = strings.TrimSpace(p.To)
	p.Subject = strings.TrimSpace(p.Subject)

	if err := headerSafe("recipient", p.To); err != nil {
		return nil, err
	}
	if err := headerSafe("subject", p.Subject); err != nil {
		return nil, err
	}
	if !addressPattern.MatchString(p.To) {
		return nil, fmt.Errorf("%q is not a single plain email address; add more recipients in your mail client", p.To)
	}
	if p.Subject == "" {
		return nil, fmt.Errorf("a subject is required")
	}
	if len(p.Body) > maxDraftBody {
		return nil, fmt.Errorf("body is %d bytes, over the %d-byte limit for a draft", len(p.Body), maxDraftBody)
	}

	dir := s.draftsDir()
	// 0700: a draft is correspondence, and it sits in the user's data dir.
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}

	name := fmt.Sprintf("%s-%s.eml", time.Now().Format("20060102-150405"), slug(p.Subject))
	path := filepath.Join(dir, name)
	// Belt and braces on the slug: confirm the path really is inside the drafts
	// directory before writing to it.
	if rel, err := filepath.Rel(dir, path); err != nil || strings.HasPrefix(rel, "..") || strings.ContainsRune(rel, os.PathSeparator) {
		return nil, fmt.Errorf("refusing to write outside the drafts directory")
	}

	// RFC 2047 for the subject so a non-ASCII one survives, and an explicit
	// charset on the body so the user's own name is not mangled by whatever
	// opens the file.
	var b strings.Builder
	b.WriteString("To: " + p.To + "\r\n")
	b.WriteString("Subject: " + mime.QEncoding.Encode("utf-8", p.Subject) + "\r\n")
	b.WriteString("Date: " + time.Now().Format(time.RFC1123Z) + "\r\n")
	b.WriteString("MIME-Version: 1.0\r\n")
	b.WriteString("Content-Type: text/plain; charset=utf-8\r\n")
	b.WriteString("Content-Transfer-Encoding: 8bit\r\n")
	b.WriteString("X-Ambxst-Draft: turret-assistant\r\n")
	b.WriteString("\r\n")
	// Normalise to LF first. Replacing every LF with CRLF turned an existing
	// \r\n into \r\r\n, so pasted Windows correspondence came out malformed.
	body := strings.ReplaceAll(p.Body, "\r\n", "\n")
	body = strings.ReplaceAll(body, "\r", "\n")
	b.WriteString(strings.ReplaceAll(body, "\n", "\r\n"))
	if !strings.HasSuffix(p.Body, "\n") {
		b.WriteString("\r\n")
	}

	// O_EXCL, and never through a symlink.
	//
	// os.WriteFile truncates whatever is already there, follows a final
	// symlink, and leaves an existing file's mode alone. So two drafts sharing
	// a slug in one second silently destroyed the first, an existing 0644
	// target stayed world-readable after being overwritten, and a predictable
	// symlink would have sent correspondence outside the drafts directory --
	// which the lexical path check cannot see.
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return nil, fmt.Errorf("could not create the draft (a file may already exist at %s): %w", path, err)
	}
	if _, err := f.WriteString(b.String()); err != nil {
		f.Close()
		return nil, err
	}
	if err := f.Close(); err != nil {
		return nil, err
	}

	// The path, never the contents: this is correspondence, and the log rule
	// for this package is that content stays out of it.
	logEvent("email draft written (%d bytes)", b.Len())
	return map[string]any{"path": path, "bytes": b.Len()}, nil
}
