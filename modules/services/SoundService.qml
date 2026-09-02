pragma Singleton

import QtQuick
import QtMultimedia
import Quickshell
import qs.config
import qs.modules.services

Singleton {
    id: root

    readonly property real effectiveVolume: Math.max(0, Math.min(1, Config.sound.volume))
    readonly property bool shellReady: Config.initialLoadComplete && Config.soundReady
    property bool bootUpPlayed: false
    // Set when play() is called for the Portal Turret theme before its async
    // directory-existence check (SoundThemes.availabilityChecked) has
    // resolved — retried once that check completes, instead of silently
    // falling back to the Default theme for whichever event fired first
    // during startup/login.
    property string pendingEventKey: ""

    function playBootUpOnce() {
        if (shellReady && !bootUpPlayed) {
            bootUpPlayed = true;
            play("bootUp");
        }
    }

    onShellReadyChanged: playBootUpOnce()
    Component.onCompleted: playBootUpOnce()

    function play(eventKey) {
        if (!Config.sound.enabled)
            return;

        const event = Config.sound.events?.[eventKey];
        if (!event || event.muted)
            return;

        const override = typeof event.sound === "string" && event.sound.startsWith("/") ? event.sound : "";

        // An absolute-path override bypasses theme resolution entirely, so
        // it never needs to wait on SoundThemes' async availability check.
        if (!override && Config.sound.theme === "portal-turret" && !SoundThemes.availabilityChecked) {
            pendingEventKey = eventKey;
            return;
        }

        let theme = SoundThemes.resolveTheme(Config.sound.theme);
        if (!theme.available)
            theme = SoundThemes.resolveTheme("default");

        const sound = override || theme.events[eventKey];
        if (!sound)
            return;

        player.source = override || theme.basePath + sound;
        player.play();
    }

    SoundEffect {
        id: player
        volume: root.effectiveVolume
    }

    Connections {
        target: SoundThemes
        function onAvailabilityCheckedChanged() {
            if (SoundThemes.availabilityChecked && root.pendingEventKey) {
                const key = root.pendingEventKey;
                root.pendingEventKey = "";
                root.play(key);
            }
        }
    }

    Connections {
        target: Notifications
        function onNotify(notif) {
            const eventKey = notif?.urgency === "critical" ? "critical"
                : notif?.urgency === "low" ? "low" : "notification";
            root.play(eventKey);
        }
    }
}
