# Changelog

Only work since the latest release is listed here. Completed notes move to
[`docs/releases`](docs/releases/) and stay linked at the bottom of this file.

Format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with entries
grouped by the part of the shell they touch once a section runs long. Versions follow
[Semantic Versioning](https://semver.org/) loosely while in `0.x`: minor versions
change features, patch versions fix them. The updater follows signed stable tags; the
settings file carries its own `__version` and migrates separately.

## [Unreleased]

- A mistyped option to `silere update`, `status`, `log`, `stop`, `restart`, `use`, `link` or `uninstall` names that
  command's usage in one line, as the control commands do, instead of printing the whole help.
- With several monitors on Hyprland, moving the pointer to another monitor asks Hyprland for its monitor list only
  when that monitor shows a workspace named other than its number, the one case Quickshell 0.3.2 loses track of.
- A notification that arrives while a web browser plays video keeps its usual timer instead of waiting over the video
  for the pointer to move. Browsers hold their wake lock through the idle daemon (hypridle), which the compositor and
  so the shell never hear of; a browser's playing media now counts as that lock.
- Settings > System > Keybinds reads a hyprlang `workspace, -1` bind as going to the previous workspace, not to workspace -1.
- On niri, the workspace arrow points to a window that needs you on a monitor whose bar is off, as it does on
  Hyprland.
- A Hyprland submap entered on a monitor whose bar is off shows its name on the bar that is on.
- Two quick middle clicks on the volume or microphone widget step two outputs or inputs, not one.
- With Hover highlight on, widgets a click does nothing on (one keyboard layout, the indicators) no longer light up
  under the pointer.
- A notification that comes in your first minutes away and is still waiting when the session goes idle counts on the
  bell as missed.
- A notification over a browser video keeps its timer after four minutes without input too, instead of waiting until
  the pointer moves.

## Releases

- [1.10.0](docs/releases/1.10.0.md) — 2026-11-25
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
