package memory

import (
	"reflect"
	"strings"
	"testing"
	"time"
)

func staleMemory(content, category string) *Item {
	it := active(content, category)
	it.CreatedAt = time.Now().Add(-365 * 24 * time.Hour).Unix()
	it.Importance = 0.1
	it.UserConfirmed = false
	it.TrustLevel = TrustDerived
	return it
}

func compactPolicy() CompactPolicy {
	return CompactPolicy{MaxAge: 30 * 24 * time.Hour, MinImportance: 0.2, RequireUnused: true}
}

func TestCompactNeverPrunesConfirmedMemory(t *testing.T) {
	s := openTest(t)
	it := staleMemory("The user reviewed this memory.", CatFact)
	it.UserConfirmed = true
	if err := s.Put(it); err != nil {
		t.Fatal(err)
	}

	result, err := s.Compact(compactPolicy())
	if err != nil {
		t.Fatal(err)
	}
	if result.Pruned != 0 {
		t.Fatalf("confirmed memory was selected: %+v", result)
	}
	if _, err := s.Get(it.ID); err != nil {
		t.Fatalf("confirmed memory was pruned: %v", err)
	}
}

func TestCompactNeverPrunesInstructions(t *testing.T) {
	s := openTest(t)
	it := staleMemory("Always answer with exact file paths.", CatInstruction)
	if err := s.Put(it); err != nil {
		t.Fatal(err)
	}

	result, err := s.Compact(compactPolicy())
	if err != nil {
		t.Fatal(err)
	}
	if result.Pruned != 0 {
		t.Fatalf("instruction was selected: %+v", result)
	}
	if _, err := s.Get(it.ID); err != nil {
		t.Fatalf("instruction was pruned: %v", err)
	}
}

func TestCompactNeverPrunesQuarantinedMemory(t *testing.T) {
	s := openTest(t)
	it := staleMemory("Evidence awaiting review.", CatFact)
	it.Status = StatusQuarantined
	if err := s.Put(it); err != nil {
		t.Fatal(err)
	}

	result, err := s.Compact(compactPolicy())
	if err != nil {
		t.Fatal(err)
	}
	if result.Pruned != 0 {
		t.Fatalf("quarantined memory was selected: %+v", result)
	}
	if _, err := s.Get(it.ID); err != nil {
		t.Fatalf("quarantined memory was pruned: %v", err)
	}
}

func TestCompactPrunesMemoryFTSAndEmbedding(t *testing.T) {
	s := openTest(t)
	content := "Unimportant dormant detail with searchable wording."
	it := staleMemory(content, CatTemporary)
	if err := s.Put(it); err != nil {
		t.Fatal(err)
	}
	if err := s.PutEmbedding(it.ID, "model", []float32{1, 0}); err != nil {
		t.Fatal(err)
	}

	var rowID int64
	if err := s.db.QueryRow(`SELECT rowid FROM memory WHERE id = ?`, it.ID).Scan(&rowID); err != nil {
		t.Fatal(err)
	}
	assertRowCount(t, s, `SELECT COUNT(*) FROM memory_fts WHERE rowid = ?`, rowID, 1)
	assertRowCount(t, s, `SELECT COUNT(*) FROM embedding WHERE memory_id = ?`, it.ID, 1)

	result, err := s.Compact(compactPolicy())
	if err != nil {
		t.Fatal(err)
	}
	if result.Scanned != 1 || result.Pruned != 1 || result.Kept != 0 ||
		len(result.Removed) != 1 || result.Removed[0] != it.ID {
		t.Fatalf("unexpected result: %+v", result)
	}
	if _, err := s.Get(it.ID); err == nil {
		t.Fatal("stale memory survived compaction")
	}
	assertRowCount(t, s, `SELECT COUNT(*) FROM memory_fts WHERE rowid = ?`, rowID, 0)
	assertRowCount(t, s, `SELECT COUNT(*) FROM embedding WHERE memory_id = ?`, it.ID, 0)

	entries, err := s.Audit(1)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Action != "compact" {
		t.Fatalf("compaction audit missing: %+v", entries)
	}
	if !strings.Contains(entries[0].Detail, "scanned=1 pruned=1 kept=0 ids="+it.ID) {
		t.Errorf("audit lacks counts and id: %+v", entries[0])
	}
	if strings.Contains(entries[0].Detail, content) {
		t.Error("audit leaked memory plaintext")
	}
}

func TestCompactDryRunReportsWithoutChanges(t *testing.T) {
	s := openTest(t)
	first := staleMemory("First dry-run memory.", CatTemporary)
	second := staleMemory("Second dry-run memory.", CatTemporary)
	for _, it := range []*Item{first, second} {
		if err := s.Put(it); err != nil {
			t.Fatal(err)
		}
	}
	beforeAudit, err := s.Audit(100)
	if err != nil {
		t.Fatal(err)
	}

	policy := compactPolicy()
	policy.DryRun = true
	dry, err := s.Compact(policy)
	if err != nil {
		t.Fatal(err)
	}
	for _, it := range []*Item{first, second} {
		if _, err := s.Get(it.ID); err != nil {
			t.Fatalf("dry run removed %s: %v", it.ID, err)
		}
	}
	afterAudit, err := s.Audit(100)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(beforeAudit, afterAudit) {
		t.Fatal("dry run changed audit log")
	}

	policy.DryRun = false
	live, err := s.Compact(policy)
	if err != nil {
		t.Fatal(err)
	}
	if dry.Scanned != live.Scanned || dry.Pruned != live.Pruned || dry.Kept != live.Kept ||
		!reflect.DeepEqual(dry.Removed, live.Removed) {
		t.Fatalf("dry run %+v differs from live run %+v", dry, live)
	}
}

func TestCompactUsesLastAccessTime(t *testing.T) {
	s := openTest(t)
	it := staleMemory("Recently accessed dormant detail.", CatTemporary)
	if err := s.Put(it); err != nil {
		t.Fatal(err)
	}
	got, err := s.Retrieve(Query{Text: "recently accessed dormant detail"})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 {
		t.Fatalf("retrieval did not access memory, got %d results", len(got))
	}

	policy := compactPolicy()
	policy.RequireUnused = false
	result, err := s.Compact(policy)
	if err != nil {
		t.Fatal(err)
	}
	if result.Pruned != 0 {
		t.Fatalf("recently accessed memory was selected: %+v", result)
	}
	if _, err := s.Get(it.ID); err != nil {
		t.Fatalf("recently accessed memory was pruned: %v", err)
	}
}

func TestCompactOnClosedStoreReturnsError(t *testing.T) {
	s, err := Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Compact(DefaultCompactPolicy()); err == nil {
		t.Fatal("Compact on a closed store must return an error")
	}
}

func assertRowCount(t *testing.T, s *Store, query string, arg any, want int) {
	t.Helper()
	var got int
	if err := s.db.QueryRow(query, arg).Scan(&got); err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Fatalf("row count = %d, want %d", got, want)
	}
}
