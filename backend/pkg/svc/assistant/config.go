package assistant

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
)

// Assistant settings persist to their own JSON file rather than living only as
// Go defaults, so voice, engine and device choices survive a restart and can be
// changed without a rebuild. A Settings panel can drive the same two IPC methods
// later; nothing here assumes a UI exists yet.

const configFileName = "assistant.json"

var configMu sync.Mutex

func configPath() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		home, _ := os.UserHomeDir()
		base = filepath.Join(home, ".config")
	}
	return filepath.Join(base, "ambxst", configFileName)
}

// loadConfig layers the on-disk file over the defaults. A missing file is normal
// on first run. A corrupt file is deliberately NOT silently overwritten -- the
// defaults are used for this session and the bad file is left alone for the user
// to inspect, which is the opposite of the config-clobbering behaviour recorded
// as a defect elsewhere in this codebase.
func loadConfig() (Config, error) {
	cfg := defaultConfig()

	data, err := os.ReadFile(configPath())
	if err != nil {
		return cfg, nil // no file yet
	}
	if err := json.Unmarshal(data, &cfg); err != nil {
		return defaultConfig(), err
	}
	// A file written by an older build can be missing newer fields; refill any
	// that came back empty so a partial file never produces a broken stack.
	def := defaultConfig()
	if cfg.StackDir == "" {
		cfg.StackDir = def.StackDir
	}
	if cfg.Endpoint == "" {
		cfg.Endpoint = def.Endpoint
	}
	if cfg.Model == "" {
		cfg.Model = def.Model
	}
	if cfg.TTSEngine == "" {
		cfg.TTSEngine = def.TTSEngine
	}
	if cfg.TTSVoice == "" {
		cfg.TTSVoice = def.TTSVoice
	}
	if cfg.STTModel == "" {
		cfg.STTModel = def.STTModel
	}
	if cfg.STTVocab == "" {
		cfg.STTVocab = def.STTVocab
	}
	if cfg.STTThreads <= 0 {
		cfg.STTThreads = def.STTThreads
	}
	if cfg.MaxTokens <= 0 {
		cfg.MaxTokens = def.MaxTokens
	}
	if cfg.Volume == "" {
		cfg.Volume = def.Volume
	}
	if cfg.Speed <= 0 {
		cfg.Speed = def.Speed
	}
	return cfg, nil
}

func saveConfig(cfg Config) error {
	configMu.Lock()
	defer configMu.Unlock()

	path := configPath()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	// Write to a sibling and rename, so an interrupted write cannot leave a
	// truncated config behind.
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, append(data, '\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// KnownVoices is the set the UI offers. Kokoro ships far more; these are the two
// the user selected by listening, plus the Piper fallback voices already on disk.
var KnownVoices = []map[string]string{
	{"engine": "kokoro", "voice": "af_heart", "label": "Kokoro — Heart (female)"},
	{"engine": "kokoro", "voice": "am_onyx", "label": "Kokoro — Onyx (male)"},
	{"engine": "kokoro", "voice": "am_michael", "label": "Kokoro — Michael (male)"},
	{"engine": "kokoro", "voice": "bm_george", "label": "Kokoro — George (British male)"},
	{"engine": "piper", "voice": "en_US-ryan-high", "label": "Piper — Ryan (fast, lower quality)"},
	{"engine": "piper", "voice": "en_US-lessac-high", "label": "Piper — Lessac (fast, lower quality)"},
	{"engine": "piper", "voice": "en_GB-cori-high", "label": "Piper — Cori (British, fast)"},
}

// sampleRateFor reports the PCM rate a given engine emits. Getting this wrong
// does not fail loudly -- it just plays back at the wrong pitch -- so it is
// derived from the engine rather than hardcoded at the call site.
func sampleRateFor(engine string) string {
	if engine == "piper" {
		return "22050"
	}
	return "24000" // kokoro
}

// voiceModelPath resolves the --model argument for the configured engine.
// Kokoro takes one shared model plus a voice name; Piper takes a per-voice file.
func (s *Service) voiceModelPath() string {
	if s.cfg.TTSEngine == "piper" {
		return filepath.Join(s.cfg.StackDir, "models", "piper", s.cfg.TTSVoice+".onnx")
	}
	return filepath.Join(s.cfg.StackDir, "models", "kokoro", "kokoro-v1.0.onnx")
}
