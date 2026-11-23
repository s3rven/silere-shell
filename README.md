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
  <b>Quiet by default. Visible when it matters.</b><br/>
  Your desktop should be the last thing you have to debug.
</p>

<p align="center">
  Silere is a lightweight Wayland desktop shell for <b>Hyprland</b> and <b>niri</b>, built with
  <a href="https://quickshell.org/">Quickshell</a>. Made for people who push their systems hard:
  developers, hackers, tinkerers, and anyone who expects their environment to stay responsive,
  predictable and out of the way.
</p>

<p align="center">
  <a href="#getting-started">Install or try</a> ·
  <a href="docs/usage.md">Everyday use</a> ·
  <a href="docs/troubleshooting.md">Troubleshooting</a> ·
  <a href="docs/README.md">All docs</a>
</p>

<p align="center">
  <img src="assets/shot-hero.webp" alt="Silere's floating bar with the menu open on Home and a notification beside it" width="100%"/>
</p>

Silere isn't trying to replace your desktop. It's trying to make the parts you interact with every
day feel effortless: the bar, notifications, tray and quick settings, in one process that replaces
Waybar and a notification daemon such as mako or dunst. It's what I run on my own desktop. Your
compositor config, launcher, wallpaper tool and lock screen stay your own.

## What's included

<table>
  <tr><td><b>Bar</b></td><td>Workspaces with app icons · window title · media with Now Playing and a visualizer · system monitor · tray · clock, calendar and weather</td></tr>
  <tr><td><b>Quick settings</b></td><td>Per-app volume · brightness, external monitors too · Wi-Fi, Bluetooth and VPN · power mode · Night Light · battery health and charge limit</td></tr>
  <tr><td><b>Notifications</b></td><td>Actions and inline replies · grouped conversations · searchable history · Do Not Disturb and quiet hours</td></tr>
  <tr><td><b>On-screen display</b></td><td>Volume, brightness and power mode · battery warnings · floating or inside the bar</td></tr>
  <tr><td><b>Look</b></td><td>Colours from your wallpaper · dark and light · your accent, interface size and bar shape</td></tr>
  <tr><td><b>Upkeep</b></td><td>Signed updates with rollback · <code>silere doctor</code> · try it in a window before you install</td></tr>
</table>

One process, near 0% CPU when idle and about 100 MB of memory ([how it's measured](docs/performance.md)).
You choose the widgets and their order.

## Getting started

You need **Hyprland or niri** and **Quickshell 0.3.1 or newer** built against **at least Qt 6.10**.
On Arch Linux:

```bash
sudo pacman -S --needed quickshell git curl ttf-jetbrains-mono-nerd
```

On other distributions, follow [Quickshell's install guide](https://quickshell.org/docs/v0.3.1/guide/install-setup/).

**Try it first.** The preview opens in a window with its own temporary settings. Its sound, network
and Bluetooth controls are live.

```bash
git clone --depth 1 https://github.com/s3rven/silere-shell
cd silere-shell
bash scripts/silere try    # Alt + / opens the menu, close the window to quit
```

**Install it.** Run `bash scripts/install.sh` from the clone, or:

```bash
curl -fsSL https://raw.githubusercontent.com/s3rven/silere-shell/main/scripts/install.sh | bash
```

The installer asks before it changes your compositor config and backs up what it edits. Stop your
old bar and notification daemon first; it shows which lines start them. Then run `silere run`.
The [installation guide](docs/install.md) has the details.

## Using it

| To open | Do this |
|---|---|
| Menu | Click the active workspace, or **Super + /** if you added the shortcut |
| Quick actions | Right-click the active workspace |
| Calendar | Click the clock |
| Now Playing | Right-click the media widget |
| Settings | Open the menu and choose **Settings**; **Ctrl+F** searches |

**Tab**, **Enter** and **Esc** work everywhere. Settings apply as you change them and are saved in
`~/.config/silere-shell/settings.json`. With several monitors, **Settings › System › Devices** picks
which ones show the bar. On Hyprland, **Settings › System › Keybinds** lists your shortcuts.

More in the [usage guide](docs/usage.md) and, for keybinds and scripts, the
[scripting guide](docs/scripting.md).

## Commands

| Command | What it does |
|---|---|
| `silere run` | Start the shell |
| `silere stop` / `silere restart` | Stop or restart it |
| `silere status` | Show what's running and the update state |
| `silere doctor` | Check your setup without changing anything |
| `silere log --follow` | Follow the log |
| `silere update` | Check for a signed release |

`silere help` lists the rest. See [updates and recovery](docs/updates.md) for installing and rolling
back releases.

## Screenshots

<p align="center">
  <img src="assets/shot-surfaces.webp" alt="Now Playing with cover art and seeking, beside the calendar and a notification with actions" width="100%"/>
</p>

<p align="center">
  <img src="assets/shot-settings.webp" alt="Theme settings for colour source, accent, base tone and bar surfaces" width="72%"/>
</p>

<p align="center">
  <img src="assets/shot-themes.webp" alt="The same desktop under four wallpapers, each in the colours Matugen draws from it, the last in light mode" width="100%"/>
</p>

## Works well with

Silere leaves these jobs to other programs. None are required; these are the ones I use.

| For | I use |
|---|---|
| Launcher, clipboard and window switching | [Vicinae](https://github.com/vicinaehq/vicinae) |
| Wallpaper | [awww](https://codeberg.org/LGFae/awww) |
| Colours from the wallpaper | [Matugen](https://github.com/InioX/matugen) |
| Lock screen and idle | [hyprlock](https://github.com/hyprwm/hyprlock) and [hypridle](https://github.com/hyprwm/hypridle) |
| Night light | [hyprsunset](https://github.com/hyprwm/hyprsunset) on Hyprland, [wlsunset](docs/troubleshooting.md#night-light-is-unavailable-on-niri) on niri |
| Screenshots | [grim](https://gitlab.freedesktop.org/emersion/grim), [slurp](https://github.com/emersion/slurp) and [Satty](https://github.com/gabm/Satty) |
| Audio visualizer | [Cava](https://github.com/karlstav/cava) |

Settings tells you when a control needs one of these. The [optional tools](docs/install.md#optional-tools)
table names the packages.

## Getting help

Run `silere doctor`, then check the [troubleshooting guide](docs/troubleshooting.md). For a bug
report, include the output of `silere version` and the steps to reproduce it.

[Ask a question](https://github.com/s3rven/silere-shell/discussions) · [Report a bug](https://github.com/s3rven/silere-shell/issues/new?template=bug_report.yml)

## Contributing

Fixes, ideas and docs are welcome. The [contributing guide](CONTRIBUTING.md) has the checks and
commit rules, and the [code guide](docs/forking.md) explains the layout. CI tests every change
against the oldest supported Quickshell and in nested compositor sessions
([what CI runs](docs/testing.md#what-ci-runs)). I test on Hyprland laptops, so reports from niri,
several monitors or NVIDIA help the most.

Using Silere? Tell me how it's going in [this thread](https://github.com/s3rven/silere-shell/discussions/3),
good or bad.

### On AI assistance

I use AI tools while building Silere. I review the changes and use the shell on my own desktop.
AI-assisted contributions are welcome too.

[MIT](LICENSE) © s3rven
