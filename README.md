<img src="assets/banner.svg" width="100%" alt="Hiraeth">

<p align="center">
  <a href="#shell">Shell</a> ·
  <a href="#greeter">Greeter</a> ·
  <a href="#polkit">Polkit</a> ·
  <a href="#lockscreen">Lockscreen</a> ·
  <a href="#sky">Sky</a> ·
  <a href="#desktop">Desktop</a> ·
  <a href="#brand">Brand</a> ·
  <a href="#system">System</a> ·
  <a href="#design">Design</a>
</p>

**Hiraeth** is a complete desktop for Hyprland on CachyOS: a Quickshell shell, a greetd login
screen, a polkit agent, a lockscreen and a live galaxy wallpaper, all built to one design.

The name is Welsh for a longing for a home you can't return to.

<img src="media/tour.gif" width="100%" alt="Hiraeth desktop with the sidebar and dashboard open">

<p align="center">
  <a href="media/tour.mp4"><b>Full tour</b></a> (1 min) ·
  <a href="media/greeter.mp4"><b>Greeter</b></a> ·
  <a href="media/polkit-first-version.mp4">Polkit, first version</a>
</p>

## Components

| Component | Description | Repository |
| --- | --- | --- |
| **Shell** | Bar, notch, launcher, dashboard, notifications, overview, assistant | this repo |
| **Greeter** | greetd login screen, replaces SDDM | [Hiraeth-greeter](https://github.com/SleepyCatHiraeth/Hiraeth-greeter) |
| **Polkit** | Authentication agent, replaces hyprpolkitagent | [Hiraeth-polkit](https://github.com/SleepyCatHiraeth/Hiraeth-polkit) |
| **Lockscreen** | Clock over the live sky | this repo |
| **Sky** | Live `.sky` wallpaper | this repo |
| **System** | fastfetch, kitty and yazi themes | this repo |

> [!NOTE]
> The shell source is not published yet. This repository currently holds the showcase and the design assets.

<!-- gallery:start -->
<a id="shell"></a>

<img src="assets/headers/01-shell.svg" width="100%" alt="01 Shell">

<table>
<tr><td width="50%"><img src="gallery/01-shell/01-bar.gif" width="100%" alt="Shell: bar"><br><sub><b>Bar</b> — Vertical sidebar with workspaces, tray and clock</sub></td><td width="50%"><img src="gallery/01-shell/02-launcher.gif" width="100%" alt="Shell: launcher"><br><sub><b>Launcher</b> — Type to search apps</sub></td></tr>
<tr><td width="50%"><img src="gallery/01-shell/03-notch.gif" width="100%" alt="Shell: notch"><br><sub><b>Notch</b> — User, splash line and notifications</sub></td><td width="50%"><img src="gallery/01-shell/04-dashboard.gif" width="100%" alt="Shell: dashboard"><br><sub><b>Dashboard</b> — Media, calendar and quick toggles</sub></td></tr>
<tr><td width="50%"><img src="gallery/01-shell/05-notifications.gif" width="100%" alt="Shell: notifications"><br><sub><b>Notifications</b> — Toasts that drop out of the notch</sub></td><td width="50%"><img src="gallery/01-shell/06-overview.gif" width="100%" alt="Shell: overview"><br><sub><b>Overview</b> — Every workspace at a glance</sub></td></tr>
<tr><td width="50%"><img src="gallery/01-shell/07-assistant.gif" width="100%" alt="Shell: assistant"><br><sub><b>Assistant</b> — AI sidebar</sub></td><td width="50%"><img src="gallery/01-shell/08-capture.gif" width="100%" alt="Shell: capture"><br><sub><b>Capture</b> — Screenshots and screen recording</sub></td></tr>
<tr><td width="50%"><img src="gallery/01-shell/09-settings.gif" width="100%" alt="Shell: settings"><br><sub><b>Settings</b> — All settings in one window, grouped</sub></td><td width="50%"><img src="gallery/01-shell/10-power.gif" width="100%" alt="Shell: power"><br><sub><b>Power</b> — Lock, sleep, log out, reboot</sub></td></tr>
<tr><td width="50%"><img src="gallery/01-shell/11-wallpapers.gif" width="100%" alt="Shell: wallpapers"><br><sub><b>Wallpapers</b> — Picker for images, GIFs and videos</sub></td><td width="50%"><img src="gallery/01-shell/12-weather.gif" width="100%" alt="Shell: weather"><br><sub><b>Weather</b> — Calendar, live weather and focus timer</sub></td></tr>
<tr><td width="50%"><img src="gallery/01-shell/13-presets.gif" width="100%" alt="Shell: presets"><br><sub><b>Presets</b> — Switch the whole shell in one click</sub></td><td width="50%"><img src="gallery/01-shell/14-mixer.gif" width="100%" alt="Shell: mixer"><br><sub><b>Mixer</b> — Volume, microphone and brightness</sub></td></tr>
<tr><td width="50%"><img src="gallery/01-shell/15-power-profile.gif" width="100%" alt="Shell: power profile"><br><sub><b>Power profile</b> — Saver, balanced, performance</sub></td></tr>
</table>

<a id="greeter"></a>

<img src="assets/headers/02-greeter.svg" width="100%" alt="02 Greeter">

<table>
<tr><td width="50%"><img src="gallery/02-greeter/01-login.png" width="100%" alt="Greeter: login"><br><sub><b>Login</b> — Avatar card, clock and splash line</sub></td><td width="50%"><img src="gallery/02-greeter/02-typing.gif" width="100%" alt="Greeter: typing"><br><sub><b>Typing</b> — Password field</sub></td></tr>
<tr><td width="50%"><img src="gallery/02-greeter/03-unlock.gif" width="100%" alt="Greeter: unlock"><br><sub><b>Unlock</b> — Straight into the session</sub></td><td width="50%"><img src="gallery/02-greeter/04-wallpapers.gif" width="100%" alt="Greeter: wallpapers"><br><sub><b>Wallpapers</b> — Uses the current desktop wallpaper</sub></td></tr>
<tr><td width="50%"><img src="gallery/02-greeter/05-live-wallpaper.png" width="100%" alt="Greeter: live wallpaper"><br><sub><b>Live wallpaper</b> — Animated wallpapers work too</sub></td></tr>
</table>

<a id="polkit"></a>

<img src="assets/headers/03-polkit.svg" width="100%" alt="03 Polkit">

<table>
<tr><td width="50%"><img src="gallery/03-polkit/01-prompt.gif" width="100%" alt="Polkit: prompt"><br><sub><b>Prompt</b> — Slides up out of the screen frame</sub></td></tr>
</table>

<a id="lockscreen"></a>

<img src="assets/headers/04-lockscreen.svg" width="100%" alt="04 Lockscreen">

<table>
<tr><td width="50%"><img src="gallery/04-lockscreen/01-lock.gif" width="100%" alt="Lockscreen: lock"><br><sub><b>Lock</b> — Lock and unlock</sub></td><td width="50%"><img src="gallery/04-lockscreen/02-card.png" width="100%" alt="Lockscreen: card"><br><sub><b>Card</b> — The password card appears as you type</sub></td></tr>
</table>

<a id="sky"></a>

<img src="assets/headers/05-sky.svg" width="100%" alt="05 Sky">

<table>
<tr><td width="50%"><img src="gallery/05-sky/01-galaxy.gif" width="100%" alt="Sky: galaxy"><br><sub><b>Galaxy</b> — Spiral arms, dust and distant light</sub></td><td width="50%"><img src="gallery/05-sky/02-systems.gif" width="100%" alt="Sky: systems"><br><sub><b>Systems</b> — The home system in motion</sub></td></tr>
<tr><td width="50%"><img src="gallery/05-sky/03-ships.gif" width="100%" alt="Sky: ships"><br><sub><b>Ships</b> — A ship crosses, then jumps</sub></td><td width="50%"><img src="gallery/05-sky/04-events.gif" width="100%" alt="Sky: events"><br><sub><b>Events</b> — Warp out</sub></td></tr>
<tr><td width="50%"><img src="gallery/05-sky/05-far-light.png" width="100%" alt="Sky: far light"><br><sub><b>Far light</b> — HR 1, the far light</sub></td></tr>
</table>

<a id="desktop"></a>

<img src="assets/headers/06-desktop.svg" width="100%" alt="06 Desktop">

<table>
<tr><td width="50%"><img src="gallery/06-desktop/01-splash.png" width="100%" alt="Desktop: splash"><br><sub><b>Splash</b> — Hyprland splash line under the notch</sub></td><td width="50%"><img src="gallery/06-desktop/02-osd.gif" width="100%" alt="Desktop: osd"><br><sub><b>OSD</b> — Volume and brightness</sub></td></tr>
</table>

<a id="brand"></a>

<img src="assets/headers/07-brand.svg" width="100%" alt="07 Brand">

<table>
<tr><td width="50%"><img src="gallery/07-brand/01-lockup.png" width="100%" alt="Brand: lockup"><br><sub><b>Lockup</b> — Wordmark and seven-star constellation</sub></td><td width="50%"><img src="gallery/07-brand/02-meters.gif" width="100%" alt="Brand: meters"><br><sub><b>Meters</b> — System metrics as segment meters</sub></td></tr>
</table>

<a id="system"></a>

<img src="assets/headers/08-system.svg" width="100%" alt="08 System">

<table>
<tr><td width="50%"><img src="gallery/08-system/01-fastfetch.png" width="100%" alt="System: fastfetch"><br><sub><b>Fastfetch</b> — Logo rendered by the shell</sub></td><td width="50%"><img src="gallery/08-system/02-terminal.png" width="100%" alt="System: terminal"><br><sub><b>Terminal</b> — kitty and yazi in the Hiraeth palette</sub></td></tr>
</table>

<!-- gallery:end -->

<a id="design"></a>

## Design

### Palette

<img src="assets/palette.svg" width="100%" alt="Hiraeth palette">

| Token | Hex | Use |
| --- | --- | --- |
| `bg` | `#05070f` | Deepest background |
| `sky` | `#070a17` | Wallpaper and canvas |
| `navy` | `#0b1330` | Panels, top of the sky |
| `line` | `#1b2140` | Borders and dividers |
| `muted` | `#8189a8` | Secondary text |
| `blue` | `#b6c4ff` | Accents, star glow |
| `engine` | `#a8eefc` | Active states, numbers |
| `ink` | `#cfdaf7` | Text and hairlines |
| `core` | `#f6f7ff` | Highlights |

### Typography

<img src="assets/type.svg" width="100%" alt="Michroma type specimen">

[Michroma](https://fonts.google.com/specimen/Michroma) for display text, set in uppercase with wide tracking.

## Credits

- [Quickshell](https://quickshell.org) — the QML toolkit the shell is built on
- [Ambxst](https://github.com/Axenide/Ambxst) — the shell Hiraeth started from
- [Michroma](https://fonts.google.com/specimen/Michroma) by Vernon Adams, SIL Open Font License
