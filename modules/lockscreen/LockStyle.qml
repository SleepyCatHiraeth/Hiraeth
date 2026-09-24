pragma Singleton

import QtQuick
import Quickshell
import qs.modules.theme
import qs.config

// The greeter's Theme API over the live shell theme, so the lockscreen
// components stay line-for-line comparable with greeter/ (which has to read
// a published snapshot instead, because it runs outside the session).
Singleton {
    id: root

    function color(name, fallback) {
        const v = Colors[name];
        return v !== undefined ? v : fallback;
    }

    readonly property color background: Colors.background
    readonly property color surfaceContainerHigh: Colors.surfaceContainerHigh
    readonly property color overSurface: Colors.overSurface
    readonly property color outline: Colors.outline
    readonly property color primary: Colors.primary
    readonly property color primaryFixed: Colors.primaryFixed
    readonly property color error: Colors.error
    readonly property color shadow: Colors.shadow

    readonly property string font: Config.theme.font
    readonly property string mono: Config.theme.monoFont
    // Matches GreeterGenerator's clockFont so lock and login share a clock.
    readonly property string clockFont: Config.theme.font
    readonly property string iconFont: Icons.font
    readonly property int roundness: Config.roundness
    readonly property bool use12h: Config.bar.use12hFormat

    // Config.animDuration is 0 in game mode, which collapses every
    // transition to an instant state change.
    readonly property int base: Config.animDuration > 0 ? Math.max(120, Config.animDuration) : 0
    function dur(factor) {
        return Math.round(base * factor);
    }

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

    function pillRadius(h) {
        return roundness > 0 ? (h / 2) * Math.min(1, roundness / 16) : 0;
    }
}
