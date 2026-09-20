import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import qs.modules.theme
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.modules.ainotch
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

FocusScope {
    id: root
    anchors.fill: parent

    required property var targetScreen

    readonly property bool active: GlobalStates.assistantVisible && targetScreen.name === GlobalStates.assistantScreenName
    property alias hitbox: sidebarContainer
    property alias hoverHitbox: notchHoverRegion
    readonly property bool hasActiveFocus: root.activeFocus
    property alias resizeHitbox: resizeHandle

    readonly property bool frameEnabled: (Config.bar?.frameEnabled ?? false)

    // Frame-wrapping is an expanded-panel behavior. The resting notch keeps its
    // own silhouette, or it would read as a square tab stuck to the bezel.
    readonly property bool frameWrapped: frameEnabled && GlobalStates.assistantMergedIntoFrame && root.active
    // The resting notch is welded to the bezel, so it takes no outer margin;
    // the expanded panel keeps the 4px gap it has always had.
    readonly property int sidebarMargin: (frameWrapped || showAsNotch) ? 0 : 4
    property bool wantsFocus: false

    // ── Right-edge notch ────────────────────────────────────────────────
    // The notch is the assistant panel's collapsed state, not a separate
    // widget that opens one: same container, same background, same geometry
    // animation, so opening reads as the notch unfolding rather than a panel
    // sliding in over it.
    readonly property bool notchEnabled: Config.ai?.notchEnabled ?? true
    readonly property bool notchKeepHidden: Config.ai?.notchKeepHidden ?? false
    readonly property int notchHoverRegionSize: Math.max(4, Config.ai?.notchHoverRegionSize ?? 16)
    readonly property bool notchHoverToOpen: Config.ai?.notchHoverToOpen ?? false
    readonly property bool notchAutoHideWithWindows: Config.ai?.notchAutoHideWithWindows ?? false

    // Window and fullscreen detection, matching the top notch: prefer the
    // parent panel's own check (it consults both ToplevelManager and
    // CompositorData) and fall back to ToplevelManager alone.
    readonly property var shellPanelRef: Visibilities.barPanels[targetScreen.name]

    // A notch module opening over the panel takes focus for its own view, and
    // closing hands it back. Kept as a local property so its change signal
    // resolves; a Connections on the var-typed panel reference does not.
    readonly property var screenVisibilities: Visibilities.getForScreen(targetScreen.name)
    readonly property bool notchModuleOpen: screenVisibilities ? (screenVisibilities.launcher || screenVisibilities.dashboard || screenVisibilities.powermenu || screenVisibilities.tools) : false

    onNotchModuleOpenChanged: restoreInputFocus()

    readonly property var compositorMonitor: AxctlService.monitorFor(targetScreen)

    readonly property bool hasWindows: {
        if (!compositorMonitor || !compositorMonitor.activeWorkspace || !AxctlService.clients.values)
            return false;
        return AxctlService.clients.values.some(client => client && client.workspace && client.workspace.id === compositorMonitor.activeWorkspace.id);
    }

    readonly property bool activeWindowFullscreen: {
        if (shellPanelRef && typeof shellPanelRef.hasFullscreenWindow !== 'undefined')
            return shellPanelRef.hasFullscreenWindow;
        const toplevel = ToplevelManager.activeToplevel;
        if (!toplevel || !toplevel.activated)
            return false;
        return toplevel.fullscreen === true;
    }

    readonly property bool hiddenByWindows: notchAutoHideWithWindows && (hasWindows || activeWindowFullscreen)

    // How far this item sits from the physical screen edge. The panel insets it
    // for the screen frame and for a bar on the same side, so anything anchored
    // to `parent` stops short of the bezel. The top notch's wake strip starts at
    // the real edge, and a strip you cannot hit by pushing the pointer into the
    // corner of the screen is not much of a wake strip.
    readonly property int edgeInset: {
        if (!root.parent)
            return 0;
        if (GlobalStates.assistantPosition === "left")
            return Math.max(0, root.x);
        return Math.max(0, root.parent.width - (root.x + root.width));
    }

    readonly property bool expanded: root.active
    readonly property bool showAsNotch: notchEnabled && !expanded
    readonly property int collapsedDepth: Config.showBackground ? 44 : 40
    readonly property int collapsedLength: Math.max(1, Math.min(height, Math.max(64, Config.ai?.notchLength ?? 180)))

    property real dragWidth: -1
    readonly property int effectiveWidth: Math.max(1, Math.min(width - sidebarMargin - 8, Math.max(300, Math.min(800, dragWidth >= 0 ? dragWidth : GlobalStates.assistantWidth))))
    readonly property real expansionProgress: notchEnabled
        ? Math.max(0, Math.min(1, (sidebarContainer.width - collapsedDepth) / Math.max(1, effectiveWidth + sidebarMargin - collapsedDepth)))
        : (revealed ? 1 : 0)

    readonly property string notchEdge: GlobalStates.assistantPosition === "left" ? "left" : "right"

    // Same rest/open radii the top notch uses, so both surfaces round by the
    // same amounts as they open.
    property int notchFlareSize: (frameWrapped || !showAsNotch) ? 0 : Styling.radius(4)
    property int notchBodyRadius: frameWrapped ? 0 : (showAsNotch ? Styling.radius(4) : Styling.radius(0))

    Behavior on notchFlareSize {
        enabled: Motion.enabled
        NumberAnimation {
            duration: Motion.normal
            easing.type: Easing.OutQuart
        }
    }

    Behavior on notchBodyRadius {
        enabled: Motion.enabled
        NumberAnimation {
            duration: Motion.normal
            easing.type: root.expanded ? Easing.OutBack : Easing.OutQuart
            easing.overshoot: root.expanded ? 1.2 : 1.0
        }
    }

    // Hover, with the top notch's 1000 ms grace so the notch does not flicker
    // shut while the pointer crosses the gap to it.
    property bool notchHoverActive: false
    property bool hoverOpenBlocked: false
    readonly property bool notchHovered: notchHoverHandler.hovered || notchBodyHover.hovered

    Timer {
        id: notchHideTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (!root.notchHovered)
                root.notchHoverActive = false;
        }
    }

    onNotchHoveredChanged: {
        if (notchHovered) {
            notchHideTimer.stop();
            notchHoverActive = true;
            if (notchHoverToOpen && !root.active && !hoverOpenBlocked)
                hoverOpenTimer.restart();
        } else {
            hoverOpenTimer.stop();
            hoverOpenBlocked = false;
            notchHideTimer.restart();
        }
    }

    Timer {
        id: hoverOpenTimer
        interval: 250
        onTriggered: if (root.notchHoverToOpen && root.notchHovered && !root.active && !root.hoverOpenBlocked) root.openFromNotch()
    }
    Timer {
        id: hoverRearmTimer
        interval: Math.max(250, Motion.normal)
        onTriggered: if (!root.notchHovered) root.hoverOpenBlocked = false
    }

    // An open panel always stays. Otherwise the notch is out of the way when it
    // has been asked to be — kept hidden, or hidden while windows are on this
    // workspace — but hovering the wake strip still brings it back, which is
    // how the top notch behaves in the same situation.
    readonly property bool revealed: {
        if (root.active)
            return true;
        if (!notchEnabled)
            return false;
        if (notchKeepHidden || hiddenByWindows)
            return notchHoverActive;
        return true;
    }

    // Opens on the screen whose notch was used, rather than on whichever
    // monitor happens to hold focus.
    function openFromNotch() {
        if (root.active) {
            GlobalStates.hideAssistant();
            return;
        }
        GlobalStates.assistantScreenName = targetScreen.name;
        GlobalStates.assistantVisible = true;
    }
    property bool menuExpanded: false
    property real menuWidth: 250
    property var slashCommands: [
        {
            name: "model",
            description: I18n.t("ai.cmd_switch_model")
        },
        {
            name: "help",
            description: I18n.t("ai.cmd_show_help")
        },
        {
            name: "new",
            description: I18n.t("ai.cmd_start_new_chat")
        },
        {
            name: "key",
            description: I18n.t("ai.cmd_set_api_key")
        },
        {
            name: "prompt",
            description: I18n.t("ai.cmd_set_system_prompt")
        }
    ]

    function focusSearchInput() {
        if (root.active && root.wantsFocus && !root.notchModuleOpen && !modelSelector.visible && !suggestionsPopup.visible)
            inputField.forceActiveFocus();
    }

    function restoreInputFocus() {
        if (!root.active || !root.wantsFocus || root.notchModuleOpen || modelSelector.visible || suggestionsPopup.visible)
            return;
        if (root.shellPanelRef && root.shellPanelRef.reassertKeyboardFocus)
            root.shellPanelRef.reassertKeyboardFocus();
        Qt.callLater(() => {
            if (root.active && root.wantsFocus && !root.notchModuleOpen && !root.activeFocus)
                focusSearchInput();
        });
    }
    onWantsFocusChanged: restoreInputFocus()

    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() { root.restoreInputFocus(); }
    }
    Connections {
        target: GlobalStates
        function onAssistantFocusRequested(wasAlreadyOpen) {
            if (!root.active)
                return;
            if (wasAlreadyOpen && root.wantsFocus && root.activeFocus)
                GlobalStates.hideAssistant();
            else {
                root.wantsFocus = true;
                root.restoreInputFocus();
            }
        }
    }
    onActiveChanged: {
        root.wantsFocus = active;
        if (active) {
            hoverOpenTimer.stop();
            root.restoreInputFocus();
        } else {
            root.hoverOpenBlocked = true;
            hoverRearmTimer.restart();
            modelSelector.close();
            suggestionsPopup.close();
        }
    }
    Keys.onEscapePressed: event => {
        if (root.active) {
            if (root.menuExpanded)
                root.menuExpanded = false;
            else
                root.wantsFocus = false;
            event.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            if (!root.wantsFocus)
                root.wantsFocus = true;
            mouse.accepted = false;
        }
    }

    MouseArea {
        id: resizeHandle
        width: 8
        height: sidebarContainer.height
        y: sidebarContainer.y
        visible: sidebarContainer.visible && root.active
        cursorShape: Qt.SplitHCursor
        preventStealing: true

        x: {
            if (GlobalStates.assistantPosition === "left")
                return sidebarContainer.x + sidebarContainer.width;
            return sidebarContainer.x - width;
        }

        property real pressMouseX: 0
        property int pressWidth: 0

        onPressed: {
            let mapped = mapToItem(root, mouseX, 0);
            pressMouseX = mapped.x;
            pressWidth = root.effectiveWidth;
            root.dragWidth = pressWidth;
        }

        onMouseXChanged: {
            if (!pressed)
                return;
            let mapped = mapToItem(root, mouseX, 0);
            let delta;
            if (GlobalStates.assistantPosition === "right")
                delta = pressMouseX - mapped.x;
            else
                delta = mapped.x - pressMouseX;
            root.dragWidth = Math.max(Math.min(300, root.width - root.sidebarMargin - 8), Math.min(root.width - root.sidebarMargin - 8, 800, pressWidth + delta));
        }

        onCanceled: root.dragWidth = -1
        onReleased: {
            // Plain assignment, not markShellChanged(): there is no Apply button
            // out here, so opening a shell-settings transaction would leave
            // Config.pauseAutoSave stuck true and block every module's autosave.
            Config.ai.sidebarWidth = root.effectiveWidth;
            root.dragWidth = -1;
        }
    }

    // Wake region for a notch set to keep hidden. Deliberately wider than the
    // notch is deep: a strip on a screen edge is a small target.
    Item {
        id: notchHoverRegion
        // Spans from the notch's own edge out to the bezel.
        width: root.notchHoverRegionSize + root.edgeInset
        height: root.collapsedLength
        x: GlobalStates.assistantPosition === "left" ? -root.edgeInset : parent.width - root.notchHoverRegionSize
        y: Math.round((parent.height - height) / 2)
        visible: root.notchEnabled && !root.active && (root.notchKeepHidden || root.hiddenByWindows)

        MouseArea {
            anchors.fill: parent
            onClicked: root.openFromNotch()
        }
        HoverHandler {
            id: notchHoverHandler
            enabled: notchHoverRegion.visible
        }
    }

    Item {
        id: sidebarContainer
        width: (root.showAsNotch ? root.collapsedDepth : root.effectiveWidth) + root.sidebarMargin
        height: root.showAsNotch ? root.collapsedLength : parent.height

        // Pinned by anchors, never by a binding on its own animated size.
        // Deriving `x` from `width` and `y` from `height` and then giving each
        // of those its own Behavior makes position chase a target that is
        // itself still moving: the panel unpins from the screen edge, lags
        // behind the shrink in the middle of the desktop, and only slides into
        // place once the size animation has finished. Anchored, the two edges
        // stay put and only the size animates, so the panel retracts into the
        // notch instead of detaching from it.
        anchors.left: GlobalStates.assistantPosition === "left" ? parent.left : undefined
        anchors.right: GlobalStates.assistantPosition === "right" ? parent.right : undefined
        anchors.verticalCenter: parent.verticalCenter

        visible: root.revealed || revealAnimation.running

        // Hiding travels outward along the bezel normal, the way the top notch
        // hides, rather than by moving the anchored edge.
        transform: Translate {
            x: {
                if (root.revealed)
                    return 0;
                return GlobalStates.assistantPosition === "left" ? -sidebarContainer.width : sidebarContainer.width;
            }

            Behavior on x {
                enabled: Motion.enabled
                NumberAnimation {
                    id: revealAnimation
                    duration: Motion.fast
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Width carries the notch's overshoot, since that is the axis the notch
        // actually pops along. Height spans most of the screen when expanded,
        // where an overshoot would only throw the flares off-screen.
        Behavior on width {
            enabled: Motion.enabled && root.dragWidth < 0
            NumberAnimation {
                id: widthAnimation
                duration: Motion.normal
                easing.type: root.expanded ? Easing.OutBack : Easing.OutQuart
                easing.overshoot: root.expanded ? 1.2 : 1.0
            }
        }

        Behavior on height {
            enabled: Motion.enabled
            NumberAnimation {
                id: heightAnimation
                duration: Motion.normal
                easing.type: Easing.OutQuart
            }
        }

        HoverHandler {
            id: notchBodyHover
            enabled: !root.active
        }

        MouseArea {
            anchors.fill: parent
            enabled: !root.active
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openFromNotch()
        }

        AiNotch {
            id: notchShell
            anchors.fill: parent
            anchors.topMargin: root.showAsNotch ? 0 : root.sidebarMargin
            anchors.bottomMargin: root.showAsNotch ? 0 : root.sidebarMargin
            anchors.leftMargin: GlobalStates.assistantPosition === "left" ? root.sidebarMargin : 0
            anchors.rightMargin: GlobalStates.assistantPosition === "right" ? root.sidebarMargin : 0

            edge: root.notchEdge
            flareSize: root.notchFlareSize
            bodyRadius: root.notchBodyRadius
            surfaceVariant: root.frameWrapped && !widthAnimation.running && !heightAnimation.running ? "transparent" : "bg"
            borderEnabled: !root.frameWrapped

            AiNotchCollapsed {
                anchors.fill: parent
                hovered: root.notchHovered

                // Driven by how notch-shaped the container currently is, not by
                // a Behavior of its own. A timed fade puts the glyph on screen
                // while the panel is still full width, so it reads as an icon
                // floating in the middle of the desktop.
                opacity: root.showAsNotch ? Math.max(0, Math.min(1, (root.collapsedDepth * 2 - sidebarContainer.width) / root.collapsedDepth)) : 0
                visible: opacity > 0.01
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                clip: true
                enabled: root.expanded
                opacity: root.expanded ? 1 : 0
                visible: opacity > 0.01

                Behavior on opacity {
                    enabled: Motion.enabled
                    NumberAnimation {
                        duration: Motion.fast
                        easing.type: Easing.OutQuart
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        AssistantIconButton {
                            glyph: Icons.list
                            label: I18n.t("ai.chat_history")
                            active: root.menuExpanded
                            onClicked: root.menuExpanded = !root.menuExpanded
                        }

                        AssistantIconButton {
                            glyph: Icons.edit
                            label: I18n.t("ai.new_chat")
                            enabled: !Ai.isLoading
                            onClicked: {
                                Ai.createNewChat();
                                root.menuExpanded = false;
                            }
                        }

                        AssistantIconButton {
                            glyph: Icons.pin
                            label: I18n.t("ai.merge_into_frame")
                            active: GlobalStates.assistantMergedIntoFrame
                            onClicked: Config.ai.sidebarMergeIntoFrame = !Config.ai.sidebarMergeIntoFrame
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        AssistantIconButton {
                            glyph: GlobalStates.assistantPosition === "right" ? Icons.caretRight : Icons.caretLeft
                            label: I18n.t("ai.close_assistant")
                            onClicked: GlobalStates.hideAssistant()
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Colors.outline
                        opacity: 0.15
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Item {
                        id: mainChatArea
                        anchors.fill: parent

                        property var pendingAttachments: []
                        property var attachmentQueue: []
                        readonly property var supportedImageTypes: ["image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp"]

                        // An image is read whole, base64-encoded, copied into the
                        // conversation, written to the store and encoded again into
                        // the request body — so one file exists several times over.
                        // Nothing bounded any of that, and a provider would reject a
                        // huge one anyway, after it had been paid for in memory.
                        readonly property int maxAttachmentBytes: 8 * 1024 * 1024
                        readonly property int maxAttachments: 8

                        // Base64 is 4 bytes per 3, so this is the encoded ceiling.
                        readonly property int maxEncodedLength: Math.ceil(maxAttachmentBytes / 3) * 4

                        function startNextAttachment() {
                            if (attachmentReadProcess.running || attachmentQueue.length === 0)
                                return;
                            const next = attachmentQueue[0];
                            attachmentQueue = attachmentQueue.slice(1);
                            attachmentReadProcess.filePath = next.path;
                            attachmentReadProcess.mimeType = next.mimeType;
                            attachmentReadProcess.fileName = next.name;
                            attachmentReadProcess.chatId = next.chatId;
                            attachmentReadProcess.running = true;
                        }

                        Connections {
                            target: Ai
                            function onCurrentChatIdChanged() {
                                mainChatArea.clearAttachments();
                                mainChatArea.attachmentQueue = [];
                            }
                        }

                        function addAttachment(mimeType, base64Data, fileName) {
                            if (pendingAttachments.length >= maxAttachments) {
                                Ai.pushSystemMessage(I18n.t("ai.too_many_attachments").replace("%1", maxAttachments));
                                return;
                            }
                            if (base64Data.length > maxEncodedLength) {
                                Ai.pushSystemMessage(I18n.t("ai.attachment_too_large").replace("%1", fileName).replace("%2", Math.round(maxAttachmentBytes / 1048576)));
                                return;
                            }
                            let list = pendingAttachments.slice();
                            list.push({
                                type: "image",
                                mimeType: mimeType,
                                base64: base64Data,
                                name: fileName
                            });
                            pendingAttachments = list;
                        }

                        function normalizeFilePath(path) {
                            let p = path ? path.trim() : "";
                            if (p.startsWith("file://"))
                                p = p.substring(7);
                            try {
                                p = decodeURIComponent(p);
                            } catch (e) {
                            }
                            return p;
                        }

                        function fileMimeForPath(path) {
                            let ext = path.split(".").pop().toLowerCase();
                            let mimeMap = {
                                png: "image/png",
                                jpg: "image/jpeg",
                                jpeg: "image/jpeg",
                                gif: "image/gif",
                                webp: "image/webp",
                                bmp: "image/bmp"
                            };
                            return mimeMap[ext] || "";
                        }

                        function addAttachmentFromFile(path) {
                            let filePath = normalizeFilePath(path);
                            if (!filePath)
                                return;
                            let mimeType = fileMimeForPath(filePath);
                            if (!mimeType) {
                                Ai.pushSystemMessage(I18n.t("ai.attachment_unsupported"));
                                return;
                            }
                            if (pendingAttachments.length + attachmentQueue.length >= maxAttachments) {
                                Ai.pushSystemMessage(I18n.t("ai.too_many_attachments").replace("%1", maxAttachments));
                                return;
                            }
                            attachmentQueue = attachmentQueue.concat([{
                                path: filePath, mimeType: mimeType, name: filePath.split("/").pop(), chatId: Ai.currentChatId
                            }]);
                            startNextAttachment();
                        }

                        function addAttachmentsFromUriList(text) {
                            let lines = text.split("\n");
                            for (let i = 0; i < lines.length; i++) {
                                let line = lines[i].trim();
                                if (line === "" || line.startsWith("#"))
                                    continue;
                                addAttachmentFromFile(line);
                            }
                        }

                        function removeAttachment(index) {
                            let list = pendingAttachments.slice();
                            list.splice(index, 1);
                            pendingAttachments = list;
                        }

                        function clearAttachments() {
                            pendingAttachments = [];
                        }
                        StyledRect {
                            id: historyPage
                            anchors.fill: parent
                            variant: "bg"
                            // Driven by opacity, not by menuExpanded directly: a
                            // `visible` bound to the same flag switches off in the
                            // frame the fade starts, so the fade-out never showed.
                            visible: opacity > 0.01
                            enabled: root.menuExpanded
                            opacity: root.menuExpanded ? 1 : 0
                            z: 10

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Motion.normal
                                }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 8

                                Text {
                                    text: I18n.t("ai.chat_history")
                                    color: Colors.overSurface
                                    font.family: Config.theme.font
                                    font.pixelSize: 18
                                    font.weight: Font.Bold
                                }

                                Text {
                                    visible: Ai.historyError !== ""
                                    Layout.fillWidth: true
                                    text: I18n.t("ai.chat_store_failed").replace("%1", Ai.historyError)
                                    color: Colors.error
                                    font.family: Config.theme.font
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
                                }

                                ListView {
                                    id: historyList
                                    visible: Ai.historyError === ""
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    model: Ai.chatHistory
                                    spacing: 4

                                    delegate: Button {
                                        enabled: !Ai.isLoading
                                        width: historyList.width
                                        height: 48
                                        flat: true

                                        contentItem: RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 8

                                            Column {
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter

                                                Text {
                                                    text: modelData.title || "New Chat"
                                                    color: Ai.currentChatId === modelData.id ? Styling.srItem("primary") : Colors.overSurface
                                                    font.family: Config.theme.font
                                                    font.pixelSize: 14
                                                    font.weight: Font.Medium
                                                    elide: Text.ElideRight
                                                    width: parent.width
                                                }

                                                Text {
                                                    text: {
                                                        // The store reports when the conversation was
                                                        // last written. Chat ids happen to be creation
                                                        // timestamps, which is the fallback, but an
                                                        // imported one is only as good as its old file.
                                                        const stamp = modelData.updatedAt || parseInt(modelData.id);
                                                        if (!stamp)
                                                            return "";
                                                        return new Date(stamp).toLocaleString(Qt.locale(), "MMM dd, hh:mm a");
                                                    }
                                                    color: Ai.currentChatId === modelData.id ? Styling.srItem("primary") : Colors.outline
                                                    font.family: Config.theme.font
                                                    font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                    width: parent.width
                                                }
                                            }

                                            Button {
                                                visible: parent.parent.hovered
                                                flat: true
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 28

                                                contentItem: Text {
                                                    text: Icons.trash
                                                    font.family: Icons.font
                                                    color: parent.hovered ? Colors.error : Colors.outline
                                                    font.pixelSize: 14
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }

                                                background: null
                                                onClicked: Ai.deleteChat(modelData.id)
                                            }
                                        }

                                        background: StyledRect {
                                            variant: Ai.currentChatId === modelData.id ? "focus" : (parent.hovered ? "surfaceVariant" : "transparent")
                                            radius: Styling.radius(6)
                                        }

                                        onClicked: {
                                            Ai.loadChat(modelData.id);
                                            root.menuExpanded = false;
                                        }
                                    }
                                }
                            }
                        }
                        property int retryIndex: -1
                        property string username: ""

                        Process {
                            running: true
                            command: ["whoami"]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let user = text.trim();
                                    if (user) {
                                        mainChatArea.username = user.charAt(0).toUpperCase() + user.slice(1);
                                    }
                                }
                            }
                        }

                        Process {
                            id: zenityProcess
                            command: ["zenity", "--file-selection", "--file-filter=Images | *.png *.jpg *.jpeg *.gif *.webp *.bmp", "--file-filter=All files | *"]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let filePath = text.trim();
                                    if (filePath.length > 0)
                                        mainChatArea.addAttachmentFromFile(filePath);
                                }
                            }
                        }

                        Process {
                            id: attachmentReadProcess
                            property string filePath: ""
                            property string mimeType: ""
                            property string fileName: ""
                            property string chatId: ""
                            // head bounds the read: a check on the file's size is a
                            // promise about a moment, and the file is still the
                            // user's to change afterwards.
                            command: ["/usr/bin/bash", "-c",
                                'head -c "$1" -- "$2" | /usr/bin/base64 -w 0',
                                // Three bytes past the limit, not one: base64 encodes
                                // in three-byte groups, so a file one byte over
                                // encodes to exactly the same length as one exactly
                                // at the limit and the check below could not tell
                                // them apart.
                                "ambxst-attachment", String(mainChatArea.maxAttachmentBytes + 3), filePath]
                            stdout: StdioCollector { id: attachmentReadStdout }
                            stderr: StdioCollector { id: attachmentReadStderr }
                            onExited: exitCode => {
                                if (attachmentReadProcess.chatId === Ai.currentChatId) {
                                    const data = attachmentReadStdout.text.trim();
                                    if (exitCode === 0 && data.length > 0)
                                        mainChatArea.addAttachment(mimeType, data, fileName);
                                    else
                                        Ai.pushSystemMessage(I18n.t("ai.attachment_read_failed").replace("%1", fileName));
                                }
                                Qt.callLater(mainChatArea.startNextAttachment);
                            }
                        }

                        Process {
                            id: clipboardTypesProcess
                            command: ["wl-paste", "--list-types"]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let types = text.trim().split("\n");
                                    let imageType = "";
                                    for (let i = 0; i < types.length; i++) {
                                        if (mainChatArea.supportedImageTypes.indexOf(types[i].trim()) >= 0) {
                                            imageType = types[i].trim();
                                            break;
                                        }
                                    }
                                    if (imageType.length > 0) {
                                        clipboardImageProcess.mimeType = imageType;
                                        clipboardImageProcess.chatId = Ai.currentChatId;
                                        clipboardImageProcess.running = true;
                                        return;
                                    }
                                    if (types.indexOf("text/uri-list") !== -1) {
                                        clipboardUrisProcess.running = true;
                                        return;
                                    }
                                    // Plain text is pasted by TextArea itself.
                                }
                            }
                            stderr: StdioCollector {
                                id: clipboardTypesStderr
                            }
                            onExited: exitCode => {
                                if (exitCode !== 0) {
                                    let err = clipboardTypesStderr.text.trim();
                                    Ai.pushSystemMessage("Clipboard read failed: " + (err.length > 0 ? err : "unknown error"));
                                }
                            }
                        }

                        Process {
                            id: clipboardImageProcess
                            property string mimeType: ""
                            property string chatId: ""
                            command: ["bash", "-c", "set -o pipefail; wl-paste --type \"$1\" | /usr/bin/base64 -w 0", "ambxst-clipboard", mimeType]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    if (clipboardImageProcess.chatId !== Ai.currentChatId)
                                        return;
                                    let data = text.trim();
                                    if (data.length > 0) {
                                        let ext = clipboardImageProcess.mimeType.split("/")[1] || "png";
                                        mainChatArea.addAttachment(clipboardImageProcess.mimeType, data, "clipboard." + ext);
                                    } else {
                                        Ai.pushSystemMessage("Clipboard image read returned no data.");
                                    }
                                }
                            }
                            stderr: StdioCollector {
                                id: clipboardImageStderr
                            }
                            onExited: exitCode => {
                                if (exitCode !== 0) {
                                    let err = clipboardImageStderr.text.trim();
                                    Ai.pushSystemMessage("Clipboard image read failed: " + (err.length > 0 ? err : "unknown error"));
                                }
                            }
                        }

                        Process {
                            id: clipboardUrisProcess
                            command: ["wl-paste", "--type", "text/uri-list"]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let data = text.trim();
                                    if (data.length > 0)
                                        mainChatArea.addAttachmentsFromUriList(data);
                                    else
                                        Ai.pushSystemMessage("Clipboard file list is empty.");
                                }
                            }
                            stderr: StdioCollector {
                                id: clipboardUrisStderr
                            }
                            onExited: exitCode => {
                                if (exitCode !== 0) {
                                    let err = clipboardUrisStderr.text.trim();
                                    Ai.pushSystemMessage("Clipboard file read failed: " + (err.length > 0 ? err : "unknown error"));
                                }
                            }
                        }
                        property bool isWelcome: Ai.currentChat.length === 0

                        ColumnLayout {
                            anchors.bottom: inputContainer.top
                            anchors.bottomMargin: 24
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: mainChatArea.isWelcome
                            spacing: 8

                            Text {
                                text: I18n.t("ai.hello_user", mainChatArea.username)
                                font.family: Config.theme.font
                                font.pixelSize: 32
                                font.weight: Font.Bold
                                textFormat: Text.StyledText
                                Layout.alignment: Qt.AlignHCenter
                                color: Colors.overBackground
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                height: 40

                                Text {
                                    text: Ai.currentModel ? Ai.currentModel.name : ""
                                    color: Colors.overBackground
                                    font.family: Config.theme.font
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                visible: false
                            }

                            ListView {
                                id: chatView
                                visible: !mainChatArea.isWelcome
                                // These delegates are expensive — avatar, bubble, action row,
                                // segmented body — so they are pooled and reused rather than
                                // rebuilt, and the cache is sized to a screenful rather than
                                // holding a thousand pixels of them either side.
                                reuseItems: true
                                cacheBuffer: 300
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                model: Ai.currentChat
                                spacing: 16
                                displayMarginBeginning: 40
                                displayMarginEnd: 40

                                bottomMargin: mainChatArea.isWelcome ? 0 : inputContainer.height

                                // Following the newest content, unless the user has scrolled
                                // away from it. Only `onCountChanged` used to scroll, and a
                                // streamed reply grows without changing the count — so a long
                                // answer wrote itself off the bottom of the view.
                                property bool followTail: true

                                onCountChanged: {
                                    followTail = true;
                                    Qt.callLater(() => positionViewAtEnd());
                                }

                                onContentHeightChanged: {
                                    if (followTail)
                                        Qt.callLater(() => positionViewAtEnd());
                                }

                                // Reading back through a conversation must not be yanked
                                // forward by the reply still arriving; returning to the
                                // bottom opts back in.
                                onMovementEnded: followTail = atYEnd
                                onFlickEnded: followTail = atYEnd

                                delegate: Item {
                                    id: messageDelegate
                                    required property var modelData
                                    required property int index

                                    property bool isUser: modelData.role === "user"
                                    property bool isSystem: modelData.role === "system" || modelData.role === "function"
                                    property bool isEditing: false
                                    property bool retryMode: false

                                    // While this message is the one being streamed into it renders
                                    // as plain text from the service, not from its own model data.
                                    // Segmenting fenced code and parsing Markdown on every chunk
                                    // meant re-doing both for the whole reply per token; the reply
                                    // is parsed once, when it is finished.
                                    readonly property bool isStreaming: index === Ai.streamingIndex
                                    readonly property string bodyText: isStreaming ? Ai.streamingText : (modelData.content || "")
                                    readonly property color bodyColor: isSystem ? Colors.outline : (isUser ? Styling.srItem("primary") : Styling.srItem("secondary"))

                                    width: ListView.view.width
                                    height: bubbleArea.height + 8

                                    // Reuse means this object now stands for a different
                                    // message. Anything it was holding about the old one has
                                    // to go, or an edit box follows the scroll.
                                    ListView.onReused: {
                                        isEditing = false;
                                        retryMode = false;
                                        retryTimer.stop();
                                    }
                                    ListView.onPooled: retryTimer.stop()

                                    Row {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.margins: 10
                                        layoutDirection: (isUser && !isSystem) ? Qt.RightToLeft : Qt.LeftToRight
                                        spacing: 12

                                        Item {
                                            width: 32
                                            height: 32
                                            visible: !isSystem

                                            StyledRect {
                                                anchors.fill: parent
                                                radius: Styling.radius(16)
                                                variant: "primary"
                                                visible: !isUser

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: Icons.robot
                                                    font.family: Icons.font
                                                    color: Colors.overPrimary
                                                    font.pixelSize: 20
                                                }
                                            }

                                            ClippingRectangle {
                                                anchors.fill: parent
                                                radius: Styling.radius(16)
                                                color: Colors.surfaceDim
                                                visible: isUser

                                                Image {
                                                    mipmap: true
                                                    anchors.fill: parent
                                                    source: "file://" + Quickshell.env("HOME") + "/.face.icon"
                                                    fillMode: Image.PreserveAspectCrop

                                                    onStatusChanged: {
                                                        if (status === Image.Error) {
                                                            source = "";
                                                        }
                                                    }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: Icons.user
                                                        font.family: Icons.font
                                                        color: Colors.overPrimary
                                                        visible: parent.status !== Image.Ready
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: bubbleArea
                                            width: parent.width
                                            height: Math.max(bubble.height, 32) + (modelIndicator.visible ? modelIndicator.implicitHeight + 4 : 0)
                                            hoverEnabled: true
                                            acceptedButtons: Qt.NoButton

                                            Row {
                                                anchors.verticalCenter: bubble.verticalCenter
                                                anchors.left: isUser ? undefined : bubble.right
                                                anchors.right: isUser ? bubble.left : undefined
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 4
                                                visible: bubbleArea.containsMouse || messageDelegate.isEditing

                                                Button {
                                                    width: 24
                                                    height: 24
                                                    flat: true
                                                    padding: 0
                                                    visible: !isSystem

                                                    property bool isHovered: hovered

                                                    contentItem: Text {
                                                        text: messageDelegate.isEditing ? Icons.accept : Icons.edit
                                                        font.family: Icons.font
                                                        color: parent.down ? Colors.overPrimary : (parent.isHovered ? Colors.overSurface : Colors.overSurface)
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                    background: StyledRect {
                                                        variant: parent.down ? "primary" : (parent.isHovered ? "focus" : "common")
                                                        radius: Styling.radius(4)
                                                    }

                                                    enabled: !Ai.isLoading
                                                    onClicked: {
                                                        if (messageDelegate.isEditing) {
                                                            Ai.updateMessage(index, bubbleContentText.text);
                                                            messageDelegate.isEditing = false;
                                                        } else {
                                                            messageDelegate.isEditing = true;
                                                            bubbleContentText.forceActiveFocus();
                                                            bubbleContentText.cursorPosition = bubbleContentText.text.length;
                                                        }
                                                    }
                                                }

                                                Button {
                                                    width: 24
                                                    height: 24
                                                    flat: true
                                                    padding: 0
                                                    visible: !messageDelegate.isEditing

                                                    property bool isHovered: hovered

                                                    contentItem: Text {
                                                        text: Icons.copy
                                                        font.family: Icons.font
                                                        color: parent.down ? Colors.overPrimary : (parent.isHovered ? Colors.overSurface : Colors.overSurface)
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                    background: StyledRect {
                                                        variant: parent.down ? "primary" : (parent.isHovered ? "focus" : "common")
                                                        radius: Styling.radius(4)
                                                    }

                                                    onClicked: {
                                                        Quickshell.clipboardText = modelData.content || "";
                                                    }
                                                }

                                                Button {
                                                    visible: !isUser && !isSystem && !messageDelegate.isEditing
                                                    width: 24
                                                    height: 24
                                                    flat: true
                                                    padding: 0

                                                    property bool isHovered: hovered

                                                    contentItem: Text {
                                                        text: Icons.arrowCounterClockwise
                                                        font.family: Icons.font
                                                        color: parent.down ? Colors.overPrimary : (parent.isHovered ? Colors.overSurface : Colors.overSurface)
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                    background: StyledRect {
                                                        variant: parent.down ? "primary" : (parent.isHovered ? "focus" : "common")
                                                        radius: Styling.radius(4)
                                                    }

                                                    enabled: !Ai.isLoading
                                                    onClicked: Ai.regenerateResponse(index)
                                                }
                                            }

                                            StyledRect {
                                                id: bubble
                                                width: Math.min(Math.max(bubbleContent.implicitWidth + 32, 100), chatView.width * (isSystem ? 0.9 : 0.7))
                                                height: bubbleContent.implicitHeight + 24

                                                anchors.right: isUser ? parent.right : undefined
                                                anchors.left: isUser ? undefined : parent.left

                                                variant: isSystem ? "surface" : (isUser ? "primary" : "secondary")
                                                radius: Styling.radius(4)
                                                border.width: isSystem || messageDelegate.isEditing ? 1 : 0
                                                border.color: messageDelegate.isEditing ? Styling.srItem("overprimary") : Colors.surfaceDim

                                                ColumnLayout {
                                                    id: bubbleContent
                                                    anchors.centerIn: parent
                                                    width: parent.width - 32
                                                    spacing: 8

                                                    AssistantMarkdown {
                                                        Layout.fillWidth: true
                                                        visible: !messageDelegate.isEditing && !bubbleContentText.visible && !messageDelegate.isStreaming
                                                        // Only built for what is on screen: an off-screen
                                                        // or streaming message segments nothing.
                                                        text: visible ? (modelData.content || "") : ""
                                                        textColor: messageDelegate.bodyColor
                                                        contentWidth: bubbleContent.width
                                                    }

                                                    Text {
                                                        id: streamingBody
                                                        Layout.fillWidth: true
                                                        visible: messageDelegate.isStreaming
                                                        text: Ai.streamingText
                                                        textFormat: Text.PlainText
                                                        color: messageDelegate.bodyColor
                                                        font.family: Config.theme.font
                                                        font.pixelSize: 14
                                                        wrapMode: Text.Wrap
                                                    }

                                                    TextEdit {
                                                        id: bubbleContentText
                                                        Layout.fillWidth: true
                                                        text: modelData.content || ""
                                                        textFormat: Text.PlainText
                                                        color: messageDelegate.bodyColor
                                                        font.family: Config.theme.font
                                                        font.pixelSize: 14
                                                        wrapMode: Text.Wrap
                                                        readOnly: !messageDelegate.isEditing
                                                        selectByMouse: true
                                                        visible: messageDelegate.isEditing
                                                    }

                                                    ColumnLayout {
                                                        id: toolCard
                                                        visible: modelData.functionCall !== undefined
                                                        Layout.fillWidth: true
                                                        spacing: 4

                                                        // The command line that will actually run, resolved
                                                        // from the proposal by the tool catalog. Empty means
                                                        // the proposal does not resolve to anything runnable,
                                                        // and then there is nothing to approve.
                                                        readonly property string resolvedCommand: modelData.functionCall ? Ai.describeToolCall(modelData.functionCall) : ""
                                                        readonly property bool runnable: resolvedCommand !== ""

                                                        Separator {}

                                                        Text {
                                                            text: modelData.functionCall ? modelData.functionCall.name : ""
                                                            color: Styling.srItem("overprimary")
                                                            font.family: Config.theme.font
                                                            font.weight: Font.Bold
                                                            font.pixelSize: 12
                                                        }

                                                        StyledRect {
                                                            Layout.fillWidth: true
                                                            visible: toolCard.runnable
                                                            variant: "surface"
                                                            color: Colors.surface
                                                            radius: Styling.radius(4)

                                                            TextEdit {
                                                                padding: 8
                                                                width: parent.width
                                                                text: toolCard.resolvedCommand
                                                                font.family: "Monospace"
                                                                color: Colors.overSurface
                                                                readOnly: true
                                                                wrapMode: Text.WrapAnywhere
                                                            }
                                                        }

                                                        Text {
                                                            visible: !toolCard.runnable
                                                            Layout.fillWidth: true
                                                            text: I18n.t("ai.tool_refused").replace("%1", modelData.functionCall ? modelData.functionCall.name : "")
                                                            color: Colors.error
                                                            font.family: Config.theme.font
                                                            font.pixelSize: 12
                                                            wrapMode: Text.Wrap
                                                        }

                                                        RowLayout {
                                                            visible: modelData.functionPending === true && toolCard.runnable
                                                            Layout.alignment: Qt.AlignRight
                                                            spacing: 8

                                                            Button {
                                                                text: I18n.t("ai.reject")
                                                                highlighted: true
                                                                flat: true
                                                                onClicked: Ai.rejectCommand(index)

                                                                background: StyledRect {
                                                                    variant: "error"
                                                                    opacity: parent.hovered ? 0.8 : 0.5
                                                                    radius: Styling.radius(4)
                                                                }

                                                                contentItem: Text {
                                                                    text: parent.text
                                                                    color: Colors.overError
                                                                    font.family: Config.theme.font
                                                                    horizontalAlignment: Text.AlignHCenter
                                                                    verticalAlignment: Text.AlignVCenter
                                                                }
                                                            }

                                                            Button {
                                                                text: I18n.t("ai.approve")
                                                                highlighted: true
                                                                flat: true
                                                                onClicked: Ai.approveCommand(index)

                                                                background: StyledRect {
                                                                    variant: "primary"
                                                                    opacity: parent.hovered ? 1 : 0.8
                                                                    radius: Styling.radius(4)
                                                                }

                                                                contentItem: Text {
                                                                    text: parent.text
                                                                    color: Colors.overPrimary
                                                                    font.family: Config.theme.font
                                                                    horizontalAlignment: Text.AlignHCenter
                                                                    verticalAlignment: Text.AlignVCenter
                                                                }
                                                            }
                                                        }

                                                        Text {
                                                            visible: modelData.functionApproved === true
                                                            text: I18n.t("ai.command_approved")
                                                            color: Colors.success
                                                            font.pixelSize: 12
                                                        }

                                                        Text {
                                                            visible: modelData.functionApproved === false && !modelData.functionPending
                                                            text: I18n.t("ai.command_rejected")
                                                            color: Colors.error
                                                            font.pixelSize: 12
                                                        }
                                                    }
                                                }
                                            }

                                            Text {
                                                id: modelIndicator
                                                visible: !isUser && !isSystem && (modelData.model ? true : false)
                                                text: retryMode ? "Retry with another model " + Icons.caretRight : (modelData.model || "")
                                                color: Colors.outline
                                                font.family: Config.theme.font
                                                font.pixelSize: Styling.fontSize(-2)
                                                font.weight: Font.Medium

                                                anchors.top: bubble.bottom
                                                anchors.topMargin: 4
                                                anchors.left: bubble.left
                                                anchors.leftMargin: 4

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor

                                                    onClicked: {
                                                        if (retryMode) {
                                                            mainChatArea.retryIndex = index;
                                                            modelSelector.open();
                                                            retryMode = false;
                                                        } else {
                                                            retryMode = true;
                                                            retryTimer.start();
                                                        }
                                                    }
                                                }

                                                Timer {
                                                    id: retryTimer
                                                    interval: 5000
                                                    onTriggered: retryMode = false
                                                }
                                            }
                                        }
                                    }
                                }

                                footer: Item {
                                    width: chatView.width
                                    height: 40
                                    visible: Ai.isLoading

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Repeater {
                                            model: 3

                                            Rectangle {
                                                width: 8
                                                height: 8
                                                radius: 4
                                                color: Styling.srItem("overprimary")
                                                opacity: 0.5

                                                SequentialAnimation on opacity {
                                                    loops: Animation.Infinite
                                                    running: root.active && visible && Ai.isLoading && Motion.enabled

                                                    PauseAnimation {
                                                        duration: index * 200
                                                    }

                                                    PropertyAnimation {
                                                        to: 1
                                                        duration: 400
                                                    }

                                                    PropertyAnimation {
                                                        to: 0.5
                                                        duration: 400
                                                    }

                                                    PauseAnimation {
                                                        duration: 400 - (index * 200)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        ModelSelectorPopup {
                            id: modelSelector
                            parent: mainChatArea

                            onModelSelected: {
                                if (mainChatArea.retryIndex > -1) {
                                    Ai.regenerateResponse(mainChatArea.retryIndex);
                                    mainChatArea.retryIndex = -1;
                                }
                            }
                        }

                        Connections {
                            target: Ai

                            function onModelSelectionRequested() {
                                if (root.active)
                                    modelSelector.open();
                            }
                        }

                        Item {
                            id: inputContainer
                            property int attachmentPreviewHeight: attachmentPreview.visible ? Math.min(attachmentPreview.contentHeight, 120) + 8 : 0
                            height: attachmentPreviewHeight + Math.min(150, Math.max(48, inputField.contentHeight + 24))

                            anchors.bottom: parent.bottom
                            property real centerMargin: (parent.height / 2) - (height / 2)
                            anchors.bottomMargin: mainChatArea.isWelcome ? centerMargin : 20
                            anchors.horizontalCenter: parent.horizontalCenter

                            width: Math.min(600, parent.width - 40)

                            Behavior on anchors.bottomMargin {
                                NumberAnimation {
                                    duration: Motion.normal
                                    easing.type: Easing.OutCubic
                                }
                            }

                            StyledRect {
                                id: inputStyledRect
                                anchors.fill: parent
                                variant: "pane"
                                radius: Styling.radius(4)
                                enableShadow: true

                                DropArea {
                                    anchors.fill: parent
                                    onDropped: drop => {
                                        if (drop.urls && drop.urls.length > 0) {
                                            for (let i = 0; i < drop.urls.length; i++)
                                                mainChatArea.addAttachmentFromFile(drop.urls[i]);
                                            drop.accepted = true;
                                            return;
                                        }
                                        if (drop.text && drop.text.length > 0) {
                                            mainChatArea.addAttachmentsFromUriList(drop.text);
                                            drop.accepted = true;
                                        }
                                    }
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 6

                                    Flickable {
                                        id: attachmentPreview
                                        height: visible ? Math.min(contentHeight, 120) : 0
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 12
                                        Layout.rightMargin: 12
                                        Layout.topMargin: 8
                                        Layout.preferredHeight: height
                                        visible: mainChatArea.pendingAttachments.length > 0
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds
                                        interactive: contentHeight > height

                                        contentWidth: width
                                        contentHeight: attachmentsFlow.height

                                        Flow {
                                            id: attachmentsFlow
                                            width: attachmentPreview.width
                                            spacing: 6

                                            Repeater {
                                                model: mainChatArea.pendingAttachments

                                                Item {
                                                    width: 48
                                                    height: 48

                                                    StyledRect {
                                                        anchors.fill: parent
                                                        variant: "surface"
                                                        radius: Styling.radius(6)

                                                        Image {
                                                            anchors.fill: parent
                                                            anchors.margins: 2
                                                            source: "data:" + modelData.mimeType + ";base64," + modelData.base64
                                                            fillMode: Image.PreserveAspectCrop
                                                            sourceSize.width: 48
                                                            sourceSize.height: 48
                                                        }
                                                    }

                                                    Button {
                                                        anchors.right: parent.right
                                                        anchors.top: parent.top
                                                        anchors.rightMargin: -4
                                                        anchors.topMargin: -4
                                                        width: 16
                                                        height: 16
                                                        flat: true
                                                        z: 1

                                                        contentItem: Text {
                                                            text: Icons.cancel
                                                            font.family: Icons.font
                                                            font.pixelSize: 10
                                                            color: Colors.overSurface
                                                            horizontalAlignment: Text.AlignHCenter
                                                            verticalAlignment: Text.AlignVCenter
                                                        }

                                                        background: Rectangle {
                                                            color: Colors.surfaceBright
                                                            radius: 8
                                                        }

                                                        onClicked: mainChatArea.removeAttachment(index)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                Popup {
                                    id: suggestionsPopup
                                    parent: inputContainer
                                    y: -height - 8
                                    x: 0
                                    width: parent.width
                                    height: Math.min(suggestionsList.contentHeight, mainChatArea.isWelcome ? 120 : 200)
                                    padding: 0
                                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                                    visible: inputField.text.startsWith("/") && suggestionsModel.count > 0

                                    background: StyledRect {
                                        variant: "popup"
                                        radius: Styling.radius(8)
                                        enableShadow: true
                                    }

                                    function selectNext() {
                                        suggestionsList.currentIndex = (suggestionsList.currentIndex + 1) % suggestionsModel.count;
                                    }

                                    function selectPrevious() {
                                        suggestionsList.currentIndex = (suggestionsList.currentIndex - 1 + suggestionsModel.count) % suggestionsModel.count;
                                    }

                                    function executeSelection() {
                                        if (suggestionsList.currentIndex >= 0 && suggestionsList.currentIndex < suggestionsModel.count) {
                                            let item = suggestionsModel.get(suggestionsList.currentIndex);
                                            inputField.text = "/" + item.name + " ";
                                            inputField.cursorPosition = inputField.text.length;
                                            inputField.forceActiveFocus();
                                        }
                                    }

                                    ListView {
                                        id: suggestionsList
                                        anchors.fill: parent
                                        clip: true

                                        model: ListModel {
                                            id: suggestionsModel
                                        }

                                        highlight: Rectangle {
                                            color: Colors.surface
                                            opacity: 0.5
                                        }
                                        highlightMoveDuration: 0

                                        delegate: Button {
                                            width: suggestionsList.width
                                            height: 40
                                            flat: true
                                            highlighted: ListView.isCurrentItem

                                            contentItem: RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: 8

                                                Text {
                                                    text: "/" + model.name
                                                    font.family: Config.theme.font
                                                    font.weight: Font.Bold
                                                    color: highlighted ? Styling.srItem("overprimary") : Colors.overSurface
                                                }

                                                Text {
                                                    text: model.description
                                                    font.family: Config.theme.font
                                                    color: highlighted ? Colors.overSurface : Colors.surfaceDim
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            background: Rectangle {
                                                color: (parent.highlighted || parent.hovered) ? Colors.surfaceBright : "transparent"
                                            }

                                            onClicked: {
                                                suggestionsList.currentIndex = index;
                                                suggestionsPopup.executeSelection();
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.leftMargin: 16
                                    Layout.rightMargin: 16
                                    Layout.topMargin: attachmentPreview.visible ? 0 : 8
                                    Layout.bottomMargin: 8

                                    ScrollView {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        TextArea {
                                            id: inputField
                                            focus: true
                                            activeFocusOnTab: true
                                            placeholderText: Ai.isLoading ? "AI is responding…" : mainChatArea.isWelcome ? I18n.t("ai.ask_or_help") : I18n.t("ai.message")
                                            placeholderTextColor: Colors.outline
                                            font.pixelSize: 14
                                            color: Colors.overBackground
                                            wrapMode: TextEdit.Wrap

                                            onTextChanged: {
                                                if (text.startsWith("/")) {
                                                    const query = text.substring(1).toLowerCase();
                                                    suggestionsModel.clear();
                                                    root.slashCommands.forEach(cmd => {
                                                        if (cmd.name.startsWith(query)) {
                                                            suggestionsModel.append(cmd);
                                                        }
                                                    });
                                                } else {
                                                    suggestionsModel.clear();
                                                }
                                            }

                                            background: null

                                            Keys.onPressed: event => {
                                                if (suggestionsPopup.visible) {
                                                    if (event.key === Qt.Key_Up) {
                                                        suggestionsPopup.selectPrevious();
                                                        event.accepted = true;
                                                        return;
                                                    } else if (event.key === Qt.Key_Down) {
                                                        suggestionsPopup.selectNext();
                                                        event.accepted = true;
                                                        return;
                                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) {
                                                        suggestionsPopup.executeSelection();
                                                        event.accepted = true;
                                                        return;
                                                    }
                                                }
                                                if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                                                    clipboardTypesProcess.running = true;
                                                    return;
                                                }
                                                if (event.key === Qt.Key_Escape) {
                                                    if (root.menuExpanded) {
                                                        root.menuExpanded = false;
                                                    } else {
                                                        root.wantsFocus = false;
                                                    }
                                                    event.accepted = true;
                                                    return;
                                                }
                                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                                    if (attachmentReadProcess.running || mainChatArea.attachmentQueue.length > 0) {
                                                        event.accepted = true;
                                                        return;
                                                    }
                                                    if (text.trim().length > 0 || mainChatArea.pendingAttachments.length > 0) {
                                                        if (Ai.sendMessage(text.trim(), mainChatArea.pendingAttachments.length > 0 ? mainChatArea.pendingAttachments : undefined) !== false) {
                                                            text = "";
                                                            mainChatArea.clearAttachments();
                                                        }
                                                    }
                                                    event.accepted = true;
                                                }
                                            }
                                            Component.onCompleted: {
                                                if (root.active)
                                                    forceActiveFocus();
                                            }
                                        }
                                    }

                                    AssistantIconButton {
                                        glyph: Icons.plus
                                        label: I18n.t("ai.attach_image")
                                        iconSize: 20
                                        iconColor: Colors.outline
                                        onClicked: zenityProcess.running = true
                                    }
                                    // Stop takes Send's place while a reply is
                                    // in flight. There was no way to end a
                                    // generation at all before: closing the
                                    // panel only hid it, and the request kept
                                    // streaming and billing.
                                    AssistantIconButton {
                                        glyph: Icons.stop
                                        label: I18n.t("ai.stop")
                                        iconSize: 20
                                        iconColor: Colors.error
                                        visible: Ai.isLoading
                                        onClicked: Ai.cancelRequest()
                                    }

                                    AssistantIconButton {
                                        glyph: Icons.paperPlane
                                        label: I18n.t("ai.send_message")
                                        iconSize: 20
                                        iconColor: Styling.srItem("overprimary")
                                        enabled: !Ai.isLoading && !attachmentReadProcess.running && mainChatArea.attachmentQueue.length === 0
                                        visible: !Ai.isLoading && (inputField.text.length > 0 || mainChatArea.pendingAttachments.length > 0)

                                        onClicked: {
                                            if (inputField.text.trim().length > 0 || mainChatArea.pendingAttachments.length > 0) {
                                                if (Ai.sendMessage(inputField.text.trim(), mainChatArea.pendingAttachments.length > 0 ? mainChatArea.pendingAttachments : undefined) !== false) {
                                                    inputField.text = "";
                                                    mainChatArea.clearAttachments();
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                            anchors.top: inputContainer.bottom
                            anchors.topMargin: 8
                            anchors.horizontalCenter: inputContainer.horizontalCenter

                            text: Ai.currentModel ? Ai.currentModel.name : ""
                            color: Colors.outline
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            font.weight: Font.Medium

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (!Ai.isLoading) modelSelector.open()
                            }

                            // Same shape as the history page: the fade drives
                            // visibility rather than the other way round.
                            visible: opacity > 0.01
                            opacity: mainChatArea.isWelcome ? 1 : 0

                            Behavior on opacity {
                                enabled: Motion.enabled
                                NumberAnimation {
                                    duration: Motion.normal
                                    easing.type: Easing.OutQuart
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
