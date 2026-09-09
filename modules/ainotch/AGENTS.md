# AGENTS.md - modules/ainotch/

## OVERVIEW
Right-edge (or left-edge) notch for the AI assistant. The notch is the collapsed
state of the assistant panel, not a separate widget that opens one: the same
container, background and geometry animation serve both states, so pressing
`Super+A` reads as the notch unfolding rather than a panel sliding in over it.

## STRUCTURE

| File | Purpose |
|------|---------|
| `NotchEdge.js` | Stack-space geometry: `isVertical`, `outward`, `radii`, `flareCorners`, `canvasTransform`. The only code that knows which axis is which |
| `AiNotch.qml` | The silhouette: masked `StyledRect`, two `RoundCorner` flares, outline `Canvas`. Purely visual — position and size belong to the caller |
| `AiNotchCollapsed.qml` | Resting content: usage rings when a reading exists, assistant glyph when not, plus a dot that pulses while `Ai.isLoading` |
| `AiUsageCell.qml` | One provider's five-hour window: ring, provider mark, percentage |

The owner is `modules/sidebar/AssistantSidebar.qml`, which sets the notch's
size, position and reveal state and hosts both this module's collapsed content
and its own chat `ColumnLayout` inside `AiNotch`.

## WHERE TO LOOK

- **Edge mapping**: `NotchEdge.js` — every per-edge difference lives here
- **Silhouette path**: `AiNotch.qml` `outlineCanvas.onPaint` — written once in
  canonical right-edge space, mapped onto the actual edge by `canvasTransform`
- **Collapsed/expanded geometry**: `AssistantSidebar.qml`, `sidebarContainer`
- **Reveal, hover grace, click-to-open**: `AssistantSidebar.qml` root properties
- **Input regions**: `UnifiedShellPanel.qml` `mask.regions` — the notch body and
  its wake strip are two separate `Region` entries
- **Usage readings**: `modules/services/AiUsage.qml` — prefers the AI Overview
  Control plugin's published snapshot, polls the plugin's helper itself only
  when that is missing or stale

## CONVENTIONS

Follows parent AGENTS.md. Config keys live under `ai` (`notchEnabled`,
`notchKeepHidden`, `notchLength`, `notchHoverRegionSize`, `notchHoverToOpen`),
not under `notch`, which belongs to the top notch.

## ANTI-PATTERNS

- Never write a second copy of the silhouette for another edge. Add the edge to
  `NotchEdge.js` instead — four hand-written variants means four copies of the
  corner-versus-flare clamping, and three of them are never the one on screen
  when it breaks.
- Clamp the body corner before the flare, never the other way round. Clamping
  the flare first collapses the corner to zero exactly when the shape folds to
  its resting width.
- Don't push the assistant panel onto a `StackView` the way the top notch does.
  It is sized from `implicitWidth`/`implicitHeight` with overshoot, and the
  panel is a full-height layout with an external resize handle.
- A new hitbox must be added to `UnifiedShellPanel.qml`'s `mask.regions` or it
  renders but never receives the pointer.
- Don't reuse `CircularSeekBar` for a read-only ring. It always draws a drag
  handle and owns a MouseArea, so making it static means overriding
  `handleSpacing`, `animatedHandleWidth` and `enabled` and still carrying its
  wavy and dashed modes. Two `ShapePath`s are less machinery.
- Don't add a second poller against the provider helpers. `AiUsage` exists to be
  the one that stands down when the plugin is publishing; a surface that wants a
  reading reads `AiUsage.snapshot`.
- A new config key needs BOTH an entry in `config/defaults/ai.js` AND a matching
  `property` on the `ai` `JsonAdapter` in `config/Config.qml`. The adapter
  declares its properties explicitly, so a defaults-only key merges into
  `ai.json` on disk, reads back `undefined`, and silently takes its `??`
  fallback forever.
