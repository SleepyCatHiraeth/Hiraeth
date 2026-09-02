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
    readonly property var eventModel: [
        { key: "notification", label: "Notification", icon: Icons.bell },
        { key: "critical", label: "Critical / Error", icon: Icons.alert },
        { key: "low", label: "Low Priority", icon: Icons.info },
        { key: "loginSuccess", label: "Login Success", icon: Icons.shieldCheck },
        { key: "wrongPassword", label: "Wrong Password", icon: Icons.lock },
        { key: "bootUp", label: "Boot Up", icon: Icons.power },
        { key: "deviceConnect", label: "Device Connect", icon: Icons.plug },
        { key: "deviceDisconnect", label: "Device Disconnect", icon: Icons.bluetoothOff }
    ]

    function updateEvent(key, property, value) {
        const events = Object.assign({}, Config.sound.events);
        events[key] = Object.assign({}, events[key]);
        events[key][property] = value;
        Config.sound.events = events;
    }

    ListView {
        id: eventList
        anchors.fill: parent
        clip: true
        spacing: 4
        model: root.eventModel

        header: Item {
            width: eventList.width
            height: headerContent.implicitHeight + 8

            ColumnLayout {
                id: headerContent
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                PanelTitlebar {
                    title: "System Sounds"
                    showToggle: true
                    toggleChecked: Config.sound.enabled
                    onToggleChanged: checked => Config.sound.enabled = checked
                }

                Text {
                    text: "Sound Theme"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    font.weight: Font.Medium
                    color: Colors.overSurfaceVariant
                }

                RowLayout {
                    id: themeRow
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(defaultContent.implicitHeight, portalContent.implicitHeight) + 24
                    spacing: 8

                    StyledRect {
                        id: defaultCard
                        readonly property var theme: SoundThemes.resolveTheme("default")
                        variant: Config.sound.theme === theme.id ? "focus" : "common"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Styling.radius(-2)

                        ColumnLayout {
                            id: defaultContent
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 4

                            Text {
                                text: defaultCard.theme.name
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(0)
                                font.weight: Font.Medium
                                color: Colors.overBackground
                            }
                            Text {
                                text: defaultCard.theme.description
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                color: Colors.overSurfaceVariant
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Config.sound.theme = defaultCard.theme.id
                        }
                    }

                    StyledRect {
                        id: portalCard
                        readonly property var theme: SoundThemes.resolveTheme("portal-turret")
                        variant: Config.sound.theme === theme.id ? "focus" : "common"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Styling.radius(-2)
                        opacity: theme.available ? 1 : 0.5

                        Behavior on opacity {
                            enabled: Config.animDuration > 0
                            NumberAnimation { duration: Config.animDuration / 2; easing.type: Easing.OutCubic }
                        }

                        ColumnLayout {
                            id: portalContent
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 4

                            Text {
                                text: portalCard.theme.name
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(0)
                                font.weight: Font.Medium
                                color: Colors.overBackground
                            }
                            Text {
                                text: portalCard.theme.description
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                color: Colors.overSurfaceVariant
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: portalCard.theme.available
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: Config.sound.theme = portalCard.theme.id
                        }
                    }
                }

                Text {
                    text: "Sound Events"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    font.weight: Font.Medium
                    color: Colors.overSurfaceVariant
                }
            }
        }

        delegate: Item {
            id: eventDelegate
            required property var modelData
            width: eventList.width
            height: 48

            RowLayout {
                width: root.contentWidth
                anchors.centerIn: parent
                spacing: 8

                Text {
                    text: eventDelegate.modelData.icon
                    font.family: Icons.font
                    font.pixelSize: 16
                    color: Colors.overBackground
                    Layout.preferredWidth: 20
                }

                Text {
                    text: eventDelegate.modelData.label
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(0)
                    color: Colors.overBackground
                    Layout.preferredWidth: 100
                }

                StyledRect {
                    variant: "common"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: Styling.radius(-2)

                    TextInput {
                        anchors.fill: parent
                        anchors.margins: 8
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        color: Colors.overBackground
                        selectByMouse: true
                        clip: true
                        verticalAlignment: TextInput.AlignVCenter
                        text: Config.sound.events?.[eventDelegate.modelData.key]?.sound || ""

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "Use theme default"
                            font: parent.font
                            color: Colors.overSurfaceVariant
                            visible: !parent.text && !parent.activeFocus
                        }

                        onEditingFinished: root.updateEvent(eventDelegate.modelData.key, "sound", text)
                    }
                }

                Button {
                    id: testButton
                    flat: true
                    implicitWidth: 28
                    implicitHeight: 28

                    background: StyledRect {
                        variant: testButton.hovered ? "focus" : "common"
                        radius: Styling.radius(-4)
                    }

                    contentItem: Text {
                        text: Icons.play
                        font.family: Icons.font
                        font.pixelSize: 14
                        color: Colors.overBackground
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: SoundService.play(eventDelegate.modelData.key)

                    StyledToolTip {
                        visible: testButton.hovered
                        tooltipText: "Test sound"
                    }
                }

                Switch {
                    id: muteSwitch
                    checked: Config.sound.events?.[eventDelegate.modelData.key]?.muted ?? false
                    onToggled: root.updateEvent(eventDelegate.modelData.key, "muted", checked)

                    indicator: Rectangle {
                        implicitWidth: 40
                        implicitHeight: 20
                        x: muteSwitch.leftPadding
                        y: parent.height / 2 - height / 2
                        radius: height / 2
                        color: muteSwitch.checked ? Styling.srItem("overprimary") : Colors.surfaceBright
                        border.color: muteSwitch.checked ? Styling.srItem("overprimary") : Colors.outline

                        Behavior on color {
                            enabled: Config.animDuration > 0
                            ColorAnimation { duration: Config.animDuration / 2 }
                        }

                        Rectangle {
                            x: muteSwitch.checked ? parent.width - width - 2 : 2
                            y: 2
                            width: parent.height - 4
                            height: width
                            radius: width / 2
                            color: muteSwitch.checked ? Colors.background : Colors.overSurfaceVariant

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
        }

        footer: Item {
            width: eventList.width
            height: volumeRow.implicitHeight + 16

            RowLayout {
                id: volumeRow
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 8
                spacing: 8

                Text {
                    text: "Volume"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(0)
                    color: Colors.overBackground
                    Layout.preferredWidth: 128
                }

                StyledSlider {
                    id: volumeSlider
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20
                    progressColor: Styling.srItem("overprimary")
                    tooltipText: `${Math.round(value * 100)}%`
                    scroll: true
                    stepSize: 0.01
                    snapMode: "always"

                    readonly property real configValue: Config.sound.volume
                    onConfigValueChanged: if (Math.abs(value - configValue) > 0.001) value = configValue
                    Component.onCompleted: value = configValue
                    onValueChanged: if (Math.abs(value - Config.sound.volume) > 0.001) Config.sound.volume = value
                }

                Text {
                    text: Math.round(Config.sound.volume * 100) + "%"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(0)
                    color: Colors.overBackground
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }
}
