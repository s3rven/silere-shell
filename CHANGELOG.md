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

- Search notification history by app, title or message; Clear removes only the visible results.
- Calendar week start and week-number visibility under Clock settings.
- Screen-reader names for the Wi-Fi password field and the missed-notification badge.
- Do Not Disturb, night light, power mode, Wi-Fi, Bluetooth and airplane mode each toggle
  over IPC, for a keybind that changes one without opening a panel.
- The installer offers a key that opens the menu, and leaves a combination the Hyprland
  config already uses alone.
- The bar and OSD blur what is behind them on Hyprland 0.56 and niri 26.04 or newer, as do popups set to match the bar's opacity.
- Muting the microphone from a key or another mixer shows on the OSD.
- Hovering the clock shows the date while the date is turned off.
- Show & order notes which widgets appear only in use, and which this machine cannot show.

### Changed

- The clock highlights while its calendar is open and keeps hour and minute digits in stable-width slots.
- Several Settings pages regroup and relabel their rows, and Show & order counts only the widgets it shows.
- Settings › Updates shows the package status only while tracking is on.
- Bar opacity and popup matching now live under Settings › Theme, beside outlines and shadows.
- Clock settings offer each date and time format as the bar would draw it.
- Choice chips, color swatches, the menu's side lists and its tab icons glide their selection to the new pick.
- The custom accent sliders are labelled with their hue and intensity, and their handles stay visible on any color.
- Sliders run the full width of their row on a slimmer track, and the value lights up while you drag.
- Toggle knobs stretch while held, and slider handles lift while dragged.
- `scripts/check.sh` runs its probes and the settings sweep side by side and finishes in about a quarter of the time.
- New notifications stack nearest the bar, and the popup limit keeps the newest ones in view.
- Notification history groups a run of messages from one app into a single card; a critical alert keeps a card of its own.
- Automatic night light changes temperature in 500 K steps through dusk and dawn.
- Scrolling volume or brightness lands on the next multiple of 5%, even from a level set elsewhere.
- Saved Wi-Fi networks are listed right after the connected one and marked Saved.
- The window title drops a terminal's spinner glyph, and names the app as its launcher entry does.
- With natural touchpad scrolling, an upward swipe still raises volume, brightness and sliders.
- The OSD and notification cards draw a heavier edge, and the notification countdown ring no longer blurs at fractional scales.

### Fixed

#### Bar

- Pill hover values reset when the bar sleeps or the widget hides.
- Calendar today markers follow the clock across midnight.
- The tray menu closes when the bar moves to the other screen edge.
- A tray tile waits for its own icon when the bar hands it a different app.
- With app icons on, the rest of the bar moves with the workspace strip when you switch, and the icons fade out under the marker.
- Moving focus between windows no longer blinks the divider beside the window title.
- On Hyprland, a window that is maximized and fullscreen at once counts as fullscreen.
- The volume icon judges a combined or virtual output by the device it plays to, not by its name.
- An output that reaches no connected device reads No device in the output list.
- A battery held at a charge limit, such as Lenovo conservation mode, reads not charging instead of charging.

#### Menu and settings

- Escape closes an open Settings dropdown before it closes the menu.
- The alert dismiss timeout is disabled when libnotify is missing.
- Popups open and close over a window without a bright flash.
- Switching menu pages from a keybind resizes the panel in one motion.
- Show & order lists Workspaces with the same icon as the settings rail.
- Outlines on the OSD, notifications, menus and settings cards stay one pixel sharp on fractionally scaled displays.
- Settings saved by a newer Silere keep the values this version would clamp, until you change them here.
- A setting changed back after a hand edit of settings.json is saved, and a hand edit made while a change is pending is no longer written over.
- A settings upgrade that cannot back up the old file leaves that file as it was.
- Calendar marks follow edits to their file while the shell runs, and a hand-written date with leading zeros marks its day.
- Refresh in Settings › Maintenance rechecks installed fonts as well.
- Quick actions show Failed when a power mode change is refused, and the IPC toggles for Wi-Fi, Bluetooth and airplane mode report the state they asked for.
- The Now page's usage bars step in whole percents, and an open Now page uses much less CPU.
- Quiet hours and the night light's sunrise and sunset follow the 12-hour clock.

#### Notifications

- A notification with no app name is named the same in history as in the app rail, and search finds it.
- A notification progress bar draws the percentage its sender set.
- A notification asking to outlast the popup limit is held at the limit instead of the default.
- Notification history grows to fit its entries instead of cutting off the last one.
- Cards below a notification its app withdraws slide up to close the gap.
- The "Show more" notification chip keeps its count while it folds away.
- Open notifications keep their age and read state when the shell reloads its files, and their hooks do not fire again.
- A notification that updates in place, like a download, restarts its timeout with each update.
- An empty reply field left behind no longer keeps its notification on screen.
- Past fifty open notifications, the oldest move to history.
- A notification's close button stays put when hovering expands the card.
- A one-line history entry keeps its expand arrow clear of the remove button.
- Searching history shows only the matches, without leftover entries or repeated day headings, and each keystroke settles in one step.
- The history scroll bar runs beside the entries rather than over their edge.

#### Media

- The audio visualizer stops retrying when cava refuses to start, and tries again at the next playback.
- Dragging the seek bar sends the player a seek at most ten times a second.

#### Network

- With two Wi-Fi adapters, confirming a disconnect drops the network you confirmed.

#### System

- The compositor restart watcher recovers once inotify-tools is installed.
- Reloading or killing the shell no longer leaves its file watchers running.
- Night light holds its memory steady over a long session.
- A failing package check backs off instead of retrying every three minutes.
- After a suspend, the clock and night light catch up as soon as NetworkManager reconnects.
- The first brightness change of a session shows the OSD.
- A low battery or hot CPU at login still raises its alert, and plugging in a full battery says so once.
- Brightness and night light report a program removed while the shell runs instead of waiting on it.
- The night light sun arc keeps moving while the menu stays open, and a midnight sun no longer reads as night after midnight.

#### Install and updates

- A downloaded copy of Silere is no longer described as package-managed; Settings › Updates points it at the installer.
- A release tag withdrawn upstream stops blocking update checks.

### Security

- The updater reads origin/main by its full ref name, so a tag of the same name cannot stand in for the branch.

## Releases

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
