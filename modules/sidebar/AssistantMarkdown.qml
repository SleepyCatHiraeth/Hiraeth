import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.config
import "MessageSegments.js" as MessageSegments

// A finished reply: prose as Markdown, fenced runs as CodeBlock.
//
// Only ever given text that has stopped arriving. A streaming reply renders as
// one plain Text node instead, because segmenting and re-parsing on every token
// was the single most expensive thing this panel did.
ColumnLayout {
    id: root

    required property string text
    required property color textColor
    // The width a segment should lay out to. Taken from the caller rather than
    // from this layout, which is still settling while its children are built.
    required property real contentWidth

    spacing: 8

    Repeater {
        model: MessageSegments.split(root.text)

        delegate: Loader {
            required property var modelData

            Layout.fillWidth: true
            sourceComponent: modelData.type === "code" ? codeComponent : textComponent

            readonly property var segment: modelData

            Component {
                id: textComponent

                TextEdit {
                    width: root.contentWidth
                    text: segment.content
                    textFormat: Text.MarkdownText
                    color: root.textColor
                    font.family: Config.theme.font
                    font.pixelSize: 14
                    wrapMode: Text.Wrap
                    readOnly: true
                    selectByMouse: true

                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
            }

            Component {
                id: codeComponent

                CodeBlock {
                    width: root.contentWidth
                    code: segment.content
                    language: segment.language
                }
            }
        }
    }
}
