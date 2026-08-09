# Changelog

Notable changes to Silere Shell.

Silere uses [Semantic Versioning](https://semver.org/) while in `0.x`: minor
versions add or change features, patch versions fix them, and neither promises a
stable interface yet. The settings file carries its own `__version` and is
migrated independently of these numbers.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Later releases group entries as Added, Changed, Fixed, Removed, or Security.
`0.1.0` is grouped by area instead, because a first release has no earlier
version to differ from.

Note that the built-in updater tracks `main` rather than tags, so a running
install receives changes as they land, not when a version is published here.

## [Unreleased]

Nothing yet.

## [0.2.0] - 2026-08-10

Settings carry over untouched. The settings format is unchanged from `0.1.0`, so
nothing is migrated and the options removed below are ignored rather than reset.

### Added

- The shell update card names the installed version by tag — `v0.1.0`, or
  `v0.1.0 +12` when the checkout sits that many commits past one — and reports
  its commit, branch and build date underneath.
- A pending shell update expands into the individual commits it would install,
  and names the version it moves to when the update crosses a tag.
- Update checks record when they last reached the remote, unattended runs
  included, so the card can report it after a restart rather than only within
  the session that ran the check.
- The daily update check reports when it next runs.
- Keyboard focus is visible everywhere in the menu. Buttons, rail entries,
  sliders, choice chips and accent swatches draw a focus ring and respond to the
  keyboard, rather than only to the pointer.
- The notification layer declares its own Wayland namespace,
  `silere-notifications`, so compositor layer rules can target notifications
  without also matching the bar or the on-screen display.

### Changed

- The update card states up front when the checkout is on another branch, on a
  detached HEAD, or carries local changes. Those are the conditions the
  installer refuses to run in, and they were previously only reported after
  Install had already failed.
- Pending commits moved out of the card's status line into their own expandable
  list, matching how pending packages are already presented.
- The bar no longer rebuilds its workspace and window models when a layer surface
  opens or closes. The shell's own menus, notifications and on-screen display are
  the usual source of those events, and none of them change what the models hold.
  Twenty open/close cycles cost 43 rebuilds of each model before, and none now.
- Panel, popup and toggle motion was retimed, and the floating shadow was split
  into an ambient and a contact layer instead of one uniform blur.
- The media widget sizes itself to the text it is showing instead of holding a
  reserved slot.
- Themes keep the chroma that blending a tint in sRGB otherwise cancels, so an
  accent stays as saturated as it was picked.
- The Hyprland Lua autostart snippet uses the native `hl.exec_cmd` API rather
  than shelling out.

### Fixed

- On niri, the workspace strip no longer pads out to a fixed number of slots.
  niri numbers workspaces per output and keeps the set dynamic, so the padding
  drew slots whose index `focus-workspace` could not resolve: they looked
  clickable and did nothing.
- The installer no longer tells you to restart your compositor when it never
  wired up autostart. A missing runtime and an unwired autostart are reported as
  two independent facts, so an install that put the files in place but has
  nothing to launch them now says so.
- Every installer autostart prompt names the full path of the file it will
  append to, instead of a bare filename that can match several candidates.
- QML modules are found under Debian's multiarch path
  (`/usr/lib/x86_64-linux-gnu/qt6/qml`). On Debian without the Qt development
  packages, the check previously reported every required module as missing.
- The installer checks for `xz` before offering the font download. The release
  archive is `.tar.xz`, so a missing `xz` used to surface as `extract failed`
  after a 30 MB download had already been fetched and verified.
- The installer detects a missing terminal by opening `/dev/tty` rather than
  testing it for readability, which succeeds even with no controlling terminal.
  Non-interactive runs now say what is wrong instead of failing on an unset
  reply at the first prompt.
- The updater's `git fetch` is bounded. A blackholed network could leave a fetch
  running past the shell's own timeout, and the orphan inherited the update lock
  and wedged every later run behind it.
- An update is type-checked after merging and before the shell restarts into it,
  and rolled back if it does not load. A broken update otherwise left the user
  service respawning every three seconds indefinitely.
- `update.sh --apply` only restarts `silere-shell.service` when that unit is
  running the checkout the script was invoked from, so an update run from a
  second clone no longer restarts an unrelated live shell.
- The niri event stream is retried after a dropped socket instead of leaving the
  workspace and window state frozen.
- A pending Wi-Fi connection is cancelled when Wi-Fi is switched off or the
  device disappears, rather than resolving against a device that is gone.
- Bluetooth battery percentage goes through one validated conversion, so a
  device reporting an out-of-range value no longer renders as a broken readout.
- Bar widgets fall back to empty models when a backend detaches, and guard their
  bindings against a null screen during output changes.
- The update split header tolerates malformed counts instead of rendering them.

### Removed

- The workspace marker trail. It was the only decoration on the bar that drew
  purely for its own sake.
- The media widget's "Track text width" setting. The widget now sizes to its
  text, so the fixed-width choice had nothing left to control.
- Home, End, Page Up and Page Down inside menu rows, list pickers and sliders.
  They jumped to the first or last entry, or to a slider's minimum or maximum,
  which the arrow keys and the pointer already covered. Escape, the arrow keys,
  and the calendar's jump-to-today are unchanged.

### Security

- Persisted notification maps are guarded against prototype pollution, so a
  crafted key in a stored notification cannot reach `Object.prototype`.

## [0.1.0] - 2026-08-08

First tagged release. Silere has been in daily use for some time; this marks a
point that can be referred to, not the start of the project.

Requires Quickshell 0.3 or newer and either Hyprland or niri. Everything else is
optional; the README lists what each tool enables.

### Shell

- Configurable bar with left, centre and right widget zones, drag-to-reorder
  arrangement, per-monitor visibility, and automatic compacting when space runs short.
- Widgets: workspaces, clock, media, system tray, network, volume, brightness,
  battery, package updates, and shell updates.
- Notification popups with urgency styling, inline actions, images, a countdown
  ring, do-not-disturb scheduling, and a history page.
- On-screen display for volume and brightness, optionally drawn inside the bar.
- Control menu with a Now page, notification history, and a settings page
  covering 108 options.
- Calendar with month marks, system tray menus, and a quick-actions popup.

### Theming

- Wallpaper colours through matugen, or a hand-picked accent from seven presets.
- Three base tones with a depth axis, adjustable outline strength, high-contrast
  mode, and a reduce-motion mode that zeroes every animation.
- Font family and scale are picked from installed Nerd Fonts and validated, so a
  removed font cannot leave the shell unreadable.

### Behaviour

- Background work stays off unless enabled. Timers are gated on idle, capability,
  and menu visibility.
- Missing optional tools hide the widget that needs them; the rest keeps working.
- No plugin layer and no additional daemon.
- Notification icons and images never load over the network. A remote URL from a
  sender is ignored rather than fetched.

### Known limitations

- Special workspaces are Hyprland-only. On niri that state is simply absent.
- The updater only fast-forwards `main`. It refuses to run when the checkout has
  local changes or has diverged, and reports why instead of resolving it.

[Unreleased]: https://github.com/s3rven/silere-shell/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/s3rven/silere-shell/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/s3rven/silere-shell/releases/tag/v0.1.0
