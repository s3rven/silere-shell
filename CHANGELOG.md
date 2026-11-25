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

- Hooks for `dnd-changed`, `idle-changed`, `media-changed`, `network-changed` and `power-source-changed`, each run
  when that state changes. An event with no hook file still costs nothing.
- `silere osd <glyph> <text> [0-100]` shows a message of your own in the OSD, with a level bar when you give one, so a
  script's key or toggle answers the way volume and brightness do.
- Hibernate in the power menu, where the system can resume from it.
- A warning when the system disk or your home has under 2 GB and under 5% free, checked at login and every few
  hours of use.
- Flatpak updates in the package count and list, checked every few hours alongside your package manager.
- Wireless mice, keyboards and pads on their own receivers warn when low, as Bluetooth devices do, and appear in
  Home's battery details on a laptop. On a desktop the bar shows one while it is low.
- Overview and the power menu's Reboot say when an update replaced the running kernel and a restart is needed.
- After a crash, the restarted shell says so once, and `silere doctor` names the last crash and where its report is.
- `silere theme <image>` takes the accent from a picture on the neutral theme, for a desktop without matugen.
- `silere indicator set <name> <glyph> [text]` shows a mark of your own in the bar until `silere indicator clear`;
  scripts push it, nothing polls.

### Changed

- Settings › System › Keybinds names keys as printed on them: Page Up, Caps Lock, Left, Brightness Up, and `.` or
  `/` for punctuation.
- A widget an update adds takes its default place in a bar you have rearranged, not the end of its side.
- The underline glow and the OSD inside the bar are compiled only once switched on, so a default start does less
  before the bar shows.
- Round buttons, chips, search fields, slider handles and level bars follow Roundness like the cards around them, and
  square off on Flat. The default look is unchanged.
- Settings › Widgets › Indicators: Hide charged battery is now **Hide while plugged in**, which is what it always did.
- The installer ends its list of missing optional tools with the one command that installs them on your system, the
  way `silere doctor` does, and stays quiet about matugen's steps when matugen is not installed.
- The optional user service treats a logout as a clean stop: Quickshell exits 255 only once the compositor is gone,
  so the unit no longer shows as failed after every logout or tries to restart without one. Crashes still restart it.

- On Hyprland the installer binds the menu key to the `silere:menu` global shortcut, which starts no process per press,
  and Settings › System › Keybinds names that bind on any key. `silere doctor` names an older `qs ipc` menu bind and
  the line that replaces it.
- Without Quickshell, the installer names the package to install on Void, and on Debian or Ubuntu when theirs is new
  enough.
- The installer, `silere`, the updater, reset and uninstall stop under sudo or doas: Silere works on your own session,
  and a run as root used root's home and left files in the checkout that later updates could not replace.
- Silere now needs Quickshell 0.3.2 or newer. On 0.3.1, `silere update` stays on the installed release and says why.
- Day and month names follow your language in the bar, Home, history and the clock settings, in your language's
  order; English is unchanged.
- Notification popups wait in history during a call, as they do in fullscreen. The switch is now **Hide in
  fullscreen and calls**.
- Clicking the welcome notification opens the menu, and the installer's last line also mentions right-clicking the
  workspace for quick actions.
- `silere update` brings the optional user service it installed up to date with the release.

### Fixed

- `silere status` and Settings › System › Overview no longer call an update check older than two days up to date; they
  say when it last found none.
- A workspace app icon no longer flashes its letter while it loads.
- The menu no longer jumps in size when it closes mid-resize or reopens on another page while fading out.
- Opening the Wi-Fi list on Home while another list is open no longer jerks the rows below it up first.
- A system reading of a few percent on Home shows a dot where its bar starts, so the bars line up.
- The calendar's month arrows, the tray's submenus and the Clear all buttons no longer draw soft-edged at fractional
  scales such as 1.25.
- With app icons on, a workspace's first window fades its icon in over the empty ring instead of swapping them in one frame.
- A notification that names no app shows its initial instead of an unrelated app's icon.
- `silere doctor` suggests a package for a missing screen locker, Git, curl or xdg-open too, and names more of them on
  openSUSE and Void.
- Settings › System › Keybinds reads a Lua workspace bind made by keycode, as other keyboard layouts need, as the
  workspace it goes to instead of a bare "Focus".
- Notification, Recent page and slider icons no longer flash a letter or glyph before they first appear.
- The menu's Now Playing label keeps an emoji or flag whole where it shortens a long track title.
- `bash scripts/uninstall.sh --help` explains the uninstaller instead of starting it, and it and `scripts/update.sh` stop
  at an option they don't know instead of carrying on without it.
- `bash scripts/install.sh --dry-run` also lists the shell completion links the install creates.
- Uninstalling removes the backup of your Hyprland or niri config once it matches the config again, and a matugen
  config that only the installer wrote.
- On Debian and Ubuntu, the installer, `silere doctor` and `silere try` name `qml6-module-qtquick-effects`, which their
  `quickshell` package leaves out and Silere cannot load without, instead of telling you to reinstall Quickshell.
- `silere try` stops with the reason when Quickshell is too old or a QML module is missing, instead of opening a
  preview with no bar in it, and its Quickshell and font hints no longer assume Arch.
- The installer no longer lists an AUR helper among the optional tools outside Arch and its derivatives.
- External monitor brightness no longer fills the system journal with ddcutil's own diagnostics, which showed up as
  warnings from Silere (about 90 a week here).
- The package updates pill no longer appears and folds away at each automatic check while nothing is pending.
- A long track title in the bar ends in an ellipsis once it stops scrolling, instead of a letter cut in half.
- Scrolling fast over the workspaces moves one workspace per notch, and no longer bounces back with Hyprland's
  workspace back-and-forth.
- A new message in a conversation no longer replaces the notification under your pointer, and resting on Clear all
  or Show more holds the cards as resting on them does.
- Notifications that arrive while you are away and are put away when the screen goes idle count as missed.
- A notification kept open for a reply is no longer counted as hidden behind Show more.
- A script that replaces its own notification by tag, such as a volume or brightness script, keeps one row in history
  instead of one per use.
- Settings search shows its results whole at larger interface scales.
- Hiding one Chromium or Electron app's tray icon, such as Discord's, no longer hides every other one's.
- Day and month names stay in your language after `silere reset`, a reinstall, or an update that restarts the shell
  without the optional service.
- `silere repair --undo` and `silere reset --undo` leave the checkout as it was when the saved edits conflict, instead
  of files full of conflict markers.
- `silere use` replaces a `silere` command left pointing at a moved or deleted checkout; `silere doctor` prints its
  failures with the rest, so a saved report keeps them; `silere reset --history` previews; `silere service install`
  says when the system has no systemd; a mistyped `osd`, `theme` or `indicator` is suggested.
- Turning Bluetooth on when its radio cannot be unblocked says why instead of doing nothing.
- A Wi-Fi network that takes long to join, such as a work network, reports NetworkManager's own answer instead of
  failing after 20 seconds.
- A power mode the laptop switches itself as the charger is pulled is no longer remembered as your plugged-in choice.
- Without pgrep, switching off a night light another program started keeps it shown as on.
- The audio visualizer keeps moving when a fullscreen window covers a monitor whose bar it is not on.
- On niri, clicking an X11 app's notification raises it when another X11 app has the focus.
- A tray app whose own icon fails gets its app's icon once the installed apps are read, not only its initial.
- On a limited network, the internet check stops while nothing shows the network.
- Unmuting an app in Settings, or saving a lock command with Enter, keeps the keyboard where it was.
- Settings › System › Devices shows one accurate hint when no screen locker is found.
- Choosing Alert for a battery or temperature warning no longer turns off a glow chosen on the Underline page.
- With `~/.config/silere-shell` linked into a dotfiles folder, settings, notification history and hooks are saved and
  run again; the installer installs through such a link, but the shell refused to write there.

## Releases

- [1.9.0](docs/releases/1.9.0.md) — 2026-11-24
- [1.8.0](docs/releases/1.8.0.md) — 2026-11-19
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
