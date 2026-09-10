pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.config

// One settings row as a hoverable card, matching the pattern PluginsPanel and
// SoundsPanel already use so this section does not invent a second visual
// language for the same job.
//
// Children are placed in the row's trailing control slot, or below it when
// `tall` is set and the control needs full width.
StyledRect {
    id: root

    property string title: ""
    property string subtitle: ""
    property string icon: ""
    property color accent: Colors.overSurface
    property bool tall: false

    default property alias controls: controlSlot.data

    variant: hover.hovered ? "focus" : "common"
    implicitHeight: layout.implicitHeight + 20

    HoverHandler {
        id: hover
    }

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                visible: root.icon !== ""
                text: root.icon
                font.family: Icons.font
                font.pixelSize: 17
                color: root.accent
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(0)
                    font.weight: Font.Medium
                    color: Colors.overSurface
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.subtitle !== ""
                    text: root.subtitle
                    wrapMode: Text.WordWrap
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.overSurfaceVariant
                }
            }

            RowLayout {
                id: inlineSlot
                visible: !root.tall
                spacing: 6
                Layout.alignment: Qt.AlignVCenter
            }
        }

        RowLayout {
            id: belowSlot
            Layout.fillWidth: true
            visible: root.tall
            spacing: 6
        }

        // One slot property, two placements: reparent on construction rather
        // than asking every caller to pick the right container.
        Item {
            id: controlSlot
            visible: false
            onChildrenChanged: Qt.callLater(root.placeControls)
        }
    }

    function placeControls() {
        const target = root.tall ? belowSlot : inlineSlot;
        const kids = controlSlot.children;
        for (let i = kids.length - 1; i >= 0; i--)
            kids[i].parent = target;
    }

    Component.onCompleted: placeControls()
}
