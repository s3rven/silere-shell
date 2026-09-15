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

- The notifications page carries a rail of the apps that have sent one; picking an app
  narrows the page to it, and Clear then takes only that app's history.
- The audio visualizer can run along the bar's underline, spanning its full width.
- The audio visualizer has an opacity slider.
- `silere update --rollback` restores the revision an update replaced when the shell does not come back.

### Changed

- Settings descriptions and connection status messages use brighter secondary text.
- Workspace taps, window drops, special-workspace entries and OSD nudges settle on one
  timing instead of five.
- Power Mode on the Home page opens the list of available profiles.
- The notifications panel uses a narrower width and a content-sized height, capped for
  long histories. Switching app filters keeps its height steady.
- Notification popups are wider.
- Device and option rows highlight the full row and follow the card’s corner.
- Maintenance names the lock and night-light programs in one line each.
- The low-battery and overheating alerts pulse on each threshold, then hold steady.
- The visualizer draws denser bars on wider tracks.

### Fixed

#### Bar fixes

- Reversing a scroll immediately changes the direction of volume and other wheel controls.
- Nested tray menus stay open while entering a child menu, and flyouts stay inside screen edges.
- A paused player no longer leaves the underline lit.

#### Menu and settings fixes

- Confirmation buttons cancel pending confirmation when disabled or busy.
- Scroll indicators stay aligned when entries are removed from a scrolled list.
- A settings category no longer shows a changed dot for a setting its page is hiding.
- Maintenance and update rows keep their labels on a machine without the optional tools.

#### Notification fixes

- A long notification title opens in full on the notifications page and in popups.
- An expanded notification stays open while the history scrolls.
- Notification history crossfades between app filters.
- Removing an entry from filtered notification history deletes the selected notification.
- Confirming Clear keeps its selected app even if the filter changes during the fade.
- Notification history survives a restart when “Keep after restart” is on.

#### Media fixes

- Long playback times move below the media buttons on narrow panels.
- Media progress follows the player’s playback speed.

#### Sound fixes

- The audio controls enforce the 100% volume limit on amplified backend levels.

#### Network fixes

- Empty Wi-Fi and Bluetooth messages wrap to fit narrow panels and larger text.
- Disconnecting a Bluetooth device preserves pairing in progress on another device.
- Work and campus Wi-Fi networks no longer offer a password field that cannot work.
- Bluetooth reports a hardware switch that has blocked it.
- Saved Wi-Fi networks and paired Bluetooth devices can be forgotten with a middle-click.

#### System fixes

- Short app names no longer jump to unrelated windows with matching suffixes.
- Auto night light tracks the sun from startup instead of after the first menu open.
- The battery-critical hook still runs while other hooks are busy.
- Settings migrated from an older version are backed up before the rewrite.
- Notification history and calendar marks saved by a newer release are left untouched.
- A systemd-managed shell recovers when Hyprland restarts instead of going stale.
- Optional features stay available when the capability check fails.

#### Install and update fixes

- Long package versions leave room for package names in the updates list.
- A failed install no longer removes the directory it moved aside.
- The updater reports when a staged release could not be fully checked.

## Releases

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
