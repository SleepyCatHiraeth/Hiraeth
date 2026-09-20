import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import qs.config
import qs.modules.components

// One flat icon button, as the assistant panel's header and composer use it.
//
// This shape was written out six times: a 32x32 flat Button, a Text in the
// icon font, a StyledRect background that fades in on hover, and its own
// Behavior. Six copies is also six places to forget an Accessible name, which
// is how four of them ended up with hardcoded English ones.
//
// Kept here rather than in modules/components because it is this panel's
// button, not a shell-wide one: ToggleButton is the shared icon button and is
// shaped for the bar (36px, shadowed, "bg" variant), and bending it to fit
// here would have made it worse at its own job.
Button {
    id: root

    required property string glyph
    // Named for assistive technology and shown on hover. One string, because a
    // button whose tooltip and accessible name disagree is a bug waiting to be
    // filed.
    required property string label

    // Draws the icon in the accent colour: for a button whose state is on.
    property bool active: false
    property int iconSize: 16
    property color iconColor: root.active ? Styling.srItem("overprimary") : Colors.overSurface

    Layout.preferredWidth: 32
    Layout.preferredHeight: 32
    flat: true
    padding: 0

    Accessible.name: root.label
    ToolTip.visible: hovered && root.label !== ""
    ToolTip.text: root.label

    contentItem: Text {
        text: root.glyph
        font.family: Icons.font
        font.pixelSize: root.iconSize
        color: root.enabled ? root.iconColor : Colors.outline
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: StyledRect {
        variant: root.hovered ? "focus" : "common"
        radius: Styling.radius(4)
        opacity: root.hovered ? 1 : 0

        Behavior on opacity {
            enabled: Motion.enabled
            NumberAnimation {
                duration: Motion.micro
            }
        }
    }
}
