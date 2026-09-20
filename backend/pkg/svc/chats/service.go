package chats

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	"ambxst/backend/pkg/ipc"
	"ambxst/backend/pkg/paths"
)

// Service exposes the chat store over IPC. The shell no longer touches the
// filesystem for conversations at all: it had been running `mkdir`, `cat`, `rm`
// and `ambxst chatlist` against a directory of plaintext JSON.
type Service struct {
	paths *paths.Paths
	store *Store
	err   error
}

func NewService(p *paths.Paths) *Service {
	s := &Service{paths: p}
	store, err := Open(p.ChatsDB(), p.ChatsKeyFile())
	if err != nil {
		// A daemon that cannot open the chat store still has to run: the bar,
		// the notch and everything else do not depend on it. The error is kept
		// and returned from every method, so the shell reports it instead of
		// silently showing an empty history.
		s.err = err
		log.Printf("[chats] %v", err)
		return s
	}
	s.store = store

	if n, err := s.importLegacy(); err != nil {
		log.Printf("[chats] importing plaintext conversations: %v", err)
	} else if n > 0 {
		log.Printf("[chats] imported %d plaintext conversation(s) into the encrypted store", n)
	}
	return s
}

func (s *Service) Register(srv *ipc.Server) {
	srv.Register(&ipc.Service{
		Name: "chats",
		Methods: map[string]ipc.HandlerFunc{
			"list":   s.list,
			"load":   s.load,
			"save":   s.save,
			"delete": s.delete,
		},
	})
}

func (s *Service) Close() error {
	if s.store == nil {
		return nil
	}
	return s.store.Close()
}

func (s *Service) ready() error {
	if s.err != nil {
		return s.err
	}
	if s.store == nil {
		return fmt.Errorf("chat store is unavailable")
	}
	return nil
}

func (s *Service) list(json.RawMessage) (any, error) {
	if err := s.ready(); err != nil {
		return nil, err
	}
	return s.store.List()
}

func (s *Service) load(params json.RawMessage) (any, error) {
	if err := s.ready(); err != nil {
		return nil, err
	}
	var p struct {
		ID string `json:"id"`
	}
	json.Unmarshal(params, &p)
	if p.ID == "" {
		return nil, fmt.Errorf("load requires id")
	}
	messages, err := s.store.Load(p.ID)
	if err != nil {
		return nil, err
	}
	// Returned as the parsed array, so the shell gets the conversation rather
	// than a string it has to parse a second time.
	var out []json.RawMessage
	if err := json.Unmarshal(messages, &out); err != nil {
		return nil, err
	}
	return map[string]any{"id": p.ID, "messages": out}, nil
}

func (s *Service) save(params json.RawMessage) (any, error) {
	if err := s.ready(); err != nil {
		return nil, err
	}
	var p struct {
		ID       string            `json:"id"`
		Messages []json.RawMessage `json:"messages"`
	}
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, err
	}
	if p.ID == "" {
		return nil, fmt.Errorf("save requires id")
	}
	encoded, err := json.Marshal(p.Messages)
	if err != nil {
		return nil, err
	}
	if err := s.store.Save(p.ID, encoded); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func (s *Service) delete(params json.RawMessage) (any, error) {
	if err := s.ready(); err != nil {
		return nil, err
	}
	var p struct {
		ID string `json:"id"`
	}
	json.Unmarshal(params, &p)
	if p.ID == "" {
		return nil, fmt.Errorf("delete requires id")
	}
	if err := s.store.Delete(p.ID); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

// importLegacy moves the plaintext JSON conversations into the encrypted store
// and removes them. Returns how many were imported.
//
// A plaintext file is deleted only after its row has been read back out of the
// database and compared byte for byte. The point of this migration is that the
// plaintext stops existing, so leaving it behind defeats it -- but deleting a
// conversation that did not survive the move is the failure this codebase has
// already had once, in the clipboard's pinned-only legacy migration. Anything
// that does not verify is kept and logged.
func (s *Service) importLegacy() (int, error) {
	dir := s.paths.ChatsLegacyDir()
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return 0, nil
		}
		return 0, err
	}

	imported := 0
	kept := 0
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}
		path := filepath.Join(dir, entry.Name())
		id := strings.TrimSuffix(entry.Name(), ".json")

		raw, err := os.ReadFile(path)
		if err != nil {
			log.Printf("[chats] keeping %s: %v", entry.Name(), err)
			kept++
			continue
		}

		// Re-encode so the stored bytes are canonical and the comparison below
		// is against what the store will actually return, not against the
		// file's original whitespace.
		var parsed []json.RawMessage
		if err := json.Unmarshal(raw, &parsed); err != nil {
			log.Printf("[chats] keeping %s: not a conversation (%v)", entry.Name(), err)
			kept++
			continue
		}
		encoded, err := json.Marshal(parsed)
		if err != nil {
			log.Printf("[chats] keeping %s: %v", entry.Name(), err)
			kept++
			continue
		}

		// A previous run may have imported this file and then failed to remove
		// it. If the database has since moved on, importing again would
		// overwrite newer messages with the older plaintext -- which looks
		// exactly like the conversation losing its most recent turns.
		if existing, err := s.store.Load(id); err == nil {
			if bytes.Equal(existing, encoded) {
				if err := os.Remove(path); err != nil {
					log.Printf("[chats] %s is already imported but could not be removed: %v", entry.Name(), err)
					kept++
					continue
				}
				imported++
				continue
			}
			log.Printf("[chats] keeping %s: the stored conversation has changed since it was imported", entry.Name())
			kept++
			continue
		}

		modified := int64(0)
		if info, err := entry.Info(); err == nil {
			modified = info.ModTime().UnixMilli()
		}
		if err := s.store.SaveAt(id, encoded, modified, modified); err != nil {
			log.Printf("[chats] keeping %s: %v", entry.Name(), err)
			kept++
			continue
		}

		readBack, err := s.store.Load(id)
		if err != nil || !bytes.Equal(readBack, encoded) {
			log.Printf("[chats] keeping %s: it did not read back identically", entry.Name())
			kept++
			continue
		}

		if err := os.Remove(path); err != nil {
			log.Printf("[chats] imported %s but could not remove the plaintext: %v", entry.Name(), err)
			kept++
			continue
		}
		imported++
	}

	// Only when nothing was left behind: an empty directory is tidy, a
	// directory still holding an unimported conversation is evidence.
	if kept == 0 {
		os.Remove(dir)
	}
	return imported, nil
}
