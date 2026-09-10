package memory

import (
	"encoding/binary"
	"math"
	"time"

	sqlite3 "github.com/ncruces/go-sqlite3"
)

// Vectors are stored as little-endian float32 blobs and normalised on write, so
// cosine similarity reduces to a dot product at query time.

func encodeVec(v []float32) []byte {
	buf := make([]byte, len(v)*4)
	for i, f := range v {
		binary.LittleEndian.PutUint32(buf[i*4:], math.Float32bits(f))
	}
	return buf
}

func decodeVec(b []byte) []float32 {
	n := len(b) / 4
	out := make([]float32, n)
	for i := 0; i < n; i++ {
		out[i] = math.Float32frombits(binary.LittleEndian.Uint32(b[i*4:]))
	}
	return out
}

// normalise scales to unit length. A zero vector is returned unchanged rather
// than producing NaNs downstream.
func normalise(v []float32) []float32 {
	var sum float64
	for _, f := range v {
		sum += float64(f) * float64(f)
	}
	if sum == 0 {
		return v
	}
	inv := float32(1 / math.Sqrt(sum))
	out := make([]float32, len(v))
	for i, f := range v {
		out[i] = f * inv
	}
	return out
}

// cosineSQL is registered as a SQLite scalar function. Both arguments are
// normalised float32 blobs, so this is a dot product. Mismatched dimensions
// return 0 rather than erroring: that happens when the embedding model changes,
// and a query should degrade to keyword ranking rather than fail.
func cosineSQL(ctx sqlite3.Context, arg ...sqlite3.Value) {
	if len(arg) != 2 {
		ctx.ResultFloat(0)
		return
	}
	a := decodeVec(arg[0].RawBlob())
	b := decodeVec(arg[1].RawBlob())
	if len(a) == 0 || len(a) != len(b) {
		ctx.ResultFloat(0)
		return
	}
	var dot float64
	for i := range a {
		dot += float64(a[i]) * float64(b[i])
	}
	ctx.ResultFloat(dot)
}

// dot is the same computation in Go, for ranking outside SQL.
func dot(a, b []float32) float64 {
	if len(a) == 0 || len(a) != len(b) {
		return 0
	}
	var sum float64
	for i := range a {
		sum += float64(a[i]) * float64(b[i])
	}
	return sum
}

// PutEmbedding stores a normalised vector for an item. The model name and
// dimension are stored alongside so a model change is detectable; vectors from
// different models are never compared.
func (s *Store) PutEmbedding(memoryID, model string, vec []float32) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	n := normalise(vec)
	_, err := s.db.Exec(`INSERT INTO embedding(memory_id, model, dim, vec, created_at)
	    VALUES(?,?,?,?,?)
	    ON CONFLICT(memory_id, model) DO UPDATE SET
	      dim=excluded.dim, vec=excluded.vec, created_at=excluded.created_at`,
		memoryID, model, len(n), encodeVec(n), time.Now().Unix())
	return err
}

// MissingEmbeddings lists active items that have no vector for this model, so a
// model change can be repaired in the background instead of invalidating the
// whole store at once.
func (s *Store) MissingEmbeddings(model string, limit int) ([]*Item, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	rows, err := s.db.Query(`SELECT `+selectCols+` FROM memory m
	    WHERE m.status = ?
	      AND NOT EXISTS (SELECT 1 FROM embedding e
	                      WHERE e.memory_id = m.id AND e.model = ?)
	    LIMIT ?`, StatusActive, model, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
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
