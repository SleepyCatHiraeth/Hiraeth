import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.services

// Publishes a read-only snapshot of the current look for the greetd greeter
// (greeter/). The greeter runs as the `greeter` user, which cannot read
// ~/.cache or ~/.config, so everything it needs is copied to a world-readable
// directory. Only public data goes here: palette, fonts, wallpaper, avatar,
// login name. Never secrets.
QtObject {
    id: root

    // /var/lib/ambxst-greeter is created (owned by the user) by
    // greeter/install.sh and survives tmpfiles cleanup; before install the
    // snapshot goes to /var/tmp so the preview still works.
    readonly property string outDir: "/var/lib/ambxst-greeter"
    readonly property string fallbackDir: "/var/tmp/ambxst-greeter"

    // Same main-screen rule as SddmGenerator: the largest screen carries the
    // login card, so its wallpaper is the one the greeter shows.
    readonly property string mainScreenName: {
        var best = "";
        var bestArea = -1;
        const screens = Quickshell.screens || [];
        for (var i = 0; i < screens.length; i++) {
            const area = screens[i].width * screens[i].height;
            if (area > bestArea) {
                bestArea = area;
                best = screens[i].name;
            }
        }
        return best;
    }

    readonly property string wallpaperPath: {
        const perScreen = wallpaperConfig.adapter.perScreenWallpapers;
        if (mainScreenName && perScreen && perScreen[mainScreenName])
            return perScreen[mainScreenName];
        return wallpaperConfig.adapter.currentWall;
    }

    function snapshot() {
        const ext = (wallpaperPath.split(".").pop() || "").toLowerCase();
        return {
            version: 1,
            user: Quickshell.env("USER"),
            wallpaper: wallpaperPath ? "wallpaper." + ext : "",
            font: Config.theme.font,
            monoFont: Config.theme.monoFont,
            clockFont: Config.theme.font,
            roundness: Config.roundness,
            // theme.animDuration, not Config.animDuration: the latter is 0 while
            // game mode is on, which must not leak into the login screen.
            animDuration: Config.theme.animDuration,
            reducedMotion: Config.theme.reducedMotion,
            use12hFormat: Config.bar.use12hFormat,
            lockPosition: Config.lockscreen.position,
            sound: {
                volume: Config.sound.volume,
                // The greeter's success cue is the theme's boot-up sound: logging
                // in is the moment the system "boots" for the user.
                loginSuccess: soundFor("bootUp") ? "sound-loginSuccess.wav" : "",
                wrongPassword: soundFor("wrongPassword") ? "sound-wrongPassword.wav" : ""
            },
            // Last successful fetch. The greeter cannot reach the backend that
            // fetches weather, so it shows this and hides it once stale.
            weather: WeatherService.dataAvailable && weatherStamp > 0 ? {
                updated: weatherStamp,
                location: Config.weather.location,
                unit: Config.weather.unit,
                temp: WeatherService.currentTemp,
                max: WeatherService.maxTemp,
                min: WeatherService.minTemp,
                code: WeatherService.weatherCode,
                description: WeatherService.weatherDescription,
                sunrise: WeatherService.sunrise,
                sunset: WeatherService.sunset
            } : null
        };
    }

    // Same resolution as SoundService.play(): absolute override, else the
    // configured theme, else the default theme. Empty when muted/disabled.
    function soundFor(key) {
        if (!Config.sound.enabled)
            return "";
        const event = Config.sound.events ? Config.sound.events[key] : null;
        if (!event || event.muted)
            return "";
        if (typeof event.sound === "string" && event.sound.startsWith("/"))
            return event.sound;
        let theme = SoundThemes.resolveTheme(Config.sound.theme);
        if (!theme.available)
            theme = SoundThemes.resolveTheme("default");
        const file = theme.events[key];
        return file ? theme.basePath + file : "";
    }

    // Coalesces the burst of change signals a theme switch produces.
    function generate() {
        debounce.restart();
    }

    property Timer debounce: Timer {
        interval: 500
        onTriggered: {
            if (writer.running) {
                root.dirty = true;
                return;
            }
            const home = Quickshell.env("HOME");
            // Arguments are passed positionally so paths with spaces or quotes
            // are never interpreted by the shell.
            writer.command = ["sh", "-c", `
                set -e
                umask 022
                out="$1"; wall="$2"; ext="$3"; json="$4"; cache="$5"
                [ -d "$out" ] && [ -w "$out" ] || out="$7"
                mkdir -p "$out"
                tmp="$out/.theme.json.tmp"
                printf '%s' "$json" > "$tmp" && mv -f "$tmp" "$out/theme.json"
                [ -f "$cache/colors.json" ] && cp -f -- "$cache/colors.json" "$out/colors.json"
                [ -f "$cache/sddm-face.png" ] && cp -f -- "$cache/sddm-face.png" "$out/avatar.png"
                if [ -n "$wall" ] && [ -f "$wall" ] && ! cmp -s -- "$wall" "$out/wallpaper.$ext"; then
                    find "$out" -maxdepth 1 -name 'wallpaper.*' ! -name "wallpaper.$ext" -delete
                    cp -f -- "$wall" "$out/.wallpaper.tmp" && mv -f "$out/.wallpaper.tmp" "$out/wallpaper.$ext"
                fi
                # Pending Arch updates as counted by arch-update's last check.
                state="$6"
                if [ -f "$state/last_updates_check" ]; then
                    grep -c . "$state/last_updates_check" > "$out/updates" || true
                else
                    rm -f "$out/updates"
                fi
                # Start of this session, shown by the greeter as "last login"
                # next time. greetd does not write wtmp, so last(1) cannot be used.
                if [ -n "$8" ] && ts=$(loginctl show-session "$8" -p Timestamp --value 2>/dev/null) && [ -n "$ts" ]; then
                    date -d "$ts" +%s > "$out/lastlogin" || true
                fi
                # Login sounds: pairs of <source> <name> after the fixed args.
                shift 8
                rm -f "$out"/sound-*.wav
                while [ $# -ge 2 ]; do
                    [ -n "$1" ] && [ -f "$1" ] && cp -f -- "$1" "$out/$2"
                    shift 2
                done
                chmod -R a+rX "$out"
            `, "sh", root.outDir, root.wallpaperPath, (root.wallpaperPath.split(".").pop() || "").toLowerCase(), JSON.stringify(root.snapshot()), home + "/.cache/ambxst",
                home + "/.local/state/arch-update", root.fallbackDir, Quickshell.env("XDG_SESSION_ID"),
                root.soundFor("bootUp"), "sound-loginSuccess.wav",
                root.soundFor("wrongPassword"), "sound-wrongPassword.wav"];
            writer.running = true;
        }
    }

    property bool dirty: false
    property real weatherStamp: 0

    property Connections weatherWatch: Connections {
        target: WeatherService
        function onIsLoadingChanged() {
            if (!WeatherService.isLoading && WeatherService.dataAvailable) {
                root.weatherStamp = Date.now();
                root.generate();
            }
        }
    }

    property Process writer: Process {
        running: false
        stderr: StdioCollector {
            onStreamFinished: {
                if (text)
                    console.error("GreeterGenerator:", text);
            }
        }
        onExited: {
            if (root.dirty) {
                root.dirty = false;
                root.debounce.restart();
            }
        }
    }

    property FileView wallpaperConfig: FileView {
        path: Quickshell.env("HOME") + "/.cache/ambxst/wallpapers.json"
        preload: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.generate()

        adapter: JsonAdapter {
            property string currentWall: ""
            property var perScreenWallpapers: ({})
        }
    }

    onWallpaperPathChanged: generate()

    property Connections configWatch: Connections {
        target: Config
        function onRoundnessChanged() { root.generate(); }
        function onDefaultFontChanged() { root.generate(); }
    }
}
