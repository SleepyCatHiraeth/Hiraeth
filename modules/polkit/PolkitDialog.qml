import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Polkit
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config

// The session's polkit authentication agent, replacing hyprpolkitagent.
//
// Registration fails while another agent owns the session, so
// hyprpolkitagent.service must be disabled for this one to take over.
//
// The dialog uses the greeter's design language: a shield badge with a
// progress ring, a terminal-style action line and the live-cipher password
// pill. One 0..1 timeline `t` drives the entrance; each element reads its own
// window of it, and running `t` back to 0 dismisses them in reverse order.
Scope {
    id: root

    readonly property AuthFlow flow: agent.flow

    // Latched on open: the flow object is destroyed as soon as polkit
    // completes, but the dialog still needs its text for the exit animation.
    property string message: ""
    property string actionId: ""

    property bool shown: false
    // "input" | "checking" | "success"
    property string phase: "input"
    property string status: ""
    property bool statusIsError: false
    property real t: 0
    property real failFlash: 0
    property ShellScreen targetScreen: Quickshell.screens[0]

    function dur(factor) { return Motion.enabled ? Math.round(Motion.base * factor) : 0; }
    function span(x, from, to) { return Math.max(0, Math.min(1, (x - from) / (to - from))); }
    function outCubic(x) { return 1 - Math.pow(1 - x, 3); }
    function outQuint(x) { return 1 - Math.pow(1 - x, 5); }
    function outBack(x) {
        const c1 = 1.70158, c3 = c1 + 1;
        return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2);
    }

    function open() {
        message = flow.message;
        actionId = flow.actionId;
        phase = "input";
        status = "";
        pill.clear();
        if (!shown) {
            const name = AxctlService.focusedMonitor?.name;
            targetScreen = Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0];
            closeAnim.stop();
            shown = true;
            openAnim.restart();
        }
        Qt.callLater(pill.focusInput);
    }

    function close() {
        if (!shown || closeAnim.running)
            return;
        openAnim.stop();
        closeAnim.restart();
    }

    function cancel() {
        if (flow && phase !== "success")
            flow.cancelAuthenticationRequest();
        close();
    }

    function submit(password) {
        if (!flow || !flow.isResponseRequired)
            return;
        phase = "checking";
        status = "";
        flow.submit(password);
    }

    // ── Caps Lock ─────────────────────────────────────────────────────────
    // A layer-shell client cannot read lock state, so hyprctl is the source,
    // as in the greeter. The key flips the flag at once so fast toggling
    // keeps up; hyprctl then confirms the real state.
    property bool capsLock: false
    property bool capsPending: false

    function refreshCaps() {
        if (capsProc.running)
            capsPending = true;
        else
            capsProc.running = true;
    }

    function capsKey() {
        capsLock = !capsLock;
        capsConfirm.restart();
    }

    Timer {
        id: capsConfirm
        interval: 150
        onTriggered: root.refreshCaps()
    }

    Timer {
        interval: 1500
        running: root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!capsConfirm.running) root.refreshCaps()
    }

    Process {
        id: capsProc
        command: ["hyprctl", "devices", "-j"]
        onExited: {
            if (root.capsPending) {
                root.capsPending = false;
                running = true;
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const kbs = JSON.parse(text).keyboards || [];
                    const main = kbs.find(k => k.main) || kbs[0];
                    root.capsLock = main ? main.capsLock === true : false;
                } catch (e) {}
            }
        }
    }

    PolkitAgent {
        id: agent
        onFlowChanged: {
            if (flow)
                root.open();
            else if (root.phase !== "success")
                root.close();
        }
    }

    Connections {
        target: root.flow
        function onAuthenticationFailed() {
            root.phase = "input";
            root.status = "authentication failed";
            root.statusIsError = true;
            pill.reject();
            ringFlash.restart();
            SoundService.play("wrongPassword");
        }
        function onAuthenticationSucceeded() {
            root.phase = "success";
            successHold.restart();
        }
        function onIsResponseRequiredChanged() {
            if (root.flow.isResponseRequired) {
                if (root.phase === "checking")
                    root.phase = "input";
                Qt.callLater(pill.focusInput);
            }
        }
        function onSupplementaryMessageChanged() {
            if (root.flow.supplementaryMessage) {
                root.status = root.flow.supplementaryMessage;
                root.statusIsError = root.flow.supplementaryIsError;
            }
        }
    }

    NumberAnimation {
        id: openAnim
        target: root; property: "t"; to: 1
        duration: root.dur(2.6)
    }

    NumberAnimation {
        id: closeAnim
        target: root; property: "t"; to: 0
        duration: root.dur(1.4)
        onFinished: root.shown = false
    }

    // Lets the ring finish its sweep before the dialog leaves.
    Timer {
        id: successHold
        interval: root.dur(2.4)
        onTriggered: root.close()
    }

    SequentialAnimation {
        id: ringFlash
        NumberAnimation { target: root; property: "failFlash"; to: 1; duration: 90 }
        PauseAnimation { duration: 500 }
        NumberAnimation { target: root; property: "failFlash"; to: 0; duration: 700; easing.type: Easing.OutCubic }
    }

    PanelWindow {
        id: window

        screen: root.targetScreen
        visible: root.shown
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "ambxst:polkit"
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        readonly property real scrimIn: root.outCubic(root.span(root.t, 0, 0.4))
        readonly property real cardIn: root.span(root.t, 0.05, 0.6)
        readonly property real badgeIn: root.span(root.t, 0.15, 0.6)
        readonly property real textIn: root.outCubic(root.span(root.t, 0.28, 0.75))
        readonly property real pillIn: root.outQuint(root.span(root.t, 0.36, 1))
        readonly property real footIn: root.span(root.t, 0.6, 1)

        Rectangle {
            anchors.fill: parent
            color: Colors.scrim
            opacity: 0.55 * window.scrimIn
            // Swallows clicks: a stray click must not cancel a request.
            MouseArea { anchors.fill: parent }
        }

        Item {
            id: card
            anchors.centerIn: parent
            anchors.verticalCenterOffset: (1 - root.outCubic(window.cardIn)) * 24
            width: 440
            height: content.implicitHeight + 64
            opacity: Math.min(1, window.cardIn * 2)
            scale: 0.92 + 0.08 * root.outBack(window.cardIn)
            focus: true

            Keys.onEscapePressed: root.cancel()

            StyledRect {
                anchors.fill: parent
                variant: "bg"
                radius: Styling.radius(20)
                layer.enabled: true
                layer.effect: Shadow {}
            }

            Column {
                id: content
                anchors.centerIn: parent
                width: parent.width - 64
                spacing: 14

                // ── Badge ─────────────────────────────────────────────────
                Item {
                    id: badge
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 88
                    height: width
                    opacity: Math.min(1, window.badgeIn * 2)
                    scale: 0.4 + 0.6 * root.outBack(window.badgeIn)

                    // Breathes while waiting for input.
                    property real pulse: 0
                    SequentialAnimation on pulse {
                        running: root.shown && root.phase === "input" && Motion.enabled
                        loops: Animation.Infinite
                        NumberAnimation { to: 1; duration: 1600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0; duration: 1600; easing.type: Easing.InOutSine }
                    }

                    RectangularShadow {
                        anchors.fill: badgeBase
                        radius: width / 2
                        blur: 36
                        color: root.failFlash > 0 ? Colors.error : Colors.primary
                        opacity: root.phase === "success" ? 0.85
                            : root.phase === "checking" ? 0.55
                            : 0.14 + 0.16 * badge.pulse + 0.5 * root.failFlash
                        Behavior on opacity {
                            enabled: Motion.enabled
                            NumberAnimation { duration: root.dur(1.2); easing.type: Easing.InOutSine }
                        }
                    }

                    Rectangle {
                        id: badgeBase
                        anchors.centerIn: parent
                        width: parent.width - 16
                        height: width
                        radius: width / 2
                        color: Colors.surfaceContainerHigh

                        Text {
                            id: shieldIcon
                            anchors.centerIn: parent
                            text: root.phase === "success" ? Icons.shieldCheck : Icons.shield
                            font.family: Icons.font
                            font.pixelSize: 32
                            color: root.failFlash > 0 ? Colors.error : Colors.primary
                            onTextChanged: if (Motion.enabled) iconPop.restart()

                            SequentialAnimation {
                                id: iconPop
                                NumberAnimation { target: shieldIcon; property: "scale"; to: 1.3; duration: root.dur(0.4); easing.type: Easing.OutQuad }
                                NumberAnimation { target: shieldIcon; property: "scale"; to: 1; duration: root.dur(1); easing.type: Easing.OutBack }
                            }
                        }
                    }

                    // Track + progress ring: spins while polkit checks, closes
                    // into a full circle on success.
                    Shape {
                        id: ring
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        property real sweep: root.phase === "success" ? 360 : root.phase === "checking" ? 100 : 0
                        Behavior on sweep {
                            enabled: Motion.enabled
                            NumberAnimation { duration: root.dur(2); easing.type: Easing.InOutCubic }
                        }
                        RotationAnimation on rotation {
                            running: root.phase === "checking" && Motion.enabled
                            loops: Animation.Infinite
                            from: 0; to: 360
                            duration: 1000
                        }

                        ShapePath {
                            strokeColor: root.failFlash > 0
                                ? Qt.rgba(Colors.error.r, Colors.error.g, Colors.error.b, 0.2 + 0.8 * root.failFlash)
                                : Qt.rgba(Colors.overSurface.r, Colors.overSurface.g, Colors.overSurface.b, 0.12)
                            strokeWidth: 2
                            fillColor: "transparent"
                            PathAngleArc {
                                centerX: ring.width / 2; centerY: ring.height / 2
                                radiusX: ring.width / 2 - 2; radiusY: radiusX
                                startAngle: 0; sweepAngle: 360
                            }
                        }
                        ShapePath {
                            strokeColor: Colors.primary
                            strokeWidth: 3.5
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: ring.width / 2; centerY: ring.height / 2
                                radiusX: ring.width / 2 - 2; radiusY: radiusX
                                startAngle: -90; sweepAngle: ring.sweep
                            }
                        }
                    }
                }

                // ── Request ───────────────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: 8
                    opacity: window.textIn
                    transform: Translate { y: (1 - window.textIn) * 12 }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "authentication required"
                        font.family: Config.theme.monoFont
                        font.pixelSize: 12
                        font.letterSpacing: 1.5
                        color: Colors.overSurface
                        opacity: 0.6
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: root.message
                        font.family: Config.theme.font
                        font.pixelSize: 17
                        color: Colors.overSurface
                    }

                    // The polkit action, as a prompt line.
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                        visible: root.actionId !== ""
                        textFormat: Text.StyledText
                        text: "<font color='" + Colors.primary + "'>❯</font> " + root.actionId
                        font.family: Config.theme.monoFont
                        font.pixelSize: 11
                        color: Colors.overSurfaceVariant
                        opacity: 0.75
                    }
                }

                // ── Identity ──────────────────────────────────────────────
                // Clicking cycles through the admin identities polkit offers;
                // with only one it is a plain label.
                Text {
                    id: identityLabel
                    anchors.horizontalCenter: parent.horizontalCenter
                    readonly property var ids: root.flow ? root.flow.identities : []
                    readonly property var current: root.flow ? root.flow.selectedIdentity : null
                    property string shownName: ""
                    onCurrentChanged: if (current) shownName = (current.isGroup ? "%" : "") + current.string
                    textFormat: Text.StyledText
                    text: "as <b>" + shownName + "</b>" + (ids.length > 1 ? "  <font color='" + Colors.primary + "'>⇄</font>" : "")
                    font.family: Config.theme.monoFont
                    font.pixelSize: 13
                    color: Colors.overSurface
                    opacity: 0.85 * window.textIn

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        enabled: identityLabel.ids.length > 1 && root.phase === "input"
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            const ids = identityLabel.ids;
                            root.flow.selectedIdentity = ids[(ids.indexOf(identityLabel.current) + 1) % ids.length];
                        }
                    }
                }

                // ── Password ──────────────────────────────────────────────
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 280
                    height: pill.height

                    PolkitPill {
                        id: pill
                        anchors.centerIn: parent
                        // Grows from a circle to the full pill.
                        width: height + (parent.width - height) * window.pillIn
                        contentOpacity: root.span(window.pillIn, 0.55, 1)
                        opacity: root.span(root.t, 0.36, 0.56)
                        busy: root.phase !== "input"
                        echo: root.flow ? root.flow.responseVisible : false
                        placeholder: {
                            const p = root.flow ? root.flow.inputPrompt.replace(/:\s*$/, "").trim().toLowerCase() : "";
                            return p || "password";
                        }
                        onSubmitted: password => root.submit(password)
                        onCapsKey: root.capsKey()
                    }
                }

                // ── Status ────────────────────────────────────────────────
                // Error or info line, or the Caps Lock warning when there is
                // none. Keeps its height so the card never jumps.
                Item {
                    width: parent.width
                    height: 18

                    Text {
                        id: statusText
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: (root.statusIsError ? "✗ " : "") + root.status.toLowerCase()
                        font.family: Config.theme.monoFont
                        font.pixelSize: 12
                        color: root.statusIsError ? Colors.error : Colors.overSurfaceVariant
                        opacity: root.status !== "" ? 1 : 0
                        transform: Translate { id: statusShift }
                        Behavior on opacity {
                            enabled: Motion.enabled
                            NumberAnimation { duration: root.dur(0.8); easing.type: Easing.OutCubic }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "[caps lock]"
                        font.family: Config.theme.monoFont
                        font.pixelSize: 12
                        color: Colors.yellow
                        opacity: root.capsLock && statusText.opacity < 0.05 ? window.pillIn : 0
                        scale: opacity > 0 ? 1 : 0.9
                        Behavior on opacity {
                            enabled: Motion.enabled
                            NumberAnimation { duration: Motion.micro }
                        }
                        Behavior on scale {
                            enabled: Motion.enabled
                            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutBack }
                        }
                    }

                    Connections {
                        target: root
                        function onStatusChanged() {
                            if (root.status !== "" && Motion.enabled)
                                statusDrop.restart();
                        }
                    }
                    NumberAnimation {
                        id: statusDrop
                        target: statusShift; property: "y"
                        from: -8; to: 0
                        duration: root.dur(1.4); easing.type: Easing.OutBack
                    }
                }

                // ── Footer ────────────────────────────────────────────────
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "esc  ·  cancel"
                    font.family: Config.theme.monoFont
                    font.pixelSize: 11
                    color: cancelArea.containsMouse ? Colors.primary : Colors.overSurface
                    opacity: 0.55 * window.footIn
                    Behavior on color {
                        enabled: Motion.enabled
                        ColorAnimation { duration: Motion.micro }
                    }

                    MouseArea {
                        id: cancelArea
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancel()
                    }
                }
            }
        }
    }
}
