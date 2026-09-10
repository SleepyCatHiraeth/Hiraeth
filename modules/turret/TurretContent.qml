pragma ComponentBehavior: Bound

import QtQuick
import qs.config

// Content that arrives after the notch shape has settled.
//
// The first version keyed content opacity off a width threshold, which meant
// text popped mid-expansion and the threshold had to be re-tuned whenever a
// size changed. Here `shown` is driven by the shape animation completing, so
// the two cannot disagree.
//
// Scale-with-overshoot plus opacity is the same arrival motion the top notch
// uses (modules/notch/NotchAnimationBehavior.qml), so both notches feel like
// one system.
Item {
    id: root

    property bool shown: false

    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.92
    visible: opacity > 0.01
    // Never intercept clicks while fading out.
    enabled: shown

    Behavior on opacity {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Math.round(Config.animDuration * 0.6)
            easing.type: Easing.OutQuart
        }
    }

    Behavior on scale {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Math.round(Config.animDuration * 0.8)
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }
}
