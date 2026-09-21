import QtQuick
import qs.modules.services
import qs.modules.theme
import qs.modules.components
import qs.modules.turret
import qs.config
import "NotchEdge.js" as NotchEdge

// Resting content of the AI notch: one ring per provider showing how much of
// its five-hour window is spent, and a moving filament while a reply is
// streaming, so the notch answers both "how much is left?" and "is it still
// working?" without being opened.
//
// AiUsage selects fresh readings and coordinates fallback refresh with the
// dashboard plugin. Unknown readings fall back to the assistant glyph.
Item {
    id: root

    property bool hovered: false
    property string edge: "right"
    readonly property bool transparentPill: Config.ai.notchTransparentPill ?? true
    readonly property rect glassInset: transparentPill
        ? Qt.rect(statsBubble.x, statsBubble.y, statsBubble.width, statsBubble.height)
        : Qt.rect(0, 0, 0, 0)
    readonly property real glassRadius: statsBubble.radius

    readonly property bool busy: Ai.isLoading
    readonly property var filamentGeometry: NotchEdge.filamentGeometry(edge, width, height, 2, 3)

    // The turret's voice state takes over the notch while a spoken turn is
    // running. This is the whole point of folding its notch into this one:
    // listening, thinking and speaking are states worth seeing without opening
    // anything, and there is now one place to see them.
    //
    // TurretStateStyle is a pure lookup table, so the colours and glyphs here
    // are the same ones the old turret notch used -- not a second set that
    // could drift.
    readonly property bool turretBusy: TurretService.busy
    readonly property string turretState: TurretService.state

    // AiUsage owns the reading: it prefers the AI Overview Control plugin's own
    // published snapshot and only polls the helper itself when the plugin has
    // not (a dashboard plugin does not run until its tab is first opened).
    readonly property var usageSnapshot: AiUsage.snapshot

    readonly property bool usageEnabled: Config.ai.notchUsageEnabled ?? true

    FontMetrics {
        id: usageFont
        font.family: Config.theme.monoFont
        font.pixelSize: Styling.monoFontSize(-2)
    }
    readonly property int cellHeight: 34 + Math.ceil(usageFont.height)
    // Leave room for the busy indicator even before a request starts.
    readonly property int maxUsageCells: Math.max(0, Math.min(3, Math.floor((height - 16 + 10) / (cellHeight + 10))))
    readonly property string providerSelection: {
        if (!usageEnabled || !usageSnapshot || maxUsageCells === 0)
            return "";
        const pinned = Config.ai.notchUsageProviders ?? [];
        const wanted = pinned.length > 0 ? pinned : AiUsage.providers;
        return Array.from(new Set(wanted)).filter(id => {
            const entry = usageSnapshot.providers[id];
            return entry && entry.windowMinutes === 300 && Number.isFinite(entry.usedPercent);
        }).slice(0, maxUsageCells).join(",");
    }
    // Stable ids preserve ring delegates and their arc animation on refresh.
    readonly property var usageProviders: providerSelection ? providerSelection.split(",") : []
    readonly property bool showUsage: usageProviders.length > 0

    StyledRect {
        id: statsBubble
        visible: root.transparentPill
        anchors.centerIn: parent
        width: Math.max(0, parent.width - 18)
        height: Math.max(0, Math.min(parent.height - 4,
            root.showUsage && !root.turretBusy ? usageColumn.implicitHeight + 6 : width * 1.8))
        variant: "bg"
        backgroundOpacity: root.hovered ? 0.58 : 0.7
        radius: Math.min(width / 2, Styling.radius(4))
        animateRadius: false
        enableBorder: false

        Behavior on height {
            enabled: Motion.enabled && root.visible
            NumberAnimation { duration: Motion.normal; easing.type: Motion.fastEasing }
        }

        Behavior on backgroundOpacity {
            enabled: Motion.enabled && root.visible
            NumberAnimation { duration: Motion.fast; easing.type: Motion.fastEasing }
        }
    }

    Column {
        id: usageColumn
        anchors.centerIn: parent
        spacing: 10
        visible: opacity > 0.01 && !root.turretBusy
        opacity: root.showUsage && !root.turretBusy ? 1 : 0
        scale: 0.96 + 0.04 * opacity

        Behavior on opacity {
            enabled: Motion.enabled
            NumberAnimation { duration: Motion.normal; easing.type: Motion.normalEasing }
        }

        Repeater {
            model: root.showUsage ? root.usageProviders : []

            delegate: AiUsageCell {
                required property var modelData
                readonly property var reading: root.usageSnapshot.providers[modelData]
                providerId: modelData
                edge: root.edge
                label: reading ? reading.name : modelData
                usedPercent: reading ? reading.usedPercent : 0
                stale: AiUsage.providerStale(modelData)
                resetsAt: reading ? (reading.resetsAt || "") : ""
                hovered: root.hovered
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 6
        visible: !root.showUsage && !root.turretBusy

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Icons.assistant
            font.family: Icons.font
            font.pixelSize: 18
            scale: root.hovered ? 1.1 : 1
            color: root.hovered ? Styling.srItem("overprimary") : Colors.overSurface

            Behavior on scale {
                enabled: Motion.enabled
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on color {
                enabled: Motion.enabled
                ColorAnimation {
                    duration: Motion.fast
                }
            }
        }
    }

    Item {
        id: filament
        x: root.filamentGeometry.x
        y: root.filamentGeometry.y
        width: root.filamentGeometry.width
        height: root.filamentGeometry.height
        visible: root.busy
        clip: true

        Rectangle {
            id: filamentSegment
            width: parent.width
            height: Motion.enabled ? Math.max(16, parent.height / 3) : parent.height
            y: Motion.enabled ? -height : 0
            radius: width / 2
            color: Styling.srItem("overprimary")

            SequentialAnimation on y {
                running: root.visible && filament.visible && Motion.enabled
                loops: Animation.Infinite
                NumberAnimation {
                    from: -filamentSegment.height
                    to: filament.height
                    duration: Motion.ambient * 2
                    easing.type: Motion.ambientEasing
                }
            }
        }
    }

    // Turret face: the state glyph over the state dot, both driven by the same
    // lookup table the turret notch used.
    Column {
        anchors.centerIn: parent
        spacing: 5
        visible: root.turretBusy

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: TurretStateStyle.glyph(root.turretState)
            font.family: Icons.font
            font.pixelSize: 18
            color: TurretStateStyle.accent(root.turretState)

            Behavior on color {
                enabled: Motion.enabled
                ColorAnimation {
                    duration: Motion.normal
                }
            }
        }

        TurretStateDot {
            anchors.horizontalCenter: parent.horizontalCenter
            accent: TurretStateStyle.accent(root.turretState)
            // The microphone pulse is a privacy indicator, not decoration: it
            // means the mic is OPEN and it outranks the busy halo.
            pulsing: TurretService.capturing
            spinning: TurretStateStyle.animated(root.turretState)
            // Nothing animates off-screen, the same gate the rings use.
            live: root.visible
        }
    }

    // Streaming indicator, shown in both states: below the glyph when there is
    // nothing else, tucked under the rings when there is.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        width: 5
        height: 5
        radius: 2.5
        color: Colors.overSurface
        opacity: (root.busy && !root.turretBusy) ? 1 : 0

        Behavior on opacity {
            enabled: Motion.enabled
            NumberAnimation {
                duration: Motion.fast
                easing.type: Easing.OutCubic
            }
        }

    }
}
