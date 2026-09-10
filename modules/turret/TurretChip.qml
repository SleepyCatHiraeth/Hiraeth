pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.components
import qs.modules.theme
import qs.config

// A small action button for the review card.
//
// Replaces bare coloured text, which gave no hit target and no press feedback:
// the user could not tell the words were clickable, and there was nothing to
// aim at. This is a real surface with hover and press states, built on the
// StyledRect the rest of the shell uses so it inherits the theme.
Item {
    id: root

    property string text: ""
    property string glyph: ""
    property color accent: Colors.overSurface

    signal activated

    implicitWidth: body.implicitWidth
    implicitHeight: 22
    Layout.preferredHeight: 22

    // StyledRect's border and radius come from its variant and are readonly, so
    // hover is expressed by swapping variant, and the accent outline lives on a
    // sibling rectangle rather than being forced onto it.
    StyledRect {
        id: body
        anchors.fill: parent
        variant: hover.hovered ? "focus" : "common"
        implicitWidth: row.implicitWidth + 18

        // Press gives a physical nudge; without it a click on a small target
        // feels like it may not have registered.
        scale: tap.pressed ? 0.94 : 1.0

        Behavior on scale {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Math.round(Config.animDuration * 0.4)
                easing.type: Easing.OutQuart
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "transparent"
            border.width: 1
            border.color: hover.hovered ? root.accent : "transparent"

            Behavior on border.color {
                enabled: Config.animDuration > 0
                ColorAnimation { duration: Math.round(Config.animDuration * 0.5) }
            }
        }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 4

            Text {
                visible: root.glyph !== ""
                text: root.glyph
                font.family: Icons.font
                font.pixelSize: 10
                color: hover.hovered ? root.accent : Colors.overSurfaceVariant
            }

            Text {
                text: root.text
                font.family: Config.theme.font
                font.pixelSize: 11
                color: hover.hovered ? root.accent : Colors.overSurface

                Behavior on color {
                    enabled: Config.animDuration > 0
                    ColorAnimation { duration: Math.round(Config.animDuration * 0.5) }
                }
            }
        }

        HoverHandler {
            id: hover
        }

        TapHandler {
            id: tap
            onTapped: root.activated()
        }
    }
}
