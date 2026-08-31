import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property var colors
    property string wallpaperPath: wallpaperConfig.adapter.currentWall

    function generate() {
        if (!colors)
            return

        const fmt = c => c.toString()
        const template = "/usr/share/sddm/themes/silent/configs/catppuccin-mocha.conf"
        const output = "/var/tmp/ambxst-sddm.conf"
        const extension = wallpaperPath.split(".").pop().toLowerCase()
        const videos = ["avi", "m4v", "mkv", "mov", "mp4", "webm"]
        const images = ["bmp", "jpeg", "jpg", "png", "tif", "tiff", "webp"]
        const supported = videos.includes(extension) || images.includes(extension) || extension === "gif"
        const outputExtension = extension === "gif" ? "mp4" : extension
        const wallpaperOutput = `/var/tmp/ambxst-sddm-wallpaper.${outputExtension}`
        const sddmWallpaper = `../../../../../../var/tmp/ambxst-sddm-wallpaper.${outputExtension}`

        if (wallpaperPath && supported && wallpaperPath !== lastWallpaper) {
            wallpaperWriter.command = extension === "gif"
                ? ["ffmpeg", "-y", "-i", wallpaperPath, "-movflags", "+faststart", "-pix_fmt", "yuv420p", wallpaperOutput]
                : ["cp", "--", wallpaperPath, wallpaperOutput]
            wallpaperWriter.running = true
            lastWallpaper = wallpaperPath
        }

        const command = `sed \
            -e 's/#1e1e2e/${fmt(colors.background)}/g' \
            -e 's/#313244/${fmt(colors.surfaceContainer)}/g' \
            -e 's/#45475a/${fmt(colors.surfaceContainerHigh)}/g' \
            -e 's/#74c7ec/${fmt(colors.primary)}/g' \
            -e 's/#89dceb/${fmt(colors.primary)}/g' \
            -e 's/#cdd6f4/${fmt(colors.overSurface)}/g' \
            -e 's/#f38ba8/${fmt(colors.error)}/g' \
            -e 's/#f9e2af/${fmt(colors.yellow)}/g' \
            ${supported ? `-e 's/use-background-color = true/use-background-color = false/g'` : ""} \
            ${supported ? `-e 's|background = ""|background = "${sddmWallpaper}"|g'` : ""} \
            '${template}' > '${output}'`

        writer.command = ["sh", "-c", command]
        writer.running = true
    }

    property string lastWallpaper: ""

    property FileView wallpaperConfig: FileView {
        path: Quickshell.env("HOME") + "/.cache/ambxst/wallpapers.json"
        preload: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.generate()

        adapter: JsonAdapter {
            property string currentWall: ""
            onCurrentWallChanged: root.generate()
        }
    }

    property Process wallpaperWriter: Process {
        running: false
        stderr: StdioCollector {
            onStreamFinished: err => {
                if (err)
                    console.error("SddmGenerator Wallpaper Error:", err)
            }
        }
    }

    property Process writer: Process {
        running: false
        stderr: StdioCollector {
            onStreamFinished: err => {
                if (err)
                    console.error("SddmGenerator Error:", err)
            }
        }
    }
}
