import QtQuick
import QtQuick.Shapes

// Minimal password field: a hairline pill with dots. The arrow slides in once
// something is typed and turns into a spinner while greetd checks; a wrong
// password shakes the pill and tints its outline red.
Item {
    id: root

    property real unit: 1
    property bool busy: false
    // Fades the dots/placeholder while the pill is still growing.
    property real contentOpacity: 1
    property alias text: input.text

    signal submitted(string password)

    implicitWidth: 260 * unit
    implicitHeight: 40 * unit

    function clear() { input.text = ""; }
    function focusInput() { input.forceActiveFocus(); }
    function insert(t) { input.insert(input.cursorPosition, t); }

    function reject() {
        errorFlash.restart();
        shake.restart();
        clear();
    }

    property real shakeX: 0
    property real flash: 0
    readonly property bool hasText: input.text.length > 0

    Rectangle {
        id: body
        x: root.shakeX
        width: parent.width
        height: parent.height
        radius: Theme.pillRadius(height)
        color: Qt.rgba(0, 0, 0, 0.18)
        border.width: 1
        border.color: root.flash > 0
            ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.35 + 0.65 * root.flash)
            : Qt.rgba(Theme.overSurface.r, Theme.overSurface.g, Theme.overSurface.b, input.activeFocus ? 0.38 : 0.18)

        Behavior on border.color {
            enabled: Theme.base > 0 && root.flash === 0
            ColorAnimation { duration: Theme.dur(1) }
        }

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 36 * root.unit
            anchors.rightMargin: 40 * root.unit
            verticalAlignment: TextInput.AlignVCenter
            echoMode: TextInput.NoEcho
            color: "transparent"
            cursorVisible: false
            // The block cursor below replaces the native one.
            cursorDelegate: Item {}
            enabled: !root.busy
            focus: true
            onAccepted: {
                if (text.length > 0)
                    root.submitted(text);
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_CapsLock)
                    Info.capsKey();
                event.accepted = false;
            }
        }

        // Shell prompt glyph.
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16 * root.unit
            anchors.verticalCenter: parent.verticalCenter
            text: "\u276f"
            font.family: Theme.mono
            font.pixelSize: 15 * root.unit
            font.weight: Font.Bold
            color: root.flash > 0 ? Theme.error : Theme.primary
            opacity: root.contentOpacity
        }

        Text {
            anchors.left: input.left
            anchors.leftMargin: 13 * root.unit
            anchors.verticalCenter: parent.verticalCenter
            text: "password"
            font.family: Theme.mono
            font.pixelSize: 13 * root.unit
            color: Theme.overSurface
            opacity: (root.hasText ? 0 : 0.45) * root.contentOpacity
            Behavior on opacity {
                enabled: Theme.base > 0
                NumberAnimation { duration: Theme.dur(0.6) }
            }
        }

        // One dot per character; the row scrolls to keep the newest in view.
        Item {
            anchors.fill: input
            clip: true
            opacity: root.contentOpacity

            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: Math.min(0, parent.width - width)
                spacing: 1 * root.unit
                Behavior on x {
                    enabled: Theme.base > 0
                    NumberAnimation { duration: Theme.dur(0.6); easing.type: Easing.OutCubic }
                }

                Repeater {
                    id: dotRepeater
                    model: input.text.length
                    // Each character arrives as a fast scramble of code glyphs,
                    // then keeps drifting slowly: a live cipher, never the
                    // real character.
                    delegate: Text {
                        id: glyph
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9 * root.unit
                        horizontalAlignment: Text.AlignHCenter
                        text: ""
                        font.family: Theme.mono
                        font.pixelSize: 15 * root.unit
                        color: settled ? Theme.overSurface : Theme.primary
                        property bool settled: false
                        property int frames: 0
                        readonly property string pool: "01{}<>/#$%&?!=+~^;:ab3f"
                        function pick(s) { return s.charAt(Math.floor(Math.random() * s.length)); }
                        Behavior on color {
                            enabled: Theme.base > 0
                            ColorAnimation { duration: Theme.dur(0.8) }
                        }
                        Component.onCompleted: if (Theme.base === 0) { text = pick(pool); settled = true; }
                        Timer {
                            // Fast while arriving, then one change every ~0.5-0.8 s.
                            interval: glyph.settled ? 480 + Math.random() * 300 : 38
                            repeat: true
                            running: !glyph.settled || Theme.base > 0
                            triggeredOnStart: true
                            onTriggered: {
                                if (glyph.settled) {
                                    glyph.text = glyph.pick(glyph.pool);
                                } else if (++glyph.frames > 5) {
                                    glyph.text = glyph.pick(glyph.pool);
                                    glyph.settled = true;
                                } else {
                                    glyph.text = glyph.pick(glyph.pool);
                                }
                            }
                        }
                    }
                }

                // Block cursor, blinking like a terminal's.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7 * root.unit
                    height: 15 * root.unit
                    radius: 1.5 * root.unit
                    color: Theme.primary
                    visible: input.activeFocus && !root.busy
                    opacity: blink.on ? 0.9 : 0
                    Timer {
                        id: blink
                        property bool on: true
                        interval: 530
                        running: parent.visible && Theme.base > 0
                        repeat: true
                        onTriggered: on = !on
                    }
                    // Solid while typing, blinking when idle.
                    Connections {
                        target: input
                        function onTextChanged() {
                            blink.on = true;
                            blink.restart();
                        }
                    }
                }
            }
        }

        // Arrow / spinner, no button chrome.
        Item {
            id: submit
            anchors.right: parent.right
            anchors.rightMargin: 12 * root.unit
            anchors.verticalCenter: parent.verticalCenter
            width: 20 * root.unit
            height: width

            readonly property real shown: root.hasText || root.busy ? 1 : 0
            property real shownAnim: shown
            Behavior on shownAnim {
                enabled: Theme.base > 0
                NumberAnimation { duration: Theme.dur(1); easing.type: Easing.OutCubic }
            }
            opacity: shownAnim * root.contentOpacity
            transform: Translate { x: (1 - submit.shownAnim) * -8 * root.unit }

            Shape {
                anchors.fill: parent
                opacity: root.busy ? 0 : (submitArea.containsMouse ? 1 : 0.8)
                scale: submitArea.pressed ? 0.85 : 1
                preferredRendererType: Shape.CurveRenderer
                Behavior on opacity { enabled: Theme.base > 0; NumberAnimation { duration: Theme.dur(0.6) } }
                Behavior on scale { enabled: Theme.base > 0; NumberAnimation { duration: Theme.dur(0.4) } }
                ShapePath {
                    strokeColor: Theme.overSurface
                    strokeWidth: 1.8 * root.unit
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    startX: 3 * root.unit; startY: 10 * root.unit
                    PathLine { x: 17 * root.unit; y: 10 * root.unit }
                    PathMove { x: 11 * root.unit; y: 4 * root.unit }
                    PathLine { x: 17 * root.unit; y: 10 * root.unit }
                    PathLine { x: 11 * root.unit; y: 16 * root.unit }
                }
            }

            Shape {
                id: spinner
                anchors.fill: parent
                opacity: root.busy ? 1 : 0
                preferredRendererType: Shape.CurveRenderer
                Behavior on opacity { enabled: Theme.base > 0; NumberAnimation { duration: Theme.dur(0.6) } }
                RotationAnimation on rotation {
                    running: root.busy
                    loops: Animation.Infinite
                    from: 0; to: 360
                    duration: 900
                }
                ShapePath {
                    strokeColor: Theme.overSurface
                    strokeWidth: 1.8 * root.unit
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: spinner.width / 2; centerY: spinner.height / 2
                        radiusX: spinner.width / 2 - 2 * root.unit; radiusY: radiusX
                        startAngle: 0; sweepAngle: 260
                    }
                }
            }

            MouseArea {
                id: submitArea
                anchors.fill: parent
                anchors.margins: -8 * root.unit
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.hasText && !root.busy)
                        root.submitted(input.text);
                }
            }
        }
    }

    SequentialAnimation {
        id: shake
        NumberAnimation { target: root; property: "shakeX"; to: 14 * root.unit; duration: 60; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: -11 * root.unit; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 7 * root.unit; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: -3 * root.unit; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 90; easing.type: Easing.OutQuad }
    }

    SequentialAnimation {
        id: errorFlash
        NumberAnimation { target: root; property: "flash"; to: 1; duration: 90 }
        PauseAnimation { duration: 400 }
        NumberAnimation { target: root; property: "flash"; to: 0; duration: 800; easing.type: Easing.OutCubic }
    }
}
