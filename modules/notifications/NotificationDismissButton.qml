import QtQuick
import QtQuick.Controls
import Quickshell.Services.Notifications
import qs.modules.theme
import qs.modules.components
import qs.config

Button {
    id: root
    property bool visibleWhen: true
    // `var`, not `int`: internal notifications store urgency as a string
    // (Notifications.qml declares `property string urgency`, and SoundService
    // compares it as text), while desktop notifications arrive as the enum.
    // Typing this `int` made every string urgency warn "Unable to assign
    // QString to int" on each render, including on every shell start for any
    // notification restored from history.
    property var urgency: NotificationUrgency.Normal
    readonly property bool isCritical: urgency === NotificationUrgency.Critical
                                       || urgency === "critical" || urgency === "2" || urgency === 2

    anchors.fill: parent
    hoverEnabled: true
    visible: visibleWhen

    background: Item {
        id: buttonBg
        property color iconColor: root.isCritical ? Colors.shadow : (root.pressed ? Colors.overError : Colors.error)
        
        Rectangle {
            anchors.fill: parent
            visible: root.isCritical
            color: parent.parent.hovered ? Qt.lighter(Colors.criticalRed, 1.3) : Colors.criticalRed
            radius: Styling.radius(4)

            Behavior on color {
                enabled: Config.animDuration > 0
                ColorAnimation {
                    duration: Config.animDuration
                }
            }
        }

        StyledRect {
            id: styledBg
            anchors.fill: parent
            visible: !root.isCritical
            variant: parent.parent.pressed ? "error" : (parent.parent.hovered ? "focus" : "common")
            radius: Styling.radius(4)
        }
    }

    contentItem: Text {
        text: Icons.cancel
        textFormat: Text.RichText
        font.family: Icons.font
        font.pixelSize: 16
        color: root.background.iconColor
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
