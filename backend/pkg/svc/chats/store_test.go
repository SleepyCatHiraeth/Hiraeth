package chats

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"ambxst/backend/pkg/paths"
)

func openTemp(t *testing.T) (*Store, string, string) {
	t.Helper()
	dir := t.TempDir()
	dbPath := filepath.Join(dir, "data", "chats.db")
	keyPath := filepath.Join(dir, "state", "chats.key")
	store, err := Open(dbPath, keyPath)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	t.Cleanup(func() { store.Close() })
	return store, dbPath, keyPath
}

const sample = `[{"role":"user","content":"what is my gpu"},{"role":"assistant","content":"a 9070 XT"}]`

func TestRoundTrip(t *testing.T) {
	store, _, _ := openTemp(t)

	if err := store.Save("1", []byte(sample)); err != nil {
		t.Fatalf("save: %v", err)
	}
	got, err := store.Load("1")
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	var a, b []json.RawMessage
	json.Unmarshal([]byte(sample), &a)
	json.Unmarshal(got, &b)
	if len(a) != len(b) {
		t.Fatalf("round trip changed the conversation: %d != %d", len(a), len(b))
	}

	if _, err := store.Load("nope"); err == nil {
		t.Fatal("loading a chat that does not exist should fail")
	}
}

// The whole point of the change: the conversation must not be readable in the
// file on disk.
func TestNothingIsStoredInPlaintext(t *testing.T) {
	store, dbPath, _ := openTemp(t)
	if err := store.Save("1", []byte(sample)); err != nil {
		t.Fatalf("save: %v", err)
	}
	if err := store.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}

	raw, err := os.ReadFile(dbPath)
	if err != nil {
		t.Fatalf("read db: %v", err)
	}
	for _, needle := range []string{"what is my gpu", "9070 XT"} {
		if strings.Contains(string(raw), needle) {
			t.Fatalf("conversation text %q is readable in the database file", needle)
		}
	}
}

func TestKeyFilePermissions(t *testing.T) {
	_, _, keyPath := openTemp(t)
	info, err := os.Stat(keyPath)
	if err != nil {
		t.Fatalf("stat key: %v", err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("key file is %v, want 0600", info.Mode().Perm())
	}
}

// Minting a fresh key beside an existing database produces one that opens and
// looks empty, so the conversations would appear deleted rather than locked.
func TestRefusesToMintAKeyOverAnExistingDatabase(t *testing.T) {
	store, dbPath, keyPath := openTemp(t)
	if err := store.Save("1", []byte(sample)); err != nil {
		t.Fatalf("save: %v", err)
	}
	store.Close()

	if err := os.WriteFile(keyPath, []byte("not a key\n"), 0o600); err != nil {
		t.Fatalf("clobber key: %v", err)
	}
	if _, err := Open(dbPath, keyPath); err == nil {
		t.Fatal("opening with a broken key beside an existing database should refuse")
	}
}

func TestListIsNewestFirstAndTitled(t *testing.T) {
	store, _, _ := openTemp(t)

	store.SaveAt("old", []byte(`[{"role":"user","content":"older question"}]`), 1000, 1000)
	store.SaveAt("new", []byte(`[{"role":"system","content":"prompt"},{"role":"user","content":"newer question"}]`), 2000, 2000)

	list, err := store.List()
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(list) != 2 {
		t.Fatalf("want 2 chats, got %d", len(list))
	}
	if list[0].ID != "new" {
		t.Fatalf("want newest first, got %q", list[0].ID)
	}
	if list[0].Title != "newer question" {
		t.Fatalf("title should come from the first user message, got %q", list[0].Title)
	}
	if list[0].Count != 2 {
		t.Fatalf("count should be the number of messages, got %d", list[0].Count)
	}
}

func TestSaveRejectsWhatIsNotAConversation(t *testing.T) {
	store, _, _ := openTemp(t)
	if err := store.Save("1", []byte(`{"not":"an array"}`)); err == nil {
		t.Fatal("a non-array must be refused rather than stored unreadable")
	}
	if err := store.Save("", []byte(sample)); err == nil {
		t.Fatal("an empty id must be refused")
	}
}

func TestDelete(t *testing.T) {
	store, _, _ := openTemp(t)
	store.Save("1", []byte(sample))
	if err := store.Delete("1"); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if _, err := store.Load("1"); err == nil {
		t.Fatal("a deleted chat must be gone")
	}
}

// ---------------------------------------------------------------------------
// Migration
// ---------------------------------------------------------------------------

func newServiceIn(t *testing.T, root string) *Service {
	t.Helper()
	p := &paths.Paths{
		DataDir:  filepath.Join(root, "data"),
		StateDir: filepath.Join(root, "state"),
	}
	if err := os.MkdirAll(p.ChatsLegacyDir(), 0o700); err != nil {
		t.Fatalf("mkdir legacy: %v", err)
	}
	return &Service{paths: p}
}

func TestImportRemovesThePlaintextOnlyWhenItVerifies(t *testing.T) {
	root := t.TempDir()
	svc := newServiceIn(t, root)

	legacy := svc.paths.ChatsLegacyDir()
	good := filepath.Join(legacy, "111.json")
	bad := filepath.Join(legacy, "222.json")
	if err := os.WriteFile(good, []byte(sample), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(bad, []byte("this is not json"), 0o600); err != nil {
		t.Fatal(err)
	}

	store, err := Open(svc.paths.ChatsDB(), svc.paths.ChatsKeyFile())
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer store.Close()
	svc.store = store

	n, err := svc.importLegacy()
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	if n != 1 {
		t.Fatalf("want 1 imported, got %d", n)
	}

	if _, err := os.Stat(good); !os.IsNotExist(err) {
		t.Fatal("a verified conversation's plaintext must be removed")
	}
	if _, err := os.Stat(bad); err != nil {
		t.Fatal("a conversation that could not be imported must be kept, not deleted")
	}
	if _, err := os.Stat(legacy); err != nil {
		t.Fatal("the directory must survive while it still holds something")
	}

	got, err := store.Load("111")
	if err != nil {
		t.Fatalf("imported chat is not readable: %v", err)
	}
	var parsed []json.RawMessage
	if err := json.Unmarshal(got, &parsed); err != nil || len(parsed) != 2 {
		t.Fatalf("imported chat did not survive intact: %v", err)
	}
}

func TestImportIsIdempotentAndTidiesUpWhenItFinishes(t *testing.T) {
	root := t.TempDir()
	svc := newServiceIn(t, root)
	if err := os.WriteFile(filepath.Join(svc.paths.ChatsLegacyDir(), "1.json"), []byte(sample), 0o600); err != nil {
		t.Fatal(err)
	}

	store, err := Open(svc.paths.ChatsDB(), svc.paths.ChatsKeyFile())
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer store.Close()
	svc.store = store

	if n, _ := svc.importLegacy(); n != 1 {
		t.Fatalf("first import should move one chat")
	}
	if _, err := os.Stat(svc.paths.ChatsLegacyDir()); !os.IsNotExist(err) {
		t.Fatal("an emptied legacy directory should be removed")
	}
	if n, err := svc.importLegacy(); err != nil || n != 0 {
		t.Fatalf("a second import should find nothing to do: %d %v", n, err)
	}
}

func TestDatabaseIsNotWorldReadable(t *testing.T) {
	_, dbPath, _ := openTemp(t)
	info, err := os.Stat(dbPath)
	if err != nil {
		t.Fatalf("stat db: %v", err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("chats.db is %v, want 0600", info.Mode().Perm())
	}
}

// A previous run can import a file and then fail to remove it. Importing it
// again must not overwrite a conversation that has since moved on.
func TestReimportDoesNotOverwriteNewerMessages(t *testing.T) {
	root := t.TempDir()
	svc := newServiceIn(t, root)
	path := filepath.Join(svc.paths.ChatsLegacyDir(), "1.json")
	if err := os.WriteFile(path, []byte(sample), 0o600); err != nil {
		t.Fatal(err)
	}

	store, err := Open(svc.paths.ChatsDB(), svc.paths.ChatsKeyFile())
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer store.Close()
	svc.store = store

	if n, _ := svc.importLegacy(); n != 1 {
		t.Fatal("first import should move the chat")
	}

	// The conversation continues, and the stale plaintext reappears.
	extended := `[{"role":"user","content":"what is my gpu"},{"role":"assistant","content":"a 9070 XT"},{"role":"user","content":"and the cpu"}]`
	if err := store.Save("1", []byte(extended)); err != nil {
		t.Fatalf("save: %v", err)
	}
	if err := os.MkdirAll(svc.paths.ChatsLegacyDir(), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(sample), 0o600); err != nil {
		t.Fatal(err)
	}

	if n, _ := svc.importLegacy(); n != 0 {
		t.Fatal("a conflicting plaintext file must not be counted as imported")
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatal("it must be kept as evidence, not deleted")
	}

	got, err := store.Load("1")
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	var parsed []json.RawMessage
	json.Unmarshal(got, &parsed)
	if len(parsed) != 3 {
		t.Fatalf("the newer conversation was overwritten: %d messages", len(parsed))
	}
}

// An already-imported file that is still identical is simply removed.
func TestReimportRemovesAnIdenticalLeftover(t *testing.T) {
	root := t.TempDir()
	svc := newServiceIn(t, root)
	path := filepath.Join(svc.paths.ChatsLegacyDir(), "1.json")
	os.WriteFile(path, []byte(sample), 0o600)

	store, err := Open(svc.paths.ChatsDB(), svc.paths.ChatsKeyFile())
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer store.Close()
	svc.store = store
	svc.importLegacy()

	os.MkdirAll(svc.paths.ChatsLegacyDir(), 0o700)
	os.WriteFile(path, []byte(sample), 0o600)
	if n, _ := svc.importLegacy(); n != 1 {
		t.Fatal("an identical leftover should be cleaned up")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("and removed")
	}
}
