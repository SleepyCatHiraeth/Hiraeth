import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config

MouseArea {
    id: root

    required property var bar
    required property SystemTrayItem item

    // Overflow wiring — only set for instances living inside the popup
    property bool inOverflow: false
    property var overflowPopupRef: null

    property int trayItemSize: 20
    property bool isHovered: false
    property bool dragging: false
    // True from the moment a press turns into a drag; blocks the
    // click activation until the next press
    property bool dragOccurred: false

    property real pressOffsetX: 0
    property real pressOffsetY: 0

    readonly property int dragThreshold: Qt.styleHints?.startDragDistance ?? 10

    readonly property string iconSource: root.item.icon

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    Layout.fillHeight: bar.orientation === "horizontal"
    Layout.fillWidth: bar.orientation === "vertical"
    implicitWidth: trayItemSize
    implicitHeight: trayItemSize

    // Native Wayland drag: the compositor carries the icon above every
    // surface and delivers the drop to whichever window sits under the
    // pointer, so bar ↔ popup transfers need no coordinate work
    Drag.dragType: Drag.Automatic
    Drag.mimeData: {
        "text/x-ambxst-tray-item": root.item?.id ?? ""
    }
    Drag.supportedActions: Qt.MoveAction
    Drag.hotSpot.x: trayItemSize / 2
    Drag.hotSpot.y: trayItemSize / 2

    onPressed: mouse => {
        dragOccurred = false;
        pressOffsetX = mouse.x;
        pressOffsetY = mouse.y;
    }

    onPositionChanged: mouse => updateDrag(mouse)

    Drag.onDragFinished: stopDrag()

    onClicked: event => {
        if (dragOccurred) {
            event.accepted = true;
            return;
        }
        switch (event.button) {
        case Qt.LeftButton:
            item.activate();
            break;
        case Qt.RightButton:
            if (item.hasMenu) {
                systrayPopup.toggle();
            }
            break;
        }
        event.accepted = true;
    }

    function updateDrag(mouse) {
        if (dragging || !(mouse.buttons & Qt.LeftButton))
            return;

        const dx = mouse.x - pressOffsetX;
        const dy = mouse.y - pressOffsetY;
        if (Math.abs(dx) < dragThreshold && Math.abs(dy) < dragThreshold)
            return;

        dragOccurred = true;

        // Render the drag image before activating: the compositor icon
        // must exist once the native drag takes over the pointer
        root.grabToImage(result => {
            if (!dragOccurred || !root.pressed)
                return;
            dragging = true;
            root.Drag.imageSource = result.url;
            root.Drag.active = true;
        });
    }

    function stopDrag() {
        dragging = false;
        root.Drag.active = false;
    }

    BarPopup {
        id: systrayPopup
        anchorItem: root
        bar: root.bar
        variant: "bg"

        // Nested inside the overflow popup it must not close it
        groupId: root.inOverflow ? "systrayMenu" : "bar"

        contentWidth: 236
        // Height follows the content (including an opening submenu, which
        // grows smoothly), capped so long menus scroll.
        contentHeight: Math.min(menuHeader.height + itemsColumn.implicitHeight + 2 * popupPadding + 6, 420)

        popupPadding: 6
        // 8px standard margin + 8px SysTray container padding to ensure correct offset from the main bar
        visualMargin: 16

        // Drives the staggered row entrance each time the menu opens.
        property real reveal: 0
        onIsOpenChanged: {
            if (isOpen) {
                reveal = 0;
                revealAnim.restart();
            }
            if (!root.inOverflow || !root.overflowPopupRef)
                return;
            root.overflowPopupRef.activeChildMenu = isOpen ? systrayPopup : null;
        }
        NumberAnimation {
            id: revealAnim
            target: systrayPopup
            property: "reveal"
            to: 1
            duration: Motion.enabled ? Motion.base * 2 : 0
        }

        // Using QsMenuOpener to access menu items
        QsMenuOpener {
            id: menuOpener
            menu: root.item.menu
        }

        // Header: the app's name as a prompt line.
        Item {
            id: menuHeader
            width: parent.width
            height: 30
            opacity: Math.min(1, systrayPopup.reveal * 4)

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "❯"
                    font.family: Config.theme.monoFont
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    color: Colors.primary
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: menuHeader.width - 40
                    text: (root.item.tooltipTitle || root.item.title || root.item.id || "").toLowerCase()
                    font.family: Config.theme.monoFont
                    font.pixelSize: 11
                    color: Colors.outline
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: (parent.width - 16) * Math.min(1, systrayPopup.reveal * 2)
                height: 1
                color: Qt.rgba(Colors.overSurface.r, Colors.overSurface.g, Colors.overSurface.b, 0.1)
            }
        }

        ScrollView {
            anchors.fill: parent
            anchors.topMargin: menuHeader.height + 4
            contentWidth: availableWidth
            clip: true

            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                id: itemsColumn
                width: parent.width
                spacing: 1

                Repeater {
                    model: menuOpener.children ? menuOpener.children.values : []

                    delegate: ColumnLayout {
                        id: entry
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        spacing: 1

                        property bool submenuExpanded: false

                        // Rows arrive one after another, sliding in from the bar side.
                        readonly property real arrive: {
                            const from = Math.min(index, 12) * 0.045;
                            const x = Math.max(0, Math.min(1, (systrayPopup.reveal - from) / 0.45));
                            return 1 - Math.pow(1 - x, 3);
                        }
                        opacity: arrive
                        transform: Translate {
                            x: (1 - entry.arrive) * (systrayPopup.barAtRight ? 10 : -10)
                        }

                        SystrayMenuItem {
                            Layout.fillWidth: true

                            textStr: entry.modelData.text || ""
                            iconSource: entry.modelData.icon || ""
                            isImageIcon: iconSource.indexOf("/") !== -1 || iconSource.indexOf(".") !== -1
                            isSeparator: entry.modelData.isSeparator || false
                            entryEnabled: entry.modelData.enabled ?? true
                            hasSubmenu: entry.modelData.hasChildren || false
                            expanded: entry.submenuExpanded
                            buttonType: entry.modelData.buttonType || 0
                            checkState: entry.modelData.checkState || 0

                            onClicked: {
                                if (entry.modelData.hasChildren) {
                                    entry.submenuExpanded = !entry.submenuExpanded;
                                } else {
                                    if (entry.modelData.triggered) {
                                        entry.modelData.triggered();
                                    } else if (entry.modelData.activate) {
                                        entry.modelData.activate();
                                    }
                                    systrayPopup.close();
                                }
                            }
                        }

                        // Submenu children — uses its own QsMenuOpener to trigger lazy loading.
                        // The wrapper animates its height so the menu grows instead of jumping.
                        Item {
                            id: submenuWrap
                            Layout.fillWidth: true
                            Layout.preferredHeight: entry.submenuExpanded ? subColumn.implicitHeight : 0
                            visible: Layout.preferredHeight > 0
                            clip: true
                            opacity: entry.submenuExpanded ? 1 : 0

                            Behavior on Layout.preferredHeight {
                                enabled: Motion.enabled
                                NumberAnimation {
                                    duration: Motion.normal
                                    easing.type: Easing.OutQuint
                                }
                            }
                            Behavior on opacity {
                                enabled: Motion.enabled
                                NumberAnimation {
                                    duration: Motion.fast
                                }
                            }

                            QsMenuOpener {
                                id: subMenuOpener
                                menu: entry.modelData.hasChildren ? entry.modelData : null
                            }

                            // Guide line tying the children to their parent row.
                            Rectangle {
                                x: 11
                                y: 4
                                width: 1
                                height: parent.height - 8
                                color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.3)
                            }

                            ColumnLayout {
                                id: subColumn
                                width: parent.width
                                spacing: 1

                                Repeater {
                                    model: subMenuOpener.children ? subMenuOpener.children.values : []

                                    delegate: SystrayMenuItem {
                                        required property var modelData

                                        Layout.fillWidth: true
                                        depth: 1

                                        textStr: modelData.text || ""
                                        iconSource: modelData.icon || ""
                                        isImageIcon: iconSource.indexOf("/") !== -1 || iconSource.indexOf(".") !== -1
                                        isSeparator: modelData.isSeparator || false
                                        entryEnabled: modelData.enabled ?? true
                                        buttonType: modelData.buttonType || 0
                                        checkState: modelData.checkState || 0

                                        onClicked: {
                                            if (modelData.triggered) {
                                                modelData.triggered();
                                            } else if (modelData.activate) {
                                                modelData.activate();
                                            }
                                            systrayPopup.close();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }


    IconImage {
        id: trayIcon
        source: root.iconSource
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        smooth: true
        opacity: root.dragging ? 0.3 : 1

        Behavior on opacity {
            enabled: Motion.enabled
            NumberAnimation {
                duration: Motion.fast
            }
        }
    }

    Tinted {
        sourceItem: trayIcon
        anchors.fill: trayIcon
    }

    StyledToolTip {
        show: root.isHovered && !root.dragging
        tooltipText: root.item.tooltipTitle || root.item.title
        desciription: root.item.tooltipDescription || ""
    }

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    Component.onDestruction: {
        if (systrayPopup.isOpen)
            systrayPopup.close();
    }
}
