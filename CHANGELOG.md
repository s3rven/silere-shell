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

- Notification history supports Enter or Down from search, arrows between messages, and Delete to remove the focused entry while keeping your place.
- Empty notification searches and app filters offer a button to clear the query or return to all notifications.
- Now Playing seeks in five-second increments with the arrow keys or scroll wheel, with larger steps on Shift+arrow or Page Up/Down. Dragging remains continuous.
- Click the brightness widget to open its slider in Home, with device choices on systems with multiple backlights.
- Click the battery widget to open Power Mode, or system readings when power profiles are unavailable.
- Hover the volume widget to see which output it controls alongside the volume.
- Bar shortcuts scroll their controls into view when Home is taller than the screen.

### Fixed

- Notification history shows the remove button on keyboard focus, and inactive rows and hidden media controls reject retained actions.
- A CPU holding at exactly 100% now triggers the sustained-load warning. The bar and Home share that warning across monitors, and separate spikes no longer add up to sustained load.
- A notification still sliding out when a newer one took the last visible place no longer disappears mid-exit and comes back later.
- The calendar takes keyboard focus the first time it opens, so Tab and the arrow keys work without a click.
- The whole height of the bar opens the calendar from the clock, like every other widget.
- `silere update --rollback` still works after the release it undoes was withdrawn upstream and a later check removed its tag.
- A shell that does not run as a service keeps its rollback until the updated shell is seen running, instead of losing it to the next daily check.
- An update stops instead of replacing an ignored file in the checkout, such as settings or notification history, if a release ever ships a file at the same path.
- Recovery from a silent Hyprland event socket restarts the service only while it is still running.
- Installing an update right after changing a setting no longer fails with "Settings could not be saved before the update" while the settings file is being read back.
- `silere reset` no longer starts a shell that was not running, or stops one it cannot bring back, because a service for the checkout is installed but stopped and disabled.
- An update keeps its rollback until this checkout's shell is seen running, even while a service for another checkout is up.
- The keyboard widget keeps showing your keyboard's layout while wtype, an emoji picker or remote input types, instead of "ER" or that tool's layout.
- The keyboard widget no longer falls back to an older layout read while you switched, and follows a layout changed by a Hyprland config reload.
- The keyboard widget labels every layout by its code, so Ukrainian reads UA and Estonian EE instead of UK and ES. English shows US or GB.
- A monitor plugged back in no longer shows its workspaces as if a special workspace were still open on it.
- The updates widget no longer counts AUR packages that pacman.conf's IgnorePkg holds back when paru checks the AUR.
- Brightness works on hybrid-graphics laptops in discrete GPU mode, and the GPU that isn't driving the screen is no longer offered as a brightness device.

## Releases

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
