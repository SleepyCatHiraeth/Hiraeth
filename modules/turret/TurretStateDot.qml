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
Item {
    id: root

    property color accent: "#ffffff"
    property bool spinning: false
    property bool pulsing: false

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
        running: root.pulsing && Config.animDuration > 0
        loops: Animation.Infinite
        alwaysRunToEnd: false
        NumberAnimation {
            target: dot; property: "opacity"
            to: 0.3; duration: 620; easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: dot; property: "opacity"
            to: 1.0; duration: 620; easing.type: Easing.InOutSine
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
        visible: root.spinning && !root.pulsing && Config.animDuration > 0
    }

    SequentialAnimation {
        running: ring.visible
        loops: Animation.Infinite
        ParallelAnimation {
            NumberAnimation {
                target: ring; property: "width"
                from: 8; to: 17; duration: 1100; easing.type: Easing.OutQuart
            }
            NumberAnimation {
                target: ring; property: "height"
                from: 8; to: 17; duration: 1100; easing.type: Easing.OutQuart
            }
            NumberAnimation {
                target: ring; property: "opacity"
                from: 0.55; to: 0; duration: 1100; easing.type: Easing.OutQuart
            }
        }
    }
}
