import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

QtObject {
    id: root

    function apply(theme) {
        if (theme !== "Numix-Cursor" && theme !== "Numix-Cursor-Light")
            return

        applyProcess.running = false
        applyProcess.command = ["sh", "-c", `
            set -eu
            theme="$1"
            size="$(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null || printf 24)"
            mkdir -p "$HOME/.icons/default" "$HOME/.config/environment.d"
            printf '[Icon Theme]\nName=Default\nInherits=%s\n' "$theme" > "$HOME/.icons/default/index.theme"
            printf 'XCURSOR_THEME=%s\nXCURSOR_SIZE=%s\n' "$theme" "$size" > "$HOME/.config/environment.d/90-ambxst-cursor.conf"
            gsettings set org.gnome.desktop.interface cursor-theme "$theme"
            hyprctl setcursor "$theme" "$size"
            export XCURSOR_THEME="$theme" XCURSOR_SIZE="$size"
            dbus-update-activation-environment --systemd XCURSOR_THEME XCURSOR_SIZE 2>/dev/null || true
            systemctl --user import-environment XCURSOR_THEME XCURSOR_SIZE 2>/dev/null || true
        `, "ambxst-cursor", theme]
        applyProcess.running = true
    }

    Component.onCompleted: apply(Config.theme.cursorTheme)

    property Connections configWatcher: Connections {
        target: Config.theme
        function onCursorThemeChanged() {
            root.apply(Config.theme.cursorTheme)
        }
    }

    property Process applyProcess: Process {
        stderr: StdioCollector {
            onStreamFinished: error => {
                if (error)
                    console.error("CursorGenerator Error:", error)
            }
        }
    }
}
