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

#### Bar

- Optional keyboard layout/Caps Lock widget.
- Optional system monitor in the bar for CPU, memory and temperature, tinted only while a reading stays high; it samples only while shown and not idle.
- The window title can lead with the app's icon, and a title that is cut short scrolls through the rest on hover.
- Accent widget icons tints resting bar icons with the accent; text, warnings and inactive states keep their own colours.

#### Menu and settings

- Keyboard navigation and visible focus across controls, lists, sliders, and pickers.
- Interface settings rescan fonts and external displays each time they open, and report scan errors.
- Dropdowns take typing to find a row, the page keys, and show a half row when there is more.
- Clearer descriptions for settings whose names alone did not say what they do.

#### Notifications

- Notifications from the same app and sender fold into one card showing the last few earlier lines; history keeps every message.
- Mute an app's popups from its notification history page; muted apps are listed under Feedback › Notifications.

#### Network

- Saved VPN controls, advanced network settings, and a guided Bluetooth passkey handoff.
- Terminal handoffs such as nmtui fall back to a common terminal when xdg-terminal-exec is missing.

#### System

- Presentation Mode and automatic niri cast detection where supported.
- Lock & sleep waits for the session's lock confirmation and cancels on failure.
- Larger UI sizes, separate text/icon fonts, and optional DDC/CI display brightness.
- Optional weather in the calendar for your time zone's city, fetched from Open-Meteo only when it opens and reused for 30 minutes.
- Home's CPU and Memory rows open a system monitor app: Mission Center, Resources, GNOME or Plasma's monitor, or btop/htop in a terminal.
- The memory readings add swap in use while the kernel reports work stalling on memory, and stay quiet about swap otherwise.

#### Install and updates

- Optional supervised startup with bounded restart attempts and owned-unit removal.
- Isolated compositor CI coverage, a pinned minimum-Quickshell job, and workload sampling.
- `silere use` makes one checkout the one that runs, for example a development clone beside an installed copy, and `silere status` says which copy is on screen and which one the service starts.

### Changed

- Home is shorter: Presentation Mode moved into Do Not Disturb's options, the VPN row appears only when a VPN is connected or saved, the System readings sit on one line each, and rows no longer repeat what their switch already shows.
- Interface settings lost the workflow shortcuts, the icon font picker and the manual refresh rows, and keep their hints for when something needs attention.
- Settings rows, page titles, and the Wi-Fi and Bluetooth lists no longer carry text that only restates what is on screen; what is left is privacy, warnings and consequences. Workspaces settings fit in two cards.
- Widget gap is Tight, Normal or Wide (4, 8 or 12 px) instead of a 4–24 px slider; wider settings snap to Wide.

### Fixed

#### Bar fixes

- Workspace clicks and scrolling work again from a named Hyprland 0.57 workspace, which the bar now rings like a special one.
- The keyboard, workspace and media widgets react when pressed.
- A bar widget that reveals more on hover, such as the keyboard layout, shrinks back as soon as the pointer leaves instead of holding its wide size for half a second.

#### Menu and settings fixes

- Rail icons name themselves when reached by keyboard, and arrow keys walk the power drawer.
- Settings pages hold their size while switching; rows with a dependency note used to flash it and shift the panel.
- Quick Actions fits Do Not Disturb beside its longest states.
- Slider headings and gradient controls grow to fit larger text without clipping or overlapping the track.
- Keyboard navigation scrolls command, password, reply and search fields into view while preserving native editing keys.
- Dropdowns preserve their selected option and keyboard cursor during expansion; list arrows skip disabled and busy actions without losing focus.
- Quick Actions shows Night Light's sun or moon to match its state, as Home does.
- With the bar at the bottom, Home's pickers, the volume and brightness choices and Settings dropdowns open above their row, so the row you clicked stays under the pointer while the menu grows upward.
- Home's System meters rest as a calm wave that stirs with CPU load and tightens on a warning, instead of the same squiggle on every reading.
- Choosing a dropdown option with the pointer no longer leaves a keyboard focus ring around the row.

#### Notifications fixes

- Notifications and media can find their app on a named or special Hyprland 0.57 workspace, and those windows resolve to the right monitor.
- A right click on the very corner pixel of a bar, notification or popup window no longer crashes the shell (a Qt bug on 6.11 and later).
- The Notifications app list keeps its rows when a new arrival reorders it, so icons no longer flash and keyboard focus stays put.
- Rail and missed-notification badges, rail labels and the history count grow with the UI scale instead of crowding their text.
- Critical app notifications and existing popups no longer bypass screen-sharing privacy.
- The notification stack's Clear all works in one click, since cleared cards stay in history; the history page's Clear all names what it removes ("Clear 12?") and shows its confirm window running out.
- The notification stack's Clear all and Show more chips are frosted like the cards, so they stay readable over a busy wallpaper with a translucent theme.
- The notification countdown clock sleeps while every card on screen is persistent or paused, instead of waking the shell 20 times a second.
- With the bar at the bottom, the notification stack's chips keep their frosted backing in place as cards arrive and leave.

#### Network fixes

- The open VPN list keeps its rows between polls, and a hidden window title no longer runs its width animation.
- Saved VPN controls refresh after overlapping requests and external connection changes.
- Home checks for saved VPNs and Interface rescans fonts at most once a minute, not on every open.

#### Media fixes

- The visualizer stays visible with a very dark custom accent, like the rest of the bar.
- Now Playing keeps its seek bar, controls and Players card on whole device pixels at fractional scales, so their outlines stay crisp whatever the track title.
- The underline visualizer follows the bar's lower edge into its rounded corners instead of stopping a corner's width short, and settles onto the edge where the curve begins.

#### System fixes

- External brightness serializes discovery and writes, preserves queued levels, and ignores stale results.
- Font refresh requests queue behind an active scan and recover cleanly when fontconfig returns.
- Lock & sleep refreshes readiness after tool checks and rejects late confirmations after required tools disappear.
- Closing the menu, calendar, tray menu or quick actions now returns their JavaScript heap, about 3 MB less resident memory after heavy use.

#### Install and updates fixes

- Rolling back to 1.4 keeps settings added since, along with a UI scale above its old limit, instead of dropping them on the next change.
- An update that leaves the optional service failed keeps its recovery journal, so `silere update --rollback` still works, and a rollback restarts that service.
- `silere use` says when a startup line in your compositor config still names another copy.
- Supervised startup refreshes session endpoints, preserves the caller's locale and tool path, and recovers from a previous crash limit.
- The Hyprland integration check writes a Lua config on Hyprland 0.55 and later instead of starting in emergency mode.
- `silere run` and `silere restart` no longer start a second shell beside one running from another copy.

## Releases

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
