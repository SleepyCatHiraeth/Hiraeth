import QtQuick
import "Splashes.js" as Splashes

// A Hyprland splash quote under the clock, like fastfetch shows in kitty,
// written as the command and its output.
// Changes every 14 s: the old line drifts up and fades, the new one rises in.
Item {
    id: root

    property real unit: 1
    property int interval: 14000

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    property int index: Math.floor(Math.random() * Splashes.list.length)
    property real swap: 1

    function next() {
        var n = index;
        while (Splashes.list.length > 1 && n === index)
            n = Math.floor(Math.random() * Splashes.list.length);
        if (Theme.base > 0) {
            pending = n;
            change.restart();
        } else {
            index = n;
        }
    }
    property int pending: 0

    Timer {
        interval: root.interval
        running: root.visible
        repeat: true
        onTriggered: root.next()
    }

    SequentialAnimation {
        id: change
        NumberAnimation { target: root; property: "swap"; to: 0; duration: Theme.dur(1.6); easing.type: Easing.InCubic }
        ScriptAction { script: root.index = root.pending }
        NumberAnimation { target: root; property: "swap"; to: 1; duration: Theme.dur(2.2); easing.type: Easing.OutCubic }
    }

    Column {
        id: row
        spacing: 6 * root.unit

        // The command fastfetch runs to get these.
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "$ hyprctl splash"
            font.family: Theme.mono
            font.pixelSize: 13 * root.unit
            color: Theme.primary
        }

        Text {
            id: quote
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, 720 * root.unit)
            horizontalAlignment: Text.AlignHCenter
            text: Splashes.list[root.index]
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: Theme.mono
            font.pixelSize: 17 * root.unit
            font.weight: Font.Medium
            color: Theme.overSurface
            opacity: root.swap
            transform: Translate { y: (1 - root.swap) * (change.running && root.index !== root.pending ? -8 : 8) * root.unit }
        }
    }
}
