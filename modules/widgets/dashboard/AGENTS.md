# DASHBOARD KNOWLEDGE BASE

## OVERVIEW
Central interactive hub of Ambxst. Tabbed interface with LRU-based lazy-loading for widgets, system controls, media, AI tools, clipboard, notes, and tmux management. Opened via the Notch overlay.

## STRUCTURE
- **Root**: `Dashboard.qml` — Orchestrates LRU logic, tab layout, and open/close animations. Its tabs are `builtInTabs.concat(PluginService.dashboardPlugins)`, so valid enabled dashboard plugins extend the three built-ins.
- **Side Tabs**: Vertical navigation bar on the left for switching main views.
- **Sub-tabs** (each a directory):
  - `widgets/`: `WidgetsTab` — Main grid: `FullPlayer`, `Calendar`, `NotificationHistory`, weather, quick toggles.
  - `controls/`: Settings panels — `ShellPanel` (1913 lines), `ThemePanel` (1564 lines), `BindsPanel` (1974 lines), `CompositorPanel`, `SystemPanel`, `VariantEditor`, `PluginsPanel` (plugin enable/disable list, Settings section 10).
  - `assistant/`: `AssistantTab` (1196 lines) — AI chat interface.
  - `clipboard/`: `ClipboardTab` (3615 lines) — Searchable clipboard history with categories.
  - `notes/`: `NotesTab` (3505 lines) — Rich text editor with file management.
  - `tmux/`: `TmuxTab` (2250 lines) — Tmux session manager.
  - `emoji/`: `EmojiTab` (934 lines) — Emoji picker with search.
  - `metrics/`: `MetricsTab` (987 lines) — Real-time CPU/RAM/GPU/disk monitoring.
  - `wallpapers/`: `WallpapersTab` / `Wallpaper.qml` — Wallpaper browser and manager.
  - `kanban/`: Kanban board for task management.

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| **Tab loading** | `Dashboard.qml` | `TabLoader` + `shouldTabBeLoaded(index)` LRU logic |
| **Plugin tabs** | `Dashboard.qml` (`tabModel`) | Built-ins + `PluginService.dashboardPlugins`; full plugin reference in `modules/services/AGENTS.md` |
| **System settings** | `controls/ShellPanel.qml` | Bar, dock, notch configuration UI |
| **Theme settings** | `controls/ThemePanel.qml` | Colors, gradients, fonts, opacity |
| **Keybindings** | `controls/BindsPanel.qml` | Compositor keybind editor |
| **AI chat** | `assistant/AssistantTab.qml` | Multi-provider chat with streaming |
| **Clipboard** | `clipboard/ClipboardTab.qml` | Largest file (3615 lines). Category filtering |
| **Notes** | `notes/NotesTab.qml` | Rich text, file tree, search |

## CONVENTIONS
- **LRU management**: Use `shouldTabBeLoaded(index)` for conditional `Loader.active`. Tabs are evicted when exceeding the cache limit unless an enabled dashboard plugin explicitly declares boolean `keepAlive` for required background work.
- **Keyboard flow**: Components implement `focusSearchInput()` so root can forward focus on open.
- **UI primitives**: ALWAYS use `StyledRect` variants (`"pane"`, `"internalbg"`, `"focus"`) for containers.
- **Service bindings**: Connect directly to service singletons (`NetworkService`, `Audio`). No prop-drilling.
- **Large files**: Most tabs exceed 900 lines. Edit with care; use targeted line ranges.

## ANTI-PATTERNS
- Creating tab content without LRU integration via `TabLoader`.
- Prop-drilling service state through parent components instead of importing singletons directly.
- Using `Rectangle` instead of `StyledRect` for any container.

## AI OVERVIEW CONTROL DASHBOARD PLUGIN

### Ownership and paths

- Maintained source: `/mnt/Files/Projects/AMBXST-AiOverviewControl/plugin`
- Live install: `~/.config/ambxst/plugins/ai-overview-control`
- Port plan: `/mnt/Files/Projects/AMBXST-AiOverviewControl/PORT_PLAN.md`
- Visual plan: `/mnt/Files/Projects/AMBXST-AiOverviewControl/VISUAL_ADAPTATION_PLAN.md`
- Pinned DMS reference: `/mnt/Files/Projects/AMBXST-AiOverviewControl/upstream` at `f2d0fc19493539c3134da3090b0887538ecbdfb0`

### Runtime design

- `Main.qml` owns persistent orchestration and three replaceable modes: overview, provider detail, and settings. Mode `Loader` objects are transient; provider data and `Process` objects stay on the root.
- Defaults are Codex, Claude, and GitHub Copilot. Settings exposes 37 canonical upstream providers with search, categories, and local dependency/auth health. Returned provider objects drive healthy/partial/error status; stderr is only a process-level failure channel.
- Provider changes immediately remove deselected results and refresh the current selection. Detail retry requests only that provider and merges the result into the existing snapshot.
- Overview supplies fleet peak pressure, live/error counts, updated time, All/Live/Issues filters, provider search, compact cards, and history trends. Detail shows all quota windows, identity/source, actionable error, and health. Settings includes provider selection, health refresh, refresh interval, and private CSV export.

### AMBXST visual contract

- The host surface is 400×430. Keep a transparent root, native `PanelTitlebar`, internal scrolling, and compact cards; never copy DMS popout/window chrome.
- Every visual value must stay live-bound to `Colors.*`, `Styling.*`, `StyledRect` variants, `Config.theme.*`, and `Config.animDuration`. Never cache palette values or introduce fixed color literals. This preserves wallpaper/Matugen, light, OLED, custom gradient/halftone, font, roundness, and animation changes.
- Use `pane` for cards/major sections, `internalbg` for nested quota windows, `common` for neutral controls, `focus` for hover/keyboard focus, and variant `itemColor` for content on configurable surfaces.
- Preserve `focusSearchInput()`, accessible provider-card role/name/description, Return/Space activation, Escape back navigation, visible focus, and error text in detail rather than overflowing cards.

### Validation and deployment

1. Before edits, archive both maintained and installed copies under `/mnt/Files/Projects/AMBXST-AiOverviewControl/backups/<UTC timestamp>/` and record SHA-256.
2. Work in a staging copy under `/home/hiraeth`; do not edit AMBXST core for plugin-only behavior.
3. Run `tests/lint.sh`. It time-bounds `qmlformat`, `qmllint`, manifest/Bash checks, prohibited-pattern scanning, provider-registry parity, and health output. Stock `qmllint` cannot resolve Quickshell's virtual `qs.*` imports, so `qmlformat` is the quiet parser gate.
4. Run the retained non-live upstream fixtures (`tests/test-*.sh`, excluding `*-live.sh`) and a normalized Codex/Claude/Copilot response check.
5. Synchronize only validated files to both maintained and live copies, confirm `diff -qr` is empty, then run host-side `ambxst reload`. Sandbox-local reload/log checks cannot see the desktop process namespace.
6. Verify with `qs list --all`, `qs log --pid <pid> --no-color`, and a host `pgrep` for orphan provider helpers. Do not leave `/usr/bin/caveman shrink -- make qml-lint` running; the repository-wide target can be slow, while the plugin gate is scoped and bounded.

### Deliberate scope

- No bar pill or multi-surface manifest extension.
- No DMS compatibility layer.
- Notification thresholds and localization remain deferred until their behavior/privacy requirements are reviewed.
- Do not split the single QML file merely for size; extract only when a change creates a second real owner or the file becomes materially harder to validate.
