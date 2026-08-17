# Changelog

Notable changes to Silere Shell, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow
[Semantic Versioning](https://semver.org/) loosely while in `0.x`: minor versions
change features, patch versions fix them. The updater follows signed stable tags;
the settings file carries its own `__version` and migrates separately.

Only work since the latest release is listed here. Completed notes move to
[`docs/releases`](docs/releases/) and stay linked below.

## [Unreleased]

### Added

- Notifications, the calendar, quick actions and tray menus can follow the bar's opacity, under Bar › Layout.
- The reactive underline can light the whole bar, under Bar › Underline.
- Quick actions open over IPC, so Do Not Disturb and airplane mode can take a keybind.
- `SILERE_ASSUME_YES=1` installs without prompts, for dotfiles scripts and containers.
- Settings say when reduce motion or a missing libnotify stops a row taking effect.

### Changed

- Sliders are built from the same groove and handle as the switches.
- Panels and page swaps settle faster.
- The gem and line workspace markers are flatter, and hold steady when you switch.
- Package update checks cover the repos only; the AUR is opt-in under System › Updates.

### Removed

- The OSD volume emphasis tint.
- The red stripe beside critical notifications in history.

### Fixed

- Menu and settings icons match the rows they sit on.
- The bar stays put when you turn shell shadows on or off.
- The installer finishes and prints the manual autostart line when a Hyprland config path is wrong.
- Leaving airplane mode brings back the radios that were on, and leaves the rest alone.
- Dot and Bullet dividers keep different sizes at compact spacing.
- Card dividers hold one weight, including under an open Wi-Fi or Bluetooth list.
- A settings section fades in already drawn.
- Keybinds open the menu, calendar, tray and quick actions on a display that has a bar.
- Quick actions show the power mode on the first open.

## Releases

- [0.6.1](docs/releases/0.6.1.md) — 2026-08-16
- [0.6.0](docs/releases/0.6.0.md) — 2026-08-15
- [0.5.1](docs/releases/0.5.1.md) — 2026-08-13
- [0.5.0](docs/releases/0.5.0.md) — 2026-08-13
- [0.4.0](docs/releases/0.4.0.md) — 2026-08-12
- [0.3.0](docs/releases/0.3.0.md) — 2026-08-11
- [0.2.0](docs/releases/0.2.0.md) — 2026-08-10
- [0.1.0](docs/releases/0.1.0.md) — 2026-08-08
