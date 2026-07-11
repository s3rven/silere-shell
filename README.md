<p align="center">
  <img src="assets/banner.svg" alt="silere shell - quiet by default." width="720"/>
</p>

<p align="center"><em>silere</em>, from Latin: to be silent.</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-747a98?style=flat-square&labelColor=17181d" alt="license: MIT"/></a>
  <a href="https://quickshell.outfoxxed.me/"><img src="https://img.shields.io/badge/built%20on-Quickshell-747a98?style=flat-square&labelColor=17181d" alt="built on Quickshell"/></a>
  <img src="https://img.shields.io/badge/runs%20on-Hyprland%20%C2%B7%20niri-747a98?style=flat-square&labelColor=17181d" alt="runs on Hyprland and niri"/>
</p>

Silere is a quiet shell for Hyprland and niri, built on Quickshell: a bar, a control menu, notifications, and colors pulled from your wallpaper or picked by hand. The quiet part is the point. Widgets only exist when their tools do, anything with a background cost stays off until you turn it on, and an idle session rounds to zero CPU. Every widget reorders, moves side to side, or switches off, and the look tunes down to separators and outlines. All plain settings, no plugin layer, no daemon.

<p align="center">
  <img src="assets/showcase.png" alt="silere shell showcase" width="900"/>
</p>

## Install

You need `git`, Hyprland or niri, and a current Quickshell build.

```bash
git clone https://github.com/s3rven/silere-shell
cd silere-shell
bash scripts/install.sh
```

The installer copies Silere to `$XDG_CONFIG_HOME/silere-shell`, backs up anything it touches, and adds an autostart entry for whichever compositor you're on. Restart it and Silere comes up on its own. To remove everything: `bash scripts/uninstall.sh`.

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

| area | actions |
|---|---|
| workspaces | click switches. On the active diamond, click opens the menu and right-click opens quick actions. Middle-click sends the focused window to that workspace. |
| clock | click opens the calendar. Middle-click cycles seconds and date. |
| calendar | scroll or arrow keys change the month. Click the header to jump back to today. |
| media | click plays or pauses. Scroll changes track. Middle-click jumps to the player. |
| volume | scroll changes volume. Click mutes. |
| brightness | scroll changes brightness. |
| tray | click jumps to the app. Right-click opens its menu. |
| menu | Escape steps back, then closes. Click anywhere outside to close. |
| history | click an entry to read it in full. |

Shell and package updates never install on their own; checks only update the badge, installing always takes a click.

## Resource use

Idle sits around half a percent of one core and 100 to 115 MB of memory (PSS). The optional clock seconds cost a bit more, closer to one percent. RSS reads higher because it counts libraries shared with every other Qt app, so PSS is the honest number. Memory doesn't creep over a session: album art and notification images drop from cache once they leave the screen, and the launcher tunes the allocator so freed pages go straight back to the OS. Heavy use peaks near 260 MB RSS and settles within seconds. The GPU rests too: the shell renders a frame only when something on screen changes.

The one real cost is the cava visualizer: 15 to 20% of a core while music plays, and nothing once it stops.

## Troubleshooting

If something looks off, run the shell in the foreground to read its errors:

```bash
qs -p shell.qml
```

If notifications never appear, another daemon probably owns `org.freedesktop.Notifications`. If icons or text render in the wrong font, install a Nerd Font (like `ttf-jetbrains-mono-nerd`) and run `fc-cache -f`. On hybrid laptops with several `/sys/class/backlight` entries, pick the right display under Settings > System.

## Contributing

Ideas, fixes, and new features are all welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) to get started.

## License

MIT (c) s3rven
