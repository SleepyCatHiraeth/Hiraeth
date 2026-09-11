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
    // Events deferred until the Portal theme's availability check resolves.
    //
    // This was a single slot, so a later event overwrote an earlier one: a
    // `turretThinking` arriving before discovery finished would discard the
    // queued `turretListening`, which is the cue that says the microphone is
    // open. A list keeps them in order, and it is bounded because these are
    // startup events, not a stream.
    property var pendingEventKeys: []

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

    // Last play time per event key, for the cooldown below.
    property var lastPlayed: ({})

    // Shortest gap between two plays of the same event. The assistant changes
    // state several times a second during a turn, and without this a cue could
    // retrigger before the previous one had finished, which sounds like a
    // stutter rather than a signal.
    readonly property int repeatCooldownMs: 400

    function play(eventKey) {
        if (!Config.sound.enabled)
            return;

        const now = Date.now();
        if (lastPlayed[eventKey] && now - lastPlayed[eventKey] < repeatCooldownMs)
            return;

        const event = Config.sound.events?.[eventKey];
        if (!event || event.muted)
            return;

        const override = typeof event.sound === "string" && event.sound.startsWith("/") ? event.sound : "";

        // An absolute-path override bypasses theme resolution entirely, so
        // it never needs to wait on SoundThemes' async availability check.
        if (!override && Config.sound.theme === "portal-turret" && !SoundThemes.availabilityChecked) {
            if (!pendingEventKeys.includes(eventKey) && pendingEventKeys.length < 8)
                pendingEventKeys = pendingEventKeys.concat([eventKey]);
            return;
        }

        // Recorded here, not on entry: marking the attempt before the deferred
        // return above meant the retry that fires when theme discovery finishes
        // was inside its own cooldown and was discarded. The cue that lost was
        // whichever fired first at startup -- including the microphone-open
        // cue, which is the one sound this shell has a duty to play.
        lastPlayed[eventKey] = now;

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
            if (!SoundThemes.availabilityChecked || root.pendingEventKeys.length === 0)
                return;
            const keys = root.pendingEventKeys;
            root.pendingEventKeys = [];
            for (const key of keys)
                root.play(key);
        }
    }

    Connections {
        target: Notifications
        function onNotify(notif) {
            // urgency arrives in two different representations. Callers that pass
            // a literal string give "critical"/"low"; callers that pass the enum
            // (Battery.qml sends NotificationUrgency.Critical) and the external
            // notification-server path (Notifications.qml's
            // `notification.urgency.toString()`) both end up as "0"/"1"/"2",
            // because the notif component declares `property string urgency` and
            // QML coerces the quint8 enum to its number. Matching only the words
            // meant every enum-passing caller silently fell through to the
            // generic notification sound. Enum: Low=0, Normal=1, Critical=2.
            const urgency = String(notif?.urgency);
            const eventKey = (urgency === "critical" || urgency === "2") ? "critical"
                : (urgency === "low" || urgency === "0") ? "low" : "notification";
            root.play(eventKey);
        }
    }
}
