pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.ainotch
import qs.modules.globals
import qs.modules.services
import qs.modules.theme
import qs.modules.components
import qs.config

// The turret assistant's own notch: a top-edge notch living in the free region
// between the centred dynamic island and the top-right screen corner.
//
// Deliberately independent of the assistant sidebar. That panel owns the
// cloud-provider chat, its keyboard-focus repair and its frame-merge geometry;
// none of that applies here. What *is* shared is the silhouette: AiNotch is
// already edge-agnostic (NotchEdge.js handles all four edges), so this is a new
// position for an existing shape, not a new shape.
//
// Motion follows the house vocabulary rather than a private one: OutQuart for
// size, OutBack with overshoot for things arriving, matching
// modules/notch/NotchAnimationBehavior.qml. Width and height are deliberately
// NOT on the same curve -- animating both identically makes the shape stretch
// diagonally, which reads as rubbery next to the top notch.
Item {
    id: root

    required property var screen

    readonly property bool onActiveScreen: screen && GlobalStates.turretScreenName === screen.name
    readonly property bool active: TurretService.enabled && GlobalStates.turretVisible && onActiveScreen

    readonly property string state: TurretService.state
    readonly property color accent: TurretStateStyle.accent(state)

    readonly property bool reviewing: TurretService.pendingMemories > 0
                                      && TurretService.reviewQueue.length > 0
                                      && !TurretService.busy
    readonly property var reviewItem: reviewing ? TurretService.reviewQueue[0] : null

    readonly property string caption: TurretStateStyle.label(
        state, TurretService.transcript, TurretService.response,
        TurretService.lastError, TurretService.lastErrorKind)

    // Size tiers. Width follows content; height only changes for the review card.
    readonly property int restingLength: 200
    readonly property int expandedLength: 460
    readonly property int reviewLength: 560
    readonly property int restingDepth: 34
    readonly property int reviewDepth: 84

    readonly property int cornerInset: 48
    readonly property int frameOffset: (Config.bar?.frameEnabled ?? false) ? (Config.bar?.frameThickness ?? 6) : 0

    // The shell panel is one full-screen surface whose `mask` limits input to
    // registered hitboxes. Anything not listed there is click-through, so this
    // must be published or the review buttons cannot be pressed. Only claim
    // input when there is something to click.
    readonly property bool interactive: active && (reviewing || TurretService.busy)
    readonly property alias hitbox: notchHitbox

    // Content fades in once the shape has essentially arrived, rather than on a
    // width threshold. `shapeSettled` is driven by the animation itself, so the
    // two can never disagree.
    property bool shapeSettled: false

    readonly property int targetLength: {
        if (!active)
            return 0;
        if (reviewing)
            return reviewLength;
        return caption.length > 22 ? expandedLength : restingLength;
    }
    readonly property int targetDepth: active ? (reviewing ? reviewDepth : restingDepth) : 0

    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: frameOffset
    anchors.rightMargin: cornerInset

    width: targetLength
    height: targetDepth
    visible: width > 1 && height > 1

    onActiveChanged: if (!active) shapeSettled = false

    // Width leads. The notch grows along its edge first, which is the axis the
    // eye reads as "opening".
    Behavior on width {
        enabled: Config.animDuration > 0
        SequentialAnimation {
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutQuart
            }
            ScriptAction {
                script: root.shapeSettled = root.active
            }
        }
    }

    // Height follows, shorter and slightly behind, so the shape settles into
    // depth instead of ballooning on both axes at once.
    Behavior on height {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Math.round(Config.animDuration * 0.7)
            easing.type: Easing.OutQuart
        }
    }

    // With animations off there is no ScriptAction to fire, so settle immediately.
    Component.onCompleted: if (Config.animDuration <= 0) shapeSettled = true
    onTargetLengthChanged: if (Config.animDuration <= 0) shapeSettled = active

    Item {
        id: notchHitbox
        anchors.fill: parent
        visible: root.interactive
    }

    AiNotch {
        anchors.fill: parent
        edge: "top"
        flareSize: 12
        bodyRadius: Config.roundness
        surfaceVariant: "bg"
        borderEnabled: true

        // ---- Status row -------------------------------------------------
        TurretContent {
            anchors.fill: parent
            shown: root.shapeSettled && !root.reviewing

            RowLayout {
                anchors.centerIn: parent
                width: parent.width - 24
                spacing: 8

                TurretStateDot {
                    Layout.alignment: Qt.AlignVCenter
                    accent: root.accent
                    spinning: TurretStateStyle.animated(root.state)
                    pulsing: TurretService.capturing
                }

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: TurretStateStyle.glyph(root.state)
                    font.family: Icons.font
                    font.pixelSize: 15
                    color: root.accent

                    Behavior on color {
                        enabled: Config.animDuration > 0
                        ColorAnimation { duration: Config.animDuration }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: root.caption
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Config.theme.font
                    font.pixelSize: 12
                    color: Colors.overSurface
                }
            }
        }

        // ---- Memory review card ------------------------------------------
        TurretContent {
            anchors.fill: parent
            shown: root.shapeSettled && root.reviewing

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 11
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: Icons.robot
                        font.family: Icons.font
                        font.pixelSize: 11
                        color: Colors.overSurfaceVariant
                    }
                    Text {
                        Layout.fillWidth: true
                        text: TurretService.pendingMemories > 1
                              ? "Remember this? · " + TurretService.pendingMemories + " waiting"
                              : "Remember this?"
                        elide: Text.ElideRight
                        font.family: Config.theme.font
                        font.pixelSize: 10
                        color: Colors.overSurfaceVariant
                    }
                    Text {
                        text: root.reviewItem ? root.reviewItem.category.replace(/_/g, " ") : ""
                        font.family: Config.theme.font
                        font.pixelSize: 10
                        color: Colors.overSurfaceVariant
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.reviewItem ? root.reviewItem.content : ""
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Config.theme.font
                    font.pixelSize: 12
                    color: Colors.overSurface
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    TurretChip {
                        text: "Keep"
                        glyph: Icons.accept
                        accent: Colors.primary
                        onActivated: if (root.reviewItem) TurretService.confirmMemory(root.reviewItem.id)
                    }
                    TurretChip {
                        text: "Discard"
                        glyph: Icons.cancel
                        accent: Colors.criticalRed
                        onActivated: if (root.reviewItem) TurretService.forgetMemory(root.reviewItem.id)
                    }
                    Item { Layout.fillWidth: true }
                }
            }
        }

        // Cancelling stays reachable whenever the assistant is working, but must
        // not sit on top of the review buttons.
        MouseArea {
            anchors.fill: parent
            enabled: TurretService.busy && !root.reviewing
            cursorShape: Qt.PointingHandCursor
            onClicked: TurretService.cancel()
        }
    }
}
