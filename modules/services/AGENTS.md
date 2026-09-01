# SERVICES KNOWLEDGE BASE

## OVERVIEW
Backend singletons bridging Wayland protocols, CLI tools (nmcli, upower, wpctl, etc.), and AI providers to the QML UI layer. 30+ services following a "Reactive Singleton" pattern — internal state derived from async system calls, exposed as QML properties.

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| **Audio/Volume** | `Audio.qml` | PipeWire/PulseAudio via `wpctl`. Sink/source management |
| **Network/WiFi** | `NetworkService.qml` | `nmcli` wrapper. WiFi scanning, connection, status |
| **Battery/Power** | `Battery.qml` | UPower integration. Percentage, charging state, time remaining |
| **Bluetooth** | `BluetoothService.qml` | Device listing, connect/disconnect |
| **Brightness** | `Brightness.qml` | Per-monitor brightness via `brightnessctl` |
| **AI Assistant** | `Ai.qml` + `ai/strategies/` | Multi-provider (OpenAI, Gemini, Mistral). Strategy pattern |
| **Clipboard** | `ClipboardService.qml` | Persistent clipboard via `clipboard.db` + helper scripts |
| **Media** | `MprisController.qml` | MPRIS D-Bus player control |
| **Notifications** | `Notifications.qml` | D-Bus notification server with persistence |
| **System Monitor** | `SystemResources.qml` | CPU, RAM, GPU, temps via Python script |
| **Compositor** | `AxctlService.qml` | Compositor abstraction. State arrives via `BackendService` subscription to the Go-owned `compositor` service; `dispatch()` is an IPC call to the backend that runs `axctl` one-shots |
| **Visibility** | `Visibilities.qml` | Per-screen UI visibility/layering orchestration |
| **State** | `StateService.qml` | JSON persistence for session state (tab positions, etc.) |
| **Focus** | `FocusGrabManager.qml` | Input focus coordination across overlays |
| **Desktop** | `DesktopService.qml` | Desktop icon grid positioning and management |
| **App Search** | `AppSearch.qml` | Application indexing for launcher |
| **Weather** | `WeatherService.qml` | Forecast, sunrise/sunset, day/night detection |
| **Keybinds** | `GlobalShortcuts.qml` | Compositor-level keybind management |
| **Plugins** | `PluginService.qml` | User plugin discovery/validation/enable-state |

## PLUGIN SYSTEM
- **Location**: Plugins live at `$XDG_CONFIG_HOME/ambxst/plugins/<id>/plugin.json`, falling back to `~/.config/ambxst/plugins/<id>/plugin.json` when `XDG_CONFIG_HOME` is unset.
- **Manifest**: Every manifest requires a non-empty, unique string `id`, a non-empty string `name`, `type` (`"bar"` or `"dashboard"` only), a non-empty relative `component` path, and a boolean `enabled` default. Dashboard plugins also require a non-empty string `icon`; bar plugin icons are optional. An optional boolean `keepAlive` lets an enabled dashboard plugin remain instantiated outside the dashboard LRU when it owns explicit background work. Component paths are URI-decoded and lexically normalized, rejecting absolute paths, query/fragment suffixes, malformed encoding, and `..` traversal outside the plugin directory.
- **Discovery and watching**: A startup scan finds immediate plugin directories and their `plugin.json` files. `FileView` watches the plugins root and an `Instantiator` watches each discovered plugin directory; changes trigger a 100 ms debounced rescan. Adding, removing, or editing a manifest is discovered automatically. Editing an already-loaded plugin QML component does not hot-replace it; use `ambxst reload`.
- **Enable state**: The manifest's `enabled` value is the default. `setEnabled(id, enabled)` persists a user override in `StateService` as `pluginEnabledOverride.<id>` and requests an immediate rescan. Plugin-owned settings use the separate `plugin.<id>.<key>` namespace through public `get(pluginId, key, fallback)` / `set(pluginId, key, value)` methods.
- **Exposed models**: `barPlugins` and `dashboardPlugins` contain effectively enabled plugin descriptors with `file://` component URLs for loaders. `allPlugins` contains every valid plugin, including disabled ones, for settings UI such as `PluginsPanel.qml`.
- **Trust model**: There is deliberately no plugin permissions or sandboxing model. Plugin QML runs with full shell authority and must be trusted like any other shell code.

## CONVENTIONS
- **Singleton pattern**: `pragma Singleton` + `Singleton { id: root }` root component.
- **System access**: Prefer `Quickshell.Io.Process` with `SplitParser` for line-by-line stdout handling.
- **Naming**: Properties in camelCase (`wifiEnabled`, `isCharging`). Methods: `update()` for polling, `toggleX()` for booleans. Signals: past-tense or action-based (`initDone`, `discard`).
- **Persistence**: `FileView` for direct JSON manipulation. Reference `Config` for global settings; keep service-specific state local.
- **Async safety**: `Qt.callLater()` when modifying lists/models inside process handlers.
- **Self-init**: Services handle own lifecycle via `Component.onCompleted: update()`.
- **Error handling**: Always provide safe fallback values (`available: device !== null`).

## ANTI-PATTERNS
- Polling without a timer guard (use `Timer` with configurable intervals).
- Modifying list models synchronously inside `Process.onStdout` handlers.
- Creating new services without registering them in `shell.qml` init sequence.
- Editing a plugin's own `plugin.json` to toggle it; use `PluginService.setEnabled()` and the persisted `StateService` override.
- Merging `pluginEnabledOverride.<id>` with plugin-owned `plugin.<id>.<key>` settings; the namespaces are separate to prevent collisions.

## AI OVERVIEW CONTROL REFERENCE

- Canonical maintained copy: `/mnt/Files/Projects/AMBXST-AiOverviewControl/plugin`; installed copy: `~/.config/ambxst/plugins/ai-overview-control`. Keep them byte-identical after changes. The reviewed DMS upstream is pinned at commit `f2d0fc19493539c3134da3090b0887538ecbdfb0` under the same project directory.
- Manifest id is `ai-overview-control`, type `dashboard`, component `Main.qml`, default `enabled: false`. The user's effective enable choice remains a `pluginEnabledOverride.ai-overview-control` StateService entry; never change the manifest to toggle it.
- Plugin settings use only `plugin.ai-overview-control.providers` and `plugin.ai-overview-control.refreshMinutes`. `Main.qml` validates provider ids, removes duplicates, preserves at least one provider, and clamps refresh to 1–60 minutes before use.
- Provider helpers are trusted upstream Bash. QML passes fixed argv arrays—never interpolated shell source—and does not store tokens. Helpers may read provider-owned CLI state, environment variables, keyrings, or local databases and contact provider APIs over TLS.
- `get-provider-usage` normalizes results, isolates provider errors, writes bounded local history under `${XDG_CACHE_HOME:-~/.cache}/AiOverviewControl`, and caps fan-out at six workers (`AIOC_MAX_PARALLEL`, clamped 1–12). Keep its per-run temporary-directory cleanup and network timeouts.
- AI Overview declares `keepAlive` because quota notifications require its refresh owner outside the dashboard LRU. Disabling notifications restores visible-only refresh; disabling the plugin destroys the component and all child processes. Do not move its timers/processes into a permanent shell singleton.
- CSV history export uses the upstream helper and mode `0600`. Notification thresholds are intentionally not enabled yet; review AMBXST notification behavior and privacy before wiring `send-quota-alert`.
