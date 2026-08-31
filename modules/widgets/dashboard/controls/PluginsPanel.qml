pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    property int maxContentWidth: 480
    readonly property int contentWidth: Math.min(width, maxContentWidth)

    component ToggleRow: RowLayout {
        id: toggleRowRoot

        property string label: ""
        property string type: ""
        property bool checked: false
        signal toggled(bool value)

        spacing: 8

        Text {
            text: toggleRowRoot.label
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            color: Colors.overBackground
            Layout.fillWidth: true
        }

        StyledRect {
            variant: "common"
            Layout.preferredWidth: typeLabel.implicitWidth + 12
            Layout.preferredHeight: typeLabel.implicitHeight + 4
            radius: Styling.radius(-4)

            Text {
                id: typeLabel
                anchors.centerIn: parent
                text: toggleRowRoot.type
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
            }
        }

        Switch {
            id: toggleSwitch
            checked: toggleRowRoot.checked
            onToggled: toggleRowRoot.toggled(checked)

            indicator: Rectangle {
                implicitWidth: 40
                implicitHeight: 20
                x: toggleSwitch.leftPadding
                y: parent.height / 2 - height / 2
                radius: height / 2
                color: toggleSwitch.checked ? Styling.srItem("overprimary") : Colors.surfaceBright
                border.color: toggleSwitch.checked ? Styling.srItem("overprimary") : Colors.outline

                Behavior on color {
                    enabled: Config.animDuration > 0
                    ColorAnimation { duration: Config.animDuration / 2 }
                }

                Rectangle {
                    x: toggleSwitch.checked ? parent.width - width - 2 : 2
                    y: 2
                    width: parent.height - 4
                    height: width
                    radius: width / 2
                    color: toggleSwitch.checked ? Colors.background : Colors.overSurfaceVariant

                    Behavior on x {
                        enabled: Config.animDuration > 0
                        NumberAnimation {
                            duration: Config.animDuration / 2
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
            background: null
        }
    }

    ListView {
        id: pluginList
        anchors.fill: parent
        clip: true
        spacing: 4
        model: PluginService.allPlugins

        header: Item {
            width: pluginList.width
            height: titlebar.height + 8

            PanelTitlebar {
                id: titlebar
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                title: "Plugins"
                actions: [{
                    icon: Icons.sync,
                    tooltip: "Rescan plugins",
                    onClicked: function () { PluginService.scan(); }
                }]
            }
        }

        delegate: Item {
            id: pluginDelegate
            required property var modelData
            width: pluginList.width
            height: toggleRow.implicitHeight + 12

            ToggleRow {
                id: toggleRow
                width: root.contentWidth
                anchors.centerIn: parent
                label: pluginDelegate.modelData.name
                type: pluginDelegate.modelData.type
                checked: pluginDelegate.modelData.enabled
                onToggled: value => PluginService.setEnabled(pluginDelegate.modelData.id, value)
            }
        }

        Text {
            anchors.centerIn: parent
            visible: PluginService.allPlugins.length === 0
            text: "No plugins installed"
            font.family: Config.theme.font
            font.pixelSize: Config.theme.fontSize
            color: Colors.overSurfaceVariant
        }
    }
}
