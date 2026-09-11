pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.globals
import qs.modules.services

// Locking is a QML property, and for a long time that was ALL it was: nothing
// outside this process knew the screen was locked.
//
// That cost two lockouts. The lockscreen is an ext-session-lock surface, and
// that protocol keeps the session locked if the locking client dies -- so
// restarting the shell while it is up destroys the only surface that can take a
// password, and the way back in is a TTY. A guard was added to `ambxst reload`
// after the first one, but it asked logind, and logind was never told.
//
// So every transition is reported to the backend, which answers the reload
// guard and publishes the state to logind for everything else on the machine.
Singleton {
    id: root

    function toggle() {
        GlobalStates.lockscreenVisible = !GlobalStates.lockscreenVisible;
    }

    function lock() {
        GlobalStates.lockscreenVisible = true;
    }

    function unlock() {
        GlobalStates.lockscreenVisible = false;
    }

    // Reported from the property itself, not from the functions above.
    //
    // Three places set `lockscreenVisible`: these functions, the keybind in
    // GlobalShortcuts.qml, and the unlock animation in LockScreen.qml. Reporting
    // from each call site means every future writer has to remember, and the
    // keybind -- the way the screen is actually locked -- is the one that
    // matters most. Watching the property covers all of them, including ones not
    // written yet.
    property Connections lockWatcher: Connections {
        target: GlobalStates

        function onLockscreenVisibleChanged() {
            root.publish();
        }
    }

    function publish() {
        const want = GlobalStates.lockscreenVisible;
        BackendService.call("lock.set", {locked: want}, (result, error) => {
            // A dropped report is the dangerous direction: the daemon would
            // keep a stale value and the guard would answer from it. Retry once
            // on the next tick rather than discarding the error.
            if (error && want === GlobalStates.lockscreenVisible)
                retry.restart();
        });
    }

    property Timer retry: Timer {
        interval: 500
        repeat: false
        onTriggered: root.publish()
    }

    // Published at startup as well as on change, because logind's LockedHint
    // survives things the shell does not. Observed on 2026-09-11: after a
    // reboot the hint read "locked" on a session that was plainly in use, which
    // would have blocked every reload until something happened to clear it.
    // Reporting only transitions would have left that stale value in place
    // indefinitely -- a shell that has just started is, by definition, not
    // showing a lockscreen.
    property Timer announce: Timer {
        running: true
        // Not 0: a Timer with interval 0 never fires in Qt, which this codebase
        // already learned once -- see the unlock timer in LockScreen.qml.
        interval: 1
        repeat: false
        onTriggered: root.publish()
    }

    // Republished whenever the backend connection comes back.
    //
    // The daemon can restart without the shell restarting, and its lock service
    // starts at false. Reporting only on transitions left that wrong until the
    // next lock or unlock: a shell sitting locked through a daemon restart would
    // have had reload allowed against it. A failed call is also retried here,
    // since a write that fails after the socket was established is otherwise
    // lost with no error surfaced.
    property Connections backendWatcher: Connections {
        target: BackendService

        function onSocketAvailableChanged() {
            if (BackendService.socketAvailable)
                root.publish();
        }
    }

    property IpcHandler ipc: IpcHandler {
        target: "lockscreen"

        function toggle() {
            root.toggle();
        }

        function lock() {
            root.lock();
        }

        function unlock() {
            root.unlock();
        }
    }
}
