import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    function generate(colors) {
        if (!colors)
            return

        const hex = color => color.toString().replace("#", "")
        writerProcess.command = ["sh", "-c", `
            [ "$(spicetify config current_theme)" = text-Retro ] &&
            [ "$(spicetify config color_scheme)" = Retro ] &&
            spicetify color \
                accent ${hex(colors.primary)} \
                accent-active ${hex(colors.primaryFixedDim)} \
                accent-inactive ${hex(colors.surfaceContainer)} \
                banner ${hex(colors.primary)} \
                border-active ${hex(colors.primary)} \
                border-inactive ${hex(colors.outlineVariant)} \
                header ${hex(colors.surfaceBright)} \
                highlight ${hex(colors.surfaceContainerHigh)} \
                main ${hex(colors.background)} \
                notification ${hex(colors.blue)} \
                notification-error ${hex(colors.error)} \
                subtext ${hex(colors.overSurfaceVariant)} \
                text ${hex(colors.overBackground)} &&
            spicetify refresh
        `]
        writerProcess.running = true
    }

    property Process writerProcess: Process {
        running: false
        stdout: StdioCollector {
            onStreamFinished: console.log("SpotifyGenerator: Theme generated.")
        }
        stderr: StdioCollector {
            onStreamFinished: error => {
                if (error)
                    console.error("SpotifyGenerator Error:", error)
            }
        }
    }
}
