# Changelog

Only work since the latest release is listed here. Completed notes move to
[`docs/releases`](docs/releases/) and stay linked at the bottom of this file.

Format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with entries
grouped by the part of the shell they touch once a section runs long. Versions follow
[Semantic Versioning](https://semver.org/) loosely while in `0.x`: minor versions
change features, patch versions fix them. The updater follows signed stable tags; the
settings file carries its own `__version` and migrates separately.

## [Unreleased]

### Added

- Settings › Theme › Background blur turns blur off or on for the bar and translucent popups, and names what is stopping it when Hyprland is older than 0.56 or has blur turned off. `silere doctor` reports the same.

### Changed

- With Popups match bar opacity on and a translucent bar, the menu turns to glass too: its pane, cards and controls let the blur through like the calendar and notifications.
- With nothing blurring behind them, because Background blur is off or Hyprland has blur turned off, the menu, popups and OSD stay solid instead of showing the window under them sharp. Popups match bar opacity waits for blur.
- Workspace app icons show in their own colours instead of grey until hovered.
- The edge gap of a floating bar now only spaces it from the screen edge, so windows sit as far below it as below a docked bar.
- Notification history is saved in `~/.local/state/silere-shell` instead of the config folder, so a dotfiles repo that tracks `~/.config` no longer picks up message text. An existing history moves there on the next start.
- The media card on the Now page shows the album cover sharp beside the track, with only a soft blur of its colours behind the text, where the cover itself used to show through the title.
- Cover art from the web downloads Spotify's 300 px cover, about a third the size of the 640 px one, and fetches a second size only when the first fails.

### Fixed

- A floating bar at 100% width keeps the edge gap at its sides too, instead of pressing its rounded corners against the screen sides.
- A floating bar with no edge gap squares the corners against the screen edge instead of leaving notches beside them.
- A bar height or edge gap set over IPC or by hand rounds to the 4 px steps the menu uses, so the bar outline stays sharp at fractional scaling.
- Notification popups keep the same side gap as a full-width floating bar instead of touching the screen edge.
- The workspace marker no longer restarts its slide while the first workspace changes width, and quick repeated switches no longer snap its bounce back.
- A workspace leaving the bar no longer shows -1 while it fades, and opening or closing a window no longer reloads the app icons of other workspaces.
- Workspace app icons stay sharp at fractional scales such as 125%.
- An app with no icon shows its own initial in the workspace bar instead of a version digit, such as Minecraft's 1.
- Toggles, sliders, colour swatches, notification count badges and the menu rail's selection sit on whole device pixels at fractional scales such as 125%, so their edges stay sharp and even on both sides, and hovering a toggle no longer blurs its outline.
- Pressing a slider's handle slightly off centre no longer nudges its value.

## Releases

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
