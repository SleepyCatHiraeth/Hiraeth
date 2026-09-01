pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string pluginsDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ambxst/plugins"
    property var allPlugins: []
    property var barPlugins: []
    property var dashboardPlugins: []
    property var pluginDirs: []
    property var runtimeData: ({})

    signal pluginsAboutToChange()
    signal settingsChanged(string pluginId)
    signal runtimeChanged(string pluginId, string key)

    function stateKey(pluginId, key) {
        return "plugin." + pluginId + "." + key;
    }

    function enabledOverrideKey(id) {
        return "pluginEnabledOverride." + id;
    }

    function isEffectivelyEnabled(id, manifestDefault) {
        return StateService.get(enabledOverrideKey(id), manifestDefault);
    }

    function setEnabled(id, enabled) {
        StateService.set(enabledOverrideKey(id), enabled);
        scan();
    }

    function get(pluginId, key, fallback) {
        return StateService.get(stateKey(pluginId, key), fallback);
    }

    function set(pluginId, key, value) {
        StateService.set(stateKey(pluginId, key), value);
        settingsChanged(pluginId);
    }

    function runtimeValue(pluginId, key, fallback) {
        const plugin = runtimeData[pluginId];
        return plugin && plugin[key] !== undefined ? plugin[key] : fallback;
    }

    function setRuntimeValue(pluginId, key, value) {
        const nextPlugin = Object.assign({}, runtimeData[pluginId] || {});
        nextPlugin[key] = value;
        const next = Object.assign({}, runtimeData);
        next[pluginId] = nextPlugin;
        runtimeData = next;
        runtimeChanged(pluginId, key);
    }

    function componentPath(pluginDir, component) {
        if (typeof component !== "string" || component.length === 0 || component.startsWith("/"))
            return "";

        let decoded;
        try {
            decoded = decodeURIComponent(component);
        } catch (error) {
            return "";
        }
        if (decoded.startsWith("/") || decoded.includes("?") || decoded.includes("#")) return "";

        const parts = decoded.split("/");
        const resolved = [];
        for (const part of parts) {
            if (part === "" || part === ".") continue;
            if (part === "..") {
                if (resolved.length === 0) return "";
                resolved.pop();
            } else {
                resolved.push(part);
            }
        }
        return resolved.length > 0 ? pluginDir + "/" + resolved.join("/") : "";
    }

    function reject(path, reason) {
        console.warn("PluginService: Skipping", path + ":", reason);
    }

    function applyScan(output) {
        const nextAll = [];
        const nextBar = [];
        const nextDashboard = [];
        const nextDirs = [];
        const ids = {};
        const lines = output.trim().length > 0 ? output.trim().split("\n") : [];

        for (const line of lines) {
            if (line.startsWith("---DIR---")) {
                nextDirs.push(line.substring(9));
                continue;
            }
            const separator = line.indexOf("\t");
            if (separator < 0) continue;

            const manifestPath = line.substring(0, separator);
            const pluginDir = manifestPath.substring(0, manifestPath.lastIndexOf("/"));
            let manifest;
            try {
                manifest = JSON.parse(line.substring(separator + 1));
            } catch (error) {
                reject(manifestPath, "invalid JSON (" + error + ")");
                continue;
            }

            if (typeof manifest.id !== "string" || manifest.id.length === 0
                    || typeof manifest.name !== "string" || manifest.name.length === 0
                    || typeof manifest.type !== "string"
                    || typeof manifest.component !== "string" || manifest.component.length === 0
                    || typeof manifest.enabled !== "boolean") {
                reject(manifestPath, "missing required field");
                continue;
            }
            if (ids[manifest.id]) {
                reject(manifestPath, "duplicate id " + manifest.id);
                continue;
            }
            if (manifest.type !== "bar" && manifest.type !== "dashboard") {
                reject(manifestPath, "unsupported type " + manifest.type);
                continue;
            }
            if (manifest.type === "dashboard" && (typeof manifest.icon !== "string" || manifest.icon.length === 0)) {
                reject(manifestPath, "dashboard plugin requires icon");
                continue;
            }
            if (manifest.keepAlive !== undefined && typeof manifest.keepAlive !== "boolean") {
                reject(manifestPath, "keepAlive must be boolean");
                continue;
            }
            if (manifest.description !== undefined && typeof manifest.description !== "string") {
                reject(manifestPath, "description must be string");
                continue;
            }

            const path = componentPath(pluginDir, manifest.component);
            if (!path) {
                reject(manifestPath, "component escapes its plugin directory");
                continue;
            }

            ids[manifest.id] = true;
            const enabled = isEffectivelyEnabled(manifest.id, manifest.enabled);
            nextAll.push({
                id: manifest.id,
                name: manifest.name,
                type: manifest.type,
                icon: manifest.icon || "",
                description: manifest.description || "",
                enabled: enabled
            });
            if (!enabled) continue;

            const descriptor = {
                id: manifest.id,
                name: manifest.name,
                icon: manifest.icon || "",
                description: manifest.description || "",
                keepAlive: manifest.keepAlive === true,
                component: "file://" + path
            };
            (manifest.type === "bar" ? nextBar : nextDashboard).push(descriptor);
        }

        pluginsAboutToChange();
        pluginDirs = nextDirs;
        allPlugins = nextAll;
        barPlugins = nextBar;
        dashboardPlugins = nextDashboard;
    }

    function scan() {
        if (!StateService.initialized) return;
        if (!scanProcess.running) scanProcess.running = true;
    }

    Connections {
        target: StateService

        function onInitializedChanged() {
            if (StateService.initialized) root.scan();
        }
    }

    Process {
        id: scanProcess
        command: ["sh", "-c", "find '" + root.pluginsDir + "' -mindepth 1 -maxdepth 1 -type d -printf '%p\\n' 2>/dev/null | sed 's/^/---DIR---/'; find '" + root.pluginsDir + "' -mindepth 2 -maxdepth 2 -name plugin.json -type f -exec sh -c 'for f do printf \"%s\\t\" \"$f\"; tr \"\\n\" \" \" < \"$f\"; printf \"\\n\"; done' sh {} + 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyScan(text)
        }
    }

    FileView {
        path: root.pluginsDir
        watchChanges: true
        printErrors: false
        onFileChanged: rescanTimer.restart()
    }

    Instantiator {
        model: root.pluginDirs
        delegate: FileView {
            required property string modelData
            path: modelData
            watchChanges: true
            printErrors: false
            onFileChanged: rescanTimer.restart()
        }
    }

    Timer {
        id: rescanTimer
        interval: 100
        onTriggered: root.scan()
    }

    Process {
        id: initProcess
        command: ["mkdir", "-p", root.pluginsDir]
        running: true
        onExited: root.scan()
    }
}
