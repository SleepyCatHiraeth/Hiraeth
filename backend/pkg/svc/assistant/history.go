package assistant

import (
	"strings"
	"sync"
	"time"
)

// Conversation history.
//
// Every turn was independent: "what did I just ask you?" got a blank look, and
// a follow-up like "and the other one?" had nothing to refer to. That is not a
// model limitation, it is that nothing was ever sent back.
//
// Three properties matter more than the feature:
//
//   - It lives in memory only. Nothing here is written to disk, ever. The
//     memory store is the deliberate, reviewed, categorised path for anything
//     durable; this is scratch.
//   - It expires. A conversation resumed two hours later is a new conversation,
//     and silently carrying the old one into it is how an assistant says
//     something the user has long forgotten telling it.
//   - It is bounded twice, by turns and by characters, because a long answer is
//     as capable of filling the context window as many short ones.

const (
	historyTurns   = 6                // three exchanges each way
	historyChars   = 4000             // hard ceiling on what is replayed
	historyIdleFor = 30 * time.Minute // silence this long starts a new conversation
)

type exchange struct {
	user      string
	assistant string
	at        time.Time
}

type conversation struct {
	mu    sync.Mutex
	turns []exchange
}

// record appends one completed exchange, dropping the oldest when full.
func (c *conversation) record(user, assistant string) {
	user, assistant = strings.TrimSpace(user), strings.TrimSpace(assistant)
	if user == "" || assistant == "" {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.turns = append(c.turns, exchange{user: user, assistant: assistant, at: time.Now()})
	if len(c.turns) > historyTurns {
		c.turns = c.turns[len(c.turns)-historyTurns:]
	}
}

// messages returns the replayable history, newest last, dropping anything older
// than the idle window and trimming from the front to stay under the ceiling.
func (c *conversation) messages() []map[string]string {
	c.mu.Lock()
	defer c.mu.Unlock()

	cutoff := time.Now().Add(-historyIdleFor)
	fresh := c.turns[:0:0]
	for _, t := range c.turns {
		if t.at.After(cutoff) {
			fresh = append(fresh, t)
		}
	}
	c.turns = fresh

	// Walk backwards so the ceiling drops the oldest, not the most relevant.
	total := 0
	first := len(fresh)
	for i := len(fresh) - 1; i >= 0; i-- {
		size := len(fresh[i].user) + len(fresh[i].assistant)
		if total+size > historyChars {
			break
		}
		total += size
		first = i
	}

	// A single exchange can exceed the ceiling on its own -- one long answer
	// does it -- and dropping everything then would leave a follow-up question
	// with no context at all. Keep the newest, trimmed to fit.
	if first == len(fresh) && len(fresh) > 0 {
		last := fresh[len(fresh)-1]
		room := historyChars - len(last.user)
		if room < 0 {
			room = 0
		}
		last.assistant = trimTo(last.assistant, room)
		last.user = trimTo(last.user, historyChars)
		fresh = []exchange{last}
		first = 0
	}

	out := make([]map[string]string, 0, (len(fresh)-first)*2)
	for _, t := range fresh[first:] {
		out = append(out,
			map[string]string{"role": "user", "content": t.user},
			map[string]string{"role": "assistant", "content": t.assistant},
		)
	}
	return out
}

// forget drops the conversation. Called when the assistant is switched off, so
// "off" means what it says, and available to the user as an explicit action.
func (c *conversation) forget() {
	c.mu.Lock()
	c.turns = nil
	c.mu.Unlock()
}

// trimTo cuts from the front: the end of an answer is the part a follow-up
// question is most likely to be about.
func trimTo(s string, n int) string {
	if len(s) <= n {
		return s
	}
	const ellipsis = "…"
	if n <= len(ellipsis) {
		return ""
	}
	// The marker counts against the budget: it is what the model reads.
	return ellipsis + s[len(s)-(n-len(ellipsis)):]
}

func (c *conversation) length() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.turns)
}
