pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.modules.components
import qs.modules.theme
import qs.modules.services
import qs.modules.globals
import qs.config

// Volume / mic / brightness OSD in the greeter's design language: a dark
// pill with a progress ring around the icon, a terminal-style label, a
// segmented meter and a counting readout. It rises in from the bottom edge,
// cascades its segments on, and sinks back out; the window stays mapped
// until the exit has finished playing.
PanelWindow {
    id: root

    property ShellScreen targetScreen
    screen: targetScreen

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ambxst:osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Only as wide as the pill, so the OSD never covers the whole bottom edge.
    anchors.bottom: true
    WlrLayershell.margins.bottom: 100 - pad

    readonly property int pad: 24
    // Fixed window, sized for the widest label; the pill inside hugs its
    // content and only the pill takes input.
    implicitWidth: 340 + pad * 2
    implicitHeight: pill.height + pad * 2

    color: "transparent"
    mask: Region {
        item: pill
    }

    readonly property bool shown: GlobalStates.osdVisible
    visible: shown || t > 0

    // Internal state for responsiveness
    property real osdValue: 0
    property bool osdMuted: false

    // Eased readout: meter, ring and number count toward the new value.
    property real shownValue: 0
    Behavior on shownValue {
        enabled: Motion.enabled
        NumberAnimation {
            duration: root.dur(0.9)
            easing.type: Easing.OutCubic
        }
    }
    onOsdValueChanged: shownValue = osdValue
    readonly property real level: Math.max(0, Math.min(1, shownValue))

    readonly property string indicator: GlobalStates.osdIndicator
    readonly property string mono: Config.theme.monoFont
    readonly property color accent: osdMuted ? Colors.outline : Colors.primary

    function dur(factor) {
        return Math.round(Math.max(120, Motion.base) * factor);
    }
    function span(t, from, to) {
        return Math.max(0, Math.min(1, (t - from) / (to - from)));
    }
    function outCubic(x) {
        return 1 - Math.pow(1 - x, 3);
    }
    function outBack(x) {
        const c1 = 1.70158, c3 = c1 + 1;
        return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2);
    }

    // Entrance / exit timeline, 0 = gone, 1 = settled.
    property real t: 0
    NumberAnimation {
        id: timeline
        target: root
        property: "t"
    }
    onShownChanged: {
        if (!Motion.enabled) {
            t = shown ? 1 : 0;
            return;
        }
        timeline.stop();
        timeline.to = shown ? 1 : 0;
        // The exit runs quicker than the entrance, scaled by the distance left.
        timeline.duration = shown ? dur(2) * (1 - t) : dur(1.1) * t;
        timeline.easing.type = shown ? Easing.Linear : Easing.InCubic;
        timeline.start();
    }

    readonly property real pillIn: outCubic(span(t, 0, 0.55))
    readonly property real badgeIn: span(t, 0.12, 0.62)
    readonly property real textIn: outCubic(span(t, 0.25, 0.75))

    Item {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.pad + (1 - root.pillIn) * 28
        width: 8 + badge.width + 12 + label.implicitWidth + 14 + meter.width + 12 + readout.width + 18
        height: 52
        Behavior on width {
            enabled: Motion.enabled
            NumberAnimation {
                duration: root.dur(0.8)
                easing.type: Easing.OutCubic
            }
        }
        opacity: Math.min(1, root.t * 2.2)
        scale: 0.9 + 0.1 * root.outBack(root.span(root.t, 0, 0.7))

        StyledRect {
            anchors.fill: parent
            variant: "bg"
            radius: Config.roundness > 0 ? (height / 2) * Math.min(1, Config.roundness / 16) : 0
            border.width: 1
            border.color: Qt.rgba(Colors.overSurface.r, Colors.overSurface.g, Colors.overSurface.b, 0.12)
            layer.enabled: true
            layer.effect: Shadow {}
        }

        // Hovering the pill dismisses it, as the old OSD did.
        HoverHandler {
            onHoveredChanged: if (hovered)
                GlobalStates.osdVisible = false
        }

        // ── Ring badge ───────────────────────────────────────────────
        Item {
            id: badge
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 38
            height: 38
            opacity: Math.min(1, root.badgeIn * 2)
            scale: 0.5 + 0.5 * root.outBack(root.badgeIn)

            Shape {
                id: ring
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Qt.rgba(Colors.overSurface.r, Colors.overSurface.g, Colors.overSurface.b, 0.1)
                    strokeWidth: 2.5
                    PathAngleArc {
                        centerX: ring.width / 2
                        centerY: ring.height / 2
                        radiusX: ring.width / 2 - 2
                        radiusY: radiusX
                        startAngle: 0
                        sweepAngle: 360
                    }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.accent
                    strokeWidth: 2.5
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: ring.width / 2
                        centerY: ring.height / 2
                        radiusX: ring.width / 2 - 2
                        radiusY: radiusX
                        startAngle: -90
                        sweepAngle: 360 * root.level * root.span(root.t, 0.2, 0.8)
                    }
                }
            }

            Text {
                id: iconText
                anchors.centerIn: parent
                text: {
                    if (root.indicator === "volume")
                        return Audio.volumeIcon(root.osdValue, root.osdMuted);
                    if (root.indicator === "mic")
                        return root.osdMuted ? Icons.micSlash : Icons.mic;
                    return Icons.sun;
                }
                font.family: Icons.font
                font.pixelSize: 17
                color: root.osdMuted ? Colors.outline : Colors.overSurface
                rotation: root.indicator === "brightness" ? root.level * 180 : 0
                scale: root.indicator === "brightness" ? 0.85 + root.level * 0.15 : 1

                Behavior on color {
                    enabled: Motion.enabled
                    ColorAnimation {
                        duration: root.dur(0.6)
                    }
                }

                // Small kick when the indicator or its glyph changes.
                onTextChanged: if (Motion.enabled && root.t > 0.9)
                    kick.restart()
                SequentialAnimation {
                    id: kick
                    NumberAnimation {
                        target: iconText
                        property: "opacity"
                        to: 0.3
                        duration: root.dur(0.25)
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: iconText
                        property: "opacity"
                        to: 1
                        duration: root.dur(0.6)
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // ── Label ────────────────────────────────────────────────────
        Row {
            id: label
            anchors.left: badge.right
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7
            opacity: root.textIn
            transform: Translate {
                x: (1 - root.textIn) * -8
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "❯"
                font.family: root.mono
                font.pixelSize: 13
                font.weight: Font.Bold
                color: root.accent
                Behavior on color {
                    enabled: Motion.enabled
                    ColorAnimation {
                        duration: root.dur(0.6)
                    }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (root.osdMuted)
                        return "muted";
                    if (root.indicator === "volume")
                        return I18n.t("osd.volume").toLowerCase();
                    if (root.indicator === "mic")
                        return I18n.t("osd.mic").toLowerCase();
                    return I18n.t("osd.brightness").toLowerCase();
                }
                font.family: root.mono
                font.pixelSize: 12
                color: Colors.overSurface
                opacity: 0.8
            }
        }

        // ── Segmented meter ──────────────────────────────────────────
        Row {
            id: meter
            readonly property int count: 20
            anchors.left: label.right
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Repeater {
                model: meter.count

                Rectangle {
                    id: seg
                    required property int index
                    readonly property real fill: Math.max(0, Math.min(1, root.level * meter.count - index))
                    // Segments cascade on, left to right, during the entrance.
                    readonly property real cascade: root.span(root.t, 0.3 + index * 0.018, 0.5 + index * 0.018)

                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: 12 * (0.4 + 0.6 * root.outCubic(cascade))
                    radius: 1
                    color: fill > 0 ? root.accent : Colors.overSurface
                    opacity: (fill > 0 ? 0.35 + 0.6 * fill : 0.12) * cascade
                }
            }
        }

        // ── Readout ──────────────────────────────────────────────────
        Text {
            id: readout
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            horizontalAlignment: Text.AlignRight
            text: Math.round(root.shownValue * 100)
            font.family: root.mono
            font.pixelSize: 13
            font.weight: Font.Bold
            color: root.osdMuted ? Colors.outline : Colors.overSurface
            opacity: root.textIn
        }
    }

    Timer {
        id: hideTimer
        interval: 2500
        onTriggered: GlobalStates.osdVisible = false
    }

    Connections {
        target: GlobalStates
        function onOsdVisibleChanged() {
            if (GlobalStates.osdVisible) {
                hideTimer.restart();
            }
        }
    }

    // Services connections - Direct and responsive
    Connections {
        target: Audio
        function onVolumeChanged(volume, muted, node) {
            root.osdValue = volume;
            root.osdMuted = muted;
            GlobalStates.osdIndicator = "volume";
            GlobalStates.osdVisible = true;
            hideTimer.restart();
        }
        function onMicVolumeChanged(volume, muted, node) {
            root.osdValue = volume;
            root.osdMuted = muted;
            GlobalStates.osdIndicator = "mic";
            GlobalStates.osdVisible = true;
            hideTimer.restart();
        }
    }

    Connections {
        target: Brightness
        function onBrightnessChanged(value, screen) {
            // Check if the change happened on THIS screen or if it's a sync change
            if (!screen || !root.targetScreen || screen.name === root.targetScreen.name || Brightness.syncBrightness) {
                root.osdValue = value;
                root.osdMuted = false;
                GlobalStates.osdIndicator = "brightness";
                GlobalStates.osdVisible = true;
                hideTimer.restart();
            }
        }
    }
}
