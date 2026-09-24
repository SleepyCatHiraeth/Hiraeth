import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// Avatar, name, password pill and status line, floating on the blurred wallpaper.
//
// `t` (0..1) is the engage timeline. Elements arrive in sequence: the avatar
// springs in, the name follows, and the password pill
// grows out of a circle into its full width. Running `t` backwards dismisses
// them in reverse order.
Item {
    id: root

    property real unit: 1
    property real t: 1
    property alias pill: pill

    readonly property real avatarIn: Theme.span(t, 0.0, 0.55)
    readonly property real nameIn: Theme.outCubic(Theme.span(t, 0.14, 0.66))
    readonly property real pillIn: Theme.outQuint(Theme.span(t, 0.24, 1.0))

    width: 460 * unit
    height: content.implicitHeight + 76 * unit

    Column {
        id: content
        anchors.centerIn: parent
        spacing: 16 * root.unit

        // ── Avatar ────────────────────────────────────────────────────────
        Item {
            id: avatarBox
            anchors.horizontalCenter: parent.horizontalCenter
            width: 112 * root.unit
            height: width
            opacity: Math.min(1, root.avatarIn * 2)
            scale: 0.4 + 0.6 * Theme.outBack(root.avatarIn)

            // Soft glow in the accent colour, brighter while checking.
            RectangularShadow {
                anchors.fill: avatarBase
                radius: width / 2
                blur: 40 * root.unit
                color: root.failFlash > 0 ? Theme.error : Theme.primary
                opacity: Session.phase === "authenticating" ? 0.55 : Session.phase === "success" ? 0.85 : 0.18 + 0.5 * root.failFlash
                Behavior on opacity {
                    enabled: Theme.base > 0
                    NumberAnimation { duration: Theme.dur(1.6); easing.type: Easing.InOutSine }
                }
            }

            Rectangle {
                id: avatarBase
                anchors.centerIn: parent
                width: parent.width - 16 * root.unit
                height: width
                radius: width / 2
                color: Theme.surfaceContainerHigh

                Text {
                    anchors.centerIn: parent
                    visible: avatarImage.status !== Image.Ready
                    text: (Theme.user || "?").charAt(0).toUpperCase()
                    font.family: Theme.clockFont
                    font.pixelSize: parent.height * 0.62
                    color: Theme.primary
                }
            }

            Image {
                id: avatarImage
                anchors.fill: avatarBase
                source: Theme.avatar
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                mipmap: true
                visible: false
            }

            MultiEffect {
                anchors.fill: avatarBase
                source: avatarImage
                visible: avatarImage.status === Image.Ready
                maskEnabled: true
                maskSource: avatarMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }

            Item {
                id: avatarMask
                anchors.fill: avatarBase
                layer.enabled: true
                layer.smooth: true
                visible: false
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                }
            }

            // Track + progress ring.
            Shape {
                id: ring
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                property real sweep: Session.phase === "success" ? 360 : Session.phase === "authenticating" ? 100 : 0
                Behavior on sweep {
                    enabled: Theme.base > 0
                    NumberAnimation { duration: Theme.dur(2.2); easing.type: Easing.InOutCubic }
                }
                RotationAnimation on rotation {
                    running: Session.phase === "authenticating"
                    loops: Animation.Infinite
                    from: 0; to: 360
                    duration: 1000
                }

                ShapePath {
                    strokeColor: root.failFlash > 0
                        ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.2 + 0.8 * root.failFlash)
                        : Qt.rgba(Theme.overSurface.r, Theme.overSurface.g, Theme.overSurface.b, 0.12)
                    strokeWidth: 2 * root.unit
                    fillColor: "transparent"
                    PathAngleArc {
                        centerX: ring.width / 2; centerY: ring.height / 2
                        radiusX: ring.width / 2 - 2 * root.unit; radiusY: radiusX
                        startAngle: 0; sweepAngle: 360
                    }
                }
                ShapePath {
                    strokeColor: Theme.primary
                    strokeWidth: 3.5 * root.unit
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: ring.width / 2; centerY: ring.height / 2
                        radiusX: ring.width / 2 - 2 * root.unit; radiusY: radiusX
                        startAngle: -90; sweepAngle: ring.sweep
                    }
                }
            }
        }

        // ── Name ──────────────────────────────────────────────────────────
        // Greeting above, user@host like a shell prompt.
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6 * root.unit
            opacity: root.nameIn
            transform: Translate { y: (1 - root.nameIn) * 14 * root.unit }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Info.greeting + ","
                font.family: Theme.mono
                font.pixelSize: 13 * root.unit
                color: Theme.overSurface
                opacity: 0.6
            }

            // user@host as one prompt, in the terminal font.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.StyledText
                text: "<b>" + Theme.user + "</b>"
                      + (Info.host ? "<font color='" + Theme.primary + "'>@" + Info.host + "</font>" : "")
                font.family: Theme.mono
                font.pixelSize: 22 * root.unit
                color: Theme.overSurface
            }
        }

        Item { width: 1; height: 2 * root.unit }

        // ── Password ──────────────────────────────────────────────────────
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 260 * root.unit
            height: pill.height

            PasswordPill {
                id: pill
                anchors.centerIn: parent
                unit: root.unit
                // Grows from a circle to the full pill.
                width: height + (parent.width - height) * root.pillIn
                contentOpacity: Theme.span(root.pillIn, 0.55, 1)
                opacity: Theme.span(root.t, 0.24, 0.44)
                busy: Session.phase !== "idle"
                onSubmitted: password => Session.login(password)
            }
        }

        // ── Status ────────────────────────────────────────────────────────
        // Error line, or the Caps Lock warning when there is no error. Keeps
        // its height so the card never jumps when a message appears.
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 260 * root.unit
            height: 18 * root.unit

            Text {
                id: status
                anchors.horizontalCenter: parent.horizontalCenter
                property string shownText: ""
                text: "\u2717 " + shownText.toLowerCase()
                font.family: Theme.mono
                font.pixelSize: 13 * root.unit
                color: Theme.error
                opacity: 0
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "[caps lock]"
                font.family: Theme.mono
                font.pixelSize: 13 * root.unit
                color: Theme.color("yellow", Theme.primary)
                opacity: Info.capsLock && status.opacity < 0.05 ? root.pillIn : 0
                Behavior on opacity {
                    enabled: Theme.base > 0
                    NumberAnimation { duration: 90 }
                }
            }
        }

        // ── Meta ──────────────────────────────────────────────────────────
        // last login · updates · layout, like a login banner.
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property var parts: {
                const p = [];
                if (Info.lastLoginText)
                    p.push("last login " + Info.lastLoginText);
                // Pending updates in the accent colour: the one item that asks
                // for action.
                if (Info.updates > 0)
                    p.push("<font color='" + Theme.primary + "'>\u2191 " + Info.updates + (Info.updates === 1 ? " update" : " updates") + "</font>");
                if (Info.layout)
                    p.push(Info.layout);
                return p;
            }
            textFormat: Text.StyledText
            text: parts.join("  \u00b7  ")
            font.family: Theme.mono
            font.pixelSize: 12 * root.unit
            color: Theme.overSurface
            opacity: 0.7 * Theme.span(root.t, 0.5, 1)
        }
    }

    property real failFlash: 0

    Connections {
        target: Session
        function onFailed(message) {
            pill.reject();
            status.shownText = message;
            statusIn.restart();
            ringFlash.restart();
        }
        function onPhaseChanged() {
            if (Session.phase === "authenticating")
                statusOut.restart();
        }
    }

    SequentialAnimation {
        id: ringFlash
        NumberAnimation { target: root; property: "failFlash"; to: 1; duration: 90 }
        PauseAnimation { duration: 500 }
        NumberAnimation { target: root; property: "failFlash"; to: 0; duration: 700; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: statusIn
        NumberAnimation { target: status; property: "opacity"; to: 1; duration: Theme.dur(1); easing.type: Easing.OutCubic }
        NumberAnimation { target: status; property: "y"; from: -8 * root.unit; to: 0; duration: Theme.dur(1.4); easing.type: Easing.OutBack }
    }

    NumberAnimation {
        id: statusOut
        target: status; property: "opacity"; to: 0
        duration: Theme.dur(0.6)
    }
}
