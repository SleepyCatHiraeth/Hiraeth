pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "UsageSnapshot.js" as UsageSnapshot

// The plugin and fallback share one runtime owner slot. A fresh dashboard is
// not loaded yet, so the fallback remains useful without multiplying requests.
Singleton {
    id: root

    readonly property string pluginId: "ai-overview-control"
    readonly property string stateKey: "ai.usageSnapshot"
    readonly property string ownerKey: "usageRefreshOwner"
    readonly property string helperPath: PluginService.pluginsDir + "/" + pluginId + "/providers/get-provider-usage"
    readonly property bool pluginEnabled: PluginService.dashboardPlugins.some(plugin => plugin.id === root.pluginId)
    readonly property bool enabled: pluginEnabled && (Config.ai.notchUsageEnabled ?? true) && (Config.ai.notchEnabled ?? true)
    readonly property int refreshMinutes: {
        const minutes = Number(PluginService.get(pluginId, "refreshMinutes", 10));
        return Number.isFinite(minutes) ? Math.max(1, Math.min(60, minutes)) : 10;
    }
    readonly property string providerSelection: {
        const selected = PluginService.get(pluginId, "providers", ["claude", "codex"]);
        return Array.isArray(selected) ? Array.from(new Set(selected.filter(id => typeof id === "string" && /^[a-z0-9-]+$/.test(id)))).join(",") : "";
    }
    readonly property var providers: providerSelection ? providerSelection.split(",") : []
    readonly property var pluginSnapshot: PluginService.runtimeValue(pluginId, "usage", null)
        || PluginService.get(pluginId, "usageSnapshot", null)
    property var ownSnapshot: null
    readonly property var snapshot: UsageSnapshot.select([pluginSnapshot, ownSnapshot], providers)
    property real now: Date.now()
    property real nextAttempt: 0
    property string lastError: ""
    property var requestedProviders: []
    property bool cancelled: false
    readonly property bool stale: !pluginEnabled || providers.some(id => providerStale(id))

    function providerStale(id) {
        return !pluginEnabled || UsageSnapshot.stale(snapshot.providers[id], now, refreshMinutes);
    }

    function loadStored() {
        ownSnapshot = StateService.get(stateKey, null);
    }

    function release() {
        if (PluginService.runtimeValue(pluginId, ownerKey, null) === root)
            PluginService.setRuntimeValue(pluginId, ownerKey, null);
    }

    function fail(message, wholeRequest = true) {
        if (lastError !== message)
            console.warn(message);
        lastError = message;
        const checkedAt = Date.now();
        const readings = Object.assign({}, snapshot.providers);
        for (const id of (wholeRequest ? requestedProviders : [])) {
            if (readings[id])
                readings[id] = Object.assign({}, readings[id], {error: true, checkedAt: checkedAt});
        }
        ownSnapshot = {providers: readings, updatedAt: checkedAt, refreshMinutes: refreshMinutes};
        StateService.set(stateKey, ownSnapshot);
        nextAttempt = checkedAt + Math.max(60000, refreshMinutes * 60000);
    }

    function check() {
        now = Date.now();
        if (!enabled || !StateService.initialized || !stale || now < nextAttempt || usageProcess.running || providers.length === 0)
            return;
        if (PluginService.runtimeValue(pluginId, ownerKey, null))
            return;
        PluginService.setRuntimeValue(pluginId, ownerKey, root);
        requestedProviders = providers.slice();
        cancelled = false;
        usageProcess.buffer = "";
        usageProcess.command = ["bash", helperPath, requestedProviders.join(",")];
        usageProcess.running = true;
        timeout.restart();
    }

    onProvidersChanged: {
        nextAttempt = 0;
        Qt.callLater(check);
    }
    onEnabledChanged: {
        if (!enabled && usageProcess.running) {
            cancelled = true;
            usageProcess.running = false;
        }
        nextAttempt = 0;
        Qt.callLater(check);
    }
    Component.onCompleted: loadStored()
    Component.onDestruction: release()

    Connections {
        target: StateService
        function onStateLoaded() {
            root.loadStored();
            Qt.callLater(root.check);
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: (Config.ai.notchEnabled ?? true) && (Config.ai.notchUsageEnabled ?? true) && StateService.initialized
        triggeredOnStart: true
        onTriggered: root.check()
    }

    Timer {
        id: timeout
        interval: 45000 + Math.max(0, Math.ceil(root.requestedProviders.length / 6) - 1) * 12000
        onTriggered: {
            root.cancelled = true;
            root.fail("AI usage refresh timed out; previous readings retained.");
            usageProcess.running = false;
        }
    }

    Process {
        id: usageProcess
        property string buffer: ""
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => usageProcess.buffer += data
        }
        onExited: code => {
            timeout.stop();
            if (!root.cancelled && root.enabled) {
                if (code !== 0) {
                    root.fail("AI usage helper failed (" + code + "); previous readings retained.");
                } else {
                    try {
                        const parsed = JSON.parse(buffer);
                        const results = Array.isArray(parsed) ? parsed : [parsed];
                        const readings = Object.assign({}, root.snapshot.providers);
                        let succeeded = 0;
                        const updatedAt = Date.now();
                        for (const id of root.requestedProviders) {
                            if (root.providers.indexOf(id) < 0)
                                continue;
                            const item = results.find(result => result && result.provider === id);
                            const value = item && !item.error ? UsageSnapshot.reading(item.usage && item.usage.primary, updatedAt) : null;
                            if (value) {
                                readings[id] = Object.assign(value, {name: id, error: false});
                                succeeded++;
                            } else if (readings[id]) {
                                readings[id] = Object.assign({}, readings[id], {error: true, checkedAt: updatedAt});
                            }
                        }
                        root.ownSnapshot = {providers: readings, updatedAt: updatedAt, refreshMinutes: root.refreshMinutes};
                        StateService.set(root.stateKey, root.ownSnapshot);
                        if (succeeded < root.requestedProviders.length)
                            root.fail("Some AI usage readings failed; previous readings retained.", false);
                        else {
                            root.lastError = "";
                            root.nextAttempt = 0;
                        }
                    } catch (error) {
                        root.fail("AI usage helper returned invalid data; previous readings retained.");
                    }
                }
            }
            root.now = Date.now();
            root.release();
        }
    }
}
