package assistant

import (
	"context"
	"encoding/json"
	"os/exec"
	"strings"
	"time"
)

// Choosing a capture device is not cosmetic here. On this machine the PipeWire
// default source is an onboard HD Audio input that records effectively silence
// (measured RMS 5.5, peak 19 over four seconds) while the real USB microphone
// records normal ambient audio (RMS 152, peak 702). Recording from the default
// would have produced an assistant that listens, transcribes nothing, and gives
// no clue why. So the device is selected explicitly, by stable node name rather
// than by the numeric id, which is reassigned across reboots.

type audioSource struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	IsDefault   bool   `json:"is_default"`
}

// audioNode covers both directions; sinks matter because the same machine that
// defaults to a silent input also defaults to a possibly-silent output.
type audioNode = audioSource

// listSources enumerates Audio/Source nodes via pw-dump. argv only, no shell.
func listSources(ctx context.Context) ([]audioSource, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	out, err := exec.CommandContext(ctx, "pw-dump").Output()
	if err != nil {
		return nil, err
	}

	var objs []struct {
		Info struct {
			Props map[string]any `json:"props"`
		} `json:"info"`
	}
	if err := json.Unmarshal(out, &objs); err != nil {
		return nil, err
	}

	var sources []audioSource
	for _, o := range objs {
		p := o.Info.Props
		if p == nil {
			continue
		}
		if s, _ := p["media.class"].(string); s != "Audio/Source" {
			continue
		}
		name, _ := p["node.name"].(string)
		if name == "" {
			continue
		}
		desc, _ := p["node.description"].(string)
		sources = append(sources, audioSource{Name: name, Description: desc})
	}
	return sources, nil
}

// pickCaptureTarget resolves which node to record from.
//
// An explicit configured target always wins -- the user's choice is never
// second-guessed. With no configuration, prefer a real external microphone over
// an onboard HD Audio input, because the latter is the common silent default.
// Returning "" means "use the PipeWire default", which stays the behaviour when
// nothing better can be identified.
func pickCaptureTarget(ctx context.Context, configured string) string {
	if strings.TrimSpace(configured) != "" {
		return configured
	}
	sources, err := listSources(ctx)
	if err != nil || len(sources) == 0 {
		return ""
	}

	// USB capture devices are almost always the actual microphone.
	for _, s := range sources {
		if strings.Contains(s.Name, "usb-") {
			return s.Name
		}
	}
	// Otherwise take any source that is not one of the onboard "pro" inputs,
	// which are the ones observed to be silent here.
	for _, s := range sources {
		if !strings.Contains(s.Name, ".pro-input-") {
			return s.Name
		}
	}
	return ""
}

// rmsOf reports the loudness of 16-bit mono PCM, used to tell a live microphone
// from a dead one.
func rmsOf(pcm []byte) float64 {
	n := len(pcm) / 2
	if n == 0 {
		return 0
	}
	var sum float64
	for i := 0; i+1 < len(pcm); i += 2 {
		v := int16(uint16(pcm[i]) | uint16(pcm[i+1])<<8)
		sum += float64(v) * float64(v)
	}
	return sqrt(sum / float64(n))
}

func sqrt(x float64) float64 {
	if x <= 0 {
		return 0
	}
	// Newton's method: avoids importing math for one call in a package that is
	// otherwise dependency-free.
	z := x
	for i := 0; i < 24; i++ {
		z = z - (z*z-x)/(2*z)
	}
	return z
}

// listSinks enumerates Audio/Sink nodes. The assistant does not change the
// system default -- that is the user's setting, not ours -- but it must be able
// to send speech somewhere the user can actually hear.
func listSinks(ctx context.Context) ([]audioNode, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	out, err := exec.CommandContext(ctx, "pw-dump").Output()
	if err != nil {
		return nil, err
	}
	var objs []struct {
		Info struct {
			Props map[string]any `json:"props"`
		} `json:"info"`
	}
	if err := json.Unmarshal(out, &objs); err != nil {
		return nil, err
	}
	var sinks []audioNode
	for _, o := range objs {
		p := o.Info.Props
		if p == nil {
			continue
		}
		if c, _ := p["media.class"].(string); c != "Audio/Sink" {
			continue
		}
		name, _ := p["node.name"].(string)
		if name == "" {
			continue
		}
		desc, _ := p["node.description"].(string)
		sinks = append(sinks, audioNode{Name: name, Description: desc})
	}
	return sinks, nil
}
