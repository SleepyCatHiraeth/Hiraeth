pragma Singleton

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io

// Small facts shown around the login card: greeting, last login, pending
// updates, keyboard layout, Caps Lock, plus the login sounds. Everything is
// read locally by the greeter user: wtmp and hyprctl are world-readable, the
// update count and sounds come from the snapshot.
Singleton {
    id: root

    property date now: new Date()
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    readonly property string greeting: {
        const h = now.getHours();
        if (h >= 5 && h < 12)
            return "good morning";
        if (h >= 12 && h < 18)
            return "good afternoon";
        if (h >= 18 && h < 23)
            return "good evening";
        return "up late";
    }

    // ── Host ──────────────────────────────────────────────────────────────
    property string host: ""
    FileView {
        path: "/etc/hostname"
        onLoaded: root.host = text().trim()
    }

    // ── Last login ────────────────────────────────────────────────────────
    // The user's shell records its session start in the snapshot; read at the
    // greeter, that is the previous login. (greetd writes no wtmp, so `last`
    // would only ever show the last login made through another manager.)
    property date lastLogin: new Date(NaN)
    readonly property string lastLoginText: {
        if (isNaN(lastLogin.getTime()))
            return "";
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const day = new Date(lastLogin.getFullYear(), lastLogin.getMonth(), lastLogin.getDate());
        const days = Math.round((today - day) / 86400000);
        const time = Qt.formatTime(lastLogin, "hh:mm");
        if (days === 0)
            return "today " + time;
        if (days === 1)
            return "yesterday " + time;
        if (days < 7)
            return lastLogin.toLocaleDateString(Qt.locale(), "ddd").toLowerCase() + " " + time;
        return Qt.formatDate(lastLogin, "dd.MM.") + " " + time;
    }

    FileView {
        path: Theme.dir + "/lastlogin"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const s = parseInt(text());
            root.lastLogin = s > 0 ? new Date(s * 1000) : new Date(NaN);
        }
    }

    // ── Updates ───────────────────────────────────────────────────────────
    property int updates: 0
    FileView {
        path: Theme.dir + "/updates"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.updates = parseInt(text()) || 0
        onLoadFailed: root.updates = 0
    }

    // ── Keyboard ──────────────────────────────────────────────────────────
    property string layout: ""
    property bool capsLock: false

    Process {
        running: true
        command: ["hyprctl", "getoption", "input:kb_layout", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.layout = (JSON.parse(text).str || "").split(",")[0].trim();
                } catch (e) {}
            }
        }
    }

    // Called on key presses and polled while the card is up; hyprctl is the
    // only source of lock state a layer-shell client has.
    function refreshCaps() {
        if (capsProc.running)
            capsPending = true;
        else
            capsProc.running = true;
    }
    property bool capsPending: false

    // Flip immediately on the key so the warning keeps up with fast
    // toggling, then let hyprctl confirm the real state.
    function capsKey() {
        capsLock = !capsLock;
        capsConfirm.restart();
    }

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
        running: Session.engaged
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!capsConfirm.running) root.refreshCaps()
    }

    // ── Sounds ────────────────────────────────────────────────────────────
    function play(key) {
        const s = key === "loginSuccess" ? successSound : key === "wrongPassword" ? wrongSound : null;
        if (s && s.source.toString() !== "")
            s.play();
    }

    readonly property var soundConfig: Theme.config.sound || ({})

    SoundEffect {
        id: successSound
        source: root.soundConfig.loginSuccess ? "file://" + Theme.dir + "/" + root.soundConfig.loginSuccess : ""
        volume: root.soundConfig.volume !== undefined ? root.soundConfig.volume : 0.8
    }

    SoundEffect {
        id: wrongSound
        source: root.soundConfig.wrongPassword ? "file://" + Theme.dir + "/" + root.soundConfig.wrongPassword : ""
        volume: root.soundConfig.volume !== undefined ? root.soundConfig.volume : 0.8
    }

    Connections {
        target: Session
        function onSucceeded() { root.play("loginSuccess"); }
        function onFailed() { root.play("wrongPassword"); }
    }
}
