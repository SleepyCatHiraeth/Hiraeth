pragma Singleton

import QtQuick
import QtMultimedia
import Quickshell
import qs.config
import qs.modules.services

Singleton {
    id: root

    readonly property real effectiveVolume: Math.max(0, Math.min(1, Config.sound.volume))
    // Audio.ready (Quickshell.Services.Pipewire's defaultAudioSink readiness)
    // is required, not just config readiness: on a genuine cold login,
    // PipeWire/WirePlumber can still be registering audio endpoints
    // (Bluetooth ones especially) for several seconds after Quickshell
    // starts. Constructing/playing a SoundEffect during that window was
    // observed to stall the whole QML main thread for ~4s on a real cold
    // login — config readiness alone has nothing to do with audio hardware
    // being ready and was the wrong signal to gate on.
    readonly property bool shellReady: Config.initialLoadComplete && Config.soundReady && Audio.ready
    property bool bootUpPlayed: false
    // Set when play() is called for the Portal Turret theme before its async
    // directory-existence check (SoundThemes.availabilityChecked) has
    // resolved — retried once that check completes, instead of silently
    // falling back to the Default theme for whichever event fired first
    // during startup/login.
    property string pendingEventKey: ""

    function playBootUpOnce() {
        // Also requires playerLoader.item, not just shellReady: shellReady
        // and the Loader's own `active` binding both react to the same
        // Audio.ready change with no guaranteed ordering, so item can still
        // be null the instant this first runs. Only mark bootUpPlayed once
        // the item is actually confirmed — otherwise a same-tick miss here
        // would permanently drop the event (playBootUpOnce never retries
        // once bootUpPlayed is true). The Loader's onLoaded calls this again
        // to catch exactly that case.
        if (shellReady && !bootUpPlayed && playerLoader.item) {
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

        // playerLoader.item can be null if something calls play() before
        // Audio.ready — bootUp's own trigger already waits for it (see
        // shellReady), but this guards any other caller that might not.
        // Silently skipping is intentional, not a bug: retrying blind after
        // an arbitrary delay risks re-entering the exact stall this exists
        // to avoid, for a missed boot/notification chime that isn't worth it.
        if (!playerLoader.item)
            return;

        playerLoader.item.source = override || theme.basePath + sound;
        playerLoader.item.play();
    }

    // Constructing a SoundEffect at all (not just calling play() on one) may
    // itself be what triggers QtMultimedia's PipeWire backend negotiation —
    // unconfirmed which of the two actually caused the observed cold-login
    // stall, so both are deferred here rather than gambling on one. active
    // is gated on Audio.ready, not just shellReady, so this also protects
    // any future caller that fires before the bootUp trigger does.
    Loader {
        id: playerLoader
        active: Audio.ready
        sourceComponent: SoundEffect {
            volume: root.effectiveVolume
        }
        onLoaded: root.playBootUpOnce()
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
