# Changelog

Notable changes to Silere Shell, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow
[Semantic Versioning](https://semver.org/) loosely while in `0.x`: minor versions
change features, patch versions fix them. The updater follows signed stable tags;
the settings file carries its own `__version` and migrates separately.

Only work since the latest release is listed here. Completed notes move to
[`docs/releases`](docs/releases/) and stay linked below.

## [Unreleased]

### Added

- With **Playback status** on, the media visualizer doubles as the progress readout:
  the spectrum past the playhead is dimmed.
- A dot in the settings rail marks each page holding a value you changed from its
  default. A collapsed group carries one for the pages inside it.
- **Mark changed pages** in Settings › Appearance › Interface turns those dots off.

### Fixed

- Reordering bar widgets no longer closes the menu, and neither does resetting them.
- The settings rail keeps the current page marked while the pointer is over it.
- Descriptions and hints across the settings pages are brighter.
- **Shell shadows** and **Depth** moved to Settings › Appearance › Theme.
- **Shell shadows** names what it covers while the bar is docked.
- Untracked files no longer block shell updates. When an incoming file genuinely
  lands on one, git's reason and the filename are reported.
- A blocked update points at `scripts/repair.sh --apply` instead of suggesting
  commit or stash.
- Installing from the Updates page checks the same blocked reasons the button does.
- Temporary Cava profiles left in `$XDG_RUNTIME_DIR` by dead processes are cleared.
- Settings rail: group headers are plain text, only the current group is marked, and
  children indent clear of it.
- The calendar's today pill grows with the font.
- Settings › Widgets › Show & order no longer claims arrow keys move between lanes.
- The font picker says it lists Nerd Fonts only.
- **Keep groups open** moved out of Text & accessibility into its own Menu group.
- Floating bar Width, Edge gap and Roundness share one disclosure, so turning it on
  plays a single reveal.
- **Order & visibility** is now **Show & order**, which fits the rail. A check keeps
  future nav labels inside the width.
- The Wi-Fi row reports a hardware rfkill block ahead of a note about Ethernet.
- `qs ipc call menu settings <name>` falls back to Theme for a renamed section, as
  documented, and still reports the unknown name.
- The network widget follows the live wired link when Ethernet and Wi-Fi are both
  connected. Disconnecting from the Wi-Fi list acts on the Wi-Fi radio.
- Night Light adopts an already-running `hyprsunset`, and says when it could not check.
- Brightness writes are bounded and report failure instead of snapping back.
- Wi-Fi and Airplane Mode no longer offer toggles a hardware rfkill switch refuses.
- Theme and Maintenance report a palette file that could not be read.
- Quick actions no longer show Power Mode as live when no daemon answers.
- Acting on a notification keeps it in history, as dismissing already did. Notifications
  a sender withdraws are kept too.
- A supervised process no longer retires on a signal sharing a number with a give-up
  exit code.
- Settings › Bar › Underline reports a missing screenshot folder instead of showing the
  control as live.

## Releases

- [0.5.1](docs/releases/0.5.1.md) — 2026-08-13
- [0.5.0](docs/releases/0.5.0.md) — 2026-08-13
- [0.4.0](docs/releases/0.4.0.md) — 2026-08-12
- [0.3.0](docs/releases/0.3.0.md) — 2026-08-11
- [0.2.0](docs/releases/0.2.0.md) — 2026-08-10
- [0.1.0](docs/releases/0.1.0.md) — 2026-08-08
