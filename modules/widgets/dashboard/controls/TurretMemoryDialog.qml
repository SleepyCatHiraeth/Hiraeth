pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

// Memory management: inspect, correct, delete, clear.
//
// Memory the user cannot see is not controlled memory, so everything stored is
// listed here with its provenance and trust level, and every item can be
// corrected or removed. Correcting supersedes rather than edits, so history
// survives; deleting is a real delete.
Dialog {
    id: root

    signal changed

    modal: true
    anchors.centerIn: Overlay.overlay
    width: 620
    height: 520
    padding: 14

    property var items: []
    property string editingId: ""

    function refresh() {
        TurretService.listMemories(result => {
            root.items = (result && result.items) ? result.items : [];
        });
    }

    onOpened: refresh()

    contentItem: ColumnLayout {
        spacing: 10

        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: "Stored memories"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(1)
                font.weight: Font.Medium
                color: Colors.overSurface
            }

            Button {
                text: "Forget everything"
                enabled: root.items.length > 0
                onClicked: confirmClear.open()
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.items.length === 0
            text: "Nothing stored yet."
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-1)
            color: Colors.overSurfaceVariant
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: root.items

            delegate: StyledRect {
                id: row
                required property var modelData
                width: ListView.view.width
                variant: rowHover.hovered ? "focus" : "common"
                implicitHeight: rowLayout.implicitHeight + 16

                HoverHandler {
                    id: rowHover
                }

                ColumnLayout {
                    id: rowLayout
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: row.modelData.category.replace(/_/g, " ")
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: Colors.overSurfaceVariant
                        }
                        Text {
                            // Trust is shown because it is the difference
                            // between something the user said and something a
                            // document claimed.
                            text: "· " + row.modelData.trust_level.replace(/_/g, " ")
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: row.modelData.trust_level === "untrusted"
                                   ? Colors.warning : Colors.overSurfaceVariant
                        }
                        Text {
                            visible: row.modelData.status !== "active"
                            text: "· " + row.modelData.status
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: Colors.overSurfaceVariant
                        }
                        Item { Layout.fillWidth: true }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.editingId !== row.modelData.id
                        text: row.modelData.content
                        wrapMode: Text.WordWrap
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.overSurface
                    }

                    TextField {
                        id: editField
                        Layout.fillWidth: true
                        visible: root.editingId === row.modelData.id
                        text: row.modelData.content
                        onAccepted: {
                            TurretService.correctMemory(row.modelData.id, text, () => {
                                root.editingId = "";
                                root.refresh();
                                root.changed();
                            });
                        }
                    }

                    RowLayout {
                        spacing: 8
                        visible: rowHover.hovered || root.editingId === row.modelData.id

                        Button {
                            text: root.editingId === row.modelData.id ? "Save" : "Correct"
                            onClicked: {
                                if (root.editingId === row.modelData.id)
                                    editField.accepted();
                                else
                                    root.editingId = row.modelData.id;
                            }
                        }
                        Button {
                            text: "Forget"
                            onClicked: TurretService.forgetMemory(row.modelData.id, () => {
                                root.refresh();
                                root.changed();
                            })
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }
        }
    }

    // Clearing everything is irreversible, so it gets its own confirmation
    // rather than riding on a single click.
    Dialog {
        id: confirmClear
        modal: true
        anchors.centerIn: Overlay.overlay
        title: "Forget everything?"
        standardButtons: Dialog.Cancel | Dialog.Ok

        Text {
            text: "Every stored memory is deleted permanently.\nThis cannot be undone."
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-1)
            color: Colors.overSurface
        }

        onAccepted: TurretService.forgetAllMemories(() => {
            root.refresh();
            root.changed();
        })
    }
}
