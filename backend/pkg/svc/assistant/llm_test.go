package assistant

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"ambxst/backend/pkg/svc/assistant/memory"
)

func TestCheckEndpointRefusesRemote(t *testing.T) {
	ok := []string{
		"http://127.0.0.1:1234/v1",
		"http://localhost:1234/v1",
		"http://[::1]:1234/v1",
	}
	for _, e := range ok {
		if err := checkEndpoint(e); err != nil {
			t.Errorf("expected %q allowed, got %v", e, err)
		}
	}
	// The whole point of local-only mode: none of these may ever be accepted.
	bad := []string{
		"http://192.168.1.50:1234/v1",
		"https://api.openai.com/v1",
		"http://evil.example.com/v1",
		"http://0.0.0.0:1234/v1",
	}
	for _, e := range bad {
		if err := checkEndpoint(e); err == nil {
			t.Errorf("expected %q refused, but it was allowed", e)
		}
	}
}

func TestSentenceEnd(t *testing.T) {
	cases := []struct {
		in   string
		want bool // whether a sentence boundary should be found
	}{
		{"Hello there. ", true},
		{"Done!", true},
		{"Really?", true},
		{"The value is 3.5 volts", false}, // decimal must not split
		{"Ask Dr. Smith about it", false}, // abbreviation must not split
		{"Not finished yet", false},       // no terminator
		{"One. Two. Three.", true},
	}
	for _, c := range cases {
		got := sentenceEnd(c.in) >= 0
		if got != c.want {
			t.Errorf("sentenceEnd(%q) = %v, want %v", c.in, got, c.want)
		}
	}
}

func TestSentenceEndSplitsInOrder(t *testing.T) {
	s := "First one. Second one. "
	i := sentenceEnd(s)
	if i < 0 || s[:i+1] != "First one." {
		t.Fatalf("expected first sentence, got %q", s[:i+1])
	}
	rest := s[i+1:]
	j := sentenceEnd(rest)
	if j < 0 || rest[:j+1] != " Second one." {
		t.Fatalf("expected second sentence, got %q", rest[:j+1])
	}
}

func TestPickCaptureTargetPrefersExplicit(t *testing.T) {
	// A configured device must never be second-guessed.
	if got := pickCaptureTarget(context.Background(), "my.chosen.device"); got != "my.chosen.device" {
		t.Errorf("configured target ignored, got %q", got)
	}
}

func TestRMSDistinguishesSilenceFromAudio(t *testing.T) {
	silence := make([]byte, 2000) // all zeroes
	if r := rmsOf(silence); r != 0 {
		t.Errorf("silence should be 0, got %f", r)
	}
	loud := make([]byte, 2000)
	for i := 0; i+1 < len(loud); i += 2 {
		loud[i] = 0x00
		loud[i+1] = 0x10 // 4096
	}
	if r := rmsOf(loud); r < 4000 || r > 4200 {
		t.Errorf("expected ~4096, got %f", r)
	}
	if rmsOf(nil) != 0 {
		t.Error("empty input must be 0")
	}
}

func TestSampleRateFollowsEngine(t *testing.T) {
	// A wrong rate here plays back at the wrong pitch instead of erroring,
	// so it is worth pinning.
	if got := sampleRateFor("kokoro"); got != "24000" {
		t.Errorf("kokoro rate = %s, want 24000", got)
	}
	if got := sampleRateFor("piper"); got != "22050" {
		t.Errorf("piper rate = %s, want 22050", got)
	}
}

func TestConfigRoundTrip(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", dir)

	cfg := defaultConfig()
	if cfg.TTSEngine != "kokoro" || cfg.TTSVoice != "af_heart" {
		t.Fatalf("unexpected defaults: %s/%s", cfg.TTSEngine, cfg.TTSVoice)
	}
	cfg.TTSVoice = "am_onyx"
	if err := saveConfig(cfg); err != nil {
		t.Fatalf("save: %v", err)
	}
	got, err := loadConfig()
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if got.TTSVoice != "am_onyx" {
		t.Errorf("voice did not persist, got %q", got.TTSVoice)
	}

	// A partial file must not produce a broken stack.
	if err := os.WriteFile(filepath.Join(dir, "ambxst", "assistant.json"),
		[]byte(`{"tts_voice":"af_heart"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	got, err = loadConfig()
	if err != nil {
		t.Fatalf("load partial: %v", err)
	}
	if got.STTThreads == 0 || got.Endpoint == "" || got.TTSEngine == "" {
		t.Errorf("partial config left holes: %+v", got)
	}

	// A corrupt file must fall back to defaults and report the error rather
	// than silently overwriting the user's file.
	if err := os.WriteFile(filepath.Join(dir, "ambxst", "assistant.json"),
		[]byte(`{not json`), 0o600); err != nil {
		t.Fatal(err)
	}
	got, err = loadConfig()
	if err == nil {
		t.Error("corrupt config should report an error")
	}
	if got.TTSVoice != "af_heart" {
		t.Errorf("corrupt config should yield defaults, got %q", got.TTSVoice)
	}
}

// The defect: default categories enabled only the two the extractor never
// emits, so every confirmed memory was excluded from retrieval and memory
// silently did nothing.
func TestDefaultCategoriesCoverEverythingTheExtractorEmits(t *testing.T) {
	s := &Service{cfg: defaultConfig()}
	enabled := s.enabledCategories()

	// Exactly the categories extract.go's validCategories admits.
	emitted := []string{
		memory.CatProfile, memory.CatPreference, memory.CatProject,
		memory.CatEnvironment, memory.CatRoutine, memory.CatInstruction,
		memory.CatFact,
	}
	for _, c := range emitted {
		if !enabled[c] {
			t.Errorf("category %q can be extracted and confirmed but is not retrievable by default", c)
		}
	}
	// The expiring ones must stay on too; they are the only auto-saved kinds.
	for _, c := range []string{memory.CatTemporary, memory.CatSummary} {
		if !enabled[c] {
			t.Errorf("auto-savable category %q is not enabled by default", c)
		}
	}
}

// The contract stated in the settings panel and the wiki: the assistant is off
// after a restart. It was false, because `enabled` was persisted and restored.
func TestEnabledNeverSurvivesARestart(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", dir)

	cfg := defaultConfig()
	cfg.Enabled = true
	cfg.TTSVoice = "am_onyx" // a real preference, which MUST survive
	if err := saveConfig(cfg); err != nil {
		t.Fatal(err)
	}

	got, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	if got.Enabled {
		t.Error("enabled survived a restart; the off-after-reboot contract is broken")
	}
	if got.TTSVoice != "am_onyx" {
		t.Errorf("a genuine preference was lost: voice = %q", got.TTSVoice)
	}

	// And it must not be on disk either, or the file contradicts the behaviour.
	raw, err := os.ReadFile(filepath.Join(dir, "ambxst", "assistant.json"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(raw), `"enabled": true`) {
		t.Error("enabled:true was written to disk; the file should never claim it")
	}
}

// The store used to check-then-act, so two concurrent callers could each open
// the encrypted database and leak whichever handle lost the assignment.
func TestConcurrentStoreOpenYieldsOneStore(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_DATA_HOME", dir)

	s := &Service{cfg: defaultConfig(), state: StateIdle}
	s.cfg.Enabled = true
	s.cfg.MemoryEnabled = true

	const n = 16
	got := make([]*memory.Store, n)
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) { defer wg.Done(); got[i] = s.store() }(i)
	}
	wg.Wait()

	first := got[0]
	if first == nil {
		t.Fatal("store() returned nil")
	}
	for i, st := range got {
		if st != first {
			t.Fatalf("caller %d got a different store instance; a handle leaked", i)
		}
	}
	_ = first.Close()
}

// release() must be safe from any state and repeatable.
func TestReleaseIsIdempotent(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_DATA_HOME", dir)

	s := &Service{cfg: defaultConfig(), state: StateIdle}
	s.cfg.Enabled = true
	s.cfg.MemoryEnabled = true
	if st := s.store(); st == nil {
		t.Fatal("expected a store")
	}
	s.release()
	s.release() // must not panic or double-close
	s.mu.Lock()
	mem := s.mem
	s.mu.Unlock()
	if mem != nil {
		t.Error("release left the memory store open")
	}
}

// Disabling is documented as releasing resources, not merely refusing work.
func TestDisableClosesTheStore(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", dir)
	t.Setenv("XDG_DATA_HOME", dir)

	s := &Service{cfg: defaultConfig(), state: StateIdle}
	s.cfg.Enabled = true
	s.cfg.MemoryEnabled = true
	if st := s.store(); st == nil {
		t.Fatal("expected a store")
	}

	if _, err := s.setConfig([]byte(`{"enabled":false}`)); err != nil {
		t.Fatalf("disable failed: %v", err)
	}
	s.mu.Lock()
	mem := s.mem
	s.mu.Unlock()
	if mem != nil {
		t.Error("disabling did not close the memory store")
	}
	if s.store() != nil {
		t.Error("store() returned a store while disabled")
	}
}

// Time to first audio is dominated by the opening sentence. A model that starts
// with a long clause used to mean silence for the whole clause.
func TestClauseEndSplitsOnlyWhenWorthwhile(t *testing.T) {
	long := "The turret assistant is ready to help you with that, and it will begin now"
	cut := clauseEnd(long)
	if cut < 0 {
		t.Fatal("a long opening clause should be speakable on its own")
	}
	if long[cut] != ',' {
		t.Errorf("cut at %q, want a comma", long[cut])
	}

	if got := clauseEnd("Yes, of course."); got >= 0 {
		t.Errorf("a short clause must not be split, got a cut at %d", got)
	}
	if got := clauseEnd("A sentence with no clause break at all here"); got >= 0 {
		t.Errorf("nothing to cut on, got %d", got)
	}
}

// max_tokens cutting an answer off mid-sentence is the most likely truncation
// there is, and `finish_reason: "length"` was being read as a clean finish.
func TestTokenLimitCountsAsTruncation(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, "data: {\"choices\":[{\"delta\":{\"content\":\"It goes on and \"},\"finish_reason\":\"length\"}]}\n\n")
		io.WriteString(w, "data: [DONE]\n\n")
	}))
	defer srv.Close()

	cfg := defaultConfig()
	cfg.Endpoint = srv.URL
	err := streamChat(context.Background(), cfg, "q", "", nil, func(string) {})
	if !errors.Is(err, errTruncated) {
		t.Fatalf("a length-limited reply must be reported as truncated, got %v", err)
	}
	if !strings.Contains(err.Error(), "length") {
		t.Errorf("the reason should say what cut it off: %v", err)
	}
}

// localhost was accepted by the URL check and then refused by the dial guard,
// so a documented-valid endpoint could never connect.
func TestLocalhostEndpointActuallyConnects(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"data":[]}`))
	}))
	defer srv.Close()

	_, port, err := net.SplitHostPort(strings.TrimPrefix(srv.URL, "http://"))
	if err != nil {
		t.Fatal(err)
	}
	endpoint := "http://localhost:" + port
	if err := checkURL(endpoint); err != nil {
		t.Fatalf("localhost must be accepted: %v", err)
	}
	if err := probeLLM(context.Background(), endpoint); err != nil {
		t.Errorf("a localhost endpoint must be reachable, got %v", err)
	}
}

// The dial guard still refuses a name that does not resolve to loopback.
//
// Hermetic: an earlier version resolved example.com for real, which needed the
// network and passed on DNS failure without proving anything at all. .invalid
// is reserved by RFC 2606 and must never resolve, so the refusal is guaranteed
// to come from the guard.
func TestDialRefusesANameThatIsNotLoopback(t *testing.T) {
	if err := localOnlyDial("tcp", "not-a-real-host.invalid:80"); err == nil {
		t.Error("a name that does not resolve to loopback must be refused")
	}
	if err := localOnlyDial("tcp", "localhost:1234"); err != nil {
		t.Errorf("localhost must be allowed: %v", err)
	}
	if err := localOnlyDial("tcp", "93.184.216.34:80"); err == nil {
		t.Error("a non-loopback literal must be refused")
	}
}
