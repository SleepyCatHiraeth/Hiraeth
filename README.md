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
  <a href="#palette">Palette</a>
</p>

*Hiraeth* is Welsh for longing for a home you can't go back to. It's also the name of my desktop.

It's my own shell on Hyprland (CachyOS), built on Quickshell and grown out of Ambxst, plus
everything around it: my own login screen, my own polkit agent, a lockscreen and a live
wallpaper that's an entire little galaxy. All of it shares one look: Michroma in capitals,
hairline constellations and a flat navy night sky.

The code isn't in here yet, but the look is. Everything below is recorded straight off my desktop.

<img src="media/tour.gif" width="100%" alt="The sky desktop with the sidebar and dashboard">

<p align="center">
  <a href="media/tour.mp4"><b>▶ Full tour</b></a> — sky, dashboard, lockscreen, fastfetch, polkit (1 min) ·
  <a href="media/greeter.mp4"><b>▶ Greeter</b></a> — login from boot to desktop ·
  <a href="media/polkit-first-version.mp4">▶ Polkit, first version</a>
</p>

| | What | Where |
| --- | --- | --- |
| **Shell** | bar, notch, launcher, dashboard, weather, overview, notifications, assistant | `shell/` |
| **Greeter** | greetd login screen, replaced SDDM | `greeter/` · [Hiraeth-greeter](https://github.com/SleepyCatHiraeth/Hiraeth-greeter) |
| **Polkit** | authentication agent, replaced hyprpolkitagent | `polkit/` · [Hiraeth-polkit](https://github.com/SleepyCatHiraeth/Hiraeth-polkit) |
| **Lockscreen** | big clock over the live sky | `shell/` |
| **Sky** | live `.sky` wallpaper | `sky/` |
| **Desktop** | splash line, OSD | `shell/` |
| **Brand** | Wordmark Sky, star meters | `brand/` |
| **System** | fastfetch, kitty, yazi | `system/` |

<!-- gallery:start -->
<a id="shell"></a>

<img src="assets/headers/01-shell.svg" width="100%" alt="01 Shell">

<table>
<tr><td width="50%"><img src="gallery/01-shell/01-bar.gif" width="100%" alt="Shell: bar"><br><sub>bar · the sidebar bar</sub></td><td width="50%"><img src="gallery/01-shell/02-launcher.gif" width="100%" alt="Shell: launcher"><br><sub>launcher · type to find an app</sub></td></tr>
<tr><td width="50%"><img src="gallery/01-shell/03-notch.gif" width="100%" alt="Shell: notch"><br><sub>notch · user, splash line, notifications</sub></td><td width="50%"><img src="gallery/01-shell/04-dashboard.gif" width="100%" alt="Shell: dashboard"><br><sub>dashboard · media, calendar, quick toggles</sub></td></tr>
<tr><td width="50%"><img src="gallery/01-shell/05-notifications.gif" width="100%" alt="Shell: notifications"><br><sub>notifications · toasts drop out of the notch</sub></td><td width="50%"><img src="gallery/01-shell/06-overview.gif" width="100%" alt="Shell: overview"><br><sub>overview · every workspace at a glance</sub></td></tr>
<tr><td width="50%"><img src="gallery/01-shell/07-assistant.gif" width="100%" alt="Shell: assistant"><br><sub>assistant · ai sidebar</sub></td><td width="50%"><img src="gallery/01-shell/08-capture.gif" width="100%" alt="Shell: capture"><br><sub>capture · screenshot and recording tools</sub></td></tr>
<tr><td width="50%"><img src="gallery/01-shell/09-settings.gif" width="100%" alt="Shell: settings"><br><sub>settings · sorted groups, one window</sub></td><td width="50%"><img src="gallery/01-shell/10-power.gif" width="100%" alt="Shell: power"><br><sub>power · lock, sleep, log out, reboot</sub></td></tr>
<tr><td width="50%"><img src="gallery/01-shell/11-wallpapers.gif" width="100%" alt="Shell: wallpapers"><br><sub>wallpapers · picker with images, gifs, videos</sub></td><td width="50%"><img src="gallery/01-shell/12-weather.gif" width="100%" alt="Shell: weather"><br><sub>weather · clock popup: calendar, live weather sky, focus timer</sub></td></tr>
<tr><td width="50%"><img src="gallery/01-shell/13-presets.gif" width="100%" alt="Shell: presets"><br><sub>presets · whole-shell presets, one click</sub></td><td width="50%"><img src="gallery/01-shell/14-mixer.gif" width="100%" alt="Shell: mixer"><br><sub>mixer · volume, mic and brightness meters</sub></td></tr>
<tr><td width="50%"><img src="gallery/01-shell/15-power-profile.gif" width="100%" alt="Shell: power profile"><br><sub>power profile · saver, balanced, performance</sub></td></tr>
</table>

<a id="greeter"></a>

<img src="assets/headers/02-greeter.svg" width="100%" alt="02 Greeter">

<table>
<tr><td width="50%"><img src="gallery/02-greeter/01-login.png" width="100%" alt="Greeter: login"><br><sub>login · avatar card, clock, splash line</sub></td><td width="50%"><img src="gallery/02-greeter/02-typing.gif" width="100%" alt="Greeter: typing"><br><sub>typing · the cipher pill</sub></td></tr>
<tr><td width="50%"><img src="gallery/02-greeter/03-unlock.gif" width="100%" alt="Greeter: unlock"><br><sub>unlock · into the session</sub></td><td width="50%"><img src="gallery/02-greeter/04-wallpapers.gif" width="100%" alt="Greeter: wallpapers"><br><sub>wallpapers · follows whatever wallpaper I use</sub></td></tr>
<tr><td width="50%"><img src="gallery/02-greeter/05-live-wallpaper.png" width="100%" alt="Greeter: live wallpaper"><br><sub>live wallpaper · gifs and videos too</sub></td></tr>
</table>

<a id="polkit"></a>

<img src="assets/headers/03-polkit.svg" width="100%" alt="03 Polkit">

<table>
<tr><td width="50%"><img src="gallery/03-polkit/01-prompt.gif" width="100%" alt="Polkit: prompt"><br><sub>prompt · slides up out of the frame</sub></td></tr>
</table>

<a id="lockscreen"></a>

<img src="assets/headers/04-lockscreen.svg" width="100%" alt="04 Lockscreen">

<table>
<tr><td width="50%"><img src="gallery/04-lockscreen/01-lock.gif" width="100%" alt="Lockscreen: lock"><br><sub>lock · lock and unlock</sub></td><td width="50%"><img src="gallery/04-lockscreen/02-card.png" width="100%" alt="Lockscreen: card"><br><sub>card · type and the card appears</sub></td></tr>
</table>

<a id="sky"></a>

<img src="assets/headers/05-sky.svg" width="100%" alt="05 Sky">

<table>
<tr><td width="50%"><img src="gallery/05-sky/01-galaxy.gif" width="100%" alt="Sky: galaxy"><br><sub>galaxy · far light, spiral arms, dust</sub></td><td width="50%"><img src="gallery/05-sky/02-systems.gif" width="100%" alt="Sky: systems"><br><sub>systems · the home system turning</sub></td></tr>
<tr><td width="50%"><img src="gallery/05-sky/03-ships.gif" width="100%" alt="Sky: ships"><br><sub>ships · a ship crossing, then jumping</sub></td><td width="50%"><img src="gallery/05-sky/04-events.gif" width="100%" alt="Sky: events"><br><sub>events · warp out</sub></td></tr>
<tr><td width="50%"><img src="gallery/05-sky/05-far-light.png" width="100%" alt="Sky: far light"><br><sub>far light · hr 1, the far light</sub></td></tr>
</table>

<a id="desktop"></a>

<img src="assets/headers/06-desktop.svg" width="100%" alt="06 Desktop">

<table>
<tr><td width="50%"><img src="gallery/06-desktop/01-splash.png" width="100%" alt="Desktop: splash"><br><sub>splash · hyprctl splash under the notch</sub></td><td width="50%"><img src="gallery/06-desktop/02-osd.gif" width="100%" alt="Desktop: osd"><br><sub>osd · volume and brightness</sub></td></tr>
</table>

<a id="brand"></a>

<img src="assets/headers/07-brand.svg" width="100%" alt="07 Brand">

<table>
<tr><td width="50%"><img src="gallery/07-brand/01-lockup.png" width="100%" alt="Brand: lockup"><br><sub>lockup · the mark</sub></td><td width="50%"><img src="gallery/07-brand/02-meters.gif" width="100%" alt="Brand: meters"><br><sub>meters · system metrics as segment meters</sub></td></tr>
</table>

<a id="system"></a>

<img src="assets/headers/08-system.svg" width="100%" alt="08 System">

<table>
<tr><td width="50%"><img src="gallery/08-system/01-fastfetch.png" width="100%" alt="System: fastfetch"><br><sub>fastfetch · logo rendered by the shell</sub></td><td width="50%"><img src="gallery/08-system/02-terminal.png" width="100%" alt="System: terminal"><br><sub>terminal · kitty and yazi in the sky palette</sub></td></tr>
</table>

<!-- gallery:end -->

<a id="palette"></a>

## Palette

<img src="assets/palette.svg" width="100%" alt="Palette">

Everything uses these nine colours.

| | Hex | Where I use it |
| --- | --- | --- |
| `bg` | `#05070f` | the deepest part of the sky |
| `sky` | `#070a17` | wallpaper and canvas fill |
| `navy` | `#0b1330` | top of the sky, panels |
| `line` | `#1b2140` | borders and dividers |
| `muted` | `#8189a8` | quiet text |
| `blue` | `#b6c4ff` | accents, star glow |
| `engine` | `#a8eefc` | active states, engine trails, numbers |
| `ink` | `#cfdaf7` | text and hairlines |
| `core` | `#f6f7ff` | star cores, the brightest bits |

## Type

<img src="assets/type.svg" width="100%" alt="Michroma">

Michroma for anything that needs a voice, always in capitals, always spaced out.
The artwork here draws it as shapes, so it looks right on GitHub too.

## Layout

```
Hiraeth/
├── shell/      the shell (bar, notch, dashboard, lockscreen, desktop)
├── greeter/    login screen
├── polkit/     polkit agent
├── sky/        live wallpaper
├── brand/      logo masters, icons, generators
├── system/     Hyprland, Limine, fastfetch, kitty, app themes
├── gallery/    screenshots and GIFs, one folder per section
├── media/      the tour GIF and demo videos
└── assets/     the artwork on this page and the script that draws it
```

Right now only `gallery/`, `media/` and `assets/` are here.

## Screenshots

Each section has a numbered folder in `gallery/`, and pictures show up in filename order.
To add one, save it with the next number, for example `gallery/06-desktop/03-orrery.gif`,
then run `python3 assets/build.py` and the page updates. Captions and sections live in `SECTIONS`
at the top of the script.
