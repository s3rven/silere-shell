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

- A menu page that fails to load, Now Playing included, offers Reload, which reloads the shell and reopens the menu on the same page.
- The volume icon turns amber while Bluetooth headphones it plays through are below 20%, and its hover shows their charge, unless the Bluetooth widget already shows that one device's charge.

### Changed

- Home and the other panels build faster: keyboard focus rings and Home's sound options are made only once they show.
- When notification history is full, the app with the most entries gives up its oldest one, so one busy chat no longer pushes every other app out.
- The uninstaller lists what it kept and how to stop the shell that is still running.
- The installer names the compositor it found, ends with `silere run`, `silere doctor` and `silere uninstall` when the command is on your PATH, and says when `~/.local/bin` is not on it.
- `silere doctor` names the package for more missing tools, and its columns line up.
- `silere ipc` names the target or call it could not find, and how to list them.
- `silere status` shows the shell's memory and when updates were last checked.

### Fixed

- An open calendar stays centred on its clock as the clock's date appears or folds away, instead of slipping to one side.
- With Reduce motion on, a tray menu opened while the app's name showed on hover opens on its icon instead of beside it.
- On a theme change, workspace markers, the OSD, notification outlines and update status colours change with the rest of the shell instead of trailing it.
- The night light's sun arc writes durations like the battery does, "1h 5m" rather than "1h 05m".
- Switching outputs with a long device name no longer pushes the volume level out of the on-screen display.
- Uninstalling leaves your compositor config exactly as it was before the install, and no longer leaves Silere's Matugen template behind after a reinstall.
- Running the installer again reports what is already set up instead of skipping it, keeps an enabled update timer, and no longer asks to overwrite an unchanged Matugen template.
- The `silere reset` preview lists whole setting names instead of cutting one off.

## Releases

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
