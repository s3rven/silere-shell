# Changelog

Only work since the latest release is listed here. Completed notes move to
[`docs/releases`](docs/releases/) and stay linked at the bottom of this file.

Format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with entries
grouped by the part of the shell they touch once a section runs long. Versions follow
[Semantic Versioning](https://semver.org/) loosely while in `0.x`: minor versions
change features, patch versions fix them. The updater follows signed stable tags; the
settings file carries its own `__version` and migrates separately.

## [Unreleased]

### Changed

- On Hyprland the installer binds the menu key to the `silere:menu` global shortcut, which starts no process per press,
  and Settings › System › Keybinds names that bind on any key. `silere doctor` names an older `qs ipc` menu bind and
  the line that replaces it.
- Without Quickshell, the installer names the package to install on Void, and on Debian or Ubuntu when theirs is new
  enough.
- The installer, `silere`, the updater, reset and uninstall stop under sudo or doas: Silere works on your own session,
  and a run as root used root's home and left files in the checkout that later updates could not replace.

### Fixed

- `silere status` and Settings › System › Overview no longer call an update check older than two days up to date; they
  say when it last found none.
- A workspace app icon no longer flashes its letter while it loads.
- The menu no longer jumps in size when it closes mid-resize or reopens on another page while fading out.
- With app icons on, a workspace's first window fades its icon in over the empty ring instead of swapping them in one frame.
- A notification that names no app shows its initial instead of an unrelated app's icon.
- `silere doctor` suggests a package for a missing screen locker, Git, curl or xdg-open too, and names more of them on
  openSUSE and Void.
- Settings › System › Keybinds reads a Lua workspace bind made by keycode, as other keyboard layouts need, as the
  workspace it goes to instead of a bare "Focus".
- Notification, Recent page and slider icons no longer flash a letter or glyph before they first appear.
- The menu's Now Playing label keeps an emoji or flag whole where it shortens a long track title.
- `bash scripts/uninstall.sh --help` explains the uninstaller instead of starting it, and it and `scripts/update.sh` stop
  at an option they don't know instead of carrying on without it.
- `bash scripts/install.sh --dry-run` also lists the shell completion links the install creates.
- Uninstalling removes the backup of your Hyprland or niri config once it matches the config again, and a matugen
  config that only the installer wrote.

## Releases

- [1.9.0](docs/releases/1.9.0.md) — 2026-11-24
- [1.8.0](docs/releases/1.8.0.md) — 2026-11-19
- [1.7.0](docs/releases/1.7.0.md) — 2026-11-12
- [1.6.0](docs/releases/1.6.0.md) — 2026-11-07
- [1.5.0](docs/releases/1.5.0.md) — 2026-11-03
- [1.4.4](docs/releases/1.4.4.md) — 2026-10-22
- [1.4.3](docs/releases/1.4.3.md) — 2026-10-18
- [1.4.2](docs/releases/1.4.2.md) — 2026-10-11
- [1.4.1](docs/releases/1.4.1.md) — 2026-10-10
- [1.4.0](docs/releases/1.4.0.md) — 2026-10-09
- [1.3.0](docs/releases/1.3.0.md) — 2026-10-05
- [1.2.0](docs/releases/1.2.0.md) — 2026-09-27
- [1.1.1](docs/releases/1.1.1.md) — 2026-09-17
- [1.1.0](docs/releases/1.1.0.md) — 2026-09-17
- [1.0.0](docs/releases/1.0.0.md) — 2026-09-07
- [0.9.0](docs/releases/0.9.0.md) — 2026-08-30
- [0.8.0](docs/releases/0.8.0.md) — 2026-08-22
- [0.7.0](docs/releases/0.7.0.md) — 2026-08-18
- [0.6.1](docs/releases/0.6.1.md) — 2026-08-16
- [0.6.0](docs/releases/0.6.0.md) — 2026-08-15
- [0.5.1](docs/releases/0.5.1.md) — 2026-08-13
- [0.5.0](docs/releases/0.5.0.md) — 2026-08-13
- [0.4.0](docs/releases/0.4.0.md) — 2026-08-12
- [0.3.0](docs/releases/0.3.0.md) — 2026-08-11
- [0.2.0](docs/releases/0.2.0.md) — 2026-08-10
- [0.1.0](docs/releases/0.1.0.md) — 2026-08-08
