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

- On Hyprland, binds can reach the menu and tray as global shortcuts, `silere:menu` and `silere:tray`, without starting a `qs` process for each press.
- While the CPU is busy, or one program keeps a whole core to itself, Home's CPU row and the bar's system monitor on hover name the process using the most, with its ID.
- Music pauses when Bluetooth or USB headphones disconnect or run flat, instead of carrying on through the speakers; Settings › Widgets › Media › Pause when headphones disconnect.
- A menu page that fails to load, Now Playing included, offers Reload, which reloads the shell and reopens the menu on the same page.
- The volume icon turns amber while Bluetooth headphones it plays through are below 20%, and its hover shows their charge, unless the Bluetooth widget already shows that one device's charge.
- Settings sliders that move in a few steps, such as Workspaces shown, Edge gap and the battery and temperature warnings, mark their stops on the track.

### Changed

- The shell uses about a third less memory on 4-thread laptops: `silere run` starts it with one allocator pool that returns freed memory after a second, unless you set your own `MALLOC_CONF`.
- Moving the pointer along the bar keeps each widget's hover detail open until you leave that part of the bar, so the widget you aim at no longer slides away as the last one closes.
- Hover details also stay out through a brief slip off the bar, and while a menu, calendar or tray menu opened from the bar is showing, instead of folding and shifting the bar under it.
- Closing a bar widget's hover detail, such as the volume's output name, slides it back under the widget's edge instead of blinking it off.
- The clock and the media title ease their hover highlight in and out the way the other bar widgets do.
- Opening notification history ends Do Not Disturb's missed count, so the bell and Home's badge no longer stay lit for notifications you have seen.
- The settings schema moves to 4 with nothing to convert, so a rollback to 1.7 keeps the headphone pause setting.
- Notification icons that apps pass as files from their own installed folders show instead of a letter, such as kitty's for programs running in it.
- Silere's own alerts show as Silere Shell, each with an icon for what it is about.
- Notification history opens on every app each time the menu opens, so an app picked earlier no longer hides the notifications you came for.
- Home and the other panels build faster: keyboard focus rings and Home's sound options are made only once they show.
- When notification history is full, the app with the most entries gives up its oldest one, so one busy chat no longer pushes every other app out.
- Home's volume and brightness percentages take the accent while you drag them, as Settings sliders do.
- A long Settings page keeps its title and search at the top while the rest scrolls under them, and Ctrl+F opens search without jumping back to the top.
- Notification history settings and muted apps have their own History page under Settings › Feedback, so Notifications fits without scrolling.
- Settings › System › Overview lists device checks under one row that opens on its own when a check needs attention.
- Switching Settings pages is quicker and steadier: the title bar and search stay in place while the page under them fades through, and the next page no longer waits on an empty pane when the panel keeps its size.
- The uninstaller lists what it kept and how to stop the shell that is still running.
- The installer names the compositor it found, ends with `silere run`, `silere doctor` and `silere uninstall` when the command is on your PATH, and says when `~/.local/bin` is not on it.
- `silere doctor` names the package for more missing tools, and its columns line up.
- `silere ipc` names the target or call it could not find, and how to list them.
- `silere status` shows the shell's memory and when updates were last checked.

### Fixed

- `scripts/bench.sh --warm` works from an SSH session.
- Text no longer has orange and blue fringes on displays at fractional scales such as 125% and 150%.
- With Auto tighten on, hovering a widget on a crowded bar no longer tightens the whole bar and loosens it again.
- A screen backlight that disappears no longer flashes the brightness display at 0%.
- Bar weather comes back as soon as a Wi-Fi sign-in page or a lost internet connection clears, instead of up to half an hour later.
- Hovering a bar widget that shows more on hover no longer makes its icon jump sideways and briefly disappear.
- A bar widget's level bar no longer sticks out past the widget while it shrinks.
- On a crowded bar, the media title resizes along with the widgets beside it instead of after them.
- With Reduce motion on, hovering a cut-short window title shows its end.
- Choosing a search result for Artist, Clock format or style, Theme source, Underline mode, or the battery and temperature warnings scrolls to that row and highlights it, as for every other setting.
- Screen readers announce rows under Settings › Feedback › History › Muted apps as "Mute popups from" and the app's name, not the bare name.
- A notification with no title shows its message as the title, in popups and in History, instead of a blank bold line above it.
- The "Notifications blocked" alert no longer comes back each time Settings rechecks your tools, and its row in Settings › System › Overview stays put while it checks.
- Muting the Unknown page in History mutes notifications from senders with no name.
- The workspace-changed hook runs when you switch between two named Hyprland workspaces and gets the workspace's name, instead of -1338; it is no longer called with -1 while niri restarts.
- Clicking a notification on a named Hyprland workspace can take you to the app's window on another named workspace, instead of the one already in front of you.
- The arrow pointing to an urgent workspace off the page no longer flips direction as it fades out.
- Home's Wi-Fi and VPN lists close when the adapter, NetworkManager or the last VPN profile goes away, instead of staying open under a missing row.
- A track change while Now Playing scrolls a long title starts the new title from its first letter.
- Switching outputs at the level just shown still shows the device name in the on-screen display.
- The bar's on-screen display no longer flashes the accent colour over a battery or temperature alert.
- Tray menu radio entries are announced as radio buttons, and Now Playing's length label and the tray menu's Hide from bar are no longer offered to screen readers while covered or closed.
- The Caps Lock light is no longer read while the overview hides the bar.
- On a copy of Silere without Git, `silere` no longer says a package manager owns it: `silere link`, `use` and `uninstall` work there, and `silere update` says once that nothing updates it.
- `silere service remove` and the uninstaller also remove the override `silere use` wrote, so a service installed later starts its own checkout.
- `silere doctor` and the installer no longer read Qt 5's modules when only a Qt 5 `qtpaths` is on PATH, which could report Qt as too old.
- Fish no longer suggests `service` after every `silere` command, and `silere help` lists `use --dry-run`.
- `silere service` with a mistyped option prints its usage instead of exiting silently, and `silere repair` gives full paths in its hints, so they work from any directory.
- `silere try` on niri accepts a terminal path containing quotes or backslashes.
- The AUR package's removal notes name the crash recovery service file, if you made one.
- A battery-critical hook runs once when the battery crosses the critical level, not again each time the reading wobbles across it or UPower restarts.
- An update-available hook added while Silere runs no longer fires when the update count falls.
- Home no longer shows an empty Connectivity section on a wired desktop with no Bluetooth and no saved VPN.
- Two on-screen display pills of different widths, such as a volume change beside a battery warning, share one centre.
- With two or more notifications showing, the cards sit on whole pixels at fractional scaling, and Clear all and Show more keep an even gap to them.
- With week numbers on, the calendar's day squares sit on whole pixels at fractional scaling instead of blurring at their sides.
- The System and Keyboard widgets fade out when switched off, as the other widgets do, instead of disappearing at once.
- Window titles that contain icon glyphs no longer cut off early with a font other than the default.
- Home's brightness display choices are named for screen readers.
- On a computer without a battery, Alerts keeps the low battery warning switch, which also covers Bluetooth devices.
- An open calendar stays centred on its clock as the clock's date appears or folds away, instead of slipping to one side.
- With Reduce motion on, a tray menu opened while the app's name showed on hover opens on its icon instead of beside it.
- On a theme change, workspace markers, the OSD, notification outlines and update status colours change with the rest of the shell instead of trailing it.
- The night light's sun arc writes durations like the battery does, "1h 5m" rather than "1h 05m".
- Switching outputs with a long device name no longer pushes the volume level out of the on-screen display.
- Above 115% UI scale, Quick Actions icons no longer run into their labels.
- The on-screen display grows with UI scale, instead of keeping its 100% size while its icon and level grew inside it.
- With week numbers on, the calendar's week column widens with UI scale, so the numbers no longer crowd the line beside them.
- Notification popups' app icon and close button grow with UI scale above 100%, instead of shrinking beside the larger title.
- Home's volume and brightness sliders are the same length when only the volume row has options to open, such as on a laptop with a microphone and one output.
- At a large interface scale or icon size, slider rows, the accent and base pickers, Home's system readings and the notes under settings rows line up with the other labels.
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
