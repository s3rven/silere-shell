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

```bash
git clone https://github.com/s3rven/silere-shell
cd silere-shell
bash scripts/install.sh
```

The installer copies Silere to `$XDG_CONFIG_HOME/silere-shell`, backs up existing files, and adds a marked Hyprland autostart block. Restart Hyprland, then check the install:

```bash
bash scripts/check.sh
```

Uninstall:

```bash
bash scripts/uninstall.sh
```

## Controls

| area | action |
|---|---|
| workspaces | left-click inactive to switch; left/right-click active marker to open the menu; middle-click to move the focused window; scroll to switch when `Scroll to switch` is enabled |
| menu | Escape closes an open picker or power confirmation first, then the menu; click outside to close |
| clock | left-click opens calendar; middle-click cycles seconds/date display |
| calendar | scroll, arrow buttons, or Left/Right changes month; today header or month label jumps back to the current month |
| media | left-click toggles play/pause; middle-click focuses the player; scroll skips tracks |
| volume | scroll adjusts; left-click mutes/unmutes |
| brightness | scroll adjusts; arrow keys work when focused |
| tray | left-click focuses or activates the item; middle-click sends secondary activate; right-click opens native menu; scroll passes through |

Updates are under `Settings -> Updates`. Shell updates install only after confirmation. Daily shell checks only update the badge.

## Requirements

Required: `git`, Hyprland, and a current Quickshell build with the Hyprland, Wayland layer-shell, Widgets, Io, Bluetooth, Mpris, Notifications, PipeWire, SystemTray, and UPower modules.

Optional widgets use `pipewire`/`wireplumber`, `upower`, `nmcli`, `brightnessctl`, `inotifywait`, `cava`, `matugen`, `hyprsunset`, `power-profiles-daemon`, and one supported package manager (`checkupdates`, `apt`, `dnf`, `zypper`, or `xbps-install`). Missing optional tools disable or trim the related widget. `scripts/check.sh` reports what is available and runs a smoke launch.

## Resource Use

Memory varies by Qt, graphics drivers, allocator, enabled widgets, and helper processes. RSS around 175-200 MB idle is not unusual because RSS counts shared Qt and graphics mappings in full. PSS/USS are better for comparing shell-private memory; one sample was 101 MB PSS / 76 MB USS for `qs`, or 106 MB PSS including helpers, at about 0.8% CPU.

Measure your session:

```bash
bash scripts/bench.sh 10
```

The cava visualizer is the main optional CPU cost and only runs while media is playing.

## Troubleshooting

```bash
bash scripts/check.sh
qs list --all
qs -p shell.qml
```

Optional warnings from `check.sh` are usually fine. A smoke-launch `FAIL` means startup broke. If notifications never appear, check whether another daemon owns `org.freedesktop.Notifications`.

## License

MIT (c) s3rven
