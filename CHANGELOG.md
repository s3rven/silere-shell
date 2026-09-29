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

- Log out in the power menu, confirmed with a second press like Reboot and Power off. On Hyprland it goes through `hyprshutdown` when that is installed, so apps close first.

### Changed

- Album art on the Home page crossfades to the next cover without dimming halfway through.
- With night light off, its row shows the sunset time in the evening and the sunrise time after midnight, instead of Recommended.
- The night light arc shows the whole day: the sun rides above the horizon by day and dips below it at night, with sunrise and sunset under the points where it crosses.
- The installer lines up its optional-tools list, and prints autostart lines to copy by hand with a readable path.
- The installer leaves an existing `~/.config` readable as it was and only takes away write access for other accounts; it no longer makes the whole folder owner-only.
- `silere` and `silere doctor` color their status words in a terminal, using its own palette; `NO_COLOR` turns this off, as it now does for the installer.
- A critical notification stays in the popup stack instead of folding behind Show more when newer ones arrive.
- When a Bluetooth device fails to connect, the list suggests forgetting it and pairing it again.

### Fixed

- Starting an inline reply in a notification popup no longer stops on a script error before it focuses the reply field.
- Scrolling over a tray icon with a touchpad sends the app whole steps instead of one per touchpad event.
- Opening or closing a tray submenu tells the app once, not twice.
- Notifications sent with `notify-send -i` show their icon instead of a letter, whether the icon is a theme name or a file in the system icon folders.
- `silere log` prints plain text when piped or saved to a file, without terminal color codes.
- `silere ipc` and `silere log` no longer print Qt's locale warning above their output in a terminal.
- `silere update` says which version is installed and whether a release is waiting, instead of finishing silently.
- `silere ipc` exits 1 when a call answers with an error, and `silere ipc <target>` lists that target's calls.
- Run from a terminal, `silere doctor` reads the Quickshell version instead of warning it could not, and `silere update` no longer refuses a release because of it.
- The updater refuses a signed release tag that was published under another version's name.

## Releases

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
