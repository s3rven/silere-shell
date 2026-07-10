<p align="center">
  <img src="assets/banner.svg" alt="silere shell - quiet by default." width="720"/>
</p>

<p align="center"><em>silere</em>, from Latin: to be silent.</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-3b3b3b?style=flat-square&labelColor=1c1c1c" alt="license: MIT"/></a>
  <a href="https://quickshell.outfoxxed.me/"><img src="https://img.shields.io/badge/quickshell-hyprland-5a4b6e?style=flat-square&labelColor=1c1c1c" alt="built on quickshell for hyprland"/></a>
</p>

Silere is a shell for Hyprland, built on Quickshell: a bar, a control menu, notifications, and colors pulled from your wallpaper or set by hand. The quiet part is the point. Widgets only exist when their tools do, anything with a background cost is off until you turn it on, and an idle session rounds to zero CPU.

It is also modular without being heavy: every bar widget can be reordered, moved between sides, or switched off, and appearance is tunable down to separators, outlines, and the active-workspace marker — all plain settings, no plugin layer, no daemon behind any of it.

<p align="center">
  <img src="assets/showcase.png" alt="silere shell showcase" width="900"/>
</p>

## Install

You need `git`, Hyprland, and a current Quickshell build with the Hyprland, Wayland layer-shell, Widgets, Io, Bluetooth, Mpris, Notifications, PipeWire, SystemTray, and UPower modules.

```bash
git clone https://github.com/s3rven/silere-shell
cd silere-shell
bash scripts/install.sh
```

The installer copies Silere to `$XDG_CONFIG_HOME/silere-shell`, backs up anything it would overwrite, and adds a marked autostart block to your Hyprland config. Restart Hyprland, then run `bash scripts/check.sh` to confirm everything is wired up. `bash scripts/uninstall.sh` removes it all again.

## Optional tools

Every widget checks for its tool at runtime. If a tool is missing, its widget hides and the rest of the shell keeps working.

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

Idle costs 0–0.5% CPU and ~100 MB PSS (~170 MB RSS). RSS looks bigger because it counts libraries shared with every other Qt app on your system; PSS is the number to trust.

Memory doesn't creep up over a session. Notification images and album art are decoded at capped sizes and dropped from the cache once they leave the screen, images don't keep a CPU-side copy once they're on the GPU, and the launcher tunes the allocator so freed pages return to the OS immediately. A notification burst costs a few MB and falls back within seconds; heavy use peaks near 260 MB RSS.

The menu is built the same way: pages load on first use, the settings pane builds one section at a time, and it all unloads again after the menu sits closed for a while.

The one real cost is the cava visualizer: 15 to 20% of a core while music plays, zero when it stops.

## Troubleshooting

```bash
bash scripts/check.sh   # tool/service checks + smoke launch
qs -p shell.qml         # run in the foreground to see errors
```

Optional warnings from `check.sh` are usually fine; a smoke-launch `FAIL` means startup broke. If notifications never appear, another daemon likely owns `org.freedesktop.Notifications`. If icons or text render in the wrong font, install a Nerd Font (e.g. `ttf-jetbrains-mono-nerd`) and run `fc-cache -f`. The `font` checks in `check.sh` catch this case.

On hybrid laptops with several entries under `/sys/class/backlight`, Silere prefers a raw panel backlight automatically. If brightness changes the wrong display, select the correct device under Settings > System.

## Contributing

Suggestions, fixes, and new features are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT (c) s3rven
