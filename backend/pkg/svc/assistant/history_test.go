package assistant

import (
	"strings"
	"testing"
	"time"
	"unicode/utf8"
)

func TestConversationKeepsTheRecentPastOnly(t *testing.T) {
	var c conversation
	for i := 0; i < historyTurns+4; i++ {
		c.record("question", "answer")
	}
	if got := c.length(); got != historyTurns {
		t.Fatalf("kept %d exchanges, want at most %d", got, historyTurns)
	}
	if got := len(c.messages()); got != historyTurns*2 {
		t.Errorf("replayed %d messages, want %d", got, historyTurns*2)
	}
}

func TestConversationExpiresAfterSilence(t *testing.T) {
	var c conversation
	c.record("old question", "old answer")
	c.mu.Lock()
	c.turns[0].at = time.Now().Add(-historyIdleFor - time.Minute)
	c.mu.Unlock()

	if msgs := c.messages(); len(msgs) != 0 {
		t.Fatalf("a stale conversation must not be replayed, got %v", msgs)
	}
	c.record("new question", "new answer")
	if got := len(c.messages()); got != 2 {
		t.Errorf("a fresh exchange must be replayed, got %d messages", got)
	}
}

// A long answer fills a context window as effectively as many short ones.
func TestConversationHasACharacterCeiling(t *testing.T) {
	var c conversation
	long := strings.Repeat("x", historyChars)
	c.record("first", long)
	c.record("second", long)

	msgs := c.messages()
	total := 0
	for _, m := range msgs {
		total += len(m["content"])
	}
	if total > historyChars {
		t.Errorf("replayed %d characters, ceiling is %d", total, historyChars)
	}
	if len(msgs) == 0 || msgs[0]["content"] != "second" {
		t.Errorf("the ceiling must drop the oldest exchange, got %v", msgs)
	}
	if len(msgs) != 2 {
		t.Errorf("the newest exchange must survive trimming, got %d messages", len(msgs))
	}
}

func TestConversationIgnoresIncompleteExchanges(t *testing.T) {
	var c conversation
	c.record("question", "")
	c.record("", "answer")
	if got := c.length(); got != 0 {
		t.Errorf("an interrupted turn must not be recorded, got %d", got)
	}
}

// Switching the assistant off must not leave it able to quote what was said.
func TestReleaseForgetsTheConversation(t *testing.T) {
	s := &Service{state: StateIdle}
	s.cfg = defaultConfig()
	s.convo.record("question", "answer")
	s.release()
	if got := s.convo.length(); got != 0 {
		t.Errorf("release must forget the conversation, %d exchanges remain", got)
	}
}

func TestBuildMessagesOrdersPersonaMemoryHistoryPrompt(t *testing.T) {
	history := []map[string]string{
		{"role": "user", "content": "earlier"},
		{"role": "assistant", "content": "earlier reply"},
	}
	msgs := buildMessages("persona", "memory", history, "now")

	want := []string{"system", "system", "user", "assistant", "user"}
	if len(msgs) != len(want) {
		t.Fatalf("got %d messages, want %d: %v", len(msgs), len(want), msgs)
	}
	for i, role := range want {
		if msgs[i]["role"] != role {
			t.Errorf("message %d is %q, want %q", i, msgs[i]["role"], role)
		}
	}
	if !strings.HasPrefix(msgs[4]["content"], "now") {
		t.Errorf("the new question must come last, got %q", msgs[4]["content"])
	}
}

// Expiring each exchange by its own age deleted the start of a long ACTIVE
// conversation. The rule is "resumed after a gap is a new conversation", so the
// gap is measured from the last exchange.
func TestConversationDoesNotExpireWhileActive(t *testing.T) {
	var c conversation
	c.record("first", "answer")
	c.record("second", "answer")

	// The first exchange is older than the idle window, but the conversation
	// never went quiet.
	c.mu.Lock()
	c.turns[0].at = time.Now().Add(-historyIdleFor - time.Hour)
	c.mu.Unlock()

	if got := len(c.messages()); got != 4 {
		t.Errorf("an active conversation must keep its start, got %d messages", got)
	}
}

func TestConversationExpiresWhenTheLastExchangeIsStale(t *testing.T) {
	var c conversation
	c.record("first", "answer")
	c.record("second", "answer")
	c.mu.Lock()
	for i := range c.turns {
		c.turns[i].at = time.Now().Add(-historyIdleFor - time.Minute)
	}
	c.mu.Unlock()

	if got := len(c.messages()); got != 0 {
		t.Errorf("a conversation resumed after a long gap starts fresh, got %d", got)
	}
}

// Slicing at an arbitrary byte offset split characters, so a trimmed reply
// containing anything outside ASCII was replayed as invalid UTF-8.
func TestTrimToCutsOnRuneBoundaries(t *testing.T) {
	// Three-byte runes, so an arbitrary cut lands mid-character.
	long := strings.Repeat("日", 200)
	for _, n := range []int{10, 37, 100, 299} {
		got := trimTo(long, n)
		if !utf8.ValidString(got) {
			t.Errorf("trimTo(%d) produced invalid UTF-8", n)
		}
		if len(got) > n {
			t.Errorf("trimTo(%d) returned %d bytes, over budget", n, len(got))
		}
	}
}

func TestConversationCeilingKeepsValidUTF8(t *testing.T) {
	var c conversation
	c.record("question", strings.Repeat("日", historyChars))
	for _, m := range c.messages() {
		if !utf8.ValidString(m["content"]) {
			t.Error("replayed history must be valid UTF-8")
		}
	}
}
