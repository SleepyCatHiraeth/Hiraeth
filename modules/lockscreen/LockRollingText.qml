import QtQuick

// Text that rolls to its new value: the old string slides up and fades while
// the new one rises into place. Used for clock digits.
Item {
    id: root

    property string text
    property alias font: current.font
    property color color: LockStyle.primaryFixed

    implicitWidth: Math.max(current.implicitWidth, previous.implicitWidth)
    implicitHeight: current.implicitHeight
    clip: true

    property string shown: text

    onTextChanged: {
        if (text === shown)
            return;
        previous.text = shown;
        shown = text;
        if (LockStyle.base > 0)
            roll.restart();
    }

    Text {
        id: previous
        anchors.horizontalCenter: parent.horizontalCenter
        font: current.font
        color: root.color
        opacity: 0
    }

    Text {
        id: current
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.shown
        color: root.color
    }

    ParallelAnimation {
        id: roll
        NumberAnimation { target: previous; property: "y"; from: 0; to: -root.height * 0.6; duration: LockStyle.dur(2); easing.type: Easing.InOutCubic }
        NumberAnimation { target: previous; property: "opacity"; from: 1; to: 0; duration: LockStyle.dur(1.6); easing.type: Easing.OutCubic }
        NumberAnimation { target: current; property: "y"; from: root.height * 0.6; to: 0; duration: LockStyle.dur(2); easing.type: Easing.OutCubic }
        NumberAnimation { target: current; property: "opacity"; from: 0; to: 1; duration: LockStyle.dur(2); easing.type: Easing.OutCubic }
    }
}
