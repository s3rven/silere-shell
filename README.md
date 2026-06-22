<p align="center">
  <img src="assets/banner.svg" alt="silere shell — quiet by default." width="720"/>
</p>

> *silere*, from Latin: to be silent.

A Quickshell shell for Hyprland. Most shells come pre-loaded. Silere starts quiet and you turn things on.

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-3b3b3b?style=flat-square&labelColor=1c1c1c" alt="license: MIT"/></a>
  <a href="https://quickshell.outfoxxed.me/"><img src="https://img.shields.io/badge/quickshell-hyprland-5a4b6e?style=flat-square&labelColor=1c1c1c" alt="built on quickshell for hyprland"/></a>
</p>

<p align="center">
  <img src="assets/showcase.png" alt="silere shell showcase" width="900"/>
</p>

---

**bar:** workspaces, clock, media, volume, brightness, battery, network, tray.

**menu:** control center with quick toggles, sliders, and a full settings UI.

**notifications:** native server with a popup stack, do-not-disturb, and history.

**theming:** wallpaper-based via [matugen](https://github.com/InioX/matugen), or set your own accent. night light included. optional [cava](https://github.com/karlstav/cava) visualizer.

---

## install

```bash
git clone https://github.com/s3rven/silere-shell
cd silere-shell
bash scripts/install.sh
```

The installer puts everything in `$XDG_CONFIG_HOME/silere-shell` — the clone is just to fetch and run this script and can be deleted after. It seeds cava and matugen configs, optionally installs JetBrainsMono Nerd Font, and wires autostart into your Hyprland config. Existing files are backed up. Uninstall removes only Silere's marked blocks and leaves the rest alone.

Restart Hyprland once it's done, then:

```bash
bash scripts/check.sh   # verify deps + smoke launch
```

---

## first use

The bar is the only thing on screen by default. Everything below is a click away.

- **menu:** click the active workspace diamond, then **Settings** for appearance, widgets, behavior, and updates.
- **calendar:** click the clock. Scroll or use the arrows to change month; click the month label to jump back to today. Middle-click the clock to cycle date and seconds visibility.
- **bar:** click a workspace to switch; middle-click to send the active window there. Scroll over volume or brightness to adjust, click volume to mute. Right-click tray icons for their menus.
- **updates:** **Settings → Updates** checks for and applies Silere updates. A daily background check can be enabled; it only raises a badge in the bar and never installs anything on its own. A separate package update count (distro packages, not Silere) lives under **Settings → Indicators** and requires a supported package manager — see the deps table below.

Escape or a click outside closes any popup.

---

## dependencies

`git`, Hyprland, and a current Quickshell build (`qs`) are required. Silere imports the Hyprland, Wayland layer-shell, Widgets, Io, Bluetooth, Mpris, Notifications, PipeWire, SystemTray, and UPower modules unconditionally, so a build that splits or disables any of them won't load. `bash scripts/check.sh` reports which modules are present and catches import failures at startup.

Everything else is per-feature. Missing tools hide or trim the widget they back rather than blocking the shell.

| tool | feature |
|---|---|
| pipewire / wireplumber | audio |
| upower | battery status + warnings |
| networkmanager / nmcli | network |
| brightnessctl | brightness |
| inotify-tools | instant brightness + screenshot flash |
| cava | media visualizer |
| matugen | wallpaper theming |
| hyprsunset | night light |
| power-profiles-daemon | power profiles |
| checkupdates / apt / dnf / zypper / xbps-install | package update badge |

---

## performance

One machine, idle, with the installer's launch environment: **101 MB PSS / 76 MB USS** in Quickshell (or **106 MB PSS** including Silere's watcher processes), at 0.8% CPU. RSS reads higher (175 MB) because it counts shared Qt and graphics mappings in full; PSS and USS are the numbers worth comparing between shells.

Run `bash scripts/bench.sh 10` against a live checkout for your own numbers. Without the installer's launch environment you'll see around 316 MB RSS and `allocator default` in the output — the gap is jemalloc and EGL tuning written into the autostart line.

The cava visualizer is the one feature with a real CPU cost. It scales with the framerate in `assets/cava.conf` (60 by default), runs only while music is playing, and stops when the screen blanks.

---

## troubleshooting

`bash scripts/check.sh` is the first stop. It checks modules, tools, notification-daemon ownership, generated config files, and does a short smoke launch. A warning on an optional feature is fine; a `FAIL` on the smoke launch means something's actually broken.

For a readable startup error, stop the running instance and run `qs -p shell.qml` from the repo inside a Hyprland session. `qs list --all` lists running instances. Re-running the installer repairs generated files and autostart wiring. If notifications never appear, check that nothing else owns `org.freedesktop.Notifications`.

---

## license

MIT © s3rven
