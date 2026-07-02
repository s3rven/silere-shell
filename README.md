<p align="center">
  <img src="assets/banner.svg" alt="silere shell - quiet by default." width="720"/>
</p>

> *silere*, from Latin: to be silent.

Silere is a Quickshell shell for Hyprland: bar, control menu, notifications, matugen/manual theming, night light, and optional cava visualizer.

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-3b3b3b?style=flat-square&labelColor=1c1c1c" alt="license: MIT"/></a>
  <a href="https://quickshell.outfoxxed.me/"><img src="https://img.shields.io/badge/quickshell-hyprland-5a4b6e?style=flat-square&labelColor=1c1c1c" alt="built on quickshell for hyprland"/></a>
</p>

<p align="center">
  <img src="assets/showcase.png" alt="silere shell showcase" width="900"/>
</p>

## Install

Requires `git`, Hyprland, and a current Quickshell build with the Hyprland, Wayland layer-shell, Widgets, Io, Bluetooth, Mpris, Notifications, PipeWire, SystemTray, and UPower modules.

```bash
git clone https://github.com/s3rven/silere-shell
cd silere-shell
bash scripts/install.sh
```

The installer copies Silere to `$XDG_CONFIG_HOME/silere-shell`, backs up existing files, and adds a marked Hyprland autostart block. Restart Hyprland, then verify with `bash scripts/check.sh`. Remove everything again with `bash scripts/uninstall.sh`.

## Optional tools

Each widget detects its tool at runtime; missing tools hide or trim the widget, nothing breaks.

| tool | enables |
|---|---|
| `pipewire` + `wireplumber` | volume, output picker |
| `upower` | battery |
| `nmcli` | network, Wi-Fi list |
| `brightnessctl` | brightness |
| `hyprsunset` | night light |
| `matugen` | wallpaper theming |
| `cava` | media visualizer |
| `powerprofilesctl` | power profiles |
| `inotifywait` | screenshot feedback |
| `checkupdates` / `apt` / `dnf` / `zypper` / `xbps-install` | package update badge |

## Controls

| area | action |
|---|---|
| workspaces | left-click switches; click the active marker to open the menu, right-click it for quick actions; middle-click moves the focused window; scroll switches when enabled |
| menu | Escape closes pickers and confirmations first, then the menu; click outside to close |
| clock | left-click opens the calendar; middle-click cycles seconds/date |
| calendar | scroll, arrows, or Left/Right changes month; the header jumps back to today |
| media | left-click play/pause; middle-click focuses the player; scroll skips tracks |
| volume | scroll adjusts; left-click mutes |
| brightness | scroll adjusts; arrow keys when focused |
| tray | left-click focuses/activates; middle-click secondary activate; right-click opens the menu; resting the pointer reveals the app name |
| history | click an entry to expand its full text; hover for per-item dismiss |
| updates | shell updates install only after confirmation; background checks only update the badge |

## Resource use

Idle sits around 0.8% CPU and ~100 MB PSS (RSS reads higher because it counts shared Qt/graphics mappings in full). The cava visualizer is the main optional cost and runs only while media is playing. Measure your own session with `bash scripts/bench.sh 10`.

## Troubleshooting

```bash
bash scripts/check.sh   # tool/service checks + smoke launch
qs -p shell.qml         # run in the foreground to see errors
```

Optional warnings from `check.sh` are usually fine; a smoke-launch `FAIL` means startup broke. If notifications never appear, another daemon likely owns `org.freedesktop.Notifications`.

## License

MIT (c) s3rven
