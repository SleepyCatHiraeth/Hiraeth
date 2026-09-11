package assistant

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"ambxst/backend/pkg/svc/assistant/memory"
)

// Memory is opt-in and off by default. Nothing here opens a database until the
// user turns it on, so an assistant left at defaults writes nothing durable.

func (s *Service) memoryDir() string {
	base := os.Getenv("XDG_DATA_HOME")
	if base == "" {
		home, _ := os.UserHomeDir()
		base = filepath.Join(home, ".local", "share")
	}
	return filepath.Join(base, "ambxst", "assistant")
}

// store returns the open memory store, opening it on first use. Returns nil
// when memory is disabled -- every caller must handle that.
// useStore hands out the store and registers the caller with the shutdown wait
// group, so a disable cannot close the database underneath work that is still
// using it.
//
// Only work started through backgroundContext was tracked, which left every
// synchronous memory handler invisible to shutdown: one IPC connection could
// disable the assistant while another was mid-embedding on a confirmed memory,
// and release would close the store under it.
//
// Returns nil when memory is off or the service is shutting down; the returned
// function must always be called.
func (s *Service) useStore() (*memory.Store, func()) {
	s.bg.mu.Lock()
	if s.bg.closed {
		s.bg.mu.Unlock()
		return nil, func() {}
	}
	s.bg.wg.Add(1)
	s.bg.mu.Unlock()

	done := func() { s.bg.wg.Done() }
	st := s.store()
	if st == nil {
		done()
		return nil, func() {}
	}
	return st, done
}

func (s *Service) store() *memory.Store {
	// The whole open is done under the lock. Previously this checked, released,
	// opened, then re-took the lock, so two concurrent callers -- the settings
	// panel and the post-turn extraction are a realistic pair -- could each open
	// the encrypted database and leak whichever handle lost the assignment.
	s.mu.Lock()
	if !(s.cfg.Enabled && s.cfg.MemoryEnabled) {
		s.mu.Unlock()
		return nil
	}
	if s.mem != nil {
		st := s.mem
		s.mu.Unlock()
		return st
	}
	dir := s.memoryDir()
	st, err := memory.Open(dir)
	if err != nil {
		s.lastErr = "memory unavailable: " + err.Error()
		state := s.state // read under the lock; this used to be read outside it
		s.seq++
		s.mu.Unlock()
		s.setState(state, nil)
		return nil
	}
	s.mem = st
	s.mu.Unlock()
	return st
}

// defaultCategories is every category the extractor can produce, plus the two
// expiring ones.
//
// An earlier default enabled ONLY the two expiring categories -- which the
// extractor never emits -- so every memory the user confirmed was then excluded
// from retrieval. Memory appeared to work and did nothing.
//
// The invariant: anything the user explicitly confirms is eligible for
// retrieval unless they disable its category. Confirmation is the consent gate;
// category enablement is a filter, not a second gate.
func defaultCategories() map[string]bool {
	return map[string]bool{
		memory.CatTemporary:   true,
		memory.CatSummary:     true,
		memory.CatProfile:     true,
		memory.CatPreference:  true,
		memory.CatProject:     true,
		memory.CatEnvironment: true,
		memory.CatRoutine:     true,
		memory.CatInstruction: true,
		memory.CatFact:        true,
	}
}

// enabledCategories merges the user's choices onto the defaults.
//
// It used to return the configured map verbatim when it was non-empty, which
// made "absent" mean "disabled". Turning ONE category off from the settings
// panel would therefore have written a single-key map and silently disabled the
// other eight. Merging is what makes a per-category switch safe to build.
func (s *Service) enabledCategories() map[string]bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	out := defaultCategories()
	for k, v := range s.cfg.MemoryCategories {
		out[k] = v
	}
	return out
}

// recall fetches context for a prompt. Failures degrade to no memory rather
// than failing the turn: an assistant that cannot remember is still useful, one
// that refuses to answer is not.
func (s *Service) recall(ctx context.Context, cfg Config, prompt string) (string, []memory.Result) {
	st, release := s.useStore()
	defer release()
	if st == nil {
		return "", nil
	}

	q := memory.Query{
		Text:          prompt,
		Limit:         cfg.MemoryLimit,
		MinConfidence: cfg.MemoryMinConfidence,
		EnabledCats:   s.enabledCategories(),
	}
	// Embedding is best-effort; without it retrieval falls back to keyword
	// ranking, which is degraded but correct.
	if vec, err := memory.Embed(ctx, s.httpClient(), cfg.Endpoint, cfg.EmbedModel, prompt); err == nil {
		q.Vector = vec
		q.Model = cfg.EmbedModel
	}

	res, err := st.Retrieve(q)
	if err != nil || len(res) == 0 {
		return "", nil
	}
	return memory.FormatContext(res), res
}

// capture runs after a turn, proposing memories. Everything durable lands as a
// candidate awaiting confirmation; only expiring categories may activate
// themselves, and secrets never reach the database at all.
func (s *Service) capture(cfg Config, userText, replyText string) {
	st, release := s.useStore()
	defer release()
	if st == nil {
		return
	}

	// Tied to the service's background context so shutdown and disable can
	// cancel it. Previously this used context.Background(), so extraction kept
	// issuing HTTP requests for up to 90s after the turn was cancelled. The
	// caller also registers this goroutine before starting it, so a release
	// cannot slip between the two.
	ctx, done := s.backgroundContext(90 * time.Second)
	defer done()

	cands, err := memory.Extract(ctx, s.httpClient(), cfg.Endpoint, cfg.Model, userText, replyText)
	if err != nil || len(cands) == 0 {
		return
	}

	// The category switches are a consent gate, not a retrieval filter. They
	// were only consulted when building a retrieval query, so a category the
	// user had switched off was still extracted and written to disk -- it just
	// was not read back. The settings panel says "never stored and never
	// recalled", and the storing half of that was not true.
	allowed := s.enabledCategories()

	var pending int
	for _, c := range cands {
		if !allowed[c.Category] {
			continue // the user said not to remember this kind of thing
		}
		it, note := memory.ToItem(c, "conversation", "")
		if it == nil {
			continue // refused; the reason is deliberately not stored
		}
		// ToItem can reclassify: external content loses the instructions
		// category. Re-check, so a rewrite cannot land in a disabled category.
		if !allowed[it.Category] {
			continue
		}
		if err := st.Put(it); err != nil {
			continue
		}
		if it.Status == memory.StatusCandidate {
			pending++
		}
		if note == "" && it.Status == memory.StatusActive {
			s.embedOrRecord(ctx, st, it.ID, it.Content)
		}
	}
	if pending > 0 {
		s.refreshPending()
	}
}

// refreshPending recomputes the review-queue size from the store.
//
// An incrementing counter drifts the moment anything else writes a memory --
// an import, a restart, a second confirmation -- and a review badge that
// disagrees with the review list is worse than no badge. Counting the rows is
// cheap and cannot be wrong.
func (s *Service) refreshPending() {
	st, release := s.useStore()
	defer release()
	if st == nil {
		return
	}
	n := 0
	for _, status := range []string{memory.StatusCandidate, memory.StatusQuarantined} {
		items, err := st.List(status, "", 100)
		if err == nil {
			n += len(items)
		}
	}
	s.mu.Lock()
	changed := s.pendingMemories != n
	s.pendingMemories = n
	if changed {
		s.seq++
	}
	s.mu.Unlock()
	if changed {
		s.broadcast()
	}
}

// --- IPC ------------------------------------------------------------------

func (s *Service) memoryList(params json.RawMessage) (any, error) {
	st, release := s.useStore()
	defer release()
	if st == nil {
		return map[string]any{"enabled": false, "items": []any{}}, nil
	}
	var p struct {
		Status   string `json:"status"`
		Category string `json:"category"`
		Limit    int    `json:"limit"`
	}
	_ = json.Unmarshal(params, &p)
	items, err := st.List(p.Status, p.Category, p.Limit)
	if err != nil {
		return nil, err
	}
	return map[string]any{"enabled": true, "items": items}, nil
}

func (s *Service) memoryPending(_ json.RawMessage) (any, error) {
	st, release := s.useStore()
	defer release()
	if st == nil {
		return map[string]any{"items": []any{}}, nil
	}
	// Both statuses need a human decision, so both belong in the review queue.
	cands, err := st.List(memory.StatusCandidate, "", 50)
	if err != nil {
		return nil, err
	}
	quar, err := st.List(memory.StatusQuarantined, "", 50)
	if err != nil {
		return nil, err
	}
	items := append(cands, quar...)
	if items == nil {
		items = []*memory.Item{}
	}
	return map[string]any{"items": items}, nil
}

func (s *Service) memoryConfirm(params json.RawMessage) (any, error) {
	st, release := s.useStore()
	defer release()
	if st == nil {
		return nil, fmt.Errorf("memory is disabled")
	}
	var p struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, err
	}
	if err := st.Confirm(p.ID); err != nil {
		return nil, err
	}
	// Embed on confirmation rather than on capture, so vectors are only ever
	// computed for memories the user actually kept.
	//
	// In the background: this is an HTTP request to the model server with a
	// 30-second timeout, and it used to run inside the handler. Pressing
	// "Keep" on the review card could therefore freeze every shell module for
	// half a minute whenever the server was slow or down -- the same defect
	// fixed in `say` and `health`, hiding one layer further in.
	if it, err := st.Get(p.ID); err == nil {
		id, content := it.ID, it.Content
		// Its own store registration, not the handler's: this goroutine
		// outlives the handler, and the handler's `defer release()` would
		// otherwise let a disable close the database mid-embedding.
		bgStore, bgRelease := s.useStore()
		if bgStore != nil {
			if !s.goBackground(30*time.Second, func(ctx context.Context) {
				defer bgRelease()
				s.embedOrRecord(ctx, bgStore, id, content)
			}) {
				bgRelease()
			}
		}
	}
	s.refreshPending()
	return map[string]any{"confirmed": p.ID}, nil
}

func (s *Service) memoryCorrect(params json.RawMessage) (any, error) {
	st, release := s.useStore()
	defer release()
	if st == nil {
		return nil, fmt.Errorf("memory is disabled")
	}
	var p struct {
		ID      string `json:"id"`
		Content string `json:"content"`
	}
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, err
	}
	if p.Content == "" {
		return nil, fmt.Errorf("content required")
	}
	it, err := st.Correct(p.ID, memory.Sanitise(p.Content, 500))
	if err != nil {
		return nil, err
	}
	// A correction is a new row with new content, so it needs its own vector.
	// Without this the corrected memory is keyword-only and invisible to
	// semantic search, which is the opposite of what correcting it was for.
	//
	// In the background, like confirmation: this is a 30-second HTTP call to
	// the model server and it was holding the shell's shared request socket.
	bgStore, bgRelease := s.useStore()
	if bgStore != nil {
		id, content := it.ID, it.Content
		if !s.goBackground(30*time.Second, func(ctx context.Context) {
			defer bgRelease()
			s.embedOrRecord(ctx, bgStore, id, content)
		}) {
			bgRelease()
		}
	}
	s.broadcast()
	return it, nil
}

func (s *Service) memoryForget(params json.RawMessage) (any, error) {
	st, release := s.useStore()
	defer release()
	if st == nil {
		return nil, fmt.Errorf("memory is disabled")
	}
	var p struct {
		ID  string `json:"id"`
		All bool   `json:"all"`
	}
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, err
	}
	if p.All {
		n, err := st.DeleteAll()
		if err != nil {
			return nil, err
		}
		s.refreshPending()
		return map[string]any{"deleted": n}, nil
	}
	if err := st.Delete(p.ID); err != nil {
		return nil, err
	}
	s.refreshPending()
	return map[string]any{"deleted": 1}, nil
}

func (s *Service) memoryStats(_ json.RawMessage) (any, error) {
	st, release := s.useStore()
	defer release()
	if st == nil {
		return map[string]any{"enabled": false}, nil
	}
	stats, err := st.Stats()
	if err != nil {
		return nil, err
	}
	stats["enabled"] = true
	stats["categories"] = s.enabledCategories()
	s.refreshPending()
	return stats, nil
}

// How often expired memories are actually deleted, as opposed to merely
// filtered out of retrieval.
const expirySweepEvery = time.Hour

// memoryAudit returns the store's own history: what was remembered, confirmed,
// corrected, superseded, refused or forgotten, and when. It contains no memory
// text, so it is safe to show without unlocking anything.
func (s *Service) memoryAudit(params json.RawMessage) (any, error) {
	var p struct {
		Limit int `json:"limit"`
	}
	_ = json.Unmarshal(params, &p)

	st, release := s.useStore()
	defer release()
	if st == nil {
		return map[string]any{"enabled": false, "entries": []any{}}, nil
	}
	entries, err := st.Audit(p.Limit)
	if err != nil {
		return nil, err
	}
	return map[string]any{"enabled": true, "entries": entries}, nil
}

// sweepExpired deletes memories whose expiry has passed.
//
// Purge ran at startup and on demand only, so a session left running for days
// never re-purged: retrieval filtered expired rows out, but they stayed on disk
// indefinitely, which is not what "expires" means to the person who set it.
// Called from the health loop, which only runs while the assistant is on.
func (s *Service) sweepExpired() {
	st, release := s.useStore()
	defer release()
	if st == nil {
		return
	}
	s.mu.Lock()
	due := time.Since(s.lastSweep) >= expirySweepEvery
	if due {
		s.lastSweep = time.Now()
	}
	s.mu.Unlock()
	if !due {
		return
	}

	n, err := st.PurgeExpired()
	if err != nil {
		logEvent("expiry sweep failed: %v", err)
		return
	}
	if n > 0 {
		logEvent("expiry sweep removed %d memories", n)
		s.broadcast()
	}
}

// memoryExport returns everything as JSON. Deliberately a separate, explicit
// action, and the payload is plaintext -- the caller is told so.
func (s *Service) memoryExport(_ json.RawMessage) (any, error) {
	st, release := s.useStore()
	defer release()
	if st == nil {
		return nil, fmt.Errorf("memory is disabled")
	}
	items, err := st.List("", "", 500)
	if err != nil {
		return nil, err
	}
	return map[string]any{
		"warning":     "this export is plaintext and unencrypted",
		"exported_at": time.Now().Unix(),
		"items":       items,
	}, nil
}

// memoryImport brings items in as quarantined, untrusted candidates. An import
// can never introduce a standing instruction or an active memory: that would
// make a file the user was handed a way to program their assistant.
func (s *Service) memoryImport(params json.RawMessage) (any, error) {
	st, release := s.useStore()
	defer release()
	if st == nil {
		return nil, fmt.Errorf("memory is disabled")
	}
	var p struct {
		Items []memory.Item `json:"items"`
	}
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, err
	}
	var added, refused int
	for i := range p.Items {
		it := p.Items[i]
		it.ID = ""
		it.Content = memory.Sanitise(it.Content, 500)
		if bad, _ := memory.IsSensitive(it.Content); bad || it.Content == "" {
			refused++
			continue
		}
		if it.Category == memory.CatInstruction {
			it.Category = memory.CatFact
		}
		it.Status = memory.StatusQuarantined
		it.TrustLevel = memory.TrustUntrusted
		it.UserConfirmed = false
		it.SourceType = "import"
		if err := st.Put(&it); err == nil {
			added++
		}
	}
	s.refreshPending()
	return map[string]any{"imported": added, "refused": refused,
		"note": "imported items are quarantined until reviewed"}, nil
}

// embedOrRecord computes and stores a vector, recording any failure in state.
//
// Embedding used to fail silently: a stopped model server produced a memory
// with no vector, invisible to semantic search, indistinguishable from success.
// A degradation the user cannot see is worse than one they can.
func (s *Service) embedOrRecord(ctx context.Context, st *memory.Store, id, content string) {
	s.mu.Lock()
	cfg := s.cfg
	s.mu.Unlock()

	vec, err := memory.Embed(ctx, s.httpClient(), cfg.Endpoint, cfg.EmbedModel, content)
	if err != nil {
		s.mu.Lock()
		s.embedErr = "embedding unavailable, memory is keyword-only: " + err.Error()
		s.seq++
		s.mu.Unlock()
		s.broadcast()
		return
	}
	if err := st.PutEmbedding(id, cfg.EmbedModel, vec); err != nil {
		return
	}
	s.mu.Lock()
	cleared := s.embedErr != ""
	s.embedErr = ""
	s.mu.Unlock()
	if cleared {
		s.broadcast()
	}
}
