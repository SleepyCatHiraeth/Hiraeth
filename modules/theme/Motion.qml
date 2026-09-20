pragma Singleton
import QtQuick
import qs.config

// The shell's motion vocabulary.
//
// Durations and curves were written out at every call site: `Config.animDuration`,
// `/2`, `/4`, `*2`, and a handful of hardcoded 200, 400, 520 and 1000 ms. The
// curves were a convention nobody had written down — OutQuart for size and
// opacity, OutCubic for movement, OutBack 1.2 for expansion, InOutSine for
// ambient pulses — which held everywhere it was remembered.
//
// Everything still scales from `Config.animDuration`, so the existing setting
// and game mode's zero keep working exactly as before.
QtObject {
    id: root

    readonly property int base: Config.animDuration

    // Enter and exit must not share a curve: an element arriving decelerates
    // into place, one leaving accelerates away. Using the same easing for both
    // is what makes a panel feel like it is being dragged rather than moving.
    readonly property int micro: Math.round(base / 4)      // hover, focus ring, ripple
    readonly property int fast: Math.round(base / 2)       // selection, small fades
    readonly property int normal: base                     // content transitions, radius
    readonly property int enter: base                      // expansion, arrival
    readonly property int exit: Math.round(base * 0.66)    // dismissal, collapse
    readonly property int ambient: 520                     // pulses, breathing

    readonly property int microEasing: Easing.OutQuad
    readonly property int fastEasing: Easing.OutCubic
    readonly property int normalEasing: Easing.OutQuart
    readonly property int enterEasing: Easing.OutBack
    readonly property real enterOvershoot: 1.2
    readonly property int exitEasing: Easing.OutQuad
    readonly property int ambientEasing: Easing.InOutSine

    // Whether motion should be suppressed.
    //
    // `Config.animDuration = 0` was the only lever and it was never a real
    // reduced-motion mode: several animations ignored it entirely, because they
    // were written with a hardcoded duration and a `running` that did not
    // consult it. Both routes land here now.
    readonly property bool reduced: Config.theme.reducedMotion || base <= 0

    // For `Behavior { enabled: Motion.enabled }` and for the `running` of any
    // looping animation. A pulse that keeps running under reduced motion is the
    // one people actually notice.
    readonly property bool enabled: !reduced
}
