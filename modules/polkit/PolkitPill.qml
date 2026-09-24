import QtQuick
import QtQuick.Shapes
import qs.modules.theme
import qs.config

// Password field for the polkit dialog, in the greeter's style: a hairline
// pill with a prompt glyph, a live cipher instead of dots, an arrow that turns
// into a spinner while polkit checks, and a shake with a red outline on
// failure. Adapted from greeter/PasswordPill.qml, which reads the greeter's
// snapshot theme instead of the shell's singletons.
Item {
    id: root

    property bool busy: false
    // Polkit asks for echo on non-secret prompts; the text is then shown as typed.
    property bool echo: false
    property string placeholder: "password"
    // Fades the content while the pill is still growing.
    property real contentOpacity: 1
    property alias text: input.text

    signal submitted(string password)
    signal capsKey()

    implicitWidth: 280
    implicitHeight: 42

    function clear() { input.text = ""; }
    function focusInput() { input.forceActiveFocus(); }

    function reject() {
        errorFlash.restart();
        shake.restart();
        clear();
    }

    function dur(factor) { return Math.round(Motion.base * factor); }

    property real shakeX: 0
    property real flash: 0
    readonly property bool hasText: input.text.length > 0
    readonly property string mono: Config.theme.monoFont

    Rectangle {
        x: root.shakeX
        width: parent.width
        height: parent.height
        radius: Config.roundness > 0 ? (height / 2) * Math.min(1, Config.roundness / 16) : 0
        color: Qt.rgba(0, 0, 0, 0.18)
        border.width: 1
        border.color: root.flash > 0
            ? Qt.rgba(Colors.error.r, Colors.error.g, Colors.error.b, 0.35 + 0.65 * root.flash)
            : Qt.rgba(Colors.overSurface.r, Colors.overSurface.g, Colors.overSurface.b, input.activeFocus ? 0.38 : 0.18)

        Behavior on border.color {
            enabled: Motion.enabled && root.flash === 0
            ColorAnimation { duration: root.dur(1) }
        }

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 36
            anchors.rightMargin: 40
            verticalAlignment: TextInput.AlignVCenter
            echoMode: TextInput.NoEcho
            color: "transparent"
            cursorVisible: false
            cursorDelegate: Item {}
            // Read-only, not disabled: a disabled input drops focus, and Esc
            // would stop reaching the dialog while polkit checks.
            readOnly: root.busy
            focus: true
            onAccepted: {
                if (text.length > 0)
                    root.submitted(text);
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_CapsLock)
                    root.capsKey();
                event.accepted = false;
            }
        }

        // Shell prompt glyph.
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: "❯"
            font.family: root.mono
            font.pixelSize: 15
            font.weight: Font.Bold
            color: root.flash > 0 ? Colors.error : Colors.primary
            opacity: root.contentOpacity
        }

        Text {
            anchors.left: input.left
            anchors.leftMargin: 13
            anchors.verticalCenter: parent.verticalCenter
            text: root.placeholder
            font.family: root.mono
            font.pixelSize: 13
            color: Colors.overSurface
            opacity: (root.hasText ? 0 : 0.45) * root.contentOpacity
            Behavior on opacity {
                enabled: Motion.enabled
                NumberAnimation { duration: root.dur(0.6) }
            }
        }

        Item {
            anchors.fill: input
            clip: true
            opacity: root.contentOpacity

            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: Math.min(0, parent.width - width)
                spacing: 1
                Behavior on x {
                    enabled: Motion.enabled
                    NumberAnimation { duration: root.dur(0.6); easing.type: Easing.OutCubic }
                }

                // Echoed prompts show the real text.
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.echo
                    text: input.text
                    font.family: root.mono
                    font.pixelSize: 14
                    color: Colors.overSurface
                }

                Repeater {
                    model: root.echo ? 0 : input.text.length
                    // Each character arrives as a fast scramble of code glyphs,
                    // then keeps drifting slowly: a live cipher, never the
                    // real character.
                    delegate: Text {
                        id: glyph
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9
                        horizontalAlignment: Text.AlignHCenter
                        font.family: root.mono
                        font.pixelSize: 15
                        color: settled ? Colors.overSurface : Colors.primary
                        property bool settled: false
                        property int frames: 0
                        readonly property string pool: "01{}<>/#$%&?!=+~^;:ab3f"
                        function pick() { return pool.charAt(Math.floor(Math.random() * pool.length)); }
                        Behavior on color {
                            enabled: Motion.enabled
                            ColorAnimation { duration: root.dur(0.8) }
                        }
                        Component.onCompleted: if (!Motion.enabled) { text = pick(); settled = true; }
                        Timer {
                            // Fast while arriving, then one change every ~0.5-0.8 s.
                            interval: glyph.settled ? 480 + Math.random() * 300 : 38
                            repeat: true
                            running: !glyph.settled || Motion.enabled
                            triggeredOnStart: true
                            onTriggered: {
                                glyph.text = glyph.pick();
                                if (!glyph.settled && ++glyph.frames > 5)
                                    glyph.settled = true;
                            }
                        }
                    }
                }

                // Block cursor, blinking like a terminal's.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7
                    height: 15
                    radius: 1.5
                    color: Colors.primary
                    visible: input.activeFocus && !root.busy
                    opacity: blink.on ? 0.9 : 0
                    Timer {
                        id: blink
                        property bool on: true
                        interval: 530
                        running: parent.visible && Motion.enabled
                        repeat: true
                        onTriggered: on = !on
                    }
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
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: width

            property real shownAnim: root.hasText || root.busy ? 1 : 0
            Behavior on shownAnim {
                enabled: Motion.enabled
                NumberAnimation { duration: root.dur(1); easing.type: Easing.OutCubic }
            }
            opacity: shownAnim * root.contentOpacity
            transform: Translate { x: (1 - submit.shownAnim) * -8 }

            Shape {
                anchors.fill: parent
                opacity: root.busy ? 0 : (submitArea.containsMouse ? 1 : 0.8)
                scale: submitArea.pressed ? 0.85 : 1
                preferredRendererType: Shape.CurveRenderer
                Behavior on opacity { enabled: Motion.enabled; NumberAnimation { duration: root.dur(0.6) } }
                Behavior on scale { enabled: Motion.enabled; NumberAnimation { duration: root.dur(0.4) } }
                ShapePath {
                    strokeColor: Colors.overSurface
                    strokeWidth: 1.8
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    startX: 3; startY: 10
                    PathLine { x: 17; y: 10 }
                    PathMove { x: 11; y: 4 }
                    PathLine { x: 17; y: 10 }
                    PathLine { x: 11; y: 16 }
                }
            }

            Shape {
                id: spinner
                anchors.fill: parent
                opacity: root.busy ? 1 : 0
                preferredRendererType: Shape.CurveRenderer
                Behavior on opacity { enabled: Motion.enabled; NumberAnimation { duration: root.dur(0.6) } }
                RotationAnimation on rotation {
                    running: root.busy
                    loops: Animation.Infinite
                    from: 0; to: 360
                    duration: 900
                }
                ShapePath {
                    strokeColor: Colors.overSurface
                    strokeWidth: 1.8
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: spinner.width / 2; centerY: spinner.height / 2
                        radiusX: spinner.width / 2 - 2; radiusY: radiusX
                        startAngle: 0; sweepAngle: 260
                    }
                }
            }

            MouseArea {
                id: submitArea
                anchors.fill: parent
                anchors.margins: -8
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
        NumberAnimation { target: root; property: "shakeX"; to: 14; duration: 60; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: -11; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 7; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: -3; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 90; easing.type: Easing.OutQuad }
    }

    SequentialAnimation {
        id: errorFlash
        NumberAnimation { target: root; property: "flash"; to: 1; duration: 90 }
        PauseAnimation { duration: 400 }
        NumberAnimation { target: root; property: "flash"; to: 0; duration: 800; easing.type: Easing.OutCubic }
    }
}
