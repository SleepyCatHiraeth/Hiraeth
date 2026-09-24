import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Services.SystemTray
import qs.modules.services
import qs.modules.theme
import qs.modules.components
import qs.config

StyledRect {
    variant: "bg"
    id: root

    required property var bar

    property real radius: 0
    property real startRadius: radius
    property real endRadius: radius

    // Orientación derivada de la barra
    property bool vertical: bar.orientation === "vertical"

    readonly property var allItems: SystemTray.items?.values ?? []
    readonly property var hiddenIds: StateService.systrayHidden
    readonly property var visibleItems: allItems.filter(item => !hiddenIds.includes(item.id))
    readonly property var overflowItems: allItems.filter(item => hiddenIds.includes(item.id))

    // The tray collapses to a chevron-only pill while every icon is in the popup
    readonly property bool hasItems: allItems.length > 0

    // Menu popup currently opened from an icon inside the overflow popup
    property var activeChildMenu: null

    // When the nested menu closes it drops the shared focus grab, so
    // the overflow popup must take it back
    onActiveChildMenuChanged: {
        if (activeChildMenu === null && overflowPopup.isOpen)
            overflowPopup.refreshFocusGrab();
    }

    // Hide when no tray items
    visible: hasItems

    topLeftRadius: root.vertical ? root.startRadius : root.startRadius
    topRightRadius: root.vertical ? root.startRadius : root.endRadius
    bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
    bottomRightRadius: root.vertical ? root.endRadius : root.endRadius

    // Ajustes de tamaño dinámicos según orientación
    height: vertical ? implicitHeight : parent.height
    Layout.preferredWidth: hasItems ? ((vertical ? columnLayout.implicitWidth : rowLayout.implicitWidth) + 16) : 0
    implicitWidth: hasItems ? ((vertical ? columnLayout.implicitWidth : rowLayout.implicitWidth) + 16) : 0
    implicitHeight: hasItems ? ((vertical ? columnLayout.implicitHeight : rowLayout.implicitHeight) + 16) : 0

    // Model mutations are deferred: committing mid-drop would destroy
    // delegates while their drop/click handlers are still on the stack
    function hideItem(id) {
        Qt.callLater(() => {
            const current = StateService.systrayHidden ?? [];
            if (current.includes(id))
                return;
            StateService.systrayHidden = [...current, id];
        });
    }

    function showItem(id) {
        Qt.callLater(() => {
            StateService.systrayHidden = (StateService.systrayHidden ?? []).filter(entry => entry !== id);
        });
    }

    function toggleOverflow() {
        overflowPopup.toggle();
    }

    // Drop zone for showing overflow icons: dropping a hidden item
    // anywhere over the tray pill puts it back in the bar
    DropArea {
        anchors.fill: parent
        keys: ["text/x-ambxst-tray-item"]

        onDropped: drop => {
            const id = drop.getDataAsString("text/x-ambxst-tray-item");
            if (id && root.hiddenIds.includes(id))
                root.showItem(id);
        }
    }

    RowLayout {
        id: rowLayout
        visible: !root.vertical
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        Repeater {
            id: rowRepeater
            model: root.visibleItems

            SysTrayItem {
                required property SystemTrayItem modelData
                bar: root.bar
                item: modelData
                overflowPopupRef: overflowPopup
            }
        }

        ChevronButton {
            id: chevronRow
            tray: root
        }
    }

    ColumnLayout {
        id: columnLayout
        visible: root.vertical
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        Repeater {
            id: columnRepeater
            model: root.visibleItems

            SysTrayItem {
                required property SystemTrayItem modelData
                bar: root.bar
                item: modelData
                overflowPopupRef: overflowPopup
            }
        }

        ChevronButton {
            id: chevronColumn
            tray: root
        }
    }

    component ChevronButton: AbstractButton {
        id: chevron

        required property var tray

        property bool hot: dropArea.containsDrag

        Layout.preferredWidth: 20
        Layout.preferredHeight: 20
        Layout.fillHeight: !chevron.tray.vertical
        Layout.fillWidth: chevron.tray.vertical

        hoverEnabled: true
        activeFocusOnTab: true
        Accessible.name: I18n.t("bar.systray.overflow")
        onClicked: chevron.tray.toggleOverflow()

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }

        // Minimal drawer handle: a mono "+N" count of stored icons (or a
        // chevron when none are stored) on a tint that lights on hover,
        // while open, and while an icon is dragged over it.
        readonly property int stored: chevron.tray.overflowItems.length
        readonly property bool open: overflowPopup.isOpen
        readonly property real glow: chevron.hot ? 1 : chevron.open ? 0.75 : chevron.hovered ? 0.5 : 0

        Rectangle {
            anchors.centerIn: parent
            width: chevron.tray.vertical ? parent.width : Math.max(parent.height, handleText.implicitWidth + 10)
            height: chevron.tray.vertical ? Math.max(20, handleText.implicitHeight + 6) : parent.height
            radius: Config.roundness > 0 ? Math.min(height, width) / 2 : 0
            color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.2 * chevron.glow)
            border.width: chevron.visualFocus || chevron.hot ? 1 : 0
            border.color: Colors.primary

            Behavior on color {
                enabled: Motion.enabled
                ColorAnimation {
                    duration: Motion.fast
                }
            }
        }

        Text {
            id: handleText
            anchors.centerIn: parent
            text: chevron.stored > 0 && !chevron.open ? "+" + chevron.stored : "\u203A"
            font.family: Config.theme.monoFont
            font.pixelSize: chevron.stored > 0 && !chevron.open ? 11 : 16
            font.weight: Font.Bold
            color: chevron.glow > 0 ? Colors.primary : Colors.outline
            // The chevron points where the drawer opens and turns back while open.
            rotation: {
                if (chevron.stored > 0 && !chevron.open)
                    return 0;
                const base = chevron.tray.bar.barPosition === "right" ? 180 : chevron.tray.bar.barPosition === "top" ? 90 : chevron.tray.bar.barPosition === "bottom" ? -90 : 0;
                return chevron.open ? base + 180 : base;
            }
            scale: chevron.pressed ? 0.85 : 1

            Behavior on rotation {
                enabled: Motion.enabled
                RotationAnimation {
                    duration: Motion.normal
                    easing.type: Easing.OutBack
                }
            }
            Behavior on scale {
                enabled: Motion.enabled
                NumberAnimation {
                    duration: Motion.micro
                }
            }
            Behavior on color {
                enabled: Motion.enabled
                ColorAnimation {
                    duration: Motion.fast
                }
            }
        }

        DropArea {
            id: dropArea
            anchors.fill: parent
            keys: ["text/x-ambxst-tray-item"]

            onDropped: drop => {
                const id = drop.getDataAsString("text/x-ambxst-tray-item");
                if (!id)
                    return;
                if (chevron.tray.hiddenIds.includes(id))
                    chevron.tray.showItem(id);
                else
                    chevron.tray.hideItem(id);
            }
        }
    }

    BarPopup {
        id: overflowPopup
        property alias activeChildMenu: root.activeChildMenu
        anchorItem: root.vertical ? chevronColumn : chevronRow
        bar: root.bar
        visualMargin: 16
        clickThroughMargins: true

        variant: "bg"
        popupPadding: 8

        readonly property int tile: 34
        readonly property int gap: 4
        readonly property int columns: Math.max(1, Math.min(root.overflowItems.length, 5))
        readonly property int rows: Math.max(1, Math.ceil(root.overflowItems.length / columns))
        readonly property int gridWidth: columns * tile + (columns - 1) * gap
        readonly property int gridHeight: rows * tile + (rows - 1) * gap

        contentWidth: Math.max(root.overflowItems.length > 0 ? gridWidth : hintLabel.implicitWidth + 16, 150) + popupPadding * 2
        contentHeight: drawerHeader.height + 6 + (root.overflowItems.length > 0 ? gridHeight : hintLabel.implicitHeight + 12) + popupPadding * 2

        // Drives the staggered tile entrance each time the drawer opens.
        property real reveal: 0
        NumberAnimation {
            id: drawerReveal
            target: overflowPopup
            property: "reveal"
            to: 1
            duration: Motion.enabled ? Motion.base * 2 : 0
        }

        // A nested tray menu must not clear this popup's focus grab
        extraGrabWindows: root.activeChildMenu ? [root.activeChildMenu] : []

        onIsOpenChanged: {
            if (isOpen) {
                reveal = 0;
                drawerReveal.restart();
                return;
            }
            const child = root.activeChildMenu;
            root.activeChildMenu = null;
            if (child)
                child.close();
        }

        // Header: prompt line with the stored count.
        Item {
            id: drawerHeader
            width: parent.width
            height: 26
            opacity: Math.min(1, overflowPopup.reveal * 4)

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: "<font color='" + Colors.primary + "'><b>❯</b></font>  tray"
                textFormat: Text.StyledText
                font.family: Config.theme.monoFont
                font.pixelSize: 11
                color: Colors.outline
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: root.overflowItems.length
                font.family: Config.theme.monoFont
                font.pixelSize: 11
                color: Colors.outline
            }
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: (parent.width - 8) * Math.min(1, overflowPopup.reveal * 2)
                height: 1
                color: Qt.rgba(Colors.overSurface.r, Colors.overSurface.g, Colors.overSurface.b, 0.1)
            }
        }

        Grid {
            id: iconsGrid
            anchors.top: drawerHeader.bottom
            anchors.topMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.overflowItems.length > 0
            columns: overflowPopup.columns
            spacing: overflowPopup.gap

            Repeater {
                model: root.overflowItems

                // Tile: a hover pill behind the icon; tiles pop in one after another.
                Item {
                    id: tile
                    required property SystemTrayItem modelData
                    required property int index

                    width: overflowPopup.tile
                    height: overflowPopup.tile

                    readonly property real arrive: {
                        const x = Math.max(0, Math.min(1, (overflowPopup.reveal - Math.min(index, 10) * 0.05) / 0.4));
                        return x;
                    }
                    opacity: Math.min(1, arrive * 1.5)
                    scale: 0.6 + 0.4 * (arrive >= 1 ? 1 : 1 + 2.70158 * Math.pow(arrive - 1, 3) + 1.70158 * Math.pow(arrive - 1, 2))

                    Rectangle {
                        anchors.fill: parent
                        radius: Styling.radius(-6)
                        color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, trayIconItem.isHovered ? 0.16 : 0.05)
                        Behavior on color {
                            enabled: Motion.enabled
                            ColorAnimation {
                                duration: Motion.fast
                            }
                        }
                    }

                    SysTrayItem {
                        id: trayIconItem
                        anchors.centerIn: parent
                        bar: root.bar
                        item: tile.modelData
                        inOverflow: true
                        overflowPopupRef: overflowPopup
                        scale: isHovered ? 1.1 : 1
                        Behavior on scale {
                            enabled: Motion.enabled
                            NumberAnimation {
                                duration: Motion.fast
                                easing.type: Easing.OutBack
                            }
                        }
                    }
                }
            }
        }

        Text {
            id: hintLabel
            anchors.top: drawerHeader.bottom
            anchors.topMargin: 12
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.overflowItems.length === 0
            text: I18n.t("bar.systray.overflow_empty")
            font.family: Config.theme.monoFont
            font.pixelSize: 11
            color: Colors.outline
            opacity: Math.min(1, overflowPopup.reveal * 2)
        }

        // Drop zone for hiding bar icons: dropping a visible item
        // over the popup card moves it into the overflow grid
        DropArea {
            id: popupDropArea
            anchors.fill: parent
            keys: ["text/x-ambxst-tray-item"]

            onDropped: drop => {
                const id = drop.getDataAsString("text/x-ambxst-tray-item");
                if (id && !root.hiddenIds.includes(id))
                    root.hideItem(id);
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            radius: Styling.radius(4)
            color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.12)
            border.width: 1
            border.color: Colors.primary
            opacity: popupDropArea.containsDrag ? 1 : 0

            Behavior on opacity {
                enabled: Motion.enabled
                NumberAnimation {
                    duration: Motion.fast
                }
            }
        }
    }
}
