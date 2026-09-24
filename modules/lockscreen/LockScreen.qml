pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import qs.modules.components
import qs.modules.corners
import qs.modules.theme
import qs.modules.globals
import qs.config

// Lockscreen, same visual language as the greeter, one idea of its own:
// locking closes the screen into a letterbox. Two dark bars slide in from the
// edges and carry the status lines, like a terminal multiplexer.
//
// Choreography
//   lock     desktop frosts and pushes in slightly, letterbox bars close in,
//            their accent hairlines draw out from the centre, clock rises
//   idle     big clock; top bar: lock state and elapsed time; bottom bar:
//            now playing and the unlock hint
//   engage   any key: clock lifts and shrinks, the card assembles, the
//            first key already lands in the pill
//   unlock   the ring ratchets shut, the bars latch with a small inward
//            kick, then glide out while the blur clears into the desktop
//
// Auth and the shared engaged state live in LockState, so every screen
// moves together. Visual pieces mirror greeter/ (see LockStyle).
WlSessionLockSurface {
    id: root

    // Transparent so the desktop shows through while the lock fades in and out.
    color: "transparent"

    readonly property real unit: Math.max(0.6, height / 1440)
    readonly property real diag: Math.sqrt(width * width + height * height)
    readonly property bool motion: LockStyle.base > 0

    property real lock: 0
    property real rise: 0
    property real t: LockState.engaged ? 1 : 0
    property real leave: 0

    readonly property real engage: LockStyle.outCubic(t)
    readonly property real closed: LockStyle.outQuint(LockStyle.span(lock, 0.15, 1)) * (1 - LockStyle.outCubic(leave))

    Behavior on t {
        enabled: root.motion
        NumberAnimation { duration: LockStyle.dur(3.2); easing.type: Easing.Linear }
    }

    Component.onCompleted: {
        intro.start();
        keys.forceActiveFocus();
    }

    ParallelAnimation {
        id: intro
        NumberAnimation { target: root; property: "lock"; to: 1; duration: LockStyle.dur(5); easing.type: Easing.InOutCubic }
        SequentialAnimation {
            PauseAnimation { duration: LockStyle.dur(1.6) }
            NumberAnimation { target: root; property: "rise"; to: 1; duration: LockStyle.dur(5); easing.type: Easing.Linear }
        }
    }

    Connections {
        target: LockState
        function onSucceeded() {
            card.pill.clear();
            outro.start();
        }
    }

    // Unlock: the ring ratchets shut, the bars latch (a small inward kick),
    // then everything glides open and the blur clears into the desktop.
    property real latch: 0

    SequentialAnimation {
        id: outro
        PauseAnimation { duration: LockStyle.dur(2.2) }        // ring ratchets shut
        NumberAnimation { target: root; property: "latch"; to: 1; duration: LockStyle.dur(0.35); easing.type: Easing.OutCubic }
        PauseAnimation { duration: LockStyle.dur(0.25) }
        ParallelAnimation {
            NumberAnimation { target: root; property: "latch"; to: 0; duration: LockStyle.dur(0.8); easing.type: Easing.InOutCubic }
            NumberAnimation { target: root; property: "leave"; to: 1; duration: LockStyle.dur(3.4); easing.type: Easing.InOutCubic }
        }
        ScriptAction { script: LockState.finish() }
    }

    // ── Background ────────────────────────────────────────────────────────
    function backgroundWallpaper() {
        return root.screen ? GlobalStates.wallpaperForScreen(root.screen.name) : GlobalStates.wallpaperManager;
    }

    function syncLockscreenVideo() {
        if (!wallpaper.isVideo)
            return;
        var wp = backgroundWallpaper();
        wallpaper.videoPlayAt(wp && wp.activeVideo ? wp.activeVideo.positionMs : 0);
    }

    // Follow the background video while locked (seek to 0 on wallpaper sync).
    Connections {
        target: GlobalStates
        function onVideoSyncTickChanged() {
            if (!wallpaper.isVideo)
                return;
            wallpaper.videoSeek(0);
            wallpaper.videoPlay();
        }
    }

    // Soft drift correction against the background video.
    Timer {
        interval: 15000
        running: wallpaper.isVideo
        repeat: true
        onTriggered: {
            var wp = root.backgroundWallpaper();
            if (!wp || !wp.activeVideo || !wallpaper.isVideo)
                return;
            if (Math.abs(wallpaper.videoPosition - wp.activeVideo.positionMs) > 1500)
                wallpaper.videoSeek(wp.activeVideo.positionMs);
        }
    }

    Item {
        id: stage
        anchors.fill: parent
        opacity: (LockStyle.outCubic(LockStyle.span(root.lock, 0, 0.4))) * (1 - LockStyle.outCubic(root.leave))
        scale: 1 + 0.045 * LockStyle.outCubic(root.lock) * (1 - root.leave) + 0.02 * root.engage

        TintedWallpaper {
            id: wallpaper
            anchors.fill: parent
            radius: 0
            tintEnabled: GlobalStates.wallpaperManager ? GlobalStates.wallpaperManager.tintEnabled : false

            property string wallpaperPath: {
                var wp = root.backgroundWallpaper();
                return wp ? wp.effectiveWallpaper : "";
            }

            source: wallpaperPath ? "file://" + wallpaperPath : ""
            posterSource: {
                var wp = root.backgroundWallpaper();
                return wp && wallpaperPath ? wp.getLockscreenFramePath(wallpaperPath) : "";
            }
            onSourceChanged: root.syncLockscreenVideo()
            Component.onCompleted: root.syncLockscreenVideo()

            layer.enabled: true
            layer.effect: MultiEffect {
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 64
                // Lightly frosted while idle so the clock carries, fully
                // frosted behind the card.
                blur: (0.45 * root.lock + 0.45 * root.engage) * (1 - root.leave)
                brightness: (-0.1 * root.lock - 0.16 * root.engage) * (1 - root.leave)
                saturation: 0.1 * root.engage
            }
        }

        // Vignette keeps the centre readable without a flat dim.
        Vignette {
            anchors.fill: parent
        }
    }

    component Vignette: Rectangle {
        color: "transparent"
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.35) }
            GradientStop { position: 0.3; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 0.7; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
        }
        opacity: root.lock * (1 - root.leave)
    }

    // ── Letterbox bars ────────────────────────────────────────────────────
    readonly property real barHeight: 58 * unit

    component Bar: Item {
        id: bar
        property bool atTop: true
        default property alias barContent: inner.data
        width: root.width
        height: root.barHeight
        y: (atTop ? -height * (1 - root.closed) : root.height - height * root.closed)
           + (atTop ? 1 : -1) * 4 * root.unit * root.latch

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(LockStyle.background.r, LockStyle.background.g, LockStyle.background.b, 0.78)
        }

        // Accent hairline on the inner edge, drawn out from the centre.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: bar.atTop ? parent.height - height : 0
            width: parent.width * LockStyle.outQuint(LockStyle.span(root.lock, 0.45, 1)) * (1 - root.leave)
            height: Math.max(1, 1.5 * root.unit)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(LockStyle.primary.r, LockStyle.primary.g, LockStyle.primary.b, 0) }
                GradientStop { position: 0.5; color: LockStyle.primary }
                GradientStop { position: 1.0; color: Qt.rgba(LockStyle.primary.r, LockStyle.primary.g, LockStyle.primary.b, 0) }
            }
            opacity: 0.7
        }

        Item {
            id: inner
            anchors.fill: parent
            anchors.leftMargin: 32 * root.unit
            anchors.rightMargin: 32 * root.unit
            opacity: LockStyle.span(root.rise, 0.3, 0.8) * (1 - LockStyle.span(root.leave, 0, 0.4))
        }
    }

    component Mono: Text {
        font.family: LockStyle.mono
        font.pixelSize: 14 * root.unit
        color: LockStyle.overSurface
    }

    component Icon: Text {
        font.family: LockStyle.iconFont
        font.pixelSize: 15 * root.unit
        color: LockStyle.primary
    }

    // Config.lockscreen.position picks the edge for the player and unlock
    // hint; the status bar takes the other one.
    readonly property bool playerOnTop: Config.lockscreen.position === "top"

    Bar {
        atTop: !root.playerOnTop

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10 * root.unit

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                text: ""
            }
            Mono {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.StyledText
                text: "<b>locked</b>  <font color='" + LockStyle.outline + "'>since " + Qt.formatTime(LockState.lockedAt, "hh:mm") + "</font>"
            }
        }

        Mono {
            anchors.centerIn: parent
            textFormat: Text.StyledText
            text: "<b>" + LockState.user + "</b><font color='" + LockStyle.primary + "'>@" + LockState.host + "</font>"
            opacity: 0.85
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 18 * root.unit

            Row {
                spacing: 8 * root.unit
                visible: LockState.capsLock
                Icon { anchors.verticalCenter: parent.verticalCenter; text: "⇪"; font.family: LockStyle.mono; color: LockStyle.color("yellow", LockStyle.primary) }
                Mono { anchors.verticalCenter: parent.verticalCenter; text: "caps"; color: LockStyle.color("yellow", LockStyle.primary) }
            }
            Row {
                spacing: 8 * root.unit
                visible: LockState.layout !== ""
                Icon { anchors.verticalCenter: parent.verticalCenter; text: "" }
                Mono { anchors.verticalCenter: parent.verticalCenter; text: LockState.layout }
            }
        }
    }

    Bar {
        atTop: root.playerOnTop

        // Now playing, as a status-line segment:
        //   [level meter]  title · artist  │  01:37 ▮▮▮▮▮▯▯▯ 04:03  │  ⏮ ⏯ ⏭
        Row {
            id: media
            readonly property var player: {
                const ps = Mpris.players.values;
                return ps.find(p => p.isPlaying) || ps[0] || null;
            }
            readonly property bool playing: player !== null && player.isPlaying
            readonly property bool timed: player !== null && player.lengthSupported && player.length > 0
            readonly property real progress: timed ? Math.min(1, player.position / player.length) : 0

            function stamp(s) {
                s = Math.max(0, Math.floor(s));
                return String(Math.floor(s / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0");
            }

            visible: player !== null
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 16 * root.unit

            component Divider: Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 16 * root.unit
                color: LockStyle.overSurface
                opacity: 0.18
            }

            component Ctl: Icon {
                id: ctl
                signal activated
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: 13 * root.unit
                color: area.containsMouse ? LockStyle.primary : LockStyle.overSurface
                opacity: area.containsMouse ? 1 : 0.7
                scale: area.pressed ? 0.85 : 1
                Behavior on color { enabled: root.motion; ColorAnimation { duration: LockStyle.dur(0.5) } }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    anchors.margins: -6 * root.unit
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ctl.activated()
                }
            }

            // Level meter: four bars that breathe while playing, flat when paused.
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2 * root.unit
                Repeater {
                    model: 4
                    Rectangle {
                        id: lvl
                        required property int index
                        property real level: 0.25
                        anchors.bottom: parent.bottom
                        width: 3 * root.unit
                        height: 14 * root.unit * level
                        radius: 1
                        color: LockStyle.primary
                        SequentialAnimation on level {
                            running: media.playing && root.motion
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35 + 0.65 * ((lvl.index * 0.37) % 1); duration: 260 + lvl.index * 70; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0.2 + 0.3 * ((lvl.index * 0.61) % 1); duration: 300 + lvl.index * 50; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0.6 + 0.4 * ((lvl.index * 0.23) % 1); duration: 240 + lvl.index * 90; easing.type: Easing.InOutSine }
                        }
                        Binding on level { when: !media.playing; value: 0.2 }
                    }
                }
                height: 14 * root.unit
            }

            Mono {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 380 * root.unit)
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: media.player
                    ? "<b>" + (media.player.trackTitle || "unknown") + "</b>"
                      + (media.player.trackArtist ? "<font color='" + LockStyle.outline + "'>  ·  " + media.player.trackArtist.toLowerCase() + "</font>" : "")
                    : ""
            }

            Divider { visible: media.timed }

            // Timecode with a segmented meter between the stamps.
            Row {
                visible: media.timed
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10 * root.unit

                Mono {
                    anchors.verticalCenter: parent.verticalCenter
                    text: media.stamp(media.player ? media.player.position : 0)
                    font.pixelSize: 12 * root.unit
                    color: LockStyle.primary
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2 * root.unit
                    Repeater {
                        model: 24
                        Rectangle {
                            required property int index
                            readonly property bool lit: (index + 1) / 24 <= media.progress + 0.001
                            readonly property bool head: !lit && index / 24 < media.progress
                            width: 3 * root.unit
                            height: 8 * root.unit
                            radius: 0.5
                            color: lit || head ? LockStyle.primary : LockStyle.overSurface
                            opacity: lit ? 0.9 : head ? 0.45 : 0.14
                            Behavior on opacity { enabled: root.motion; NumberAnimation { duration: LockStyle.dur(1) } }
                        }
                    }
                }
                Mono {
                    anchors.verticalCenter: parent.verticalCenter
                    text: media.stamp(media.player ? media.player.length : 0)
                    font.pixelSize: 12 * root.unit
                    color: LockStyle.outline
                }
            }

            Divider {}

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14 * root.unit
                Ctl { text: ""; onActivated: media.player.previous() }
                Ctl { text: media.playing ? "" : ""; onActivated: media.player.togglePlaying() }
                Ctl { text: ""; onActivated: media.player.next() }
            }

            Timer {
                interval: 1000
                repeat: true
                running: media.playing
                onTriggered: media.player.positionChanged()
            }
        }

        // Unlock hint, fades once the card is up.
        Row {
            anchors.centerIn: parent
            spacing: 8 * root.unit
            opacity: 1 - LockStyle.span(root.t, 0, 0.35)

            Mono { text: "❯"; font.weight: Font.Bold; color: LockStyle.primary }
            Mono { text: "type to unlock" }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 8 * root.unit
                height: 16 * root.unit
                radius: 1.5 * root.unit
                color: LockStyle.overSurface
                opacity: hintBlink.on ? 0.85 : 0
                Timer {
                    id: hintBlink
                    property bool on: true
                    interval: 530
                    running: root.motion && !LockState.engaged
                    repeat: true
                    onTriggered: on = !on
                }
            }
        }

    }

    // ── Clock ─────────────────────────────────────────────────────────────
    LockClock {
        id: clock
        unit: root.unit
        rise: root.rise
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * (0.47 - 0.21 * root.engage) - height / 2
           - 60 * root.unit * LockStyle.outCubic(root.leave)
        scale: 1 - 0.44 * root.engage
        opacity: 1 - LockStyle.outCubic(LockStyle.span(root.leave, 0, 0.6))
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: LockStyle.shadow
            shadowOpacity: 0.55
            shadowBlur: 1.0
            shadowVerticalOffset: 6 * root.unit
        }
    }

    // ── Card ──────────────────────────────────────────────────────────────
    LockCard {
        id: card
        visible: root.t > 0
        unit: root.unit
        t: root.t
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.6 - height / 2
           + 50 * root.unit * (1 - root.engage)
           - 70 * root.unit * LockStyle.outCubic(root.leave)
        opacity: 1 - LockStyle.outCubic(LockStyle.span(root.leave, 0, 0.6))
    }

    // ── Input ─────────────────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        property point last: Qt.point(-1, -1)
        onPositionChanged: mouse => {
            if (last.x >= 0 && (Math.abs(mouse.x - last.x) + Math.abs(mouse.y - last.y)) > 6)
                LockState.activity();
            last = Qt.point(mouse.x, mouse.y);
        }
        onClicked: LockState.activity()
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_CapsLock)
                LockState.capsKey();
            if (!LockState.engaged) {
                LockState.activity();
                if (event.text.length > 0 && event.text.charCodeAt(0) >= 32)
                    card.pill.insert(event.text);
                event.accepted = true;
            }
        }
    }

    Connections {
        target: LockState
        function onEngagedChanged() {
            if (LockState.engaged) {
                card.pill.focusInput();
            } else {
                card.pill.clear();
                keys.forceActiveFocus();
            }
        }
    }

    // Shortcut, not Keys: the focused pill would swallow Escape otherwise.
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (LockState.engaged && LockState.phase === "idle")
                LockState.disengage();
        }
    }

    Connections {
        target: card.pill
        function onTextChanged() { LockState.activity(); }
    }

    // ── Screen corners ────────────────────────────────────────────────────
    RoundCorner {
        size: Styling.radius(4)
        anchors.left: parent.left
        anchors.top: parent.top
        corner: RoundCorner.CornerEnum.TopLeft
        z: 100
    }
    RoundCorner {
        size: Styling.radius(4)
        anchors.right: parent.right
        anchors.top: parent.top
        corner: RoundCorner.CornerEnum.TopRight
        z: 100
    }
    RoundCorner {
        size: Styling.radius(4)
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        corner: RoundCorner.CornerEnum.BottomLeft
        z: 100
    }
    RoundCorner {
        size: Styling.radius(4)
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        corner: RoundCorner.CornerEnum.BottomRight
        z: 100
    }
}
