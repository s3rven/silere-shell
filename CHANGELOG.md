# Changelog

Notable changes to Silere Shell.

Versions follow [Semantic Versioning](https://semver.org/) loosely while in `0.x`:
minor versions change features, patch versions fix them. The settings file has its
own `__version` and migrates separately.

The updater tracks `main`, not tags, so a running install gets changes as they land
rather than when a version is published here.

## [Unreleased]

Settings carry over; a stored `barCornerStyle` of "flat" becomes a Roundness of 0.

### Added

- Night Light and the daily update check say why a switch flipped back, instead of
  failing silently. `hyprsunset` exiting on its own now reports its own last line.
- Reset backups are stamped with the time, so a second reset no longer overwrites
  the record of the first. The five newest are kept.

### Changed

- Choice controls — Source, Date, Position and the rest — are separated chips. The
  selected one carries an accent outline instead of a filled plate, so accent stays
  a state colour rather than a resting one.
- Bar corner style folded into Roundness: 0 is flat. The slider only appears for a
  floating bar, since a docked bar does not paint its own corners.
- The Night Light panel builds when you open it, as the Wi-Fi and Bluetooth panels
  already did.
- "Fully-charged OSD" is now "Fully charged alert", and the desktop-notification
  timeout reads "Dismiss after" like the other two timeout rows.
- README resource figures re-measured, including how much of the memory is the Qt
  and GPU driver floor rather than Silere.

### Fixed

- A setting changed in the last fraction of a second before logout is no longer
  lost. Toggles and choices are written immediately; sliders still settle first.
- The same for marking a day in the calendar.
- A double-click can no longer arm and confirm a destructive action in one gesture.
  Affects the power actions, clearing notification history, and resetting settings.
- A row that disables itself while handling its own click no longer comes back
  looking keyboard-focused.
- "Always show speed" no longer appears underneath a Network speed row that is
  disabled for want of NetworkManager.
- The bar underline preview no longer reaches for an effect that is not built yet.

### Removed

- The "Bar corner style" setting. Roundness 0 is flat.

### Security

- The installer creates its config directory as 0700 for the whole path, not only
  the last segment.

## [0.2.0] - 2026-08-10

Mostly install and update fixes. Settings carry over untouched, nothing migrates.

### Added

- Update card shows the installed version by tag, plus commit, branch and build date.
- Pending updates expand into the commits they would install.
- Update checks remember when they last reached the remote, unattended runs included.
- The daily update check shows when it next runs.
- Keyboard focus works across the menu: buttons, rail, sliders, chips and swatches.
- Notifications get their own Wayland namespace, `silere-notifications`, so layer
  rules can target them without also hitting the bar.

### Changed

- The update card warns about a wrong branch, detached HEAD or local edits before
  you press Install, not after it fails.
- Pending commits moved into their own expandable list.
- The bar stops rebuilding its workspace and window models when a layer opens or
  closes. Twenty menu cycles cost 43 rebuilds before, none now.
- Retimed panel, popup and toggle motion. Split the floating shadow into an
  ambient and a contact layer.
- The media widget sizes to its text instead of holding a fixed slot.
- Accents keep the chroma that sRGB blending used to cancel.
- The Hyprland Lua autostart snippet uses the native `hl.exec_cmd`.

### Fixed

- The installer no longer says "restart your compositor" when it never added an
  autostart line.
- Autostart prompts name the full path of the file they will write to.
- QML modules are found on Debian and Ubuntu (`/usr/lib/x86_64-linux-gnu/qt6/qml`).
  They were all reported missing there before.
- The installer checks for `xz` before downloading 30 MB of font it cannot extract.
- The installer detects a missing terminal properly instead of dying at the first
  prompt.
- The updater's `git fetch` is bounded. A dead network could wedge every later
  check behind an orphaned fetch holding the lock.
- Updates are type-checked after merging and rolled back if they do not load. A
  broken update used to leave the shell respawning every three seconds.
- `update.sh --apply` only restarts the shell that runs the checkout it was called
  from.
- On niri, the workspace strip no longer pads out with slots that do nothing.
- The niri event stream reconnects after a dropped socket instead of freezing.
- A pending Wi-Fi connection is cancelled when Wi-Fi goes off or the device leaves.
- Bluetooth battery percentages go through one validated conversion.
- Bar widgets fall back to empty models when a backend detaches.
- The update split header tolerates malformed counts.

### Removed

- The workspace marker trail.
- The media widget's "Track text width" setting. It sizes to its text now.
- Home, End, Page Up and Page Down in menu rows, pickers and sliders. Arrow keys,
  Escape and the calendar's jump-to-today still work.

### Security

- Stored notifications are guarded against prototype pollution.

## [0.1.0] - 2026-08-08

First tagged release. Silere had been in daily use for a while; this is just a
point to refer back to.

Needs Quickshell 0.3 or newer and either Hyprland or niri. Everything else is
optional, and the README lists what each tool turns on. Grouped by area here,
since a first release has nothing to differ from.

### Shell

- Bar with left, centre and right zones, drag-to-reorder, per-monitor visibility,
  and compacting when space runs short.
- Widgets: workspaces, clock, media, tray, network, volume, brightness, battery,
  package updates, shell updates.
- Notification popups with urgency styling, inline actions, images, a countdown
  ring, do-not-disturb scheduling and a history page.
- On-screen display for volume and brightness, optionally drawn inside the bar.
- Control menu with a Now page, notification history, and 108 settings.
- Calendar with month marks, tray menus, and a quick-actions popup.

### Theming

- Wallpaper colours through matugen, or one of seven hand-picked accents.
- Three base tones with a depth axis, adjustable outline strength, high-contrast
  mode, and a reduce-motion mode that zeroes every animation.
- Font family and scale come from installed Nerd Fonts and are validated, so a
  removed font cannot leave the shell unreadable.

### Behaviour

- Background work stays off unless you turn it on. Timers are gated on idle,
  capability and menu visibility.
- A missing optional tool hides its widget. The rest keeps working.
- No plugin layer and no extra daemon.
- Notification icons and images never load over the network. A remote URL from a
  sender is ignored.

### Known limitations

- Special workspaces are Hyprland-only. On niri that state is absent.
- The updater only fast-forwards `main`. It refuses to run on a checkout with
  local changes or a diverged history, and says why instead of fixing it.

[Unreleased]: https://github.com/s3rven/silere-shell/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/s3rven/silere-shell/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/s3rven/silere-shell/releases/tag/v0.1.0
