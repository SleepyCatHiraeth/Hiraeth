pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Reads the snapshot that modules/theme/GreeterGenerator.qml publishes.
// Every value has a fallback so a missing or half-written snapshot still
// produces a usable login screen.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("AMBXST_GREETER_DIR") || "/var/lib/ambxst-greeter"

    property var palette: ({})
    property var config: ({})

    function color(name, fallback) {
        const v = palette[name];
        return v ? v : fallback;
    }

    readonly property color background: color("background", "#0d0d0e")
    readonly property color surface: color("surface", "#131315")
    readonly property color surfaceContainer: color("surfaceContainer", "#1f1f21")
    readonly property color surfaceContainerHigh: color("surfaceContainerHigh", "#2a2a2c")
    readonly property color surfaceContainerHighest: color("surfaceContainerHighest", "#353436")
    readonly property color overSurface: color("overSurface", "#e4e2e4")
    readonly property color overSurfaceVariant: color("overSurfaceVariant", "#c5c6cd")
    readonly property color outline: color("outline", "#8f9097")
    readonly property color outlineVariant: color("outlineVariant", "#45474d")
    readonly property color primary: color("primary", "#cfdaf7")
    readonly property color overPrimary: color("overPrimary", "#253046")
    readonly property color primaryFixed: color("primaryFixed", "#d8e2ff")
    readonly property color primaryFixedDim: color("primaryFixedDim", "#bbc6e3")
    readonly property color error: color("error", "#ffb4ab")
    readonly property color overError: color("overError", "#690005")
    readonly property color shadow: color("shadow", "#000000")

    readonly property string user: config.user || Quickshell.env("AMBXST_GREETER_USER") || ""
    readonly property string font: config.font || "Roboto Condensed"
    readonly property string mono: config.monoFont || "monospace"
    readonly property string clockFont: config.clockFont || "League Gothic"
    readonly property int roundness: config.roundness !== undefined ? config.roundness : 16
    readonly property bool use12h: config.use12hFormat === true
    readonly property bool reducedMotion: config.reducedMotion === true || config.animDuration === 0
    readonly property url wallpaper: config.wallpaper ? "file://" + dir + "/" + config.wallpaper : ""
    // May not exist; LoginCard falls back to the initial when it fails to load.
    readonly property url avatar: "file://" + dir + "/avatar.png"

    readonly property string wallpaperKind: {
        const ext = (config.wallpaper || "").split(".").pop().toLowerCase();
        if (ext === "gif")
            return "gif";
        if (["mp4", "webm", "mkv", "mov", "avi", "m4v"].includes(ext))
            return "video";
        return config.wallpaper ? "image" : "none";
    }

    // Base unit for all motion. The shell's own setting scales everything, so a
    // user who likes snappier animations gets a snappier greeter too; 0 or
    // reduced motion collapses every transition to an instant state change.
    readonly property int base: reducedMotion ? 0 : Math.max(120, config.animDuration || 300)
    function dur(factor) {
        return Math.round(base * factor);
    }

    // Staggered choreography: one 0..1 timeline, each element reads its own
    // window of it. Reversing the timeline reverses every element in order.
    function span(t, from, to) {
        return Math.max(0, Math.min(1, (t - from) / (to - from)));
    }
    function outCubic(x) {
        return 1 - Math.pow(1 - x, 3);
    }
    function outQuint(x) {
        return 1 - Math.pow(1 - x, 5);
    }
    function outBack(x) {
        const c1 = 1.70158, c3 = c1 + 1;
        return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2);
    }

    readonly property string iconFont: "Phosphor-Bold"

    // Matches Config.roundness semantics: 16 is fully rounded pills.
    function pillRadius(h) {
        return roundness > 0 ? (h / 2) * Math.min(1, roundness / 16) : 0;
    }

    FileView {
        path: root.dir + "/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.palette = JSON.parse(text());
            } catch (e) {
                console.warn("greeter: colors.json unreadable, using fallback palette");
            }
        }
    }

    FileView {
        path: root.dir + "/theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.config = JSON.parse(text());
            } catch (e) {
                console.warn("greeter: theme.json unreadable, using defaults");
            }
        }
    }
}
