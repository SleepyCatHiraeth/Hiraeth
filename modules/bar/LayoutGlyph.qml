import QtQuick
import qs.modules.theme

// A live miniature of a tiling layout drawn from tiles instead of a font
// glyph. Switching `layout` morphs the tiles into the new arrangement,
// `playing` loops a small demonstration of how the layout behaves (dwindle
// re-splits, master's split breathes, scrolling columns glide past, monocle
// lifts its front card), and `reveal` (0..1) builds the tiles in one by one.
Item {
    id: root

    property string layout: "dwindle"
    property color color: Colors.overSurface
    property bool playing: false
    property real reveal: 1

    implicitWidth: 18
    implicitHeight: 18
    clip: true

    readonly property real gap: Math.max(1, Math.round(width / 12))
    readonly property real tileRadius: Math.max(1, width * 0.1)

    // One continuous clock drives every loop; `amp` fades the motion in when
    // hovering starts and back out when it ends, so nothing ever snaps.
    property real clock: 0
    property real amp: playing && Motion.enabled ? 1 : 0
    readonly property bool looping: amp > 0.001

    NumberAnimation on clock {
        running: root.looping && Motion.enabled
        from: 0
        to: 1
        duration: 2600
        loops: Animation.Infinite
    }
    Behavior on amp {
        NumberAnimation {
            duration: root.playing ? 260 : 520
            easing.type: root.playing ? Easing.OutCubic : Easing.InOutCubic
        }
    }
    onLoopingChanged: if (!looping)
        clock = 0

    // Smooth 0 → 1 → 0 swell over one clock cycle.
    readonly property real swell: amp * (1 - Math.cos(clock * 2 * Math.PI)) / 2
    // Scrolling: hold, then glide one column; the wrap at clock = 1 lands on
    // an identical frame, so the strip scrolls forever without a seam.
    readonly property real glide: {
        const x = Math.max(0, Math.min(1, (clock - 0.3) / 0.7));
        return amp * (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
    }

    function lerp(a, b, t) {
        return a + (b - a) * t;
    }

    // Unit-square rectangles [x, y, w, h] for tile i, or null when unused.
    function geom(layout, i) {
        const p = swell;
        switch (layout) {
        case "master": {
            const m = lerp(0.58, 0.44, p);
            return [[0, 0, m, 1], [m, 0, 1 - m, 1 / 3], [m, 1 / 3, 1 - m, 1 / 3], [m, 2 / 3, 1 - m, 1 / 3]][i];
        }
        case "scrolling": {
            // A centred column with equal peeks of its neighbours; a fourth
            // column waits off the right edge to scroll in.
            const w = 0.5, step = w + 0.02;
            return [0.25 + (i - 1 - glide) * step, 0, w, 1];
        }
        case "monocle": {
            // A stacked deck; the front card lifts off and settles back.
            const off = 0.14, w = 1 - off * 2;
            return [[off * 2, 0, w, w], [off, off, w, w], [lerp(0, -0.18, p), lerp(off * 2, off * 2 + 0.1, p), w, w], null][i];
        }
        default: {
            // Dwindle: the last pair flips its split direction.
            return [[0, 0, 0.5, 1], [0.5, 0, 0.5, 0.5],
                [0.5, 0.5, lerp(0.25, 0.5, p), lerp(0.5, 0.25, p)],
                [lerp(0.75, 0.5, p), lerp(0.5, 0.75, p), lerp(0.25, 0.5, p), lerp(0.5, 0.25, p)]][i];
        }
        }
    }

    Repeater {
        model: 4

        Rectangle {
            id: tile
            required property int index

            readonly property var g: root.geom(root.layout, index)
            readonly property bool used: g !== null && g !== undefined
            // The solid tile: monocle's front card, whichever scrolling
            // column is centred, otherwise the first tile.
            readonly property real lit: {
                if (!used)
                    return 0;
                if (root.layout === "monocle")
                    return index === 2 ? 1 : 0;
                if (root.layout === "scrolling")
                    return Math.max(0, 1 - Math.abs(g[0] + g[2] / 2 - 0.5) / 0.5);
                return index === 0 ? 1 : 0;
            }
            // Staggered build-in, each tile easing up from its own centre.
            readonly property real grow: {
                const x = Math.max(0, Math.min(1, (root.reveal - index * 0.12) / 0.55));
                return 1 - Math.pow(1 - x, 3);
            }

            x: used ? g[0] * root.width + root.gap / 2 : root.width / 2
            y: used ? g[1] * root.height + root.gap / 2 : root.height / 2
            width: used ? Math.max(0, g[2] * root.width - root.gap) : 0
            height: used ? Math.max(0, g[3] * root.height - root.gap) : 0
            radius: root.tileRadius
            color: root.color
            opacity: (used ? 0.5 + 0.5 * lit : 0) * grow
            scale: 0.55 + 0.45 * grow

            // Morph between layouts; while looping the clock drives geometry.
            Behavior on x { enabled: Motion.enabled && !root.looping; NumberAnimation { duration: Motion.normal * 1.3; easing.type: Easing.InOutCubic } }
            Behavior on y { enabled: Motion.enabled && !root.looping; NumberAnimation { duration: Motion.normal * 1.3; easing.type: Easing.InOutCubic } }
            Behavior on width { enabled: Motion.enabled && !root.looping; NumberAnimation { duration: Motion.normal * 1.3; easing.type: Easing.InOutCubic } }
            Behavior on height { enabled: Motion.enabled && !root.looping; NumberAnimation { duration: Motion.normal * 1.3; easing.type: Easing.InOutCubic } }
            Behavior on color { enabled: Motion.enabled; ColorAnimation { duration: Motion.normal } }
        }
    }
}
