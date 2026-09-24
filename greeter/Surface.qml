import QtQuick
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import Quickshell.Wayland

// One full-screen layer per monitor. The primary (largest) screen carries the
// clock and login card; the others show the same wallpaper and follow the
// same blur, so all screens move as one.
//
// Choreography
//   reveal   an iris opens from the centre while the wallpaper pulls into
//            focus and settles from a slight zoom; clock digits rise in turn
//   ambient  still wallpapers drift very slowly; faint motes of accent light
//            float upward
//   engage   first key or pointer move: the wallpaper blurs and dims, the
//            clock lifts and shrinks, the glass card assembles in sequence
//   idle     25 s without input plays engage backwards and clears the field
//   success  the avatar ring ratchets shut, the UI glides away as the blur
//            clears, and everything fades to black for the hand-off
PanelWindow {
    id: root

    property bool primary: false

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ambxst-greeter"
    WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "black"

    readonly property real unit: Math.max(0.6, height / 1440)
    readonly property real diag: Math.sqrt(width * width + height * height)
    readonly property bool motion: Theme.base > 0

    // Every visual reads from these timelines, so an interrupted transition
    // simply retargets from wherever it currently is.
    property real reveal: 0
    property real rise: 0
    property real t: Session.engaged ? 1 : 0
    property real leave: 0

    readonly property real engage: Theme.outCubic(t)

    Behavior on t {
        enabled: root.motion
        NumberAnimation { duration: Theme.dur(3.4); easing.type: Easing.Linear }
    }

    Component.onCompleted: revealWait.start()

    // Wait for the first wallpaper frame, but never longer than 1.5 s.
    Timer {
        id: revealWait
        interval: 16
        repeat: true
        property int ticks: 0
        onTriggered: {
            ticks++;
            if (wallpaper.ready || ticks > 90) {
                stop();
                intro.start();
            }
        }
    }

    ParallelAnimation {
        id: intro
        NumberAnimation { target: root; property: "reveal"; to: 1; duration: Theme.dur(6); easing.type: Easing.InOutCubic }
        SequentialAnimation {
            PauseAnimation { duration: Theme.dur(2.2) }
            NumberAnimation { target: root; property: "rise"; to: 1; duration: Theme.dur(5); easing.type: Easing.Linear }
        }
    }

    Connections {
        target: Session
        function onSucceeded() { outro.start(); }
    }

    SequentialAnimation {
        id: outro
        PauseAnimation { duration: Theme.dur(2.8) }        // ring ratchets shut
        NumberAnimation { target: root; property: "leave"; to: 1; duration: Theme.dur(4.2); easing.type: Easing.InOutCubic }
        ScriptAction { script: if (root.primary) Session.launch(); }
    }

    // Slow drift for still wallpapers, so the idle screen is never frozen.
    property real drift: 0
    SequentialAnimation on drift {
        running: root.motion && Theme.wallpaperKind === "image"
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 26000; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0; duration: 26000; easing.type: Easing.InOutSine }
    }

    // ── Wallpaper ─────────────────────────────────────────────────────────
    Item {
        id: stage
        anchors.fill: parent
        opacity: 1 - root.leave
        scale: 1.12 - 0.12 * root.reveal
               + 0.035 * root.engage * (1 - root.leave)
               + 0.03 * root.drift
        transform: Translate { x: (root.drift - 0.5) * 36 * root.unit }

        Wallpaper {
            id: wallpaper
            anchors.fill: parent
            layer.enabled: true
            visible: false
        }

        // Iris mask for the reveal; dropped once fully open.
        Item {
            id: iris
            anchors.fill: parent
            layer.enabled: true
            visible: false
            Rectangle {
                anchors.centerIn: parent
                width: root.diag * 1.15 * root.reveal
                height: width
                radius: width / 2
            }
        }

        MultiEffect {
            anchors.fill: parent
            source: wallpaper
            autoPaddingEnabled: false
            maskEnabled: root.reveal < 1
            maskSource: iris
            maskThresholdMin: 0.15
            maskSpreadAtMin: 1.0
            blurEnabled: true
            blurMax: 64
            // Focus pull during reveal, frosted while engaged.
            blur: Math.max((1 - root.reveal) * 0.9, 0.85 * root.engage * (1 - root.leave))
            brightness: -0.22 * root.engage * (1 - root.leave)
            saturation: 0.12 * root.engage
        }

        // Soft floor and ceiling shade so light text stays readable.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.22) }
                GradientStop { position: 0.4; color: Qt.rgba(0, 0, 0, 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
            }
            opacity: 0.55 + 0.45 * root.engage
        }
    }

    // ── Ambient light ─────────────────────────────────────────────────────
    ParticleSystem {
        id: motes
        anchors.fill: parent
        running: root.motion && root.leave < 1
    }

    ImageParticle {
        system: motes
        source: "qrc:///particleresources/glowdot.png"
        color: Theme.primary
        colorVariation: 0.08
        alpha: 0.45
        alphaVariation: 0.25
        entryEffect: ImageParticle.Fade
        opacity: root.rise * (0.8 - 0.4 * root.engage) * (1 - root.leave)
    }

    Emitter {
        system: motes
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * 0.4
        emitRate: root.motion ? 5 : 0
        lifeSpan: 11000
        lifeSpanVariation: 3000
        size: 14 * root.unit
        sizeVariation: 10 * root.unit
        endSize: 4 * root.unit
        velocity: AngleDirection {
            angle: -90
            angleVariation: 18
            magnitude: 26 * root.unit
            magnitudeVariation: 14 * root.unit
        }
        acceleration: PointDirection { xVariation: 3 * root.unit }
    }

    // ── Clock ─────────────────────────────────────────────────────────────
    Clock {
        id: clock
        visible: root.primary
        unit: root.unit
        rise: root.rise
        anchors.horizontalCenter: parent.horizontalCenter
        // Idle: optical centre. Engaged: lifted, the card takes the centre.
        y: parent.height * (0.46 - 0.2 * root.engage) - height / 2
           - 60 * root.unit * Theme.outCubic(root.leave)
        scale: 1 - 0.44 * root.engage
        opacity: 1 - root.leave
        // Soft shadow keeps the light digits readable on bright wallpapers.
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowOpacity: 0.55
            shadowBlur: 1.0
            shadowVerticalOffset: 6 * root.unit
        }
    }

    // ── Hint ──────────────────────────────────────────────────────────────
    Row {
        visible: root.primary
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 110 * root.unit - 24 * root.unit * root.engage
        spacing: 8 * root.unit
        opacity: Theme.span(root.rise, 0.6, 1) * (1 - Theme.span(root.t, 0, 0.35))

        Text {
            text: "\u276f"
            font.family: Theme.mono
            font.pixelSize: 15 * root.unit
            font.weight: Font.Bold
            color: Theme.primary
        }
        Text {
            text: "press any key"
            font.family: Theme.mono
            font.pixelSize: 15 * root.unit
            color: Theme.overSurface
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 8 * root.unit
            height: 16 * root.unit
            radius: 1.5 * root.unit
            color: Theme.overSurface
            opacity: hintBlink.on ? 0.85 : 0
            Timer {
                id: hintBlink
                property bool on: true
                interval: 530
                running: root.motion && !Session.engaged
                repeat: true
                onTriggered: on = !on
            }
        }
    }

    // ── Login card ────────────────────────────────────────────────────────
    LoginCard {
        id: card
        visible: root.primary && root.t > 0
        unit: root.unit
        t: root.t
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.6 - height / 2
           + 50 * root.unit * (1 - root.engage)
           - 70 * root.unit * Theme.outCubic(root.leave)
        opacity: 1 - root.leave
    }

    // ── Weather ───────────────────────────────────────────────────────────
    // The sidepanel's animated sky, with the location underneath. Hidden when
    // the last fetch from the user session is missing or stale.
    Column {
        id: weather
        visible: root.primary && Weather.dataAvailable
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 40 * root.unit
        spacing: 10 * root.unit
        readonly property real local: Theme.outCubic(Theme.span(root.rise, 0.55, 1))
        opacity: local * (1 - 0.35 * root.engage) * (1 - root.leave)
        transform: Translate { y: (1 - weather.local) * -16 * root.unit }

        WeatherSky {
            width: 300 * root.unit
            height: 150 * root.unit
            cornerRadius: 22 * root.unit * Math.min(1, Theme.roundness / 16)
            fontSize: 14 * root.unit
            animationsEnabled: root.motion && root.leave < 1
        }

        Row {
            anchors.right: parent.right
            spacing: 6 * root.unit
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\ue316"
                font.family: Theme.iconFont
                font.pixelSize: 14 * root.unit
                color: Theme.primary
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Weather.location.toLowerCase()
                font.family: Theme.mono
                font.pixelSize: 14 * root.unit
                color: Theme.overSurface
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowOpacity: 0.45
            shadowBlur: 0.8
            shadowVerticalOffset: 6 * root.unit
        }
    }

    // ── Splash quote ──────────────────────────────────────────────────────
    // Sits under the clock's visual bottom (the clock scales about its
    // centre), so it rides up with the clock when the login card appears.
    Splash {
        visible: root.primary && opacity > 0
        unit: root.unit
        anchors.horizontalCenter: parent.horizontalCenter
        y: clock.y + clock.height * (0.5 + 0.5 * clock.scale) + (44 - 20 * root.engage) * root.unit
        opacity: Theme.span(root.rise, 0.7, 1) * (1 - root.leave)
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowOpacity: 0.9
            shadowBlur: 0.8
            shadowVerticalOffset: 2 * root.unit
        }
    }

    // ── Power ─────────────────────────────────────────────────────────────
    Row {
        visible: root.primary
        layoutDirection: Qt.RightToLeft
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 36 * root.unit
        spacing: 10 * root.unit
        opacity: Theme.span(root.rise, 0.7, 1) * (0.6 + 0.4 * root.engage) * (1 - root.leave)

        PowerButton {
            unit: root.unit
            icon: ""
            label: "poweroff"
            onActivated: Session.power("poweroff")
        }
        PowerButton {
            unit: root.unit
            icon: ""
            label: "reboot"
            onActivated: Session.power("reboot")
        }
    }

    // ── Input ─────────────────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: root.primary
        hoverEnabled: true
        property point last: Qt.point(-1, -1)
        onPositionChanged: mouse => {
            // Ignore the synthetic event from a pointer already resting here.
            if (last.x >= 0 && (Math.abs(mouse.x - last.x) + Math.abs(mouse.y - last.y)) > 6)
                Session.activity();
            last = Qt.point(mouse.x, mouse.y);
        }
        onClicked: Session.activity()
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: root.primary

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (Session.engaged && Session.phase === "idle")
                    Session.disengage();
                else if (Session.mock && !Session.engaged)
                    Qt.quit();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_CapsLock)
                Info.capsKey();
            if (!Session.engaged) {
                Session.activity();
                if (event.text.length > 0 && event.text.charCodeAt(0) >= 32)
                    card.pill.insert(event.text);
                event.accepted = true;
            }
        }
    }

    Connections {
        target: Session
        function onEngagedChanged() {
            if (!root.primary)
                return;
            if (Session.engaged) {
                card.pill.focusInput();
            } else {
                card.pill.clear();
                keys.forceActiveFocus();
            }
        }
    }

    // Keystrokes in the pill count as activity.
    Connections {
        target: card.pill
        function onTextChanged() { Session.activity(); }
    }

    // Final black: the session's Hyprland starts on a dark screen, so ending
    // on black makes the hand-off one continuous motion.
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: Theme.span(root.leave, 0.35, 1)
    }
}
