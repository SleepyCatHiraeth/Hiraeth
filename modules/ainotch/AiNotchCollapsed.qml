import QtQuick
import qs.modules.services
import qs.modules.theme
import qs.modules.turret
import qs.config

// Resting content of the AI notch: one ring per provider showing how much of
// its five-hour window is spent, and a dot that pulses while a reply is
// streaming, so the notch answers both "how much is left?" and "is it still
// working?" without being opened.
//
// AiUsage selects fresh readings and coordinates fallback refresh with the
// dashboard plugin. Unknown readings fall back to the assistant glyph.
Item {
    id: root

    property bool hovered: false

    readonly property bool busy: Ai.isLoading

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
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-4)
    }
    readonly property int cellHeight: 30 + Math.ceil(usageFont.height)
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

    Column {
        anchors.centerIn: parent
        spacing: 10
        visible: root.showUsage && !root.turretBusy

        Repeater {
            model: root.showUsage ? root.usageProviders : []

            delegate: AiUsageCell {
                required property var modelData
                readonly property var reading: root.usageSnapshot.providers[modelData]
                providerId: modelData
                label: reading ? reading.name : modelData
                usedPercent: reading ? reading.usedPercent : 0
                stale: AiUsage.providerStale(modelData)
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
            font.pixelSize: root.hovered ? 20 : 18
            color: root.hovered ? Styling.srItem("overprimary") : Colors.overSurface

            Behavior on font.pixelSize {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on color {
                enabled: Config.animDuration > 0
                ColorAnimation {
                    duration: Config.animDuration / 2
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
                enabled: Config.animDuration > 0
                ColorAnimation {
                    duration: Config.animDuration
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
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration / 2
                easing.type: Easing.OutCubic
            }
        }

        SequentialAnimation on scale {
            running: root.visible && root.busy && !root.turretBusy && Config.animDuration > 0
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation {
                to: 1.6
                duration: 520
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                to: 1.0
                duration: 520
                easing.type: Easing.InOutSine
            }
        }
    }
}
