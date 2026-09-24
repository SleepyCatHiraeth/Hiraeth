pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.modules.globals
import qs.config

Item {
    id: root

    required property var bar

    property bool vertical: bar.orientation === "vertical"
    property bool isHovered: false
    property bool layerEnabled: true
    
    property real radius: 0
    property real startRadius: radius
    property real endRadius: radius

    // Popup visibility state (tracks intent, not animation)
    property bool popupOpen: layoutPopup.isOpen

    Layout.preferredWidth: 36
    Layout.preferredHeight: 36
    Layout.maximumWidth: 36
    Layout.maximumHeight: 36
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    function getLayoutDisplayName(layout) {
        switch (layout) {
        case "dwindle":
            return "Dwindle";
        case "master":
            return "Master";
        case "scrolling":
            return "Scrolling";
        case "monocle":
            return "Monocle";
        default:
            return layout;
        }
    }

    // Main button
    StyledRect {
        id: buttonBg
        variant: root.popupOpen ? "primary" : "bg"
        anchors.fill: parent
        enableShadow: root.layerEnabled

        topLeftRadius: root.vertical ? root.startRadius : root.startRadius
        topRightRadius: root.vertical ? root.startRadius : root.endRadius
        bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
        bottomRightRadius: root.vertical ? root.endRadius : root.endRadius

        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: root.popupOpen ? 0 : (root.isHovered ? 0.25 : 0)
            radius: parent.radius ?? 0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                }
            }
        }

        LayoutGlyph {
            anchors.centerIn: parent
            width: 18
            height: 18
            layout: GlobalStates.compositorLayout
            color: root.popupOpen ? buttonBg.item : Styling.srItem("overprimary")
            playing: root.isHovered && !root.popupOpen
            scale: root.isHovered && !root.popupOpen ? 1.08 : 1
            Behavior on scale {
                enabled: Motion.enabled
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Easing.OutBack
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: false
            cursorShape: Qt.PointingHandCursor
            onClicked: layoutPopup.toggle()
        }

        StyledToolTip {
            visible: root.isHovered && !root.popupOpen
            tooltipText: I18n.t("bar.tooltip.layout", root.getLayoutDisplayName(GlobalStates.compositorLayout))
        }
    }

    // Layout popup
    BarPopup {
        id: layoutPopup
        anchorItem: buttonBg
        bar: root.bar
        variant: "bg"
        popupPadding: 6

        contentWidth: 176
        contentHeight: layoutHeader.height + 4 + layoutColumn.height + popupPadding * 2

        // Drives the staggered entrance each time the popup opens.
        property real reveal: 0
        onIsOpenChanged: if (isOpen) {
            reveal = 0;
            revealAnim.restart();
        }
        NumberAnimation {
            id: revealAnim
            target: layoutPopup
            property: "reveal"
            to: 1
            duration: Motion.enabled ? Motion.base * 2.4 : 0
        }

        // Header: prompt line with the active layout.
        Item {
            id: layoutHeader
            width: parent.width
            height: 26
            opacity: Math.min(1, layoutPopup.reveal * 4)

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "<font color='" + Colors.primary + "'><b>❯</b></font>  layout"
                textFormat: Text.StyledText
                font.family: Config.theme.monoFont
                font.pixelSize: 11
                color: Colors.outline
            }
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: (parent.width - 12) * Math.min(1, layoutPopup.reveal * 2)
                height: 1
                color: Qt.rgba(Colors.overSurface.r, Colors.overSurface.g, Colors.overSurface.b, 0.1)
            }
        }

        Item {
            id: layoutColumn
            anchors.top: layoutHeader.bottom
            anchors.topMargin: 4
            width: parent.width
            height: GlobalStates.availableLayouts.length * (rowHeight + rowGap) - rowGap

            readonly property int rowHeight: 38
            readonly property int rowGap: 2
            readonly property int currentIndex: GlobalStates.availableLayouts.indexOf(GlobalStates.compositorLayout)

            // Selection pill that glides to the active layout.
            Rectangle {
                visible: layoutColumn.currentIndex >= 0
                width: parent.width
                height: layoutColumn.rowHeight
                y: Math.max(0, layoutColumn.currentIndex) * (layoutColumn.rowHeight + layoutColumn.rowGap)
                radius: Config.roundness > 0 ? Math.min(height / 2, Styling.radius(-4)) : 0
                color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.16)
                opacity: Math.min(1, layoutPopup.reveal * 2)

                Behavior on y {
                    enabled: Motion.enabled
                    NumberAnimation {
                        duration: Motion.normal
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.2
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: parent.height - 16
                    radius: 1.5
                    color: Colors.primary
                }
            }

            Repeater {
                model: GlobalStates.availableLayouts

                delegate: Item {
                    id: layoutRow
                    required property string modelData
                    required property int index

                    readonly property bool isSelected: layoutColumn.currentIndex === index
                    readonly property bool hovered: rowMouse.containsMouse
                    // Rows slide in one after another; their glyph builds in behind them.
                    readonly property real arrive: {
                        const x = Math.max(0, Math.min(1, (layoutPopup.reveal - index * 0.08) / 0.45));
                        return 1 - Math.pow(1 - x, 3);
                    }

                    width: layoutColumn.width
                    height: layoutColumn.rowHeight
                    y: index * (layoutColumn.rowHeight + layoutColumn.rowGap)
                    opacity: arrive
                    transform: Translate {
                        x: (1 - layoutRow.arrive) * (layoutPopup.barAtRight ? 10 : -10)
                    }

                    // Hover pill for unselected rows.
                    Rectangle {
                        anchors.fill: parent
                        radius: Config.roundness > 0 ? Math.min(height / 2, Styling.radius(-4)) : 0
                        color: Qt.rgba(Colors.overSurface.r, Colors.overSurface.g, Colors.overSurface.b, 0.06)
                        opacity: layoutRow.hovered && !layoutRow.isSelected ? 1 : 0
                        Behavior on opacity {
                            enabled: Motion.enabled
                            NumberAnimation {
                                duration: Motion.fast
                            }
                        }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 16 + (layoutRow.hovered ? 3 : 0)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        Behavior on anchors.leftMargin {
                            enabled: Motion.enabled
                            NumberAnimation {
                                duration: Motion.normal
                                easing.type: Easing.OutQuint
                            }
                        }

                        LayoutGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            height: 20
                            layout: layoutRow.modelData
                            color: layoutRow.isSelected || layoutRow.hovered ? Colors.primary : Colors.overSurface
                            playing: layoutRow.hovered
                            reveal: Math.max(0, Math.min(1, (layoutPopup.reveal - 0.15 - layoutRow.index * 0.08) / 0.6))
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.getLayoutDisplayName(layoutRow.modelData).toLowerCase()
                            font.family: Config.theme.monoFont
                            font.pixelSize: 12
                            font.weight: layoutRow.isSelected ? Font.Bold : Font.Normal
                            color: layoutRow.isSelected || layoutRow.hovered ? Colors.primary : Colors.overSurface
                            Behavior on color {
                                enabled: Motion.enabled
                                ColorAnimation {
                                    duration: Motion.fast
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: GlobalStates.setCompositorLayout(layoutRow.modelData)
                    }
                }
            }
        }
    }
}
