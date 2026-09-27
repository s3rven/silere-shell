<p align="center">
  <picture>
    <source media="(prefers-color-scheme: light)" srcset="assets/banner-light.svg"/>
    <img src="assets/banner.svg" alt="silere shell - quiet by default." width="720"/>
  </picture>
</p>

<p align="center">
  <a href="https://github.com/s3rven/silere-shell/releases"><img src="https://img.shields.io/github/v/release/s3rven/silere-shell?style=flat-square&labelColor=0f1013&color=2a2d33&logo=github&logoColor=9a9ca1" alt="latest release"/></a>
  <a href="https://github.com/s3rven/silere-shell/actions/workflows/validate.yml"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fs3rven%2Fsilere-shell%2Fbadges%2Fchecks.json&style=flat-square" alt="checks passed on main"/></a>
  <a href="#performance"><img src="https://img.shields.io/badge/idle-under%201%25%20CPU-2a2d33?style=flat-square&labelColor=0f1013" alt="idle: under 1% CPU"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2a2d33?style=flat-square&labelColor=0f1013" alt="license: MIT"/></a>
  <a href="https://quickshell.org/"><img src="https://img.shields.io/badge/built%20on-Quickshell-2a2d33?style=flat-square&labelColor=0f1013" alt="built on Quickshell"/></a>
  <img src="https://img.shields.io/badge/runs%20on-Hyprland%20%C2%B7%20niri-2a2d33?style=flat-square&labelColor=0f1013&logo=hyprland&logoColor=9a9ca1" alt="runs on Hyprland and niri"/>
</p>

Silere is a bloat-free desktop shell for Hyprland and niri, built on Quickshell. It's the
bar, the menu, notifications, the OSD, the calendar and the tray, all running in one
process, and its only runtime dependency is Quickshell.

The name is Latin for *to be silent*, and that's the idea. An idle session sits well under
1% of one CPU core, because timers and polls only run while something on screen needs
them, and it uses [roughly 80 to 100 MB](#performance) of memory. Every setting is in the
menu and applies the moment you change it. There's no plugin system; hooks run your own
commands as separate processes with a time limit.

<p align="center">
  <img src="assets/shot-desktop.webp" alt="The floating Silere bar with the home page open and a notification" width="900"/>
</p>

## Features

- A bar with workspaces, the window title, media, network, Bluetooth, volume, microphone,
  brightness, battery, the clock, the tray, and badges for package and shell updates. Drag
  widgets between the left, centre and right, and put the bar on the top or bottom edge,
  docked or floating.
- One menu for quick controls, every setting, and your notification history.
- Notifications with actions, images, inline replies and quiet hours, plus a history you
  can search and filter by app. Middle-click a notification to jump to the app that sent it.
- Colours from your wallpaper through Matugen, or an accent you pick, over three dark base
  tones. With a translucent bar, Hyprland 0.56 and niri 26.04 blur what's behind it.
- A calendar from the clock, an OSD for volume, brightness and mic mute, and quick actions
  for Do Not Disturb, night light, power mode, Wi-Fi, Bluetooth and airplane mode.
- A bar on every screen, or only the ones you pick, with notifications and the OSD
  following focus or staying on one display.

There's no launcher, dock, lock screen, wallpaper setter or clipboard manager here, so keep
whichever ones you already use. The lock button runs hyprlock, swaylock, gtklock,
`loginctl lock-session` or a command of your own.

<p align="center">
  <img src="assets/shot-surfaces.webp" alt="The home page, the settings rail, and the calendar" width="900"/>
</p>

<p align="center">
  <img src="assets/shot-popups.webp" alt="The floating bar, notification history, a notification, the OSD and quick actions" width="900"/>
</p>

<p align="center">
  <img src="assets/shot-themes.webp" alt="The home page in the neutral theme, and in colours taken from the wallpaper" width="900"/>
  <br/>
  <sub>The neutral theme, and the colours Matugen took from the wallpaper.</sub>
</p>

## Install

You need Hyprland or niri, Quickshell 0.3.1 or newer built on Qt 6.9 or newer, and `git`.
On Arch, `sudo pacman -S --needed quickshell git` covers it. For other distros, follow
[Quickshell's install guide](https://quickshell.org/docs/v0.3.1/guide/install-setup/).

```bash
git clone https://github.com/s3rven/silere-shell
cd silere-shell
bash scripts/install.sh
```

The checkout goes to `~/.config/silere-shell` unless you pick another path. The installer
backs up every file it edits and asks before it adds autostart, and `--dry-run` prints the
whole plan without writing anything.

Restart your compositor, or run `silere run` to start it now. If you skipped the `silere`
command, that's `~/.config/silere-shell/scripts/silere run`, and
`~/.config/silere-shell/scripts/silere link` adds the command later.

Volume, battery, brightness, night light and the rest show up once their tool is
installed. `silere doctor` lists what's missing and checks the install without changing
anything, `silere log --follow` shows the running shell's log, and `silere restart` starts
it again.

[docs/install.md](docs/install.md) covers fonts, optional tools, unattended installs,
Matugen and uninstalling, and [docs/troubleshooting.md](docs/troubleshooting.md) the
common problems.

## Usage

The installer offers to bind the menu to **Super + /**, and clicking the active workspace
(the diamond) opens it too. On niri, or with a Hyprland config written in Lua, add the bind
yourself. niri runs it without a shell, so write out the full path:

```bash
qs ipc -p ~/.config/silere-shell/shell.qml call menu toggle
```

Everything else is done with the mouse. The only keyboard paths are Escape, Ctrl+F in the
notification history, and text fields.

<details>
<summary>Every widget's controls</summary>


| area | pointer |
|---|---|
| workspaces | **click** switches · on the active diamond, **click** opens the menu and **right-click** opens quick actions · **middle-click** sends the focused window there · **scroll** switches too, once you turn it on under Settings › Widgets › Workspaces |
| clock | **click** opens the calendar · **middle-click** cycles seconds and date |
| calendar | **scroll** changes the month · **click** the header to jump back to today · **click** a date to mark it · choose week start and week numbers under Settings › Widgets › Clock |
| media | **click** plays or pauses · **scroll** changes track · **middle-click** jumps to the player |
| volume | **scroll** changes volume · **click** mutes · **middle-click** moves to the next output · **right-click** opens pwvucontrol or pavucontrol · in the menu, expand it for output, input and per-app levels |
| microphone | **click** mutes · **scroll** changes the input level · **middle-click** moves to the next input · **right-click** opens pwvucontrol or pavucontrol · it appears while an app is listening |
| brightness | **scroll** changes brightness |
| updates | **click** rechecks for packages |
| shell update | **click** opens Settings › System › Updates |
| tray | **click** jumps to the app's window, or activates the app when it has none · **right-click** opens its menu · **middle-click** runs the app's secondary action · **scroll** is passed through to the app |
| notifications | **click** runs the default action · **right-click** dismisses · **middle-click** jumps to the app that sent it · a reply action opens an inline text field when the sender supports one |
| wi-fi list | **click** joins a saved network, or opens a password field for a personal one · **right-click** or **middle-click** a saved network twice to forget it, unless you are connected to it |
| bluetooth list | **click** pairs or connects · **right-click** or **middle-click** a paired device twice to forget it, unless it is connected |
| menu | **Escape** steps back, then closes · **click** anywhere outside to close |
| history | **type** in Search, or press **Ctrl+F** to get there, to find an app or message · **click** an app in the rail to show only its notifications · **click** an entry to read it in full · **Clear** removes what's shown, after a second click to confirm · **Escape** clears search, then closes |

</details>

## Settings and scripting

Settings save themselves as you change them. If you want the file, it's
`$XDG_CONFIG_HOME/silere-shell/settings.json` wherever the checkout lives, and it only
holds what differs from the defaults. Values are type-checked and clamped on load, and a
file Silere can't read is left alone instead of being overwritten.

To start over, use **Settings › System › Maintenance** or replace the file with
`{ "__version": 1 }`. Deleting a single key resets just that option.

The menu, calendar, quick actions and settings also answer over Quickshell IPC, and Silere
can run an executable of yours on events like `battery-critical` or `workspace-changed`.

```bash
silere ipc menu toggle
silere ipc calendar toggle
silere ipc quickActions dnd
silere ipc settings set osdTimeout 3000
```

Without the `silere` command, each call is `qs ipc -p ~/.config/silere-shell/shell.qml call`
followed by the same words. [docs/scripting.md](docs/scripting.md) has every call, the
settings page names and the hooks.

## Updates

Nothing installs itself. Shell updates follow stable tags, only accept releases signed with
the key bundled in the checkout, and show you the new commits before a two-step
confirmation. A signature proves who published a release, not that its code is harmless.
Package updates just move the badge.

## Performance

An idle session uses well under 1% of one CPU core. Memory, measured on the reference
machine as proportional set size (PSS):

| state | memory |
|---|---|
| an empty Quickshell panel, for comparison | ~57 MB |
| Silere, before the menu is first opened | ~82 MB |
| Silere, after the menu has opened once | ~93 MB |

Most of that is Qt and the GPU driver. The first time the menu opens it loads code and
caches that stay resident, so the number goes up once and then holds.

Run `bash scripts/bench.sh 30` to measure your own checkout, or add `--warm` for the
after-menu number. [docs/performance.md](docs/performance.md) explains the method, and
[docs/perf-history.md](docs/perf-history.md) has the numbers for each release.

## Docs

- [install.md](docs/install.md): optional tools, fonts, Matugen, unattended installs, removal
- [scripting.md](docs/scripting.md): IPC calls, settings over IPC, page names, hooks
- [troubleshooting.md](docs/troubleshooting.md): symptom by symptom, starting with `silere doctor`
- [performance.md](docs/performance.md): how the numbers are measured, fonts, the animation driver
- [forking.md](docs/forking.md): the tree, and what a change or a rename has to touch
- [releasing.md](docs/releasing.md): tags, signing and key rotation, for maintainers
- [CHANGELOG.md](CHANGELOG.md): what changed since the last release, with older ones in [docs/releases](docs/releases/)

## Contributing

Bug fixes, new widgets and half-finished ideas are all welcome.
[CONTRIBUTING.md](CONTRIBUTING.md) has the short version, and
[Discussions](https://github.com/s3rven/silere-shell/discussions) is the place for
questions. If you'd rather fork it and make it your own, [docs/forking.md](docs/forking.md)
maps the tree.

## On AI assistance

I use AI tools to build Silere, and I think it makes the project better. It's just me
working on this. With the help, bugs get fixed the same day I find them instead of sitting
around for weeks.

I still decide what goes in, and I read every change myself. Silere is the only desktop I
use, so anything broken breaks my own machine first.

AI-assisted pull requests are welcome too. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT (c) s3rven
