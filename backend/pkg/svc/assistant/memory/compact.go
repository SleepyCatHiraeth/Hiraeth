package memory

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"
)

// CompactPolicy decides what is stale enough to drop.
type CompactPolicy struct {
	MaxAge        time.Duration // consider items older than this
	MinImportance float64       // only items BELOW this importance
	RequireUnused bool          // only items never accessed since creation
	DryRun        bool
}

// DefaultCompactPolicy preserves anything used during the last quarter and
// limits pruning to weak memories the user never reviewed. LLM summarisation is
// deliberately excluded because it requires model availability and can fail;
// deterministic pruning delivers the storage bound without those failure modes.
func DefaultCompactPolicy() CompactPolicy {
	return CompactPolicy{
		MaxAge:        90 * 24 * time.Hour,
		MinImportance: 0.3,
		RequireUnused: true,
	}
}

type CompactResult struct {
	Scanned int
	Pruned  int
	Kept    int
	Removed []string // ids, for the audit trail and for tests
}

// Compact prunes stale memories. Cancellable, because it is not.
//
// It previously took no context and held the store lock across every delete, so
// a large compaction ran past both of shutdown's five-second caps and then
// blocked `Close`, which needs the same lock. Shutdown advertised a bound it
// could not keep. Deletes now stop at a cancelled context and commit what was
// already done, which is safe: pruning is idempotent and the next sweep
// finishes the rest.
func (s *Store) Compact(ctx context.Context, p CompactPolicy) (CompactResult, error) {
	result := CompactResult{Removed: []string{}}
	if p.MaxAge <= 0 {
		return result, fmt.Errorf("compact max age must be positive")
	}
	if p.MinImportance < 0 || p.MinImportance > 1 {
		return result, fmt.Errorf("compact minimum importance must be between 0 and 1")
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return result, fmt.Errorf("memory store is closed")
	}

	tx, err := s.db.Begin()
	if err != nil {
		return result, err
	}
	defer tx.Rollback()

	if err := tx.QueryRow(`SELECT COUNT(*) FROM memory`).Scan(&result.Scanned); err != nil {
		return result, err
	}
	cutoff := time.Now().Add(-p.MaxAge).Unix()
	// Candidates are excluded alongside quarantined items: both are waiting for
	// a decision the user has not made yet. Listing one for review does not
	// touch last_accessed_at and the notch holds a detached copy, so a sweep
	// could delete the memory whose text was on screen and turn the user's
	// "Keep" into "no memory" -- losing the item during the very review meant
	// to decide its fate.
	query := `SELECT id FROM memory
	    WHERE user_confirmed = 0
	      AND category != ?
	      AND status NOT IN (?, ?)
	      AND importance < ?
	      AND COALESCE(last_accessed_at, created_at) < ?`
	args := []any{CatInstruction, StatusQuarantined, StatusCandidate, p.MinImportance, cutoff}
	if p.RequireUnused {
		query += ` AND last_accessed_at IS NULL`
	}
	query += ` ORDER BY id`

	rows, err := tx.Query(query, args...)
	if err != nil {
		return result, err
	}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return result, err
		}
		result.Removed = append(result.Removed, id)
	}
	if err := rows.Close(); err != nil {
		return result, err
	}
	if err := rows.Err(); err != nil {
		return result, err
	}
	result.Pruned = len(result.Removed)
	result.Kept = result.Scanned - result.Pruned

	if p.DryRun {
		return result, nil
	}
	done := 0
	for _, id := range result.Removed {
		if err := ctx.Err(); err != nil {
			// Keep what has been deleted so far rather than rolling back an
			// hour of work; report only what actually went.
			result.Removed = result.Removed[:done]
			result.Pruned = done
			result.Kept = result.Scanned - done
			break
		}
		n, err := deleteMemory(tx, id)
		if err != nil {
			return CompactResult{}, err
		}
		if n != 1 {
			return CompactResult{}, fmt.Errorf("compact selected missing memory %s", id)
		}
		done++
	}
	if err := tx.Commit(); err != nil {
		return CompactResult{}, err
	}

	// Ids are capped. Joining every id wrote a single unbounded row into the
	// audit log, which is the one place that has to stay readable after a big
	// compaction; the counts are the part anyone reads.
	const maxAuditIDs = 20
	shown := result.Removed
	suffix := ""
	if len(shown) > maxAuditIDs {
		shown = shown[:maxAuditIDs]
		suffix = fmt.Sprintf(" +%d more", result.Pruned-maxAuditIDs)
	}
	s.audit("compact", "", fmt.Sprintf("scanned=%d pruned=%d kept=%d ids=%s%s",
		result.Scanned, result.Pruned, result.Kept, strings.Join(shown, ","), suffix))
	return result, nil
}

// deleteMemory is shared by explicit deletion and compaction so both erase all
// searchable and derived forms of a memory in one transaction.
func deleteMemory(tx *sql.Tx, id string) (int64, error) {
	if _, err := tx.Exec(`DELETE FROM memory_fts WHERE rowid =
	    (SELECT rowid FROM memory WHERE id = ?)`, id); err != nil {
		return 0, err
	}
	if _, err := tx.Exec(`DELETE FROM embedding WHERE memory_id = ?`, id); err != nil {
		return 0, err
	}
	res, err := tx.Exec(`DELETE FROM memory WHERE id = ?`, id)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}
