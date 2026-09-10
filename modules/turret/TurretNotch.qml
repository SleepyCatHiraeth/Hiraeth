pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.ainotch
import qs.modules.globals
import qs.modules.services
import qs.modules.theme
import qs.config

// The turret assistant's own notch: a top-edge notch living in the free region
// between the centred dynamic island and the top-right screen corner.
//
// Deliberately independent of the assistant sidebar. That panel owns the
// cloud-provider chat, its keyboard-focus repair and its frame-merge geometry;
// none of that applies here, and sharing the container would have meant
// re-deriving all of it. What *is* shared is the silhouette: AiNotch is already
// edge-agnostic (NotchEdge.js handles all four edges, and NotchEdge.test.js
// covers them), so this is a new position for an existing shape, not a new
// shape.
Item {
    id: root

    required property var screen

    // Only draw on the screen the toggle placed us on. Every other screen's
    // instance stays zero-sized and invisible, the same way the rest of the
    // per-screen shell surfaces behave.
    readonly property bool onActiveScreen: screen && GlobalStates.turretScreenName === screen.name
    readonly property bool active: GlobalStates.turretVisible && onActiveScreen

    readonly property string state: TurretService.state

    // Widen while there is text to show, so the resting notch stays small.
    readonly property string caption: {
        switch (root.state) {
        case "listening":
            return "Listening";
        case "transcribing":
            return "Transcribing";
        case "thinking":
            return "Thinking";
        case "speaking":
            return TurretService.response !== "" ? TurretService.response : "Speaking";
        case "cancelled":
            return "Cancelled";
        case "error":
            return TurretService.lastError !== "" ? TurretService.lastError : "Error";
        default:
            return TurretService.transcript !== "" ? TurretService.transcript : "Ready";
        }
    }

    readonly property int restingLength: 220
    readonly property int expandedLength: 460
    readonly property int restingDepth: 34

    // How far the notch sits in from the right screen corner. Keeps the flare
    // off the corner radius rather than fighting it.
    readonly property int cornerInset: 48

    readonly property int frameOffset: (Config.bar?.frameEnabled ?? false) ? (Config.bar?.frameThickness ?? 6) : 0

    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: frameOffset
    anchors.rightMargin: cornerInset

    width: active ? (caption.length > 24 ? expandedLength : restingLength) : 0
    height: active ? restingDepth : 0
    visible: width > 0 && height > 0

    Behavior on width {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: Easing.OutCubic
        }
    }

    Behavior on height {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: Easing.OutCubic
        }
    }

    AiNotch {
        anchors.fill: parent
        edge: "top"
        flareSize: 12
        bodyRadius: Config.roundness
        surfaceVariant: "bg"
        borderEnabled: true

        Row {
            anchors.centerIn: parent
            spacing: 8
            // Cross-fade contents in only once the shell has most of its width,
            // so the glyph never appears floating in a sliver.
            opacity: root.width > root.restingLength * 0.6 ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                }
            }

            // Microphone capture indicator. Bound to the backend's real state,
            // never to the UI's belief about it, and it is not suppressible:
            // if the microphone is open, this is visible.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 4
                color: Colors.criticalRed
                visible: TurretService.capturing

                SequentialAnimation on opacity {
                    running: TurretService.capturing && Config.animDuration > 0
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.state === "error" ? Icons.alert : Icons.robot
                font.family: Icons.font
                font.pixelSize: 16
                color: root.state === "error" ? Colors.criticalText : Colors.overSurface
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.caption
                elide: Text.ElideRight
                width: Math.min(implicitWidth, root.width - 90)
                font.family: Config.theme.font
                font.pixelSize: 12
                color: Colors.overSurface
            }
        }

        // Escape and a click both cancel. Cancelling is always reachable while
        // the assistant is doing anything at all.
        MouseArea {
            anchors.fill: parent
            enabled: TurretService.busy
            cursorShape: Qt.PointingHandCursor
            onClicked: TurretService.cancel()
        }
    }
}
