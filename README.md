<p align="center">
  <img src="assets/banner.svg" alt="silere shell — quiet by default." width="720"/>
</p>

> *silere*, from Latin: to be silent.

A Quickshell shell for Hyprland. Most shells come pre-loaded. Silere starts quiet and you turn things on.

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-3b3b3b?style=flat-square&labelColor=1c1c1c" alt="license: MIT"/></a>
  <a href="https://quickshell.outfoxxed.me/"><img src="https://img.shields.io/badge/quickshell-hyprland-5a4b6e?style=flat-square&labelColor=1c1c1c" alt="built on quickshell for hyprland"/></a>
</p>

---

**bar:** workspaces, clock, media, volume, brightness, battery, network, tray.

**menu:** control center with quick toggles, sliders, and a full settings UI.

**notifications:** native server with popup stack, do-not-disturb, and history.

**theming:** wallpaper-based via [matugen](https://github.com/InioX/matugen), or pick your own accent. night light included. optional [cava](https://github.com/karlstav/cava) visualizer.

---

## install

```bash
git clone https://github.com/s3rven/silere-shell
cd silere-shell
bash scripts/install.sh
```

Seeds the cava and matugen configs, optionally installs JetBrainsMono Nerd Font, and wires autostart to whichever Hyprland config you use (`hyprland.conf` or Lua). Existing files are backed up. Restart Hyprland.

```bash
bash scripts/check.sh   # verify deps + smoke launch
```

---

## performance

idle: **~185 MB RAM · ~0.5% CPU.** The floor is Qt6 + Mesa.

The only meaningful cost is the optional cava visualizer: ~13% on a single core at 20 fps while music plays. That's under 1% of total CPU on any modern multi-core machine. Drops to ~0.5% when paused, stops when the screen blanks.

The installer sets the correct jemalloc and EGL environment. Without it, RSS sits at ~316 MB instead.

---

## dependencies

**required:** `quickshell` `hyprland`

**optional:** a missing tool turns its feature off silently.

| tool | feature |
|---|---|
| pipewire / wireplumber | audio |
| networkmanager / nmcli | network |
| brightnessctl | brightness |
| inotify-tools | instant brightness + screenshot flash |
| cava | media visualizer |
| matugen | wallpaper theming |
| hyprsunset | night light |
| power-profiles-daemon | power profiles |

---

## license

MIT © s3rven
