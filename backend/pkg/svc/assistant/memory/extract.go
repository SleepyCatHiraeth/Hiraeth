package memory

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

// Embed asks the local model server for a vector. Endpoint validation is the
// caller's job; this package never decides what is a safe address.
func Embed(ctx context.Context, endpoint, model, text string) ([]float32, error) {
	body, err := json.Marshal(map[string]any{"model": model, "input": text})
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		endpoint+"/embeddings", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := (&http.Client{Timeout: 30 * time.Second}).Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("embeddings returned %s", resp.Status)
	}
	var out struct {
		Data []struct {
			Embedding []float32 `json:"embedding"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	if len(out.Data) == 0 || len(out.Data[0].Embedding) == 0 {
		return nil, fmt.Errorf("embeddings returned no vector")
	}
	return out.Data[0].Embedding, nil
}

// Candidate is a proposed memory, before any policy has been applied.
type Candidate struct {
	Category   string  `json:"category"`
	Content    string  `json:"content"`
	Confidence float64 `json:"confidence"`
	Importance float64 `json:"importance"`
}

const extractPrompt = `You extract durable facts worth remembering about a user from one exchange.

Return ONLY a JSON array. No prose, no code fences. An empty array is the correct
answer when nothing is worth keeping, which is most of the time.

Each element: {"category": string, "content": string, "confidence": 0..1, "importance": 0..1}

Allowed categories:
  user_profile     who the user is
  preferences      how they like things done
  projects         what they are working on
  environment      their machine, tools, setup
  routines         recurring habits and schedules
  instructions     an explicit standing instruction they gave you
  important_facts  anything else durable and specific

Rules:
- Extract only what the USER stated about themselves. Never extract your own replies.
- One clear fact per element, written as a short third-person sentence.
- Do not extract questions, chit-chat, or anything true only right now.
- Never extract passwords, keys, tokens, card or account numbers.
- If the user said "remember that ...", use category instructions only when it
  tells you how to behave; otherwise pick the category that fits the content.`

// Extract asks the model for memory candidates. It is a text-to-JSON transform
// with no tool surface at all: the extraction model is never given the ability
// to act, only to propose, and everything it proposes is filtered afterwards.
func Extract(ctx context.Context, endpoint, model, userText, assistantText string) ([]Candidate, error) {
	convo := fmt.Sprintf("User said: %s\n\nAssistant replied: %s", userText, assistantText)

	body, err := json.Marshal(map[string]any{
		"model": model,
		"messages": []map[string]string{
			{"role": "system", "content": extractPrompt},
			{"role": "user", "content": convo + "\n\nJSON array only. /no_think"},
		},
		"max_tokens":  400,
		"temperature": 0.1,
		"stream":      false,
	})
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		endpoint+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := (&http.Client{Timeout: 60 * time.Second}).Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("extraction returned %s", resp.Status)
	}
	var out struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	if len(out.Choices) == 0 {
		return nil, nil
	}
	return parseCandidates(out.Choices[0].Message.Content), nil
}

var validCategories = map[string]bool{
	CatProfile: true, CatPreference: true, CatProject: true,
	CatEnvironment: true, CatRoutine: true, CatInstruction: true, CatFact: true,
}

// parseCandidates tolerates the model wrapping JSON in prose or fences, and
// discards anything that is not a well-formed candidate in a known category.
// A malformed extraction yields nothing rather than a guess.
func parseCandidates(raw string) []Candidate {
	s := strings.TrimSpace(raw)
	if i := strings.Index(s, "["); i >= 0 {
		if j := strings.LastIndex(s, "]"); j > i {
			s = s[i : j+1]
		}
	}
	var cands []Candidate
	if err := json.Unmarshal([]byte(s), &cands); err != nil {
		return nil
	}
	var out []Candidate
	for _, c := range cands {
		c.Content = Sanitise(c.Content, 500)
		if c.Content == "" || !validCategories[c.Category] {
			continue
		}
		if c.Confidence <= 0 || c.Confidence > 1 {
			c.Confidence = 0.6
		}
		if c.Importance <= 0 || c.Importance > 1 {
			c.Importance = 0.5
		}
		out = append(out, c)
		if len(out) >= 5 { // one exchange should not produce a flood
			break
		}
	}
	return out
}

// ToItem applies policy to a candidate and returns the item to store, or nil
// when the candidate must be refused outright.
//
// This is the single choke point between "the model suggested something" and
// "it is on disk", and it is where the package's two rules are enforced.
func ToItem(c Candidate, sourceType, sourceRef string) (*Item, string) {
	if bad, why := IsSensitive(c.Content); bad {
		return nil, "refused: " + why
	}

	it := &Item{
		Category:        c.Category,
		Content:         c.Content,
		SourceType:      sourceType,
		SourceReference: sourceRef,
		Confidence:      c.Confidence,
		Importance:      c.Importance,
		Sensitivity:     "none",
		Language:        "en",
		TrustLevel:      TrustDerived,
		Status:          StatusCandidate,
	}

	// Content from outside the conversation can never be trusted or automatic,
	// and can never become a standing instruction no matter what it claims.
	external := sourceType == "file" || sourceType == "email" || sourceType == "tool"
	if external {
		it.TrustLevel = TrustUntrusted
		if it.Category == CatInstruction {
			it.Category = CatFact
		}
	}

	if bad, why := LooksLikeInjection(c.Content); bad {
		it.TrustLevel = TrustUntrusted
		it.Status = StatusQuarantined
		return it, "quarantined: " + why
	}

	if it.Category == CatTemporary {
		it.ExpiresAt = time.Now().Add(24 * time.Hour).Unix()
	}

	if !RequiresConfirmation(it.Category, it.Sensitivity, it.Confidence) {
		it.Status = StatusActive
	}
	return it, ""
}
