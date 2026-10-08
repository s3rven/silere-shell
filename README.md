<p align="center">
  <picture>
    <source media="(prefers-color-scheme: light)" srcset="assets/banner-light.svg"/>
    <img src="assets/banner.svg" alt="Silere Shell — quiet by default" width="720"/>
  </picture>
</p>

<p align="center">
  <a href="https://github.com/s3rven/silere-shell/releases"><img src="https://img.shields.io/github/v/release/s3rven/silere-shell?style=flat-square&labelColor=0f1013&color=2a2d33" alt="Latest release"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2a2d33?style=flat-square&labelColor=0f1013" alt="MIT license"/></a>
</p>

<p align="center">A desktop shell for <b>Hyprland</b> and <b>niri</b>.</p>
<p align="center"><a href="#install">Install</a> · <a href="#use">First steps</a> · <a href="docs/usage.md">Controls</a> · <a href="#help">Help</a></p>

Silere runs in your existing desktop session. It combines a bar, notifications,
calendar, system tray and quick controls in one interface built with Quickshell.
Change its layout and appearance from the menu.

The visualizer, network speed readings and clock seconds start switched off.
[See the performance measurements](docs/performance.md).

<p align="center">
  <img src="assets/shot-surfaces.gif" alt="Silere's Home, Now Playing and Settings pages" width="480"/>
  <br/>
  <sub><a href="assets/shot-surfaces.webp">View the still preview</a></sub>
</p>

- Arrange your bar and choose the widgets you need.
- Control audio, brightness, Wi-Fi, Bluetooth and power from one menu.
- Search past notifications and control your music in Now Playing.
- Pick your colours, use a wallpaper palette, and adjust the font, scale and motion.

<details>
<summary>Desktop, popups and themes</summary>

<p align="center"><img src="assets/shot-desktop.webp" alt="Silere's floating bar on the desktop" width="960"/></p>
<p align="center"><img src="assets/shot-popups.webp" alt="Notifications, calendar, volume display and quick actions" width="960"/></p>
<p align="center"><img src="assets/shot-themes.webp" alt="Custom accent and wallpaper colours" width="720"/></p>

</details>

## Install

### 1. Install the prerequisites

You need a **Hyprland or niri session**, **git**, and **Quickshell 0.3.1 or newer**,
built against **at least Qt 6.9**. The one-line installer below also needs **curl**.

On Arch Linux:

```bash
sudo pacman -S --needed quickshell git curl
```

For other distributions, follow [Quickshell's install guide](https://quickshell.org/docs/v0.3.1/guide/install-setup/).

### 2. Install Silere

```bash
curl -fsSL https://raw.githubusercontent.com/s3rven/silere-shell/main/scripts/install.sh | bash
```

The installer offers fonts, autostart, the menu shortcut and a `silere` command.
It asks before editing your compositor config and backs up files it changes.
The default install is `~/.config/silere-shell`.

[Install from a clone, preview the changes, or choose another path](docs/install.md).

### 3. Start the shell

Stop your previous bar and notification daemon, then run:

```bash
silere run
```

If you skipped the command link, use `~/.config/silere-shell/scripts/silere run`.
Keep your preferred launcher, wallpaper tools and lock screen; choose the lock command
in **Settings › Appearance › Interface**.

## Use

| To open | Do this |
|---|---|
| Menu | Click the active workspace |
| Quick actions | Right-click the active workspace |
| Calendar | Click the clock |
| Now Playing | Right-click the media widget |

The installer offers **Super + /** as a menu shortcut on Hyprland. Press **Escape**
to step back or close a popup. [All controls and shortcuts](docs/usage.md).

Open **Settings** to change the shell. Changes apply immediately.
**System › Overview** holds updates, diagnostics and restore defaults.
Silere verifies release signatures and asks for confirmation in the menu.
[Updating and rolling back](docs/usage.md#updates).

<details>
<summary>Config files and scripting</summary>

Preferences are saved to `~/.config/silere-shell/settings.json`, or your
`$XDG_CONFIG_HOME` path. Only changes from the defaults are stored.
To reset the file, replace its contents with `{ "__version": 1 }`.
[The scripting guide](docs/scripting.md) lists IPC calls and event hooks.

</details>

## Help

Start with `silere doctor` to check your setup. `silere log --follow` shows the log,
and `silere restart` restarts the shell.

[Common problems](docs/troubleshooting.md) · [Ask a question](https://github.com/s3rven/silere-shell/discussions) · [Report a bug](https://github.com/s3rven/silere-shell/issues/new?template=bug_report.yml)

| Guide | What you'll find |
|---|---|
| [Installation](docs/install.md) | Fonts, optional tools, autostart and removal |
| [Controls](docs/usage.md) | Widgets, settings and updates |
| [Scripting](docs/scripting.md) | IPC calls and event hooks |
| [Performance](docs/performance.md) | Measurements and benchmarking |
| [Changelog](CHANGELOG.md) | Changes and release history |

## Contributing

Fixes, ideas and documentation changes are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md)
and [the code guide](docs/forking.md).

### On AI assistance

I use AI tools while building Silere. I review the changes and use the shell on my own desktop.
AI-assisted contributions are welcome too.

[MIT](LICENSE) © s3rven
