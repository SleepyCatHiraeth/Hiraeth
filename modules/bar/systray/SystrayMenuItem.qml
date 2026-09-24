import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import qs.config

// One row of a tray app's menu, in the greeter's design language: hover
// lifts a tinted pill with an accent bar under the row and nudges the text
// in; check and radio marks animate their state; submenu rows carry a
// chevron that turns when they open.
Button {
    id: root

    property string textStr: ""

    // Clean text logic from ContextMenu.qml
    readonly property string cleanText: {
        let t = textStr;
        if (!t) return "";
        t = String(t);
        if (t.startsWith(":/// ")) {
            t = t.substring(5);
        }
        return t.trim();
    }

    property var iconSource: ""
    property bool isImageIcon: false
    property bool isSeparator: false
    property bool hasSubmenu: false
    property bool expanded: false
    property int depth: 0
    // 0 = None, 1 = CheckBox, 2 = RadioButton
    property int buttonType: 0
    // Qt.Unchecked = 0, Qt.PartiallyChecked = 1, Qt.Checked = 2
    property int checkState: 0
    // The app's own enabled flag for this entry.
    property bool entryEnabled: true

    readonly property bool lit: hovered && enabled
    readonly property bool isChecked: checkState !== Qt.Unchecked
    readonly property real rowRadius: Config.roundness > 0 ? Math.min(height / 2, Styling.radius(-4)) : 0

    implicitWidth: 200
    implicitHeight: isSeparator ? 9 : 32
    enabled: !isSeparator && entryEnabled
    opacity: isSeparator || entryEnabled ? 1 : 0.4
    hoverEnabled: true

    padding: 0
    background: Item {
        // Hover pill.
        Rectangle {
            visible: !root.isSeparator
            anchors.fill: parent
            anchors.leftMargin: root.depth * 12
            radius: root.rowRadius
            color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, root.pressed ? 0.22 : 0.13)
            opacity: root.lit ? 1 : 0
            Behavior on opacity {
                enabled: Motion.enabled
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on color {
                enabled: Motion.enabled
                ColorAnimation {
                    duration: Motion.micro
                }
            }

            // Accent bar that grows from the row's centre.
            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: root.lit ? parent.height - 14 : 0
                radius: 1.5
                color: Colors.primary
                Behavior on height {
                    enabled: Motion.enabled
                    NumberAnimation {
                        duration: Motion.normal
                        easing.type: Easing.OutQuint
                    }
                }
            }
        }

        // Separator: a hairline that fades out at both ends.
        Rectangle {
            visible: root.isSeparator
            anchors.centerIn: parent
            width: parent.width - 16
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.2; color: Qt.rgba(Colors.overSurface.r, Colors.overSurface.g, Colors.overSurface.b, 0.14) }
                GradientStop { position: 0.8; color: Qt.rgba(Colors.overSurface.r, Colors.overSurface.g, Colors.overSurface.b, 0.14) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }

    contentItem: Item {
        visible: !root.isSeparator

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14 + root.depth * 12 + (root.lit ? 4 : 0)
            anchors.rightMargin: 10
            spacing: 10

            Behavior on anchors.leftMargin {
                enabled: Motion.enabled
                NumberAnimation {
                    duration: Motion.normal
                    easing.type: Easing.OutQuint
                }
            }

            // Check / radio indicator
            Item {
                visible: root.buttonType > 0
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16

                // Checkbox
                Rectangle {
                    visible: root.buttonType === 1
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    radius: Config.roundness > 0 ? 4 : 0
                    color: root.isChecked ? Colors.primary : "transparent"
                    border.color: root.isChecked ? Colors.primary : Qt.rgba(Colors.overSurface.r, Colors.overSurface.g, Colors.overSurface.b, 0.4)
                    border.width: 1.5
                    Behavior on color {
                        enabled: Motion.enabled
                        ColorAnimation {
                            duration: Motion.fast
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.checkState === Qt.PartiallyChecked ? "−" : "✓"
                        color: Colors.overPrimary
                        font.pixelSize: 10
                        font.bold: true
                        scale: root.isChecked ? 1 : 0.3
                        opacity: root.isChecked ? 1 : 0
                        Behavior on scale {
                            enabled: Motion.enabled
                            NumberAnimation {
                                duration: Motion.normal
                                easing.type: Easing.OutBack
                            }
                        }
                        Behavior on opacity {
                            enabled: Motion.enabled
                            NumberAnimation {
                                duration: Motion.fast
                            }
                        }
                    }
                }

                // RadioButton
                Rectangle {
                    visible: root.buttonType === 2
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    radius: 7
                    color: "transparent"
                    border.color: root.isChecked ? Colors.primary : Qt.rgba(Colors.overSurface.r, Colors.overSurface.g, Colors.overSurface.b, 0.4)
                    border.width: 1.5

                    Rectangle {
                        anchors.centerIn: parent
                        width: 6
                        height: 6
                        radius: 3
                        color: Colors.primary
                        scale: root.isChecked ? 1 : 0
                        Behavior on scale {
                            enabled: Motion.enabled
                            NumberAnimation {
                                duration: Motion.normal
                                easing.type: Easing.OutBack
                            }
                        }
                    }
                }
            }

            // Icon
            Loader {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                visible: root.iconSource !== "" && root.buttonType === 0
                sourceComponent: root.isImageIcon ? imageIcon : fontIcon

                Component {
                    id: fontIcon
                    Text {
                        text: root.iconSource
                        font.family: Icons.font
                        font.pixelSize: 14
                        color: root.lit ? Colors.primary : Colors.overSurface
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Component {
                    id: imageIcon
                    Image {
                        source: root.iconSource
                        fillMode: Image.PreserveAspectFit
                        mipmap: true
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.cleanText
                color: root.lit ? Colors.primary : Colors.overSurface
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                Behavior on color {
                    enabled: Motion.enabled
                    ColorAnimation {
                        duration: Motion.fast
                    }
                }
            }

            // Submenu chevron, turns down when open.
            Text {
                visible: root.hasSubmenu
                text: "›"
                color: root.lit || root.expanded ? Colors.primary : Colors.outline
                font.family: Config.theme.monoFont
                font.pixelSize: 16
                verticalAlignment: Text.AlignVCenter
                rotation: root.expanded ? 90 : 0
                Behavior on rotation {
                    enabled: Motion.enabled
                    NumberAnimation {
                        duration: Motion.normal
                        easing.type: Easing.OutBack
                    }
                }
            }
        }
    }
}
