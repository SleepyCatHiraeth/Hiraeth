import QtQuick

// Round icon button whose label slides out on hover, so the corner stays quiet
// until the pointer goes there.
Rectangle {
    id: root

    property real unit: 1
    property string icon
    property string label
    signal activated

    readonly property real open: area.containsMouse ? 1 : 0
    property real openAnim: open
    Behavior on openAnim {
        enabled: Theme.base > 0
        NumberAnimation { duration: Theme.dur(1.2); easing.type: Easing.OutQuint }
    }

    height: 46 * unit
    width: height + (caption.implicitWidth + 14 * unit) * openAnim
    radius: Theme.pillRadius(height)
    color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.4 + 0.4 * openAnim)
    border.width: 1
    border.color: Qt.rgba(Theme.overSurface.r, Theme.overSurface.g, Theme.overSurface.b, 0.08 + 0.14 * openAnim)
    scale: area.pressed ? 0.92 : 1
    clip: true

    Behavior on scale {
        enabled: Theme.base > 0
        NumberAnimation { duration: Theme.dur(0.6); easing.type: Easing.OutBack }
    }

    Text {
        id: glyph
        x: (root.height - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        font.family: Theme.iconFont
        font.pixelSize: 20 * root.unit
        color: Theme.overSurface
    }

    Text {
        id: caption
        anchors.left: glyph.right
        anchors.leftMargin: 10 * root.unit + 6 * root.unit * (1 - root.openAnim)
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        font.family: Theme.mono
        font.pixelSize: 13 * root.unit
        color: Theme.overSurface
        opacity: root.openAnim
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
