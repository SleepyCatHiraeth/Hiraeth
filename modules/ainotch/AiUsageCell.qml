import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import QtQuick.Effects
import qs.modules.theme
import qs.config

// One provider's five-hour window: a ring carrying the percentage used, the
// provider's mark in the middle, and the figure below it.
//
// The ring is drawn here rather than reusing CircularSeekBar. That component is
// a media seek control — it always draws a drag handle, carries wavy and dashed
// modes, and owns a MouseArea — so making it read-only means overriding
// handleSpacing, animatedHandleWidth and enabled and still shipping the rest.
// Two ShapePaths are less total machinery, and use the same Shape/CurveRenderer
// rendering the seek bar already established.
Item {
    id: root

    required property string providerId
    property string label: ""
    property real usedPercent: 0
    property bool stale: false
    property bool hovered: false

    property int ringSize: 28
    property int lineWidth: 3

    Accessible.role: Accessible.Indicator
    Accessible.name: label || providerId
    Accessible.description: Math.round(usedPercent) + "% of five-hour quota used" + (stale ? "; stale reading" : "")
    ToolTip.visible: hover.hovered
    ToolTip.text: (label || providerId) + ": " + Accessible.description
    HoverHandler { id: hover }

    implicitWidth: ringSize
    implicitHeight: ringSize + 2 + percentLabel.implicitHeight

    readonly property real fraction: Math.max(0, Math.min(1, usedPercent / 100))

    // The same thresholds the plugin warns at, so the notch and its
    // notifications never disagree about when usage is worth noticing.
    readonly property color arcColor: {
        if (root.usedPercent >= 95)
            return Colors.red;
        if (root.usedPercent >= 80)
            return Colors.yellow;
        return Colors.primary;
    }

    // Swept, not snapped: a ring that jumps to a new value reads as a glitch,
    // one that travels reads as a measurement.
    property real animatedFraction: root.fraction

    Behavior on animatedFraction {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration * 2
            easing.type: Easing.OutQuart
        }
    }

    opacity: root.stale ? 0.45 : 1

    Behavior on opacity {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: Easing.OutQuart
        }
    }

    Item {
        id: ring
        width: root.ringSize
        height: root.ringSize
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        readonly property real centre: width / 2
        readonly property real arcRadius: (width / 2) - (root.lineWidth / 2)

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                // outlineVariant rather than outline: on a small ring the arc
                // and a mid-tone track are hard to tell apart, and the reading
                // is the whole point of the ring.
                strokeColor: Colors.outlineVariant
                strokeWidth: root.lineWidth
                capStyle: ShapePath.RoundCap
                fillColor: "transparent"

                PathAngleArc {
                    centerX: ring.centre
                    centerY: ring.centre
                    radiusX: ring.arcRadius
                    radiusY: ring.arcRadius
                    startAngle: -90
                    sweepAngle: 360
                }
            }

            ShapePath {
                strokeColor: root.arcColor
                strokeWidth: root.lineWidth
                capStyle: ShapePath.RoundCap
                fillColor: "transparent"

                PathAngleArc {
                    centerX: ring.centre
                    centerY: ring.centre
                    radiusX: ring.arcRadius
                    radiusY: ring.arcRadius
                    startAngle: -90
                    sweepAngle: 360 * root.animatedFraction
                }
            }
        }

        // Any provider whose id matches a mark in assets/aiproviders gets one;
        // anything else simply shows an empty ring rather than a broken image.
        Image {
            id: logo
            anchors.centerIn: parent
            width: Math.round(root.ringSize * 0.42)
            height: width
            source: /^[a-z0-9-]+$/.test(root.providerId) ? "../../assets/aiproviders/" + root.providerId + ".svg" : ""
            fillMode: Image.PreserveAspectFit
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            asynchronous: true
            visible: status === Image.Ready

            // The marks are monochrome by intent: brightness flattens the source
            // to white first, so a vendor-colored file and a currentColor file
            // (which QtSvg renders black) both land on the theme color.
            layer.enabled: true
            layer.effect: MultiEffect {
                brightness: 1.0
                contrast: 0.0
                colorization: 1.0
                colorizationColor: root.hovered ? Styling.srItem("overprimary") : Colors.overSurface
            }
        }
        Text {
            anchors.centerIn: parent
            visible: logo.status !== Image.Ready
            text: (root.label || root.providerId).slice(0, 1).toUpperCase()
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-4)
            color: Colors.overSurface
        }
    }

    Text {
        id: percentLabel
        anchors.top: ring.bottom
        anchors.topMargin: 2
        anchors.horizontalCenter: parent.horizontalCenter
        text: Math.round(root.usedPercent) + "%"
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-4)
        font.weight: Font.Medium
        color: root.arcColor

        Behavior on color {
            enabled: Config.animDuration > 0
            ColorAnimation {
                duration: Config.animDuration
            }
        }
    }
}
