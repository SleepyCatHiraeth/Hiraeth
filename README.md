<img src="assets/banner.png" width="100%" alt="Hiraeth">

<p align="center">
  <a href="#shell">Shell</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="#login">Login</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="#sky">Sky</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="#terminal">Terminal</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="#design">Design</a>
</p>

<br>

Hiraeth is my desktop for Hyprland on CachyOS. The shell, login screen, lockscreen, polkit prompt
and wallpaper share one look: a dark night sky, thin lines and a few bright stars.

*Hiraeth* is a Welsh word for homesickness for a place you can't go back to.

<img src="media/tour.gif" width="100%" alt="Opening the sidebar, dashboard and launcher">

<p align="center"><sub><a href="media/tour.mp4">Full tour, 1 min</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="media/greeter.mp4">Greeter</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="media/polkit-first-version.mp4">First polkit prototype</a></sub></p>

| Part | What it is | Source |
| :-- | :-- | :-- |
| Shell | Quickshell config: sidebar, notch, launcher, dashboard, notifications | not public yet |
| Greeter | greetd login screen | [Hiraeth-greeter](https://github.com/SleepyCatHiraeth/Hiraeth-greeter) |
| Polkit | Authentication agent | [Hiraeth-polkit](https://github.com/SleepyCatHiraeth/Hiraeth-polkit) |
| Sky | Animated wallpaper, also behind the lockscreen | not public yet |

<br>

<a id="shell"></a>
<picture><source media="(prefers-color-scheme: dark)" srcset="assets/headers/01-shell-dark.svg"><img src="assets/headers/01-shell-light.svg" width="100%" alt="Shell"></picture>

The bar sits on the left edge, the notch at the top. Everything else opens out of one of the two.

<img src="gallery/01-shell/04-dashboard.gif" width="100%" alt="Dashboard">
<p align="center"><sub>Dashboard with media, calendar, toggles and notifications</sub></p>

<table>
<tr>
<td width="50%"><img src="gallery/01-shell/02-launcher.gif" width="100%" alt="Launcher"><br><sub>Launcher</sub></td>
<td width="50%"><img src="gallery/01-shell/06-overview.gif" width="100%" alt="Overview"><br><sub>Workspace overview</sub></td>
</tr>
<tr>
<td><img src="gallery/01-shell/09-settings.gif" width="100%" alt="Settings"><br><sub>Settings and keybinds</sub></td>
<td><img src="gallery/01-shell/13-presets.gif" width="100%" alt="Presets"><br><sub>Presets swap the whole setup at once</sub></td>
</tr>
<tr>
<td><img src="gallery/01-shell/07-assistant.gif" width="100%" alt="Assistant"><br><sub>Assistant panel</sub></td>
<td><img src="gallery/01-shell/12-weather.gif" width="100%" alt="Weather and calendar"><br><sub>Calendar, weather and a focus timer</sub></td>
</tr>
<tr>
<td><img src="gallery/01-shell/14-mixer.gif" width="100%" alt="Mixer"><br><sub>Volume, mic and brightness</sub></td>
<td><img src="gallery/01-shell/15-power-profile.gif" width="100%" alt="Power profile"><br><sub>Power profile, cycled from the bar</sub></td>
</tr>
<tr>
<td><img src="gallery/01-shell/11-wallpapers.gif" width="100%" alt="Wallpapers"><br><sub>Wallpaper picker for images, GIFs and video</sub></td>
<td><img src="gallery/07-brand/02-meters.gif" width="100%" alt="System monitor"><br><sub>System monitor</sub></td>
</tr>
</table>

The notch holds the user, a Hyprland splash line and anything short-lived.

<table>
<tr>
<td width="50%"><img src="gallery/01-shell/03-notch.gif" width="100%" alt="Notch"><br><sub>Notch</sub></td>
<td width="50%"><img src="gallery/01-shell/05-notifications.gif" width="100%" alt="Notification"><br><sub>Notification</sub></td>
</tr>
<tr>
<td><img src="gallery/01-shell/08-capture.gif" width="100%" alt="Screen capture"><br><sub>Screenshot and recording tools</sub></td>
<td><img src="gallery/01-shell/10-power.gif" width="100%" alt="Power menu"><br><sub>Power menu</sub></td>
</tr>
<tr>
<td><img src="gallery/06-desktop/02-osd.gif" width="100%" alt="Volume OSD"><br><sub>Volume OSD</sub></td>
<td><img src="gallery/06-desktop/01-splash.png" width="100%" alt="Splash line"><br><sub>Splash line</sub></td>
</tr>
</table>

<br>

<a id="login"></a>
<picture><source media="(prefers-color-scheme: dark)" srcset="assets/headers/02-login-dark.svg"><img src="assets/headers/02-login-light.svg" width="100%" alt="Login"></picture>

The greeter replaces SDDM and uses whatever wallpaper the desktop has, animated ones included.
The lockscreen and the polkit prompt follow the same layout.

<img src="gallery/02-greeter/01-login.png" width="100%" alt="Greeter">

<table>
<tr>
<td width="50%"><img src="gallery/02-greeter/02-typing.gif" width="100%" alt="Typing the password"><br><sub>Password</sub></td>
<td width="50%"><img src="gallery/02-greeter/03-unlock.gif" width="100%" alt="Logging in"><br><sub>Logging in</sub></td>
</tr>
<tr>
<td><img src="gallery/02-greeter/04-wallpapers.gif" width="100%" alt="Greeter wallpapers"><br><sub>Desktop wallpaper carried over</sub></td>
<td><img src="gallery/02-greeter/05-live-wallpaper.png" width="100%" alt="Animated wallpaper"><br><sub>Animated wallpaper</sub></td>
</tr>
</table>

<img src="gallery/04-lockscreen/01-lock.gif" width="100%" alt="Lockscreen">
<p align="center"><sub>Lockscreen over the live sky</sub></p>

<table>
<tr>
<td width="50%"><img src="gallery/04-lockscreen/02-card.png" width="100%" alt="Lockscreen password card"><br><sub>The password card shows up once you type</sub></td>
<td width="50%"><img src="gallery/03-polkit/01-prompt.gif" width="100%" alt="Polkit prompt"><br><sub>Polkit prompt</sub></td>
</tr>
</table>

<br>

<a id="sky"></a>
<picture><source media="(prefers-color-scheme: dark)" srcset="assets/headers/03-sky-dark.svg"><img src="assets/headers/03-sky-light.svg" width="100%" alt="Sky"></picture>

A wallpaper drawn live instead of a picture. Stars drift, the galaxy turns slowly, and now and
then a ship passes through.

<img src="gallery/05-sky/01-galaxy.gif" width="100%" alt="Galaxy">

<table>
<tr>
<td width="50%"><img src="gallery/05-sky/02-systems.gif" width="100%" alt="Home system"><br><sub>Home system</sub></td>
<td width="50%"><img src="gallery/05-sky/03-ships.gif" width="100%" alt="Ship"><br><sub>A ship crossing, then jumping</sub></td>
</tr>
<tr>
<td><img src="gallery/05-sky/04-events.gif" width="100%" alt="Warp"><br><sub>Warp out</sub></td>
<td><img src="gallery/05-sky/05-far-light.png" width="100%" alt="Far light"><br><sub>HR 1, the far light from the logo</sub></td>
</tr>
</table>

<br>

<a id="terminal"></a>
<picture><source media="(prefers-color-scheme: dark)" srcset="assets/headers/04-terminal-dark.svg"><img src="assets/headers/04-terminal-light.svg" width="100%" alt="Terminal"></picture>

<img src="gallery/08-system/02-terminal.png" width="100%" alt="Terminal and yazi">
<p align="center"><sub>The terminal and yazi in the Hiraeth colours</sub></p>

<p align="center"><img src="gallery/08-system/01-fastfetch.png" width="60%" alt="fastfetch"></p>
<p align="center"><sub>fastfetch, with the logo drawn by the shell</sub></p>

<br>

<a id="design"></a>
<picture><source media="(prefers-color-scheme: dark)" srcset="assets/headers/05-design-dark.svg"><img src="assets/headers/05-design-light.svg" width="100%" alt="Design"></picture>

The logo is HIRAETH in Michroma under seven stars, one for each letter. The brightest one sits
over the A. The bar icons are small constellations drawn the same way.

<picture><source media="(prefers-color-scheme: dark)" srcset="assets/palette-dark.svg"><img src="assets/palette-light.svg" width="100%" alt="Palette"></picture>

| Name | Hex | Used for |
| :-- | :-- | :-- |
| bg | `#05070f` | Deepest background |
| sky | `#070a17` | Wallpaper |
| navy | `#0b1330` | Panels |
| line | `#1b2140` | Borders |
| muted | `#8189a8` | Secondary text |
| blue | `#b6c4ff` | Accents, star glow |
| engine | `#a8eefc` | Active states |
| ink | `#cfdaf7` | Text and lines |
| core | `#f6f7ff` | Highlights |

<br>

<picture><source media="(prefers-color-scheme: dark)" srcset="assets/type-dark.svg"><img src="assets/type-light.svg" width="100%" alt="Michroma"></picture>

<br>

## Credits

- [Quickshell](https://quickshell.org), the QML toolkit the shell runs on
- [Ambxst](https://github.com/Axenide/Ambxst), which the shell started as a fork of
- [Michroma](https://fonts.google.com/specimen/Michroma) by Vernon Adams, SIL Open Font License
