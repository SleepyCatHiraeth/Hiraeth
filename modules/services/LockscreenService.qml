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
        BackendService.call("lock.set", {locked: GlobalStates.lockscreenVisible}, () => {});
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
        interval: 0
        repeat: false
        onTriggered: root.publish()
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
