import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import qs.config
import qs.modules.components
import qs.modules.services

// The saved-conversation list, shown over the chat.
//
// Its own file mostly because it is self-contained: it reads Ai.chatHistory,
// loads and deletes through Ai, and tells its host when to put it away. The
// panel it covers does not need to know any of that.
StyledRect {
    id: root

    required property bool expanded
    // Raised when a chat is chosen or the list should otherwise close.
    signal dismissed

    variant: "bg"
    // Driven by opacity rather than by `expanded` directly: a `visible` bound
    // to the same flag switches off in the frame the fade starts, so the
    // fade-out never showed.
    visible: opacity > 0.01
    enabled: root.expanded
    opacity: root.expanded ? 1 : 0

    Behavior on opacity {
        enabled: Motion.enabled
        NumberAnimation {
            duration: Motion.normal
            easing.type: Motion.normalEasing
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        Text {
            text: I18n.t("ai.chat_history")
            color: Colors.overSurface
            font.family: Config.theme.font
            font.pixelSize: 18
            font.weight: Font.Bold
        }

        Text {
            visible: Ai.historyError !== ""
            Layout.fillWidth: true
            text: I18n.t("ai.chat_store_failed").replace("%1", Ai.historyError)
            color: Colors.error
            font.family: Config.theme.font
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }

        ListView {
            id: historyList
            visible: Ai.historyError === ""
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: Ai.chatHistory
            spacing: 4

            delegate: Button {
                enabled: !Ai.isLoading
                width: historyList.width
                height: 48
                flat: true

                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            text: modelData.title || "New Chat"
                            color: Ai.currentChatId === modelData.id ? Styling.srItem("primary") : Colors.overSurface
                            font.family: Config.theme.font
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: {
                                // The store reports when the conversation was
                                // last written. Chat ids happen to be creation
                                // timestamps, which is the fallback, but an
                                // imported one is only as good as its old file.
                                const stamp = modelData.updatedAt || parseInt(modelData.id);
                                if (!stamp)
                                    return "";
                                return new Date(stamp).toLocaleString(Qt.locale(), "MMM dd, hh:mm a");
                            }
                            color: Ai.currentChatId === modelData.id ? Styling.srItem("primary") : Colors.outline
                            font.family: Config.theme.font
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    Button {
                        visible: parent.parent.hovered
                        flat: true
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28

                        contentItem: Text {
                            text: Icons.trash
                            font.family: Icons.font
                            color: parent.hovered ? Colors.error : Colors.outline
                            font.pixelSize: 14
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: null
                        onClicked: Ai.deleteChat(modelData.id)
                    }
                }

                background: StyledRect {
                    variant: Ai.currentChatId === modelData.id ? "focus" : (parent.hovered ? "surfaceVariant" : "transparent")
                    radius: Styling.radius(6)
                }

                onClicked: {
                    Ai.loadChat(modelData.id);
                    root.expanded = false;
                }
            }
        }
    }
}
