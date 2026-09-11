package assistant

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// The first and only tool, deliberately boring.
//
// Its job is to prove the framework end to end with a blast radius of zero:
// read-only, no arguments, no approval, nothing of the user's in it, and no
// subprocess at all. Anything that writes, executes, reads the user's files or
// touches the network comes later, behind the approval path, and only once a
// human has reviewed this machinery.
//
// It is native Go rather than a shell-out on purpose. The obvious way to write
// this would have been `sh -c "df -h / && uptime"`, and that is precisely the
// habit this layer exists to break: a tool that needs no process should not
// start one.
func init() {
	registerTool(Tool{
		Name:     "system_status",
		Describe: "Battery level, free disk space on /, uptime and the current time.",
		Timeout:  5 * time.Second,
		Run: func(ctx context.Context, _ map[string]any) (string, error) {
			var parts []string

			if pct, ok := batteryPercent(); ok {
				parts = append(parts, fmt.Sprintf("battery %d%%", pct))
			}
			if free, ok := diskFreeGiB("/"); ok {
				parts = append(parts, fmt.Sprintf("%.1f GiB free on /", free))
			}
			if up, ok := uptime(); ok {
				parts = append(parts, "up "+up.Round(time.Minute).String())
			}
			parts = append(parts, "time "+time.Now().Format("15:04"))

			return strings.Join(parts, ", "), nil
		},
	})
}

// batteryPercent reads sysfs. Desktops have no battery, and saying nothing is
// better than saying zero.
func batteryPercent() (int, bool) {
	for _, name := range []string{"BAT0", "BAT1"} {
		raw, err := os.ReadFile("/sys/class/power_supply/" + name + "/capacity")
		if err != nil {
			continue
		}
		if pct, err := strconv.Atoi(strings.TrimSpace(string(raw))); err == nil {
			return pct, true
		}
	}
	return 0, false
}

func diskFreeGiB(path string) (float64, bool) {
	var st syscall.Statfs_t
	if err := syscall.Statfs(path, &st); err != nil {
		return 0, false
	}
	return float64(st.Bavail) * float64(st.Bsize) / (1 << 30), true
}

func uptime() (time.Duration, bool) {
	raw, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return 0, false
	}
	fields := strings.Fields(string(raw))
	if len(fields) == 0 {
		return 0, false
	}
	secs, err := strconv.ParseFloat(fields[0], 64)
	if err != nil {
		return 0, false
	}
	return time.Duration(secs) * time.Second, true
}
