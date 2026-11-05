<p align="center">
  <picture>
    <source media="(prefers-color-scheme: light)" srcset="assets/banner-light.svg"/>
    <img src="assets/banner.svg" alt="Silere Shell" width="720"/>
  </picture>
</p>

<p align="center">
  <a href="https://github.com/s3rven/silere-shell/releases"><img src="https://img.shields.io/github/v/release/s3rven/silere-shell?style=flat-square&labelColor=0f1013&color=2a2d33&logo=github&logoColor=9a9ca1" alt="latest release"/></a>
  <a href="https://github.com/s3rven/silere-shell/actions/workflows/validate.yml"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fs3rven%2Fsilere-shell%2Fbadges%2Fchecks.json&style=flat-square" alt="checks passed on main"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2a2d33?style=flat-square&labelColor=0f1013" alt="license: MIT"/></a>
</p>

<p align="center">
  A desktop shell for <b>Hyprland</b> and <b>niri</b>, built on
  <a href="https://quickshell.org/">Quickshell</a>.<br/>
  <i>Quiet on the surface. Over-engineered underneath.</i>
</p>

<p align="center">
  <img src="assets/shot-desktop.webp" alt="Silere's floating bar on the desktop" width="960"/>
</p>

Silere is the bar, notifications, OSD, tray and quick settings I use every day, in one
process. It replaces waybar, mako or dunst and the small scripts around them. Your
compositor config, launcher, wallpaper tool and lock screen stay as they are.

[Install](#install) · [Controls](docs/usage.md) · [Fix a problem](docs/troubleshooting.md) · [All docs](docs/README.md)

## Philosophy

**Quiet.** Keep everyday information easy to glance at. Bring controls and detail
forward when needed, then return attention to your work.

**Efficient.** Do work when it serves the desktop. Avoid unnecessary polling,
disk writes and animations, and pause activity when it is no longer useful.

**Independent.** Fit into the desktop you already have. Keep your distribution,
compositor configuration and dotfiles, and choose the tools that run alongside Silere.

**Over-engineered.** Silere looks simple on purpose. The work is in what you never see:
what happens when a tool hangs, an app misbehaves or a session runs for days.
[Under the hood](#under-the-hood) shows it.

## Install

You need a Linux desktop running **Hyprland or niri**, and **Quickshell 0.3.1 or newer**
built against **at least Qt 6.10**. On Arch:

```bash
sudo pacman -S --needed quickshell git curl
curl -fsSL https://raw.githubusercontent.com/s3rven/silere-shell/main/scripts/install.sh | bash
```

Stop your old bar and notification daemon, then run this in a terminal inside your
Wayland session:

```bash
silere run
```

The installer offers fonts, autostart, a menu shortcut and the `silere` command. It asks
before editing your compositor config and backs up what it changes. `silere uninstall`
removes all of that and keeps your settings.

For other distributions, start with [Quickshell's install guide](https://quickshell.org/docs/v0.3.1/guide/install-setup/).
The [installation guide](docs/install.md) covers installing from a clone, previewing
changes, choosing a directory with `--dir`, unattended setup with `--yes`, and crash
recovery. If `silere` is not on your `PATH`, run
`~/.config/silere-shell/scripts/silere run`, using your install path if it differs.

## What's in it

| | |
|---|---|
| **Bar** | Workspaces with app icons, window title, media, network, volume, brightness, battery, tray, clock and a system monitor. You choose what shows and in what order. |
| **Menu** | Volume per output and per app, brightness, Wi-Fi, Bluetooth, VPN, power mode, night light, Keep Awake and Do Not Disturb. |
| **Notifications** | Actions, inline replies and searchable history. A conversation stays on one card, and you can mute any app. Volume scripts written for dunst or mako replace their card instead of stacking. |
| **Now Playing** | Cover art, seeking, player switching and an optional visualizer. |
| **OSD** | Volume, brightness, power mode changes and battery warnings, floating or built into the bar. |
| **Colours** | Taken from your wallpaper through Matugen, or an accent you pick. |
| **Updates** | Signed releases, installed from the menu. `silere update --rollback` puts the last version back. |

<p align="center">
  <img src="assets/shot-surfaces.webp" alt="Silere's Home, Now Playing and Settings panels" width="960"/>
</p>

## What it leaves to you

Silere doesn't include an app launcher, wallpaper picker, lock screen, clipboard manager
or AI assistant. It calls the tools you already use, and Settings is where you point it
at them. It won't set up your system or replace your dotfiles either.

This is what I run next to it. None of it is required, and any of it can be swapped.

| For | I use |
|---|---|
| Launcher, clipboard history, file search, window switching | [Vicinae](https://github.com/vicinaehq/vicinae) |
| Wallpaper | [awww](https://codeberg.org/LGFae/awww) |
| Colours from the wallpaper | [Matugen](https://github.com/InioX/matugen) |
| Lock screen and idle | [hyprlock](https://github.com/hyprwm/hyprlock) and [hypridle](https://github.com/hyprwm/hypridle) |
| Night light | [hyprsunset](https://github.com/hyprwm/hyprsunset) |
| Screenshots | [grim](https://gitlab.freedesktop.org/emersion/grim), [slurp](https://github.com/emersion/slurp) and [Satty](https://github.com/gabm/Satty) |
| Audio visualizer | [cava](https://github.com/karlstav/cava) |

## Getting around

| To open | Do this |
|---|---|
| Menu | Click the active workspace, or Super + / if you took the shortcut |
| Quick actions | Right-click the active workspace |
| Calendar | Click the clock |
| Now Playing | Right-click the media widget |

Escape steps back one level, then closes. Tab, Shift+Tab, Enter and the arrow keys work
through the controls, and an open dropdown takes typing to find a row.
[docs/usage.md](docs/usage.md) lists the rest.

## Settings

Everything is in the menu under **Settings** and applies as you change it. A page you've
changed shows a dot in the sidebar, and **Settings › System › Overview** restores the
defaults. Press **Ctrl+F** in Settings to find an option by name or feature.

<p align="center">
  <img src="assets/shot-themes.png" alt="Silere with a custom accent and colours taken from the wallpaper" width="720"/>
</p>

Preferences live in `~/.config/silere-shell/settings.json`, which only stores what differs
from the defaults. A custom `$XDG_CONFIG_HOME` changes that location.
See [everyday use](docs/usage.md#settings) for customisation and
[scripting](docs/scripting.md) for keybinds, IPC calls and event hooks.

## Useful commands

| Command | What it does |
|---|---|
| `silere run` | Start the shell, or report that it is already running. |
| `silere stop` | Stop the shell and its user service, when installed. |
| `silere restart` | Restart the shell after an update or config change. |
| `silere doctor` | Check the setup without changing it. |
| `silere log --follow` | Follow the running shell's log. |
| `silere update` | Check for a signed release. |
| `silere help` | List all commands. |

Installing a release uses `silere update --apply`; undoing it uses
`silere update --rollback`. See [updates and recovery](docs/updates.md).

## Under the hood

**It doesn't look like much. That's the point.** Silere is the bar, notifications and menus
on the machine I use all day, so it has to keep working when things around it don't. I'd
rather ship a reliable shell than a fragile small one.

### Tested

About 22,000 lines of test tooling sit next to 42,000 lines of shell. Every change has to pass:

| Check | What it does |
|---|---|
| Logic | 2,400+ checks on services, parsers and state machines. |
| UI stress | 1,300+ checks with real pointer and wheel events, over 120 cycles. |
| Live settings | 192 settings states changed underneath 60 surfaces. |
| Popups | 107 behaviours, such as the bar changing under an open popup. |
| Layout | Menu labels have to fit at every interface size from 100% to 150%. |
| Real compositors | A whole shell in private Hyprland, niri and KWin sessions, with outputs added and removed. |
| Real audio | A private PipeWire with no hardware: volume feedback, a device replaced under its name, daemons restarting. |
| Oldest supported | The minimum Quickshell and Qt, plus 125% and 150% display scaling, in CI. |

An update has to start cleanly before it replaces the version you're running.

### Attacked

[`dev/test-faults.sh`](docs/testing.md#fault-injection) tries to break a running shell:

- Every tool it calls hangs forever, fails, returns garbage or returns nothing.
- Notifications arrive with 5 MB bodies, 60,000 combining marks on one character and the wrong type in every field.
- Media players send cover art urls that try to run commands, and thousands of signals a second.
- Tray items send broken icons and huge titles.

The shell has to stay up and responsive, throw no script errors and leave no stuck process behind.
If something still takes it down, it's back in about a second with your notification history intact.
[The known limits](docs/testing.md#fault-injection) are written down too.

### Measured

Releases record their memory and CPU in the [performance history](docs/perf-history.md).
An optimization that doesn't measure better doesn't ship.

| On my laptop | |
|---|---|
| Memory at start | About 80 MB |
| Memory once the menu has opened | About 95 MB |
| CPU at idle | About 0.2% of one core |
| Activity at idle | No processes started, nothing written to disk |
| Bar on screen after a restart | Under a second |

Those memory numbers use the [optional tuning](docs/performance.md#optional-tuning), with the
visualizer playing. Yours will depend on your hardware, fonts and which widgets you turn on.
[docs/performance.md](docs/performance.md) has the measurements and how to take your own.

The visualizer, network speed, clock seconds and underline effects start switched off, and
animations and system readings stop when the session goes idle.

Tools such as cava, Matugen and brightnessctl are optional. Without one, its feature is off and
Settings tells you what's missing. The [optional tools table](docs/install.md#optional-tools)
explains which package enables each feature.

## When something's wrong

`silere doctor` checks your setup, `silere log --follow` shows the log and `silere restart`
restarts the shell. [Common problems](docs/troubleshooting.md) covers the usual fixes.

[Ask a question](https://github.com/s3rven/silere-shell/discussions) · [Report a bug](https://github.com/s3rven/silere-shell/issues/new?template=bug_report.yml)

## Contributing

Fixes, ideas and documentation changes are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md)
and [the code guide](docs/forking.md).

### On AI assistance

I use AI tools while building Silere. I review the changes and use the shell on my own desktop.
AI-assisted contributions are welcome too.

[MIT](LICENSE) © s3rven
