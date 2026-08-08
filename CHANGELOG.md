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

[Unreleased]: https://github.com/s3rven/silere-shell/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/s3rven/silere-shell/releases/tag/v0.1.0
