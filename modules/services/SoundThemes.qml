pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string portalBasePath: Quickshell.env("HOME") + "/.config/ambxst/sounds/portal-turret/"
    property bool portalAvailable: false
    readonly property var defaultTheme: ({
        "id": "default",
        "name": "Default",
        "description": "AMBXST default cues",
        "available": true,
        "basePath": Quickshell.shellDir + "/assets/sound/",
        "events": {
            "notification": "polite-warning-tone.wav",
            "critical": "polite-warning-tone.wav",
            "low": "polite-warning-tone.wav"
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
            "low": "low.wav"
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
            onStreamFinished: root.portalAvailable = text.trim() === "yes"
        }
    }

    Component.onCompleted: availabilityProcess.running = true
}
