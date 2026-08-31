import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    function generate(colors) {
        if (!colors) return

        const argb = color => {
            const value = color.toString()
            return value.length === 7 ? "#ff" + value.slice(1) : value
        }
        const palette = [
            colors.overBackground, colors.surface, colors.surfaceBright,
            colors.surfaceContainerHigh, colors.surfaceContainerLowest,
            colors.surfaceVariant, colors.overBackground, colors.white,
            colors.overBackground, colors.background, colors.background,
            colors.shadow, colors.primary, colors.overPrimary, colors.tertiary,
            colors.tertiary, colors.surface, colors.background,
            colors.surfaceContainerHigh, colors.overBackground, colors.outline
        ].map(argb)
        const disabled = palette.slice()
        for (const role of [0, 6, 8, 13, 19, 20])
            disabled[role] = argb(colors.outline)

        const ini = "[ColorScheme]\n" +
            `active_colors=${palette.join(", ")}\n` +
            `disabled_colors=${disabled.join(", ")}\n` +
            `inactive_colors=${palette.join(", ")}\n`
        const home = Quickshell.env("HOME")
        const qt5Dir = home + "/.config/qt5ct/colors"
        const qt6Dir = home + "/.config/qt6ct/colors"

        writerProcess.command = ["sh", "-c", `
            mkdir -p "${qt5Dir}" "${qt6Dir}" && \
            echo "${ini}" | tee "${qt5Dir}/ambxst.conf" "${qt6Dir}/ambxst.conf" > /dev/null
        `]
        writerProcess.running = true
    }

    property Process writerProcess: Process {
        running: false
        stdout: StdioCollector {
            onStreamFinished: console.log("QtCtGenerator: Colors generated.")
        }
        stderr: StdioCollector {
            onStreamFinished: error => {
                if (error) console.error("QtCtGenerator Error:", error)
            }
        }
    }
}
