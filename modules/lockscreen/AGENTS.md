# AGENTS.md: modules/lockscreen/

## OVERVIEW
Lock screen UI on `WlSessionLockSurface`, PAM authentication via
`Quickshell.Services.Pam`. Visual language shared with the greetd greeter
(`greeter/`): same clock, avatar ring, and password pill.

## STRUCTURE
```
modules/lockscreen/
├── LockScreen.qml       # Per-screen surface: background, letterbox bars, clock, card, choreography
├── LockState.qml        # Singleton: PAM, engaged/idle, phase, lockedAt, host, layout, caps lock
├── LockStyle.qml        # Singleton: greeter Theme API over Colors/Config (dur, span, easing, pillRadius)
├── LockCard.qml         # Avatar + ring, user@host, pill, status, meta (from greeter/LoginCard.qml)
├── LockPill.qml         # Password pill (from greeter/PasswordPill.qml)
├── LockClock.qml        # Clock (from greeter/Clock.qml)
├── LockRollingText.qml  # Rolling digits (from greeter/RollingText.qml)
└── ambxst-auth          # Helper script
```
PAM rules: `config/pam/password.conf`.

The `Lock*` component files are ports of their `greeter/` counterparts with
`Theme` -> `LockStyle` and `Info`/`Session` -> `LockState`. The greeter runs
outside the session and reads a published snapshot, so the two cannot share
files; keep them in step by hand when changing either.

## KEY BEHAVIORS
- One `PamContext` in `LockState` serves every screen, so success runs the
  unlock animation on all monitors together.
- Timelines on `LockScreen`: `lock` (entry), `rise` (clock), `t`/`engage`
  (card up), `latch` + `leave` (unlock). Every visual reads from them.
- Unlock: ring ratchets shut (LockCard), bars kick inward (`latch`), then
  everything glides out; the last step calls `LockState.finish()`, which sets
  `GlobalStates.lockscreenVisible = false`.
- `Config.lockscreen.position` picks the edge of the player bar; the status
  bar takes the other edge.
- `Config.animDuration` 0 (game mode) collapses all motion; the unlock then
  finishes immediately.

## ANTI-PATTERNS
- Never log passwords or PAM responses.
- `LockState.pending` holds the password only until the PAM prompt; keep it
  cleared on both success and failure.
- Never add a remote unlock path (see LockscreenService.qml).
- Escape only disengages the card; it must never end the lock.
