import QtQuick

// The greeter clock (greeter/Clock.qml) on the live shell theme.
//
// `rise` (0..1) drives the entrance: each glyph lifts in slightly after the one
// before it, the accent line draws out, then the date settles.
Column {
    id: root

    property real unit: 1
    property real rise: 1
    property date now: new Date()

    spacing: 10 * unit

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    readonly property string hours: LockStyle.use12h ? String(now.getHours() % 12 || 12).padStart(2, "0") : Qt.formatTime(now, "hh")
    readonly property string minutes: Qt.formatTime(now, "mm")

    component Glyph: LockRollingText {
        id: glyph
        property int order: 0
        readonly property real local: LockStyle.outCubic(LockStyle.span(root.rise, order * 0.09, order * 0.09 + 0.55))
        font.family: LockStyle.clockFont
        font.pixelSize: 250 * root.unit
        opacity: local
        transform: Translate { y: (1 - glyph.local) * 70 * root.unit }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6 * root.unit

        Glyph { id: firstGlyph; order: 0; text: root.hours.charAt(0) }
        Glyph { order: 1; text: root.hours.charAt(1) }

        // Colon as two dots: the font's own colon is square and reads heavy.
        Item {
            id: colon
            width: 34 * root.unit
            height: firstGlyph.implicitHeight
            readonly property real local: LockStyle.outCubic(LockStyle.span(root.rise, 0.18, 0.7))
            opacity: local * pulse

            property real pulse: 1
            SequentialAnimation on pulse {
                running: LockStyle.base > 0
                loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 1000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 1000; easing.type: Easing.InOutSine }
            }

            Repeater {
                model: 2
                Rectangle {
                    width: 17 * root.unit
                    height: width
                    radius: width / 2
                    color: LockStyle.primary
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * (index === 0 ? 0.36 : 0.62) - height / 2
                    scale: colon.local
                }
            }
        }

        Glyph { order: 2; text: root.minutes.charAt(0) }
        Glyph { order: 3; text: root.minutes.charAt(1) }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 64 * root.unit * LockStyle.outQuint(LockStyle.span(root.rise, 0.35, 0.9))
        height: 3 * root.unit
        radius: height / 2
        color: LockStyle.primary
        opacity: 0.8
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        readonly property real local: LockStyle.outCubic(LockStyle.span(root.rise, 0.45, 1))
        text: root.now.toLocaleDateString(Qt.locale(), "dddd, d. MMMM yyyy").toLowerCase()
        font.family: LockStyle.mono
        font.pixelSize: 18 * root.unit
        font.letterSpacing: 2 * root.unit * (0.6 + 0.4 * local)
        color: LockStyle.overSurface
        opacity: 0.9 * local
    }
}
