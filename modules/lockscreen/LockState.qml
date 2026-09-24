pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import qs.modules.globals
import qs.modules.services

// State shared by every lock surface: PAM, the engaged/idle toggle, and the
// small facts shown on the bars. One PamContext for all screens, so a success
// plays the unlock on every monitor at once.
Singleton {
    id: root

    // idle | authenticating | success
    property string phase: "idle"
    // True while the card is up; every screen frosts together.
    property bool engaged: false
    property date lockedAt: new Date()

    signal failed(string message)
    signal succeeded

    readonly property string user: Quickshell.env("USER") || ""

    // A fresh lock starts on the idle clock.
    Connections {
        target: GlobalStates
        function onLockscreenVisibleChanged() {
            if (!GlobalStates.lockscreenVisible)
                return;
            root.phase = "idle";
            root.engaged = false;
            root.lockedAt = new Date();
            root.now = new Date();
        }
    }

    function activity() {
        engaged = true;
        idleTimer.restart();
    }

    function disengage() {
        if (phase !== "idle")
            return;
        idleTimer.stop();
        engaged = false;
    }

    Timer {
        id: idleTimer
        interval: 20000
        onTriggered: root.disengage()
    }

    // ── Auth ──────────────────────────────────────────────────────────────
    // Held only between start() and the PAM prompt, then cleared.
    property string pending: ""

    function unlock(password) {
        if (phase !== "idle" || password.length === 0)
            return;
        pending = password;
        phase = "authenticating";
        idleTimer.stop();
        pam.start();
    }

    // Called by a surface once its unlock animation has finished.
    function finish() {
        GlobalStates.lockscreenVisible = false;
    }

    PamContext {
        id: pam
        configDirectory: Qt.resolvedUrl("../../config/pam").toString().replace("file://", "")
        config: "password.conf"

        onPamMessage: {
            if (this.responseRequired) {
                this.respond(root.pending);
                root.pending = "";
            }
        }

        onCompleted: result => {
            root.pending = "";
            if (result === PamResult.Success) {
                root.phase = "success";
                SoundService.play("loginSuccess");
                root.succeeded();
            } else {
                root.phase = "idle";
                idleTimer.restart();
                SoundService.play("wrongPassword");
                root.failed("incorrect password");
            }
        }
    }

    // ── Facts ─────────────────────────────────────────────────────────────
    property date now: new Date()
    Timer {
        interval: 60000
        running: GlobalStates.lockscreenVisible
        repeat: true
        onTriggered: root.now = new Date()
    }

    property string host: ""
    FileView {
        path: "/etc/hostname"
        onLoaded: root.host = text().trim()
    }

    property string layout: ""
    property bool capsLock: false

    Process {
        running: GlobalStates.lockscreenVisible
        command: ["hyprctl", "getoption", "input:kb_layout", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.layout = (JSON.parse(text).str || "").split(",")[0].trim();
                } catch (e) {}
            }
        }
    }

    // Flip immediately on the key so the warning keeps up with fast
    // toggling, then let hyprctl confirm the real state.
    function capsKey() {
        capsLock = !capsLock;
        capsConfirm.restart();
    }

    function refreshCaps() {
        if (capsProc.running)
            capsPending = true;
        else
            capsProc.running = true;
    }
    property bool capsPending: false

    Timer {
        id: capsConfirm
        interval: 150
        onTriggered: root.refreshCaps()
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

    Timer {
        interval: 1500
        running: GlobalStates.lockscreenVisible
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!capsConfirm.running) root.refreshCaps()
    }
}
