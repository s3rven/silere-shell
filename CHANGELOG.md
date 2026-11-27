# Changelog

Only work since the latest release is listed here. Completed notes move to
[`docs/releases`](docs/releases/) and stay linked at the bottom of this file.

Format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with entries
grouped by the part of the shell they touch once a section runs long. Versions follow
[Semantic Versioning](https://semver.org/) loosely while in `0.x`: minor versions
change features, patch versions fix them. The updater follows signed stable tags; the
settings file carries its own `__version` and migrates separately.

## [Unreleased]

- A mistyped option to `silere update`, `status`, `log`, `stop`, `restart`, `use`, `link` or `uninstall` names that
  command's usage in one line, as the control commands do, instead of printing the whole help.
- With several monitors on Hyprland, moving the pointer to another monitor asks Hyprland for its monitor list only
  when that monitor shows a workspace named other than its number, the one case Quickshell 0.3.2 loses track of.
- A notification that arrives while a web browser plays video keeps its usual timer instead of waiting over the video
  for the pointer to move. Browsers hold their wake lock through the idle daemon (hypridle), which the compositor and
  so the shell never hear of; a browser's playing media now counts as that lock.
- Settings > System > Keybinds reads a hyprlang `workspace, -1` bind as going to the previous workspace, not to workspace -1.
- On niri, the workspace arrow points to a window that needs you on a monitor whose bar is off, as it does on
  Hyprland.
- A Hyprland submap entered on a monitor whose bar is off shows its name on the bar that is on.
- Two quick middle clicks on the volume or microphone widget step two outputs or inputs, not one.
- With Hover highlight on, widgets a click does nothing on (one keyboard layout, the indicators) no longer light up
  under the pointer.
- A notification that comes in your first minutes away and is still waiting when the session goes idle counts on the
  bell as missed.
- A notification over a browser video keeps its timer after four minutes without input too, instead of waiting until
  the pointer moves.
- Notification timeouts wait while the calendar or a tray menu is open too, not only the menu and quick actions.
- A volume or brightness script replacing its notification no longer makes the cards below it dip and slide back.
- Turning on Do not disturb counts the notifications it files before they were ever shown on the bell as missed.
- Notifications waiting behind Show more while you are away are filed at idle with the rest, instead of staying up
  while newer ones went to History.
- A key or wheel step on the Night Light, display brightness or seek slider still applies when Escape or closing the
  menu follows it at once.
- Settings and History reopen at the height they closed at again; the heights were lost as soon as the menu finished
  closing.
- An empty Wi-Fi list says No networks found instead of switching back to Searching every eight seconds.
- Now Playing says Stopped, not Paused, for a player that stopped with its track still loaded.
- An app whose window, tray or audio stream id is a file path no longer has that file loaded as its icon.
- A track you pause from the bar or Now Playing, or one paused as headphones disconnect, stays on the bar until you
  play again or step away, instead of folding after 15 seconds with nothing left to resume it.
- Right-click the clock to open notification history, where its missed-notification bell leads; again to close it.
- On a computer without Wi-Fi, clicking the network widget with the cable unplugged shows Ethernet as Disconnected
  instead of a Home page with no network row.
- On a desktop, hovering the battery pill for a low mouse or keyboard names the device.
- On a laptop without power modes (TLP, auto-cpufreq), clicking the battery opens its details in Home.
- With the OSD off, a low battery sends a notification instead of nothing; only the critical level used to.
- Two browser tabs recording read as one app listening on the microphone widget, not two.
- The microphone widget and the apps under Input follow the microphone each app records from, so they no longer read
  Muted while an app hears an unmuted one.
- `silere mic mute` shows the same Microphone · Muted OSD as the mute key, so the OSD keeps its width.
- On Hyprland with `workspace_back_and_forth`, jumping to a window on the current workspace (a notification click,
  Now Playing) no longer flips to the previous workspace and back.
- The `media-changed` hook reports `stopped` for a player that stopped with its track loaded, and runs when a paused
  player stops.
- A hyprsunset started outside Silere (its own unit) takes Night Light's temperature when Silere finds it running,
  instead of staying neutral while the switch reads on.
- Behind a sign-in page or with no internet, the updates widget no longer reports the package check as broken.
- A settings file Silere cannot change the mode of (root's, after a run under sudo) no longer leaves notification
  history and hooks off for the session.
- Settings no longer marks Devices as changed for a custom lock command or a display list that is folded out of sight.
- Searching Settings for roundness finds the Roundness row.
- Let critical through is greyed while popup notifications are off, since nothing can pop up past them.
- Switch animation and Notification pulse say they are off while Reduce motion is on.
- Icon size says it sizes the tray and workspace app icons.
- Undoing a settings reset in the menu removes its backup, so `silere reset --undo` no longer puts the older settings
  back over yours later.
- Updates install where an older qmllint is present (Fedora's Qt tools, Qt 6.10), instead of being refused as an
  update that does not load.
- `silere service start` keeps your locale for the shell and the session, instead of starting them in the C locale.
- The updater's repair and rollback hints work when copied for a checkout whose path has a space.
- Shell completion offers `--yes` only after `repair --apply` or `--undo`, and `run`'s two flags in either order.
- Behind a sign-in page the package check waits for the network to clear instead of rerunning every three minutes.
- The microphone widget's glyph, colour, text and level all follow whether an app hears you, instead of mixing the
  default microphone's mute in.
- A notification that times out while you are away with browser music playing counts on the bell as missed.
- Cards filed from behind Show more at idle count as missed only if they came after your last input.
- The updater's repair and rollback hints quote the path so bash, zsh and fish all read it, accented names included.
- History opened from the clock stays centred on it as the missed bell folds, and the clock is marked while it is
  open, as for the calendar.
- The menu opened from its keybind puts the focus on its tab, so the arrow keys move at once, as in Quick Actions
  and tray menus.
- Wi-Fi or Bluetooth blocked by the hardware switch keeps its row readable in Home; only the switch dims.
- With a bar on each monitor, an open tray menu lights its app's icon only on the bar it opened from.
- Greyed tray menu entries follow High contrast like every other disabled row.
- With Reduce motion on, Clear history and the widget reset show no ring that never drains, and every confirm says
  Press again.
- A bar widget stays marked while the menu page it opened is showing, as the clock and the tray already were.
- Quick Actions lights Power Mode for Power Saver as well as Performance, as Home does.
- Without JetBrainsMono Nerd Font, opening Settings no longer switches the shell to the first font installed (often a
  serif); another Nerd Font stands in.
- `silere theme` saves its accent and mode in one write instead of two.

## Releases

- [1.10.0](docs/releases/1.10.0.md) — 2026-11-25
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
