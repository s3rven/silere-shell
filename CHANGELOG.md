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

- Tray settings offer Show all apps to restore hidden icons without resetting the bar layout.
- Clicking an adjacent-month date in the calendar opens that month.
- Log out in the power menu, confirmed with a second press like Reboot and Power off. On Hyprland it goes through `hyprshutdown` when that is installed, so apps close first.
- Tray apps can be hidden from the bar with Hide from bar in their right-click menu, and shown again from the tray row in Settings › Widgets.

### Changed

- Dropdowns build and reuse only the options around their viewport instead of creating every row and font preview at once.
- Hovering the active workspace prepares the menu for up to 2.5 seconds, then releases it if no click follows.
- The calendar is a compact month view without date marking or a footer. Its marks file is no longer loaded or watched; existing files are left untouched.
- Clicking the system updates badge opens package details instead of starting another check. Right-click rechecks, and both update badges can open their details while busy.
- Quick actions explain hardware-blocked Wi-Fi and Bluetooth radios, night light and power mode failures, and limited performance mode. Quiet hours and fullscreen silencing highlight Do Not Disturb while keeping its manual switch state accurate.
- Settings reads more plainly: Theme's Source chips say Neutral instead of Custom, Spacing's slider is Widget gap, Workspaces shows Workspaces shown, and rows that needed guessing (Brightness display, Overlay display, Connection beside VPN, Match bar shape, Keep groups open) gained a one-line description. OSD settings are one card, and Notifications keeps its popup options under one POPUPS card beneath the switch that controls them.
- Cover art from the web is downloaded by `curl` into `~/.cache/silere-shell/art` and shown from there. Turning the setting off deletes those files. It needs `curl`.
- Album art on the Home page crossfades to the next cover without dimming halfway through.
- With night light off, its row shows the coming sunset late in the day and the next sunrise once the sun is down, instead of Recommended.
- The night light arc shows the whole day: the sun rides above the horizon by day and dips below it at night, with sunrise and sunset under the points where it crosses.
- The installer lines up its optional-tools list, and prints autostart lines to copy by hand with a readable path.
- The installer leaves an existing `~/.config` readable as it was and only takes away write access for other accounts; it no longer makes the whole folder owner-only.
- Started with `silere run`, the shell keeps only warnings and errors in its log, instead of every debug line in memory at about 3 MB an hour.
- The installer offers to start Silere when it finishes, or to restart it on a reinstall, instead of only telling you to restart your compositor.
- The autostart and keybind lines the installer adds spell out the install path, instead of an octal-encoded one, unless the path holds spaces or other special characters.
- `install.sh --dry-run` says that settings, notification history and hooks carry over when it replaces a config folder that is not a checkout.
- `silere` and `silere doctor` color their status words in a terminal, using its own palette; `NO_COLOR` turns this off, as it now does for the installer.
- A critical notification stays in the popup stack instead of folding behind Show more when newer ones arrive.
- A right or middle click outside the menu, calendar, quick actions or a tray menu closes it, as a left click does, and so does a click on another monitor.
- Gliding selections (the menu rail, choice chips and color swatches) move on every frame of a high refresh rate display instead of at 62 fps, and settle sooner.
- The menu no longer has the compositor blur the desktop behind it; it is opaque, so that blur was never visible.
- When a Bluetooth device fails to connect, the list suggests forgetting it and pairing it again.
- Hover highlight, Reveal values on hover and Level bars moved from Settings › Widgets › Indicators to Settings › Bar › Layout.
- With automatic night light on, its Home row shows Auto beside the temperature.
- The Home page's System card shows memory in use, free disk space and the battery's time left beside their percentages.
- A hot CPU pulses its Home page tile for 15 seconds and then keeps the warning colour, like a low battery.
- The menu, calendar, quick actions and volume OSD animate with far fewer dropped frames on high refresh rate displays.
- Tray menu rows, the notification close button and notification cards respond while pressed.
- A notification that arrives while the menu, calendar, quick actions or a tray menu is open waits until it closes instead of appearing on top of it, and then shows for its full time. Critical notifications still appear at once.
- Low battery warnings are on by default: an alert at the Low below threshold and again at half of it. Settings › Feedback › Alerts turns them off.
- `silere doctor` fails when Hyprland 0.57 or later runs with Quickshell 0.3.1, which cannot read its workspaces.

### Removed

- The workspace marker's Menu open pulse.
- The settings for workspace dot opacity, app icon opacity, monochrome app icons, visualizer opacity, separator opacity and Mark changed pages. Each keeps its former default.

### Fixed

- Pooled-row lint checks delegate animations without incorrectly flagging the containing dropdown's header and disclosure animations.
- Sandboxed test shells no longer display a Notifications blocked alert for the desktop's running notification server.
- `scripts/bench.sh --warm` opens Home consistently even when the menu is already open, and refuses a sample if the menu cannot open.
- Notifications arriving while the Recent page is open no longer slide in on top of older ones, and removing one no longer overlaps its neighbours.
- Tray, tray menu, notification and Recent page icons sit on whole device pixels at fractional scaling instead of looking blurred.
- A longer window title no longer shows cut off with an ellipsis while the title box widens.
- Sliders reach their exact limits when their range does not divide evenly into the step size.
- Tray apps with no icon, or a failed icon, try their installed app icon before showing an initial. Missing icons show the initial immediately, and settings use the same fallback.
- The launcher clears inherited `QSG_TRANSIENT_IMAGES`, which can leave loaded tray icons blank after another window uses their image. Installation diagnostics warn about older services that still set it.
- Showing an app in tray settings also enables a disabled tray, and rows distinguish Shown, Hidden, Tray off and Not running.
- Quickly disabling and enabling the tray keeps its item delegates intact. Shown icons reload without reusing an earlier failed image.
- Switching from an app menu to a menu-less tray item clears the old app's menu. Items without an app ID cannot hide the previous app. Menus close when their app disappears or is hidden.
- Clicking a tray submenu already opened by hover keeps it open, and menu-only tray icons always open their menu on a primary click.
- Tray menu widths and click targets grow with interface scaling, and fading menu actions cannot fire after the popup closes.
- A delayed or repeated notification close cannot remove a newer notification that reused its ID, or duplicate its history.
- Bluetooth discovery follows changes of adapter, releases the previous adapter, and leaves another application's discovery alone when the picker opens or closes.
- Revisiting cover art removed by cache cleanup downloads it again instead of keeping a link to the deleted file.
- The media player switcher keeps stopped players with a track ready to resume, while skipping empty browser sessions.
- CPU readings recover after counter resets, CPU hotplug and failed reads instead of keeping a stale percentage or flashing 100%. Invalid memory readings no longer produce negative percentages or keep stale values.
- Switching brightness displays clears the previous error, and a write finishing on the old display cannot overwrite the new display's status or discard its queued write.
- Battery status distinguishes charging, charge limits, discharge and AC power. Charging estimates disappear when charging stops, and estimates shorter than a minute show 1m instead of 0m.
- Calendar date targets grow with interface scaling, and adjacent dates announce their actual month and year to assistive readers.
- Starting an inline reply in a notification popup no longer stops on a script error before it focuses the reply field.
- Typing right after clicking Reply on a notification goes into the reply field, without moving the pointer first.
- With week numbers off, the calendar's side borders draw at the same weight on a 125% display.
- The update card in Settings grows with the interface scale instead of keeping a fixed height.
- The divider after the workspace dots sits centred between them and the next widget, like every other divider on the bar.
- Straight bar dividers sit on whole device pixels with uniform widths at fractional scaling.
- Scrolling over a tray icon with a touchpad sends the app whole steps instead of one per touchpad event.
- Opening or closing a tray submenu tells the app once, not twice.
- Notifications sent with `notify-send -i` show their icon instead of a letter, whether the icon is a theme name or a file in the system icon folders.
- `silere log` prints plain text when piped or saved to a file, without terminal color codes.
- `silere ipc` and `silere log` no longer print Qt's locale warning above their output in a terminal.
- `silere update` says which version is installed and whether a release is waiting, instead of finishing silently.
- `silere ipc` exits 1 when a call fails, including an unknown target or function or unusable arguments, and `silere ipc <target>` lists that target's calls.
- Run from a terminal, `silere doctor` reads the Quickshell version instead of warning it could not, and `silere update` no longer refuses a release because of it.
- Starting Silere, and `silere doctor`, no longer log a Qt warning about a non-UTF-8 locale to the journal.
- `scripts/check.sh` no longer shows extra bars on your screen, pushing windows aside, while its startup checks run.
- Test runs no longer leave compiled QML in `~/.cache/quickshell/qmlcache`, about 40 MB per `scripts/check.sh` run.
- Startup checks keep their artwork and icon caches separate from the running shell's cache.
- The updater refuses a signed release tag that was published under another version's name.
- A tray icon whose app has no menu opens one holding Hide from bar, instead of an empty card or nothing.
- On Hyprland, the shell restarts itself when Hyprland stops sending it events, instead of the bar staying stuck on old workspaces and window titles.
- Changing the volume of a Bluetooth output changes what you hear on devices without hardware volume, instead of only moving the slider. This uses `wpctl` when it is installed.
- Paging the workspace dots fades the old page out before the new one appears, instead of showing the new page twice.
- A workspace page that grows without paging updates its active marker with the new cells.
- The Wi-Fi, Bluetooth and night light pickers on the Home page close when that service goes away, instead of staying open on an empty list.
- When another Quickshell config holds notifications, the alert and Settings › System › Maintenance name that config instead of `qs`.

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
