pragma Singleton

import QtQuick
import QtMultimedia
import Quickshell
import qs.config
import qs.modules.services

Singleton {
    id: root

    readonly property real effectiveVolume: Math.max(0, Math.min(1, Config.sound.volume))

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
