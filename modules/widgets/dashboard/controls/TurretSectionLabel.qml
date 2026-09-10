import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.config

// Group heading, matching the weight and colour SoundsPanel uses for its
// section delegates.
Text {
    Layout.fillWidth: true
    Layout.topMargin: 6
    font.family: Config.theme.font
    font.pixelSize: Styling.fontSize(-1)
    font.weight: Font.Medium
    color: Colors.overSurfaceVariant
}
