// Package chats owns AI sidebar conversations.
//
// They used to be plaintext JSON in ~/.local/share/ambxst/chats, written by the
// QML side through `mkdir` and a FileView. A conversation with an assistant is
// at least as sensitive as the clipboard, which this codebase already encrypts
// at rest with the adiantum VFS, so the precedent for doing better was already
// in the tree and unused here.
//
// The encrypted-open and key-handling code below is the third copy of that
// pattern (clipboard/store.go and assistant/memory/store.go are the others).
// Extracting the common half is worth doing, but as its own behaviour-
// preserving change rather than folded into a security fix.
package chats

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	sqlite3 "github.com/ncruces/go-sqlite3"
	"github.com/ncruces/go-sqlite3/driver"
	_ "github.com/ncruces/go-sqlite3/vfs/adiantum"
)

const schemaSQL = `
CREATE TABLE IF NOT EXISTS chats (
	id TEXT PRIMARY KEY,
	messages BLOB NOT NULL,
	created_at INTEGER NOT NULL,
	updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_chats_updated ON chats(updated_at DESC);
CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL);
`

// The messages blob is the conversation exactly as the shell serialises it.
// Re-modelling the message shape here would create a second source of truth
// about what a message is, and the two would drift the first time a field is
// added on the QML side.
const currentSchema = 1

// migrations[i] upgrades a database at version i+1 to version i+2. Empty:
// version 1 is the first schema. Append, never insert, and update schemaSQL to
// match so a fresh database is created at the current version directly.
var migrations []func(*sql.DB) error

// Summary is one row of the history list: enough to render it without reading
// every conversation back out of the database.
type Summary struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	UpdatedAt int64  `json:"updatedAt"`
	Count     int    `json:"count"`
}

// Store owns the encrypted database. Every access is serialised; this is a
// single-user assistant and lock contention is not the bottleneck.
type Store struct {
	mu     sync.Mutex
	db     *sql.DB
	closed bool
}

// Open creates or opens the chat database, generating a 32-byte key on first
// use. Key file and database are 0600 inside a 0700 directory, matching the
// clipboard and memory stores.
func Open(dbPath, keyPath string) (*Store, error) {
	if err := os.MkdirAll(filepath.Dir(dbPath), 0o700); err != nil {
		return nil, err
	}
	if err := os.MkdirAll(filepath.Dir(keyPath), 0o700); err != nil {
		return nil, err
	}

	hexKey, err := loadOrCreateKey(keyPath, dbPath)
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
	db, err := driver.Open(u.String(), func(conn *sqlite3.Conn) error { return nil })
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
	// SQLite creates the file under the process umask, so the 0600 promised
	// above was only ever true on a 077 umask. The memory store does the same
	// thing for the same reason.
	if err := os.Chmod(dbPath, 0o600); err != nil {
		db.Close()
		return nil, fmt.Errorf("securing %s: %w", dbPath, err)
	}
	return &Store{db: db}, nil
}

// loadOrCreateKey reads the hex key, creating one only when there is no
// database that would become unreadable without it.
//
// Minting a fresh key beside an existing encrypted database does not fail
// loudly -- it produces a database that opens and appears empty -- so the
// conversations would look deleted rather than locked. This refuses instead.
func loadOrCreateKey(keyPath, dbPath string) (string, error) {
	data, readErr := os.ReadFile(keyPath)
	if readErr == nil {
		if key := strings.TrimSpace(string(data)); len(key) == 64 {
			return key, nil
		}
		readErr = errors.New("key file is malformed (expected 64 hex characters)")
	}

	if fi, err := os.Stat(dbPath); err == nil && fi.Size() > 0 {
		return "", fmt.Errorf(
			"chat key at %s is unusable (%v) but an encrypted database exists at %s. "+
				"Refusing to generate a new key, which would make every stored "+
				"conversation permanently unreadable. Restore the key from a backup, "+
				"or move the database aside to start fresh",
			keyPath, readErr, dbPath)
	}

	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	key := hex.EncodeToString(raw)
	if err := os.WriteFile(keyPath, []byte(key+"\n"), 0o600); err != nil {
		return "", err
	}
	return key, nil
}

func migrate(db *sql.DB) error {
	var version int
	err := db.QueryRow(`SELECT version FROM schema_version LIMIT 1`).Scan(&version)
	switch {
	case errors.Is(err, sql.ErrNoRows):
		_, err := db.Exec(`INSERT INTO schema_version(version) VALUES (?)`, currentSchema)
		return err
	case err != nil:
		return err
	}

	if version > currentSchema {
		return fmt.Errorf(
			"chat database is at schema version %d but this build understands %d: "+
				"it was written by a newer AMBXST. Refusing to open it rather than "+
				"risk writing a schema this build does not understand",
			version, currentSchema)
	}

	for version < currentSchema {
		if err := migrations[version-1](db); err != nil {
			return fmt.Errorf("migrating chat database from version %d: %w", version, err)
		}
		version++
		if _, err := db.Exec(`UPDATE schema_version SET version = ?`, version); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed || s.db == nil {
		return nil
	}
	s.closed = true
	return s.db.Close()
}

// Save replaces a conversation. `messages` is the JSON array the shell holds;
// it is validated as an array here so a malformed write cannot make the row
// unreadable later, but its contents are otherwise opaque.
func (s *Store) Save(id string, messages []byte) error {
	if strings.TrimSpace(id) == "" {
		return errors.New("chat id is required")
	}
	var probe []json.RawMessage
	if err := json.Unmarshal(messages, &probe); err != nil {
		return fmt.Errorf("messages must be a JSON array: %w", err)
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now().UnixMilli()
	_, err := s.db.Exec(`
		INSERT INTO chats(id, messages, created_at, updated_at) VALUES (?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET messages = excluded.messages, updated_at = excluded.updated_at`,
		id, messages, now, now)
	return err
}

// SaveAt is Save with an explicit timestamp, so an import can keep a
// conversation's original age instead of stamping every one with the moment
// the migration happened.
func (s *Store) SaveAt(id string, messages []byte, createdAt, updatedAt int64) error {
	if strings.TrimSpace(id) == "" {
		return errors.New("chat id is required")
	}
	var probe []json.RawMessage
	if err := json.Unmarshal(messages, &probe); err != nil {
		return fmt.Errorf("messages must be a JSON array: %w", err)
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	_, err := s.db.Exec(`
		INSERT INTO chats(id, messages, created_at, updated_at) VALUES (?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET messages = excluded.messages, updated_at = excluded.updated_at`,
		id, messages, createdAt, updatedAt)
	return err
}

// Load returns the raw messages array for one conversation.
func (s *Store) Load(id string) ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	var messages []byte
	err := s.db.QueryRow(`SELECT messages FROM chats WHERE id = ?`, id).Scan(&messages)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, fmt.Errorf("no chat %q", id)
	}
	return messages, err
}

func (s *Store) Delete(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, err := s.db.Exec(`DELETE FROM chats WHERE id = ?`, id)
	return err
}

// List returns every conversation, newest first.
//
// The old path shelled out to `ambxst chatlist`, which read every file in the
// directory in full on every refresh -- and a refresh ran after every saved
// reply. Titles are derived here instead, from the rows the database already
// has to touch.
func (s *Store) List() ([]Summary, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	rows, err := s.db.Query(`SELECT id, messages, updated_at FROM chats ORDER BY updated_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []Summary{}
	for rows.Next() {
		var id string
		var messages []byte
		var updated int64
		if err := rows.Scan(&id, &messages, &updated); err != nil {
			return nil, err
		}
		title, count := summarize(messages)
		out = append(out, Summary{ID: id, Title: title, UpdatedAt: updated, Count: count})
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	// ORDER BY already did this; the explicit sort keeps the contract true for
	// rows that share a timestamp, which an import produces in bulk.
	sort.SliceStable(out, func(i, j int) bool { return out[i].UpdatedAt > out[j].UpdatedAt })
	return out, nil
}

const titleLimit = 60

// summarize names a conversation by its first user message, which is what the
// old `chatlist` did and what the history list shows.
func summarize(messages []byte) (string, int) {
	var parsed []struct {
		Role    string `json:"role"`
		Content string `json:"content"`
	}
	if err := json.Unmarshal(messages, &parsed); err != nil {
		return "", 0
	}

	title := ""
	for _, m := range parsed {
		if m.Role != "user" {
			continue
		}
		title = strings.TrimSpace(strings.ReplaceAll(m.Content, "\n", " "))
		if title != "" {
			break
		}
	}
	if len([]rune(title)) > titleLimit {
		title = string([]rune(title)[:titleLimit]) + "…"
	}
	return title, len(parsed)
}
