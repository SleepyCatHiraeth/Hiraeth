package assistant

import (
	"context"
	"os"
	"path/filepath"
	"testing"
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
