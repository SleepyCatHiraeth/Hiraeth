pragma ComponentBehavior: Bound

import QtQuick
import qs.config

// The state indicator: a small dot that carries "is it working?" without
// needing to be read.
//
// Two distinct motions, because they mean different things:
//   pulsing  the microphone is OPEN. Not suppressible, and the loudest signal
//            the notch has -- this is a privacy indicator, not decoration.
//   spinning the assistant is busy but not capturing.
//
// A static dot means it is waiting for the user.
//
// Three rules the first version broke:
//   - Nothing animates while it cannot be seen. Both loops ran whenever the
//     state said so, including while the notch was collapsed or on another
//     screen, waking the compositor to repaint nothing. `live` is the gate,
//     and AiNotchCollapsed.qml does the same thing for the same reason.
//   - Motion is scale, not geometry. The ring animated width and height, so
//     every frame re-ran layout for an effect that is purely visual.
//   - Durations come from the theme. 620ms and 1100ms were hardcoded, so the
//     animation speed setting moved everything in the shell except this.
Item {
    id: root

    property color accent: "#ffffff"
    property bool spinning: false
    property bool pulsing: false
    // False whenever this indicator is not actually on screen.
    property bool live: true

    readonly property bool animate: Config.animDuration > 0 && live
    // The theme's duration is a UI transition; these are ambient loops, which
    // read as frantic at that speed. Scaled, not invented, so the setting still
    // governs them.
    readonly property int breathe: Math.round(Config.animDuration * 2.1)
    readonly property int halo: Math.round(Config.animDuration * 3.7)

    implicitWidth: 9
    implicitHeight: 9

    Rectangle {
        id: dot
        anchors.centerIn: parent
        width: 8
        height: 8
        radius: 4
        color: root.accent

        Behavior on color {
            enabled: Config.animDuration > 0
            ColorAnimation { duration: Config.animDuration }
        }
    }

    // Capture pulse. Runs whenever the microphone is open, and takes priority
    // over the busy ring below.
    SequentialAnimation {
        running: root.pulsing && root.animate
        loops: Animation.Infinite
        alwaysRunToEnd: false
        NumberAnimation {
            target: dot; property: "opacity"
            to: 0.3; duration: root.breathe; easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: dot; property: "opacity"
            to: 1.0; duration: root.breathe; easing.type: Easing.InOutSine
        }
        onRunningChanged: if (!running) dot.opacity = 1
    }

    // Busy ring: a halo that breathes outward. Cheap, and reads as activity
    // without the jitter of a spinner at this size.
    Rectangle {
        id: ring
        anchors.centerIn: parent
        width: 8
        height: 8
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: root.accent
        opacity: 0
        visible: root.spinning && !root.pulsing && root.animate
        transformOrigin: Item.Center
    }

    SequentialAnimation {
        running: ring.visible
        loops: Animation.Infinite
        ParallelAnimation {
            NumberAnimation {
                target: ring; property: "scale"
                from: 1.0; to: 2.15; duration: root.halo; easing.type: Easing.OutQuart
            }
            NumberAnimation {
                target: ring; property: "opacity"
                from: 0.55; to: 0; duration: root.halo; easing.type: Easing.OutQuart
            }
        }
        onRunningChanged: if (!running) { ring.scale = 1; ring.opacity = 0; }
    }
}
