import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import qs.modules.theme
import qs.modules.components
import qs.config

// One provider's five-hour window: an open gauge carrying the percentage used, the
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
    property string resetsAt: ""
    property string edge: "right"

    property int ringSize: 30
    property real lineWidth: 2

    Accessible.role: Accessible.Indicator
    Accessible.name: label || providerId
    Accessible.description: Math.round(usedPercent) + "% of five-hour quota used" + (stale ? "; stale reading" : "")
    ToolTip {
        id: details
        visible: hover.hovered
        delay: Motion.normal
        x: root.edge === "left" ? root.width + 12 : -width - 12
        y: (root.height - height) / 2
        padding: 12
        width: Styling.monoFontSize(0) * 16 + padding * 2
        transformOrigin: root.edge === "left" ? Item.Left : Item.Right
        text: {
            const reset = new Date(root.resetsAt);
            return (root.label || root.providerId) + "\n" + root.Accessible.description
                + "\n" + Math.round((1 - root.fraction) * 100) + "% remaining"
                + (Number.isFinite(reset.getTime()) ? "\nResets " + reset.toLocaleTimeString(Qt.locale(), "hh:mm") : "");
        }
        background: StyledRect {
            variant: "popup"
            backgroundOpacity: 0.96
            enableBorder: false
            radius: Styling.radius(-4)
            animateRadius: false
        }
        contentItem: ColumnLayout {
            implicitWidth: Styling.monoFontSize(0) * 16
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: root.label || root.providerId
                textFormat: Text.PlainText
                font.family: Config.theme.monoFont
                font.pixelSize: Styling.monoFontSize(0)
                font.weight: Font.DemiBold
                color: Colors.overBackground
                elide: Text.ElideRight
            }
            Text {
                text: "5-hour quota"
                font.family: Config.theme.monoFont
                font.pixelSize: Styling.monoFontSize(-2)
                color: Qt.alpha(Colors.overBackground, 0.7)
            }
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: Math.round(root.animatedFraction * 100) + "%"
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.monoFontSize(10)
                    font.weight: Font.Medium
                    color: root.arcColor
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: Math.round((1 - root.fraction) * 100) + "% left"
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.monoFontSize(-2)
                    color: Colors.overBackground
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 3
                radius: height / 2
                color: Qt.alpha(Colors.overBackground, 0.12)
                Rectangle {
                    width: parent.width * root.animatedFraction
                    height: parent.height
                    radius: parent.radius
                    color: root.arcColor
                }
            }
            Text {
                Layout.fillWidth: true
                readonly property var reset: new Date(root.resetsAt)
                visible: Number.isFinite(reset.getTime())
                text: visible ? "Resets at " + reset.toLocaleTimeString(Qt.locale(), "hh:mm") : ""
                font.family: Config.theme.monoFont
                font.pixelSize: Styling.monoFontSize(-2)
                color: Qt.alpha(Colors.overBackground, 0.7)
            }
            Text {
                visible: root.stale
                text: "Reading out of date"
                font.family: Config.theme.monoFont
                font.pixelSize: Styling.monoFontSize(-2)
                color: Colors.yellow
            }
        }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.enabled ? Motion.fast : 0 }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Motion.enabled ? Motion.fast : 0; easing.type: Motion.fastEasing }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: Motion.enabled ? Motion.micro : 0 }
        }
    }
    HoverHandler { id: hover }

    implicitWidth: ringSize
    implicitHeight: ringSize + 4 + percentLabel.implicitHeight

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
        enabled: Motion.enabled && root.visible
        NumberAnimation {
            duration: Motion.normal * 2
            easing.type: Easing.OutQuart
        }
    }

    opacity: root.stale ? 0.62 : 1

    Behavior on opacity {
        enabled: Motion.enabled
        NumberAnimation {
            duration: Motion.normal
            easing.type: Easing.OutQuart
        }
    }

    Item {
        id: ring
        width: root.ringSize
        height: root.ringSize
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        scale: root.hovered || hover.hovered ? 1.08 : 1

        Behavior on scale {
            enabled: Motion.enabled && root.visible
            NumberAnimation { duration: Motion.fast; easing.type: Motion.fastEasing }
        }

        readonly property real centre: width / 2
        readonly property real arcRadius: (width / 2) - (root.lineWidth / 2)

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                // A quiet track leaves the measured arc as the primary signal.
                strokeColor: Qt.alpha(Colors.overBackground, 0.12)
                strokeWidth: root.lineWidth
                capStyle: ShapePath.RoundCap
                fillColor: "transparent"

                PathAngleArc {
                    centerX: ring.centre
                    centerY: ring.centre
                    radiusX: ring.arcRadius
                    radiusY: ring.arcRadius
                    startAngle: 135
                    sweepAngle: 270
                }
            }

            ShapePath {
                strokeColor: root.arcColor
                strokeWidth: root.lineWidth
                capStyle: ShapePath.RoundCap
                fillColor: "transparent"

                Behavior on strokeColor {
                    enabled: Motion.enabled && root.visible
                    ColorAnimation { duration: Motion.normal }
                }

                PathAngleArc {
                    centerX: ring.centre
                    centerY: ring.centre
                    radiusX: ring.arcRadius
                    radiusY: ring.arcRadius
                    startAngle: 135
                    sweepAngle: 270 * root.animatedFraction
                }
            }
        }

        // Any provider whose id matches a mark in assets/aiproviders gets one;
        // anything else simply shows an empty ring rather than a broken image.
        Image {
            id: logo
            anchors.centerIn: parent
            width: Math.round(root.ringSize * 0.46)
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
            font.family: Config.theme.monoFont
            font.pixelSize: Styling.monoFontSize(-2)
            color: Colors.overSurface
        }
    }

    Text {
        id: percentLabel
        anchors.top: ring.bottom
        anchors.topMargin: 4
        anchors.horizontalCenter: parent.horizontalCenter
        text: Math.round(root.animatedFraction * 100) + "%"
        font.family: Config.theme.monoFont
        font.pixelSize: Styling.monoFontSize(-2)
        font.weight: Font.DemiBold
        font.italic: root.stale
        color: root.usedPercent >= 80 ? root.arcColor : Colors.overBackground

        Behavior on color {
            enabled: Motion.enabled
            ColorAnimation {
                duration: Motion.normal
            }
        }
    }
}
