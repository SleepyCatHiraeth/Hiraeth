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

    function playBootUpOnce() {
        if (shellReady && !bootUpPlayed) {
            bootUpPlayed = true;
            // Deferred: on the very first play() call ever, playerLoader.item
            // may not exist yet (async Loader creation) — every later call is
            // fine since active is already true by then. See SoundService.qml
            // incident notes in the wiki for the TypeError this guards.
            Qt.callLater(() => play("bootUp"));
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

        let theme = SoundThemes.resolveTheme(Config.sound.theme);
        if (!theme.available)
            theme = SoundThemes.resolveTheme("default");

        const override = typeof event.sound === "string" && event.sound.startsWith("/") ? event.sound : "";
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
        target: Notifications
        function onNotify(notif) {
            const eventKey = notif?.urgency === "critical" ? "critical"
                : notif?.urgency === "low" ? "low" : "notification";
            root.play(eventKey);
        }
    }
}
