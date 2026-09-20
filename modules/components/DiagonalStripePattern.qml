import QtQuick
import Quickshell.Widgets
import qs.modules.theme
import qs.config

ClippingRectangle {
    id: root

    property color stripeColor: Colors.criticalRed
    property int stripeWidth: 8
    property int stripeSpacing: 20
    property int animationDuration: 1000
    property bool animationRunning: true

    color: Colors.shadow

    Repeater {
        model: Math.ceil((parent.width + parent.height) / root.stripeWidth)

        Rectangle {
            width: root.stripeWidth
            height: parent.height * 3
            rotation: -45
            color: root.stripeColor
            x: ((index * root.stripeSpacing) - (animationOffset % root.stripeSpacing)) - root.stripeSpacing
            y: -parent.height

            property real animationOffset: 0

            NumberAnimation on animationOffset {
                from: 0
                to: root.stripeSpacing
                duration: root.animationDuration
                loops: Animation.Infinite
                // The critical-notification stripes ran forever at a hardcoded
                // duration, so they kept moving under reduced motion — on the
                // one surface a user in that mode is most likely to be reading.
                running: root.animationRunning && Motion.enabled
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        color: Colors.shadow
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        color: root.stripeColor
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        color: Colors.shadow
    }
}
