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
    // The store's own history. Never contains memory text, so showing it costs
    // nothing in privacy terms and answers the question the list cannot:
    // what was decided, and when.
    property var history: []
    property bool showingHistory: false

    function refresh() {
        TurretService.listMemories(result => {
            root.items = (result && result.items) ? result.items : [];
        });
        if (root.showingHistory)
            root.refreshHistory();
    }

    function refreshHistory() {
        TurretService.memoryAudit(100, entries => {
            root.history = entries || [];
        });
    }

    function describeAction(action) {
        // Names come from Store.audit() in the Go memory package; keep them in
        // step with it rather than inventing friendlier ones here.
        switch (action) {
        case "put": return "remembered";
        case "confirm": return "you kept";
        case "correct": return "you corrected";
        case "delete": return "you forgot";
        case "delete_all": return "you forgot everything";
        case "purge_expired": return "expired";
        case "purge_failed": return "expiry sweep failed";
        default: return action.replace(/_/g, " ");
        }
    }

    onOpened: refresh()

    contentItem: ColumnLayout {
        spacing: 10

        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: root.showingHistory ? "History" : "Stored memories"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(1)
                font.weight: Font.Medium
                color: Colors.overSurface
            }

            Button {
                text: root.showingHistory ? "Memories" : "History"
                onClicked: {
                    root.showingHistory = !root.showingHistory;
                    if (root.showingHistory)
                        root.refreshHistory();
                }
            }

            Button {
                text: "Forget everything"
                visible: !root.showingHistory
                enabled: root.items.length > 0
                onClicked: confirmClear.open()
            }
        }

        Text {
            Layout.fillWidth: true
            visible: !root.showingHistory && root.items.length === 0
            text: "Nothing stored yet."
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-1)
            color: Colors.overSurfaceVariant
        }

        // History: what the store decided, newest first. Deliberately plain --
        // this is a record to read, not a list to act on.
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.showingHistory
            clip: true
            spacing: 2
            model: root.history

            delegate: RowLayout {
                id: auditRow
                required property var modelData
                width: ListView.view.width
                spacing: 8

                Text {
                    text: new Date(auditRow.modelData.at * 1000)
                          .toLocaleString(Qt.locale(), Locale.ShortFormat)
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.overSurfaceVariant
                }
                Text {
                    Layout.fillWidth: true
                    text: root.describeAction(auditRow.modelData.action)
                          + (auditRow.modelData.detail ? " · " + auditRow.modelData.detail : "")
                    elide: Text.ElideRight
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    color: Colors.overSurface
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.showingHistory && root.history.length === 0
            text: "Nothing has happened yet."
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-1)
            color: Colors.overSurfaceVariant
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.showingHistory
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
