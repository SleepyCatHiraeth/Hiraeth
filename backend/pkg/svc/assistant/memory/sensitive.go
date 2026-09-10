package memory

import (
	"math"
	"regexp"
	"strings"
)

// Secret detection runs before anything is written. A hit means the candidate is
// DROPPED, not stored-and-flagged: a credential that reaches the database has
// already leaked into a file, a backup and any future export, and marking it
// sensitive afterwards does not undo that.
//
// The drop is logged without the payload, so the audit trail records that
// something was refused without becoming the leak it prevented.

var secretPatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)-----BEGIN [A-Z ]*PRIVATE KEY-----`),
	regexp.MustCompile(`(?i)\b(api[_-]?key|secret[_-]?key|access[_-]?token|auth[_-]?token|bearer|client[_-]?secret)\b\s*[:=]\s*\S{8,}`),
	regexp.MustCompile(`(?i)\bpassword\b\s*[:=]\s*\S{4,}`),
	regexp.MustCompile(`\bsk-[A-Za-z0-9_-]{16,}\b`),                     // OpenAI-style
	regexp.MustCompile(`\bghp_[A-Za-z0-9]{20,}\b`),                      // GitHub PAT
	regexp.MustCompile(`\bxox[baprs]-[A-Za-z0-9-]{10,}\b`),              // Slack
	regexp.MustCompile(`\bAKIA[0-9A-Z]{16}\b`),                          // AWS access key id
	regexp.MustCompile(`\bAIza[0-9A-Za-z_-]{35}\b`),                     // Google API key
	regexp.MustCompile(`\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.`), // JWT
	// A seed phrase is 12 or 24 lowercase words; catching the shape is enough
	// to refuse, and a false positive only costs one declined memory.
	regexp.MustCompile(`(?i)\b(seed|recovery|mnemonic)\s+phrase\b`),
	regexp.MustCompile(`\b(?:\d[ -]?){13,19}\b`),           // payment card shape
	regexp.MustCompile(`\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b`), // IBAN shape
}

// IsSensitive reports whether content must never be stored, and why.
func IsSensitive(content string) (bool, string) {
	for _, re := range secretPatterns {
		if re.MatchString(content) {
			return true, "matched a credential or account-number pattern"
		}
	}
	// A long, high-entropy unbroken token is a credential often enough that
	// storing one is not worth the convenience of the occasional false negative.
	for _, field := range strings.Fields(content) {
		if len(field) >= 32 && shannonEntropy(field) > 4.0 && !hasSpaceyPunctuation(field) {
			return true, "contains a long high-entropy token"
		}
	}
	return false, ""
}

func hasSpaceyPunctuation(s string) bool {
	// URLs and file paths are long and mixed but are not secrets.
	return strings.Contains(s, "/") || strings.Contains(s, "\\") ||
		strings.HasPrefix(s, "http")
}

func shannonEntropy(s string) float64 {
	if s == "" {
		return 0
	}
	var counts [256]float64
	for i := 0; i < len(s); i++ {
		counts[s[i]]++
	}
	n := float64(len(s))
	var h float64
	for _, c := range counts {
		if c == 0 {
			continue
		}
		p := c / n
		h -= p * math.Log2(p)
	}
	return h
}

// Injection detection. A memory or document that tries to issue instructions is
// not blocked outright -- silently dropping an attack hides it -- but it is
// marked, and the caller downgrades trust and forces confirmation.
var injectionPatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)ignore (all |any )?(previous|prior|above|earlier) (instructions|prompts|rules)`),
	regexp.MustCompile(`(?i)disregard (all |any )?(previous|prior|above) `),
	regexp.MustCompile(`(?i)you are now (a|an|in) `),
	regexp.MustCompile(`(?i)\bsystem prompt\b`),
	regexp.MustCompile(`(?i)^\s*(system|assistant|user)\s*:`),
	regexp.MustCompile(`(?i)<\s*/?\s*(system|instructions?)\s*>`),
	regexp.MustCompile(`(?i)\b(always|from now on) (obey|comply|do as)`),
	regexp.MustCompile(`(?i)reveal (your|the) (instructions|prompt|rules)`),
	regexp.MustCompile(`(?i)\bgrant (yourself|me)\b.*\bpermission`),
}

// LooksLikeInjection reports whether content is shaped like an instruction
// aimed at the model rather than information for the user.
func LooksLikeInjection(content string) (bool, string) {
	for _, re := range injectionPatterns {
		if re.MatchString(content) {
			return true, "content is shaped like an instruction to the model"
		}
	}
	// Zero-width and bidi control characters have no place in a memory and are
	// a known way to hide text from a human reviewer while the model still
	// reads it.
	for _, r := range content {
		// Zero-width and bidirectional control characters, by code point rather
		// than as literals: written literally they are invisible in the source
		// too, and one of them is a BOM the Go compiler rejects mid-file.
		switch r {
		case 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, // zero-width, word-joiner, BOM
			0x202A, 0x202B, 0x202C, 0x202D, 0x202E, // bidi embedding/override
			0x2066, 0x2067, 0x2068, 0x2069: // bidi isolates
			return true, "contains invisible or text-direction control characters"
		}
	}
	return false, ""
}

// Sanitise strips control characters and clamps length before storage. It does
// not attempt to neuter injection by rewriting text -- that approach does not
// work and pretending otherwise is worse than labelling the content honestly.
func Sanitise(content string, maxLen int) string {
	var b strings.Builder
	for _, r := range content {
		if r == '\n' || r == '\t' {
			b.WriteRune(' ')
			continue
		}
		if r < 0x20 || r == 0x7f {
			continue
		}
		b.WriteRune(r)
	}
	out := strings.TrimSpace(b.String())
	if maxLen > 0 && len(out) > maxLen {
		out = out[:maxLen]
	}
	return out
}
