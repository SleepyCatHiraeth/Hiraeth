pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Greetd

// Login state machine over greetd. Without a greetd socket (running inside a
// normal session to preview the design) it switches to mock mode: any
// password succeeds except "fail", and success quits instead of launching.
Singleton {
    id: root

    readonly property bool mock: !Greetd.available
    // Same entry point SDDM used, through a wrapper that reproduces SDDM's
    // login-shell environment setup.
    readonly property var sessionCommand: ["/usr/share/ambxst-greeter/session.sh", "start-hyprland"]
    readonly property var sessionEnv: ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=Hyprland", "XDG_CURRENT_DESKTOP=Hyprland"]

    // idle | authenticating | success
    property string phase: "idle"
    property string message: ""

    // True while the login card is up. Shared so every screen blurs together.
    property bool engaged: false

    function activity() {
        engaged = true;
        idleTimer.restart();
    }

    function disengage() {
        if (phase !== "idle")
            return;
        idleTimer.stop();
        engaged = false;
        message = "";
    }

    Timer {
        id: idleTimer
        interval: 25000
        onTriggered: root.disengage()
    }

    function power(action) {
        if (mock) {
            console.log("greeter (mock): would run systemctl", action);
            return;
        }
        Quickshell.execDetached(["systemctl", action]);
    }

    signal failed(string message)
    signal succeeded

    property string pending: ""
    property bool answered: false

    function login(password) {
        if (phase !== "idle")
            return;
        message = "";
        phase = "authenticating";
        if (mock) {
            pending = password;
            mockTimer.restart();
            return;
        }
        pending = password;
        answered = false;
        Greetd.createSession(Theme.user);
    }

    // Called by the UI once its exit animation has finished.
    function launch() {
        if (mock) {
            Qt.quit();
            return;
        }
        Greetd.launch(sessionCommand, sessionEnv, true);
    }

    function fail(text) {
        pending = "";
        if (!mock && Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
        phase = "idle";
        message = text;
        failed(text);
    }

    Timer {
        id: mockTimer
        interval: 900
        onTriggered: {
            if (root.pending === "fail") {
                root.fail("Incorrect password");
            } else {
                root.pending = "";
                root.phase = "success";
                root.succeeded();
            }
        }
    }

    Connections {
        target: root.mock ? null : Greetd

        function onAuthMessage(text, error, responseRequired, echoResponse) {
            if (!responseRequired) {
                if (error)
                    root.message = text;
                return;
            }
            // Only a single secret prompt (the password) is supported. A second
            // prompt, e.g. an OTP, would otherwise receive the password again.
            if (root.answered || echoResponse) {
                root.fail(text || "Unsupported login prompt");
                return;
            }
            root.answered = true;
            Greetd.respond(root.pending);
            root.pending = "";
        }

        function onAuthFailure(text) {
            root.fail(text || "Incorrect password");
        }

        function onError(text) {
            root.fail(text || "Login service error");
        }

        function onReadyToLaunch() {
            root.phase = "success";
            root.succeeded();
        }
    }
}
