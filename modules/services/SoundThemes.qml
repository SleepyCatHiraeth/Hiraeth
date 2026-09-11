pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string portalBasePath: Quickshell.env("HOME") + "/.config/ambxst/sounds/portal-turret/"
    property bool portalAvailable: false
    // False until the async directory-existence check below has completed at
    // least once. play() (SoundService.qml) must not treat "not yet checked"
    // as "confirmed unavailable" — that race silently played the Default
    // theme's sound instead of Portal Turret's on early startup/login events.
    property bool availabilityChecked: false
    readonly property var defaultTheme: ({
        "id": "default",
        "name": "Default",
        "description": "AMBXST default cues",
        "available": true,
        "basePath": Quickshell.shellDir + "/assets/sound/",
        "events": {
            "notification": "polite-warning-tone.wav",
            "critical": "polite-warning-tone.wav",
            "low": "polite-warning-tone.wav",
            "loginSuccess": "polite-warning-tone.wav",
            "wrongPassword": "polite-warning-tone.wav",
            "bootUp": "polite-warning-tone.wav",
            "deviceConnect": "polite-warning-tone.wav",
            "deviceDisconnect": "polite-warning-tone.wav",
            "batteryLow": "polite-warning-tone.wav",
            "shutdown": "polite-warning-tone.wav",
            // The turret assistant's cues. The default theme has one tone, so
            // these are deliberately sparse: only the microphone opening and a
            // failure are worth a sound when every sound is the same sound.
            "turretListening": "polite-warning-tone.wav",
            "turretThinking": "",
            "turretDone": "",
            "turretError": "polite-warning-tone.wav",
            "turretReview": "polite-warning-tone.wav"
        }
    })
    readonly property var portalTurretTheme: ({
        "id": "portal-turret",
        "name": "Portal Turret",
        "description": "Portal turret-inspired cues. Provide your own extracted audio files (from a copy of Portal you own) in the folder below — none are bundled with AMBXST for licensing reasons.",
        "available": root.portalAvailable,
        "basePath": root.portalBasePath,
        "events": {
            "notification": "notification.wav",
            "critical": "critical.wav",
            "low": "low.wav",
            "loginSuccess": "loginSuccess.wav",
            "wrongPassword": "wrongPassword.wav",
            "bootUp": "bootUp.wav",
            "deviceConnect": "deviceConnect.wav",
            "deviceDisconnect": "deviceDisconnect.wav",
            "batteryLow": "batteryLow.wav",
            "shutdown": "shutdown.wav",
            "turretListening": "turretListening.wav",
            "turretThinking": "turretThinking.wav",
            "turretDone": "turretDone.wav",
            "turretError": "turretError.wav",
            "turretReview": "turretReview.wav"
        }
    })

    function resolveTheme(themeId) {
        return themeId === "portal-turret" ? portalTurretTheme : defaultTheme;
    }

    FileView {
        id: portalDirectory
        path: root.portalBasePath
        watchChanges: true
        printErrors: false
        onFileChanged: availabilityProcess.running = true
    }

    Process {
        id: availabilityProcess
        running: false
        command: ["sh", "-c", "test -d \"$1\" && echo yes || echo no", "sh", root.portalBasePath]
        stdout: StdioCollector {
            onStreamFinished: {
                root.portalAvailable = text.trim() === "yes";
                root.availabilityChecked = true;
            }
        }
    }

    Component.onCompleted: availabilityProcess.running = true
}
