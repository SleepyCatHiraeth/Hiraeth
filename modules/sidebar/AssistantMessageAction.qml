import QtQuick
import QtQuick.Controls
import qs.modules.theme
import qs.config
import qs.modules.components

// One 24x24 action beside a message: edit, copy, retry.
//
// Three hand-rolled copies of the same Button, each with its own
// `property bool isHovered: hovered` and a colour ternary whose two branches
// were identical. None carried an accessible name, and the row they live in was
// shown on hover only — so without a pointer these were unreachable.
Button {
    id: root

    required property string glyph
    required property string label

    width: 24
    height: 24
    flat: true
    padding: 0
    activeFocusOnTab: true

    Accessible.name: root.label
    ToolTip.visible: hovered
    ToolTip.text: root.label

    contentItem: Text {
        text: root.glyph
        font.family: Icons.font
        color: root.down ? Colors.overPrimary : (root.enabled ? Colors.overSurface : Colors.outline)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: StyledRect {
        variant: root.down ? "primary" : (root.hovered || root.activeFocus ? "focus" : "common")
        radius: Styling.radius(4)
    }
}
