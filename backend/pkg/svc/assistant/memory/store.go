// Package memory implements the assistant's controlled long-term memory.
//
// Two rules shape the whole package and are worth stating before the code:
//
//  1. A memory is data, never an instruction. Retrieved memories are labelled
//     with their provenance and trust level and injected as quoted context, so a
//     sentence stored from a document can never become policy.
//  2. Nothing meaningful is stored without the user agreeing to it. Only
//     short-lived, expiring categories may be written automatically; everything
//     durable arrives as a candidate and waits.
//
// Storage reuses the encrypted SQLite already proven in this codebase for the
// clipboard: pure-Go driver, adiantum VFS, FTS5. Vector search is a Go-registered
// cosine function over an FTS5-narrowed candidate set, which at this corpus size
// is both faster to write and faster to run than an ANN index.
package memory

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	sqlite3 "github.com/ncruces/go-sqlite3"
	"github.com/ncruces/go-sqlite3/driver"
	"github.com/ncruces/go-sqlite3/ext/fts5"
	_ "github.com/ncruces/go-sqlite3/vfs/adiantum"
)

// Categories. Only the first two may ever be written without confirmation.
const (
	CatTemporary     = "temporary_context"
	CatSummary       = "conversation_summaries"
	CatProfile       = "user_profile"
	CatPreference    = "preferences"
	CatProject       = "projects"
	CatEnvironment   = "environment"
	CatRoutine       = "routines"
	CatInstruction   = "instructions" // procedural: ALWAYS requires confirmation
	CatFact          = "important_facts"
	CatFileDerived   = "file_derived"
	CatEmailDerived  = "email_derived"
	CatNegative      = "negative"
	CatDoNotRemember = "do_not_remember"
)

// Trust levels, highest first. Trust may be lowered automatically; raising it
// requires the user.
const (
	TrustUserStated    = "user_stated"
	TrustUserConfirmed = "user_confirmed"
	TrustDerived       = "derived"
	TrustUntrusted     = "untrusted"
)

// Status values.
const (
	StatusCandidate   = "candidate"
	StatusActive      = "active"
	StatusSuperseded  = "superseded"
	StatusQuarantined = "quarantined"
)

// autoSavable reports whether a category may be written without asking. The
// list is deliberately tiny and deliberately excludes instructions: a sentence
// in a conversation must never silently become standing policy.
func autoSavable(category string) bool {
	return category == CatTemporary || category == CatSummary
}

// RequiresConfirmation is the inverse, plus the always-confirm cases.
func RequiresConfirmation(category string, sensitivity string, confidence float64) bool {
	if category == CatInstruction {
		return true
	}
	if !autoSavable(category) {
		return true
	}
	if sensitivity != "none" {
		return true
	}
	return confidence < 0.8
}

// Item is one memory.
type Item struct {
	ID              string  `json:"id"`
	Category        string  `json:"category"`
	Content         string  `json:"content"`
	StructuredValue string  `json:"structured_value,omitempty"`
	SourceReference string  `json:"source_reference,omitempty"`
	SourceType      string  `json:"source_type"`
	CreatedAt       int64   `json:"created_at"`
	UpdatedAt       int64   `json:"updated_at"`
	LastAccessedAt  int64   `json:"last_accessed_at,omitempty"`
	ExpiresAt       int64   `json:"expires_at,omitempty"`
	Confidence      float64 `json:"confidence"`
	Importance      float64 `json:"importance"`
	UserConfirmed   bool    `json:"user_confirmed"`
	Sensitivity     string  `json:"sensitivity"`
	Language        string  `json:"language"`
	Supersedes      string  `json:"supersedes,omitempty"`
	Status          string  `json:"status"`
	TrustLevel      string  `json:"trust_level"`
}

const schemaSQL = `
PRAGMA foreign_keys = ON;
PRAGMA secure_delete = ON;
PRAGMA temp_store = MEMORY;

CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL);

CREATE TABLE IF NOT EXISTS memory (
  id                TEXT PRIMARY KEY,
  category          TEXT NOT NULL,
  content           TEXT NOT NULL,
  structured_value  TEXT,
  source_reference  TEXT,
  source_type       TEXT NOT NULL,
  created_at        INTEGER NOT NULL,
  updated_at        INTEGER NOT NULL,
  last_accessed_at  INTEGER,
  expires_at        INTEGER,
  confidence        REAL NOT NULL,
  importance        REAL NOT NULL,
  user_confirmed    INTEGER NOT NULL,
  sensitivity       TEXT NOT NULL,
  language          TEXT NOT NULL,
  supersedes        TEXT,
  status            TEXT NOT NULL,
  trust_level       TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS memory_status  ON memory(status);
CREATE INDEX IF NOT EXISTS memory_expires ON memory(expires_at);

CREATE TABLE IF NOT EXISTS embedding (
  memory_id  TEXT NOT NULL,
  model      TEXT NOT NULL,
  dim        INTEGER NOT NULL,
  vec        BLOB NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (memory_id, model)
);

-- Audit rows never contain memory plaintext: deleting a memory must not leave
-- its content behind in the log that recorded the deletion.
CREATE TABLE IF NOT EXISTS audit (
  ts        INTEGER NOT NULL,
  action    TEXT NOT NULL,
  memory_id TEXT,
  detail    TEXT
);

CREATE VIRTUAL TABLE IF NOT EXISTS memory_fts USING fts5(content, tokenize = 'porter');
`

// Schema version.
//
// The version row was written on creation and never read again, which meant two
// things could go wrong silently. A future version of this code could not tell
// an old database from a current one, and -- worse -- an OLDER binary opening a
// NEWER database would write into a schema it did not understand. The second is
// the one that loses data, and it is the reason this refuses rather than
// guesses.
const currentSchema = 1

// migrations[i] upgrades a database at version i+1 to version i+2. Empty today:
// version 1 is the first schema. A new migration is appended here, never
// inserted, and the CREATE TABLE statements in schemaSQL are updated to match
// so a fresh database is created at the current version directly.
var migrations []func(*sql.DB) error

func migrate(db *sql.DB) error {
	var version int
	err := db.QueryRow(`SELECT version FROM schema_version LIMIT 1`).Scan(&version)
	switch {
	case errors.Is(err, sql.ErrNoRows):
		// Fresh database, or one created before the version row existed.
		if _, err := db.Exec(`INSERT INTO schema_version(version) VALUES (?)`, currentSchema); err != nil {
			return err
		}
		return nil
	case err != nil:
		return err
	}

	if version > currentSchema {
		return fmt.Errorf(
			"memory database is at schema version %d but this build understands %d: "+
				"it was written by a newer AMBXST. Refusing to open it rather than "+
				"risk writing a schema this build does not understand",
			version, currentSchema)
	}

	for version < currentSchema {
		step := migrations[version-1]
		if err := step(db); err != nil {
			return fmt.Errorf("migrating memory database from version %d: %w", version, err)
		}
		version++
		if _, err := db.Exec(`UPDATE schema_version SET version = ?`, version); err != nil {
			return err
		}
	}
	return nil
}

// Store owns the encrypted database. Every access is serialised; this is a
// single-user assistant and lock contention is not the bottleneck.
type Store struct {
	mu     sync.Mutex
	db     *sql.DB
	dir    string
	closed bool
}

// Open creates or opens the memory database under dir, generating a 32-byte key
// on first use. Key file and database are 0600 inside a 0700 directory, matching
// the clipboard store's posture.
func Open(dir string) (*Store, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	dbPath := filepath.Join(dir, "memory.db")
	hexKey, err := loadOrCreateKey(filepath.Join(dir, "memory.key"), dbPath)
	if err != nil {
		return nil, err
	}

	u := url.URL{
		Scheme: "file",
		Path:   dbPath,
		RawQuery: url.Values{
			"vfs":    []string{"adiantum"},
			"hexkey": []string{hexKey},
		}.Encode(),
	}
	db, err := driver.Open(u.String(), func(conn *sqlite3.Conn) error {
		if err := fts5.Register(conn); err != nil {
			return err
		}
		// Cosine similarity as a SQL function. sqlite-vec cannot be loaded into
		// this WASM build, and at a few thousand rows a linear scan over an
		// FTS5-narrowed candidate set is comfortably fast enough.
		return conn.CreateFunction("cosine", 2, sqlite3.DETERMINISTIC, cosineSQL)
	})
	if err != nil {
		return nil, err
	}
	if _, err := db.Exec(schemaSQL); err != nil {
		db.Close()
		return nil, err
	}
	if err := migrate(db); err != nil {
		db.Close()
		return nil, err
	}
	// SQLite creates the file with the process umask, which lands at 0644 here.
	// The contents are encrypted and the parent is 0700, so this is
	// defence in depth rather than a hole -- but it is free, and the clipboard
	// store already sets the same mode.
	if err := os.Chmod(dbPath, 0o600); err != nil {
		db.Close()
		return nil, err
	}

	s := &Store{db: db, dir: dir}
	if _, err := s.purgeExpiredLocked(); err != nil {
		// Never fatal: a failed purge must not stop the assistant from starting.
		s.audit("purge_failed", "", err.Error())
	}
	return s, nil
}

// Close releases the database. Idempotent.
//
// The handle is deliberately NOT set to nil. Every method here dereferences
// s.db, so nil-ing it turned "used after close" -- which happens whenever a
// slow background embed outlives a disable -- into a nil dereference in a
// goroutine, which takes the whole daemon down. database/sql already returns
// "sql: database is closed" for calls after Close, so leaving the handle in
// place converts a panic into an error at all twenty-six call sites without
// touching any of them.
func (s *Store) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return nil
	}
	s.closed = true
	return s.db.Close()
}

// loadOrCreateKey reads the database key, creating one ONLY when there is no
// database to orphan.
//
// The previous version generated a fresh key whenever the file could not be
// read. If a database already existed -- the normal case -- that silently made
// every stored memory permanently undecryptable, turning a transient read error
// or a truncated file into total data loss. A missing key beside an existing
// database is a situation only the user can resolve, so it fails closed and
// says how to recover.
func loadOrCreateKey(path, dbPath string) (string, error) {
	data, readErr := os.ReadFile(path)
	if readErr == nil {
		if key := strings.TrimSpace(string(data)); len(key) == 64 {
			return key, nil
		}
		readErr = fmt.Errorf("key file is malformed (expected 64 hex characters)")
	}

	dbExists := false
	if fi, err := os.Stat(dbPath); err == nil && fi.Size() > 0 {
		dbExists = true
	}
	if dbExists {
		return "", fmt.Errorf(
			"memory key at %s is unusable (%v) but an encrypted database exists at %s. "+
				"Refusing to generate a new key, which would make every stored memory "+
				"permanently unreadable. Restore the key from a backup, or move the "+
				"database aside to start fresh",
			path, readErr, dbPath)
	}

	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	key := hex.EncodeToString(raw)
	// O_EXCL: never clobber a key that appeared between the read and the write.
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return "", fmt.Errorf("creating memory key: %w", err)
	}
	defer f.Close()
	if _, err := f.WriteString(key + "\n"); err != nil {
		return "", err
	}
	return key, nil
}

func newID() string {
	raw := make([]byte, 12)
	_, _ = rand.Read(raw)
	return hex.EncodeToString(raw)
}

func (s *Store) audit(action, id, detail string) {
	if s.db == nil {
		return
	}
	_, _ = s.db.Exec(`INSERT INTO audit(ts, action, memory_id, detail) VALUES(?,?,?,?)`,
		time.Now().Unix(), action, nullIfEmpty(id), detail)
}

func nullIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}

// Put writes an item. A candidate stays out of retrieval until confirmed.
func (s *Store) Put(it *Item) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.putLocked(it)
}

func (s *Store) putLocked(it *Item) error {
	if strings.TrimSpace(it.Content) == "" {
		return fmt.Errorf("empty memory content")
	}
	if it.ID == "" {
		it.ID = newID()
	}
	now := time.Now().Unix()
	if it.CreatedAt == 0 {
		it.CreatedAt = now
	}
	it.UpdatedAt = now
	if it.Status == "" {
		it.Status = StatusCandidate
	}
	if it.Sensitivity == "" {
		it.Sensitivity = "none"
	}
	if it.Language == "" {
		it.Language = "en"
	}
	if it.TrustLevel == "" {
		it.TrustLevel = TrustDerived
	}

	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`
	  INSERT INTO memory (id, category, content, structured_value, source_reference,
	    source_type, created_at, updated_at, last_accessed_at, expires_at, confidence,
	    importance, user_confirmed, sensitivity, language, supersedes, status, trust_level)
	  VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
	  ON CONFLICT(id) DO UPDATE SET
	    category=excluded.category, content=excluded.content,
	    structured_value=excluded.structured_value, updated_at=excluded.updated_at,
	    expires_at=excluded.expires_at, confidence=excluded.confidence,
	    importance=excluded.importance, user_confirmed=excluded.user_confirmed,
	    sensitivity=excluded.sensitivity, status=excluded.status,
	    trust_level=excluded.trust_level, supersedes=excluded.supersedes`,
		it.ID, it.Category, it.Content, nullIfEmpty(it.StructuredValue),
		nullIfEmpty(it.SourceReference), it.SourceType, it.CreatedAt, it.UpdatedAt,
		nullIfEmpty(""), zeroToNull(it.ExpiresAt), it.Confidence, it.Importance,
		boolToInt(it.UserConfirmed), it.Sensitivity, it.Language,
		nullIfEmpty(it.Supersedes), it.Status, it.TrustLevel); err != nil {
		return err
	}

	// FTS is a plain (non-external-content) table, so it is maintained here.
	if _, err := tx.Exec(`DELETE FROM memory_fts WHERE rowid = (
	    SELECT rowid FROM memory_fts WHERE content = ? LIMIT 1)`, it.Content); err != nil {
		return err
	}
	if _, err := tx.Exec(`INSERT INTO memory_fts(rowid, content)
	    VALUES ((SELECT rowid FROM memory WHERE id = ?), ?)`, it.ID, it.Content); err != nil {
		return err
	}

	if err := tx.Commit(); err != nil {
		return err
	}
	s.audit("put", it.ID, it.Category+"/"+it.Status)
	return nil
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

func zeroToNull(v int64) any {
	if v == 0 {
		return nil
	}
	return v
}

// Confirm promotes a candidate to active. This is the only path by which a
// durable memory becomes retrievable, and it raises trust, which is why it is a
// distinct operation rather than a field update.
func (s *Store) Confirm(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	// Quarantined items are confirmable too: quarantine means "a human must look
	// at this before it counts", and this IS that human looking at it. What
	// quarantine prevents is activation happening automatically.
	res, err := s.db.Exec(`UPDATE memory
	    SET status = ?, user_confirmed = 1, trust_level = ?, updated_at = ?
	    WHERE id = ? AND status IN (?, ?)`,
		StatusActive, TrustUserConfirmed, time.Now().Unix(), id,
		StatusCandidate, StatusQuarantined)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return fmt.Errorf("no reviewable memory with id %s", id)
	}
	s.audit("confirm", id, "")
	return nil
}

// Correct supersedes an item with new content, preserving history: the old row
// is kept and marked superseded rather than edited in place.
func (s *Store) Correct(id, content string) (*Item, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	old, err := s.getLocked(id)
	if err != nil {
		return nil, err
	}
	next := *old
	next.ID = newID()
	next.Content = content
	next.CreatedAt = 0
	next.Supersedes = old.ID
	next.Status = StatusActive
	next.UserConfirmed = true
	next.TrustLevel = TrustUserConfirmed
	if err := s.putLocked(&next); err != nil {
		return nil, err
	}
	if _, err := s.db.Exec(`UPDATE memory SET status = ?, updated_at = ? WHERE id = ?`,
		StatusSuperseded, time.Now().Unix(), old.ID); err != nil {
		return nil, err
	}
	s.audit("correct", next.ID, "supersedes "+old.ID)
	return &next, nil
}

// Delete removes an item outright, along with its embedding and FTS row.
// "Forget that" must actually forget, so this is a real DELETE and not a status
// change. Physical erasure from the underlying SSD is not guaranteed; see the
// wiki page for what that does and does not mean.
func (s *Store) Delete(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	n, err := deleteMemory(tx, id)
	if err != nil {
		return err
	}
	if n == 0 {
		return fmt.Errorf("no memory with id %s", id)
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	s.audit("delete", id, "")
	return nil
}

// DeleteAll erases everything. Used by the "clear memory" control.
func (s *Store) DeleteAll() (int64, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	res, err := s.db.Exec(`DELETE FROM memory`)
	if err != nil {
		return 0, err
	}
	_, _ = s.db.Exec(`DELETE FROM memory_fts`)
	_, _ = s.db.Exec(`DELETE FROM embedding`)
	_, _ = s.db.Exec(`VACUUM`)
	n, _ := res.RowsAffected()
	s.audit("delete_all", "", fmt.Sprint(n))
	return n, nil
}

// PurgeExpired removes items past their expiry. Called at startup and by the
// periodic sweep: expiry is enforced by deletion, not merely by filtering, so a
// forgotten memory does not linger in the file.
func (s *Store) PurgeExpired() (int64, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.purgeExpiredLocked()
}

// purgeExpiredLocked assumes the caller holds s.mu. Open() calls this during
// construction, before the store is shared, which is why the public wrapper
// exists separately rather than Open taking its own lock.
func (s *Store) purgeExpiredLocked() (int64, error) {
	now := time.Now().Unix()
	rows, err := s.db.Query(`SELECT id FROM memory WHERE expires_at IS NOT NULL AND expires_at <= ?`, now)
	if err != nil {
		return 0, err
	}
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err == nil {
			ids = append(ids, id)
		}
	}
	rows.Close()

	var n int64
	for _, id := range ids {
		if _, err := s.db.Exec(`DELETE FROM memory_fts WHERE rowid =
		    (SELECT rowid FROM memory WHERE id = ?)`, id); err != nil {
			continue
		}
		_, _ = s.db.Exec(`DELETE FROM embedding WHERE memory_id = ?`, id)
		if _, err := s.db.Exec(`DELETE FROM memory WHERE id = ?`, id); err == nil {
			n++
		}
	}
	if n > 0 {
		s.audit("purge_expired", "", fmt.Sprint(n))
	}
	return n, nil
}

func (s *Store) Get(id string) (*Item, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.getLocked(id)
}

const selectCols = `id, category, content, COALESCE(structured_value,''),
	COALESCE(source_reference,''), source_type, created_at, updated_at,
	COALESCE(last_accessed_at,0), COALESCE(expires_at,0), confidence, importance,
	user_confirmed, sensitivity, language, COALESCE(supersedes,''), status, trust_level`

func scanItem(sc interface{ Scan(...any) error }) (*Item, error) {
	var it Item
	var confirmed int
	if err := sc.Scan(&it.ID, &it.Category, &it.Content, &it.StructuredValue,
		&it.SourceReference, &it.SourceType, &it.CreatedAt, &it.UpdatedAt,
		&it.LastAccessedAt, &it.ExpiresAt, &it.Confidence, &it.Importance,
		&confirmed, &it.Sensitivity, &it.Language, &it.Supersedes, &it.Status,
		&it.TrustLevel); err != nil {
		return nil, err
	}
	it.UserConfirmed = confirmed != 0
	return &it, nil
}

func (s *Store) getLocked(id string) (*Item, error) {
	row := s.db.QueryRow(`SELECT `+selectCols+` FROM memory WHERE id = ?`, id)
	return scanItem(row)
}

// List returns items filtered by status and/or category. Empty means "any".
func (s *Store) List(status, category string, limit int) ([]*Item, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if limit <= 0 || limit > 500 {
		limit = 200
	}
	q := `SELECT ` + selectCols + ` FROM memory WHERE 1=1`
	var args []any
	if status != "" {
		q += ` AND status = ?`
		args = append(args, status)
	}
	if category != "" {
		q += ` AND category = ?`
		args = append(args, category)
	}
	q += ` ORDER BY updated_at DESC LIMIT ?`
	args = append(args, limit)

	rows, err := s.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	// Non-nil so an empty result marshals as [] rather than null: a client
	// reading `items[0]` on a JSON null gets a type error, not an empty list.
	out := []*Item{}
	for rows.Next() {
		it, err := scanItem(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

// Stats powers the settings UI without exposing content.
// AuditEntry is one line of the memory store's own history.
type AuditEntry struct {
	At       int64  `json:"at"`
	Action   string `json:"action"`
	MemoryID string `json:"memory_id,omitempty"`
	Detail   string `json:"detail,omitempty"`
}

// Audit returns the most recent audit entries, newest first.
//
// The log was written from the first version and never readable, so "what did
// it decide to remember, and when did it forget it?" had no answer short of
// opening the encrypted database by hand. Entries never contain memory
// plaintext; see the schema comment.
func (s *Store) Audit(limit int) ([]AuditEntry, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	s.mu.Lock()
	defer s.mu.Unlock()

	rows, err := s.db.Query(
		`SELECT ts, action, COALESCE(memory_id, ''), COALESCE(detail, '')
		   FROM audit ORDER BY ts DESC, rowid DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []AuditEntry{}
	for rows.Next() {
		var e AuditEntry
		if err := rows.Scan(&e.At, &e.Action, &e.MemoryID, &e.Detail); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func (s *Store) Stats() (map[string]any, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := map[string]any{}
	byStatus := map[string]int{}
	rows, err := s.db.Query(`SELECT status, COUNT(*) FROM memory GROUP BY status`)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var st string
		var n int
		if err := rows.Scan(&st, &n); err == nil {
			byStatus[st] = n
		}
	}
	rows.Close()
	out["by_status"] = byStatus

	byCat := map[string]int{}
	rows2, err := s.db.Query(`SELECT category, COUNT(*) FROM memory
	    WHERE status = ? GROUP BY category`, StatusActive)
	if err == nil {
		for rows2.Next() {
			var c string
			var n int
			if err := rows2.Scan(&c, &n); err == nil {
				byCat[c] = n
			}
		}
		rows2.Close()
	}
	out["active_by_category"] = byCat

	var embedded int
	_ = s.db.QueryRow(`SELECT COUNT(*) FROM embedding`).Scan(&embedded)
	out["embedded"] = embedded
	return out, nil
}
