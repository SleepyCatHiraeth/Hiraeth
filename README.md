<div align="center">

<img src="./assets/hiraeth/logo-color.png" alt="Hiraeth" width="46%" />

### A personal fork of [**Ambxst**](https://github.com/Axenide/Ambxst)

A local-first voice assistant, a plugin host, a system sound engine,<br/>
and a pile of security fixes — on top of Axenide's Wayland shell.

<p>
  <img src="https://img.shields.io/badge/fork_of-Axenide%2FAmbxst-F6A8C4?style=for-the-badge&labelColor=0d1117" alt="Fork of Axenide/Ambxst" />
  <img src="https://img.shields.io/badge/upstream-1.3.6-F6A8C4?style=for-the-badge&labelColor=0d1117" alt="Upstream 1.3.6" />
  <img src="https://img.shields.io/badge/license-AGPL--3.0-F6A8C4?style=for-the-badge&labelColor=0d1117" alt="AGPL-3.0" />
  <img src="https://img.shields.io/badge/compositor-Hyprland-F6A8C4?style=for-the-badge&labelColor=0d1117" alt="Hyprland" />
</p>

</div>

---

> [!NOTE]
> **All credit for Ambxst goes to [Axenide](https://github.com/Axenide).** This fork only adds to it,
> tracks its releases, and keeps its AGPL-3.0 licence. Upstream's own README is preserved in full
> below the divider — start there for installation and general use.

## What this fork adds

| | |
|---|---|
| **Turret** | A local-first voice assistant with its own pipeline in the Go backend: wake word, STT biased toward domain vocabulary, a Kokoro TTS engine with selectable voices, and a tool layer reaching email drafting. The conversation survives restarts and the transcriber stays warm between turns. The model is loopback-only — nothing leaves the machine. |
| **Controlled memory** | Opt-in, with retrieval, hard policy gates, and a review surface in the notch. Memories can be inspected, expired, adjusted and compacted. Secrets are refused outright rather than stored and flagged. |
| **Plugin host** | Discovery, manifest validation, persisted enable state and a defined trust boundary, with extension points for bar and dashboard widgets. Two plugins ship against it: AI Overview Control and a Corsair mouse battery readout. |
| **System sounds** | A `sound.json` data model with theme resolution and a playback service, hooked into notifications, boot, shutdown, login, Bluetooth connect/disconnect and battery-low. |
| **Assistant web search** | An iterative tool loop, so a turn can fetch and cite live results instead of answering from the model alone. |
| **Wallpaper transitions** | Preload-before-swap: the incoming image is decoded at a shared size across every monitor, then a two-layer dissolve drives the visible swap — the screen never passes through black and the fade does not trail on the larger display. |
| **Palette fixes** | Repaired ANSI entries anchor on their canonical hue instead of the widest free gap, so a terminal asking for yellow gets yellow. Matugen runs once with `--prefer saturation` rather than twice, which removed a regeneration loop. |
| **Encrypted clipboard** | Separate pinned and unpinned stores, with image blobs handled apart from text. |
| **Per-screen polish** | Each screen keeps its own wallpaper, its own lockscreen video and its own preloaded lock frame; SDDM follows the largest screen, since the greeter has only one background. |

### Security fixes

API keys kept out of `argv` on every path that leaked them through `curl`, `sqlite3` or a shell · the
shell tool gated off by default · an IPC unlock bypass removed from the lockscreen · screenshot freeze
frames kept private and short-lived · updates fetched over HTTPS.

## Build and run

Requires the upstream dependencies plus `qt6-multimedia` and a Qt multimedia backend
(`qt6-multimedia-ffmpeg` or `qt6-multimedia-gstreamer`) for video and GIF wallpapers.

```bash
make build                  # Go backend
make run                    # backend + shell
qs -p shell.qml             # shell only
./ambxst                    # daemon with supervision
make qml-lint               # takes a few minutes; exits 0 when clean
```

Replacing a running install needs an atomic rename — `cp` fails with *Text file busy*:

```bash
cp ambxst ~/.local/bin/ambxst.new && mv -f ~/.local/bin/ambxst.new ~/.local/bin/ambxst
setsid -f ~/.local/bin/ambxst
```

## Branches

| Branch | Purpose |
|---|---|
| `feature/corsair-battery-redesign` | The working branch, and the one to read. |
| `integration/<version>` | Where each upstream release is merged and verified before the working branch moves onto it. |
| `safety/local-customizations-2026-08-31` | Preservation point from before the first upstream merge. |
| `main` | Mirror of upstream. |

<details>
<summary><b>Tracking upstream</b></summary>

<br/>

`origin` is this fork; `upstream` is `Axenide/Ambxst` with its push URL deliberately set to the
literal string `DISABLED`, so nothing can be pushed there by accident.

```bash
git fetch upstream --tags
git switch -c integration/<version>
git merge --no-commit --no-ff <version-tag>
```

Two traps, both learned the hard way, neither of which produces a conflict or a failing check:

- **A resolution that drops a branch of a conditional still compiles and lints.** After resolving a
  conflict inside a function body, diff the resolved function against both sides and confirm every
  path still assigns what it used to.
- **A new setting lives in two objects** — its default in `config/defaults/<module>.js` and its
  property on that module's `JsonAdapter` in `config/Config.qml`. When both sides append to the same
  object, git keeps one and drops the other silently. Check both, or a settings toggle will write to
  a property that does not exist and `ConfigValidator` will strip it on every save.

</details>

## Notes

The example wallpaper directory carries only upstream's own images — the local wallpaper library is
third-party art and is not published here. Since 1.3.6 dropped mpvpaper for QtMultimedia, `ambxst
mpvipc` no longer exists. The niri-specific work upstream added is inert on this machine, which runs
Hyprland.

<div align="center">
<br/>
<img src="./assets/hiraeth/shark-color.png" alt="" width="15%" />
</div>

---

<p align="center">
<img src="./assets/ambxst/ambxst-logo-color.svg" alt="Ambxst Logo" style="width: 50%;" align="center" />
  <br>
  <br>
An <i><b>Ax</b>tremely</i> customizable shell.
</p>

  <p align="center">
  <a href="https://github.com/Axenide/Ax-Shell/stargazers">
    <img src="https://img.shields.io/github/stars/Axenide/Ambxst?style=for-the-badge&logo=github&color=E3B341&logoColor=D9E0EE&labelColor=000000" alt="GitHub stars">
  </a>
  <a href="https://ko-fi.com/Axenide">
    <img src="https://img.shields.io/badge/Support me on-Ko--fi-FF6433?style=for-the-badge&logo=kofi&logoColor=white&labelColor=000000" alt="Ko-Fi">
  </a>
  <a href="https://axeni.de/discord">
    <img src="https://img.shields.io/discord/669048311034150914?style=for-the-badge&logo=discord&logoColor=D9E0EE&labelColor=000000&color=5865F2&label=Discord" alt="Discord">
  </a>
</p>

---

<h2><sub><img src="https://raw.githubusercontent.com/Tarikul-Islam-Anik/Animated-Fluent-Emojis/master/Emojis/Objects/Camera%20with%20Flash.png" alt="Camera with Flash" width="32" height="32" /></sub> Screenshots</h2>

<div align="center">
  <img src="./assets/screenshots/1.png" width="100%" />

  <br />

  <img src="./assets/screenshots/2.png" width="32%" />
  <img src="./assets/screenshots/3.png" width="32%" />
  <img src="./assets/screenshots/4.png" width="32%" />

  <img src="./assets/screenshots/5.png" width="32%" />
  <img src="./assets/screenshots/6.png" width="32%" />
  <img src="./assets/screenshots/7.png" width="32%" />

  <img src="./assets/screenshots/8.png" width="32%" />
  <img src="./assets/screenshots/9.png" width="32%" />
  <img src="./assets/screenshots/10.png" width="32%" />
</div>

---

<h2><sub><img src="https://raw.githubusercontent.com/Tarikul-Islam-Anik/Animated-Fluent-Emojis/master/Emojis/Objects/Package.png" alt="Package" width="32" height="32" /></sub> Installation</h2>

```bash
curl -fsSL get.axeni.de/ambxst | sh
```

This will install Ambxst and its dependencies. You will have the `ambxst` command available in your terminal, which you can use to start the shell.

### Hyprland (more compositors coming soon!)

1. Run the installation command above.

2. Run `ambxst install hyprland` to add Ambxst's configuration to Hyprland. This will source a config file that applies Ambxst's settings. If you use `hyprland.lua`, or if no Hyprland config exists yet, it will look like this:

```lua
-- Ambxst
loadfile(os.getenv("HOME") .. "/.local/share/ambxst/hyprland.lua")()

-- OVERRIDES
-- Down here you can write or source anything that you want to override from Ambxst's settings.
```

If you only have `hyprland.conf`, Ambxst will keep using the legacy import there for compatibility:

```bash
# Ambxst
source = ~/.local/share/ambxst/hyprland.conf

# OVERRIDES
# Down here you can write or source anything that you want to override from Ambxst's settings.
```

As stated, anything you want to override from Ambxst's settings should be written under the "OVERRIDES" section.

3. Start Ambxst by running `ambxst` in your terminal. If you want to keep it running without having the terminal window open, you can run `ambxst & disown`. This will be only necessary for your first test run, as Ambxst will start automatically on login after step 2.

Ambxst is currently supported on **Arch**, **Fedora**, and **NixOS**. This means both based and derivative distributions.

> [!IMPORTANT]
> The only pre-requisite is having Hyprland installed.

> [!NOTE]
> For NixOS users, the screen recording utility `gpu-screen-recorder` will only be able to use the `portal` backend until you add `programs.gpu-screen-recorder.enable = true;` to your `configuration.nix` or **home-manager**.

### NixOS + home-manager (Hyprland ≥0.56 Lua)

When you run Ambxst on NixOS with [home-manager](https://github.com/nix-community/home-manager), **do not** configure Hyprland via `wayland.windowManager.hyprland.settings` with `$mod` / `$terminal` variables. Hyprland 0.56 expects a Lua entrypoint (`hl.config(...)`, `hl.bind(...)`, `hl.exec_cmd(...)`), not the legacy `bind = "$mod, Return, exec, $terminal"` syntax. The home-manager module generates `hyprland.lua` verbatim from `settings`, so the resulting file is invalid Lua.

Use a declarative `xdg.configFile` instead and let it `loadfile()` the file Ambxst writes:

```nix
# home.nix
{ lib, ... }: {
  wayland.windowManager.hyprland.enable = false;

  xdg.configFile."hypr/hyprland.lua".text = ''
    -- Import the config axctl/ambxst writes to ~/.local/share/ambxst/
    loadfile(os.getenv("HOME") .. "/.local/share/ambxst/hyprland.lua")()

    -- OVERRIDES (hl.* API, Hyprland >=0.56)
    hl.config({ input = { kb_layout = "latam", follow_mouse = 1 } })
    hl.monitor({ output = "", mode = "preferred", scale = 1 })
    hl.bind("SUPER + Return", hl.dsp.exec_cmd("kitty"))
    hl.bind("SUPER + Q",     hl.dsp.window.close())
  '';

  home.activation.fixHyprlandAmbxst = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ -f "$HOME/.config/hypr/hyprland.conf" ] \
       && [ ! -L "$HOME/.config/hypr/hyprland.conf" ]; then
      mv "$HOME/.config/hypr/hyprland.conf" \
         "$HOME/.config/hypr/hyprland.conf.bak.$(date +%F-%H%M)"
    fi
    mkdir -p "$HOME/.local/share/ambxst"
    [ -f "$HOME/.local/share/ambxst/hyprland.lua" ] \
      || echo '-- placeholder' > "$HOME/.local/share/ambxst/hyprland.lua"
  '';
}
```

Notes:

- `ambxst install hyprland` detects home-manager-managed files (symlinks into `/nix/store`) and prints a guide instead of trying to append — it will never break the symlink or write through it.
- `~/.local/share/ambxst/hyprland.lua` is regenerated by the `axctl` daemon on every theme/gaps/binds change. Cosmetic tweaks do **not** require `nixos-rebuild`; only structural changes (new binds, layout switch) need a `home-manager switch`.

---

## Will this change my config?

Nope! Besides the Ambxst import block in your `hyprland.conf` or `hyprland.lua`, Ambxst is designed to be non-intrusive. It won't modify any of your existing configurations.

---

<h2><sub><img src="https://raw.githubusercontent.com/Tarikul-Islam-Anik/Telegram-Animated-Emojis/main/Activity/Sparkles.webp" alt="Sparkles" width="32" height="32" /></sub> Features</h2>

- [x] Customizable components
- [x] Themes
- [x] System integration
- [x] App launcher
- [x] Clipboard manager
- [x] Quick notes (and not so quick ones)
- [x] Wallpaper manager
- [x] Emoji picker
- [x] [tmux](https://github.com/tmux/tmux) session manager
- [x] System monitor
- [x] Media control
- [x] Notification system
- [x] Wi-Fi manager
- [x] Bluetooth manager
- [x] Audio mixer
- [x] [EasyEffects](https://github.com/wwmm/easyeffects) integration
- [x] Screen capture
- [x] Screen recording
- [x] Color picker
- [x] OCR
- [x] QR and barcode scanner
- [x] "Mirror" (webcam)
- [x] Game mode
- [x] Night mode
- [x] Power profile manager
- [x] AI Assistant
- [x] Weather
- [x] Calendar
- [x] Power menu
- [x] Workspace management
- [x] Support for different layouts (dwindle, master, scrolling, etc.)
- [x] Multi-monitor support
- [x] Customizable keybindings
- [x] Plugin and extension system
- [x] [Mod manager with native Settings integration](docs/mods/README.md)
- [x] Compatibility with other Wayland compositors

---

## I need help!

If you are having trouble or have any questions:
- You can ask anything on [Discord](https://discord.com/invite/gHG9WHyNvH) or in the [GitHub discussions](https://github.com/Axenide/Ambxst/discussions).
- You can open an issue on the [GitHub repository](https://github.com/Axenide/Ambxst/issues).
- The main configuration is located at `~/.config/ambxst`.

---

## Credits
- [outfoxxed](https://outfoxxed.me/) for creating Quickshell and great documentation!
- [end-4](https://github.com/end-4) for his awesome projects. I learned a lot from them! (And *yoinked* a lot of code, too. 😅)
- [soramane](https://github.com/soramanew) for helping me when I started with Quickshell. (You probably don't remember, but still, heh.)
- [tr1x_em](https://trix.is-a.dev/) for being a great friend and helping me find great tools. You rock!
- [Darsh](https://github.com/its-darsh) for not killing me when I left Fabric. u_u (Also for being a great friend and creating Fabric! Without Fabric, Ax-Shell wouldn't exist, so Ambxst wouldn't either. Thank you!)
- [Mario](https://github.com/mariokhz) for being a great friend and showing me Quickshell!
- [Samouly](https://samouly.is-a.dev/) for being Samouly. :3
- [Brys](https://github.com/brys0) for being his continuous support and for being a great friend!
- [Zen](https://github.com/wer-zen) for being a great friend and helping me when I started with Quickshell too!
- [kh](https://www.youtube.com/watch?v=dQw4w9WgXcQ) for being an awesome human being and listening to my delusions about Ambxst. :D
- And you, the user, for trying out Ambxst! You're awesome! 💖

(If I forgot someone, please let me know. 🙏)
