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
- While a web browser plays video or music, a notification keeps its usual timer however long since your last input,
  instead of waiting over the video for the pointer to move.
- Settings › System › Keybinds reads a hyprlang `workspace, -1` bind as going to the previous workspace, not to
  workspace -1.
- On niri, the workspace arrow points to a window that needs you on a monitor whose bar is off, as it does on
  Hyprland.
- A Hyprland submap entered on a monitor whose bar is off shows its name on the bar that is on.
- Two quick middle clicks on the volume or microphone widget step two outputs or inputs, not one.
- With Hover highlight on, widgets a click does nothing on (one keyboard layout, the indicators) no longer light up
  under the pointer.
- A notification that comes in your first minutes away and is still waiting when the session goes idle counts on the
  bell as missed.
- Notification timeouts wait while the calendar or a tray menu is open too, not only the menu and quick actions.
- A volume or brightness script replacing its notification no longer makes the cards below it dip and slide back.
- Turning on Do Not Disturb counts the notifications it files before they were ever shown on the bell as missed.
- Notifications waiting behind Show more while you are away are filed at idle with the rest, instead of staying up
  while newer ones went to History; those that came after your last input count on the bell as missed.
- A key or wheel step on the Night Light, display brightness or seek slider still applies when Escape or closing the
  menu follows it at once.
- Settings and History open at the height they closed at, instead of growing into place as the page fades in.
- An empty Wi-Fi list says No networks found instead of switching back to Searching every eight seconds.
- Now Playing says Stopped, not Paused, for a player that stopped with its track still loaded.
- A window, tray app or audio stream whose id is a file path no longer gets that file as its icon; a named pipe there
  stopped every icon and cover from loading until a restart.
- A notification icon name with a slash in it shows no icon: one climbing out of the icon theme to a named pipe stopped
  every icon and cover from loading.
- A cover on disk shows from Silere's own copy, so a player that swaps a named pipe in for it after the check can no
  longer stop every icon and cover from loading.
- Dismissing a notification closes it as its card starts to slide out, so a card cut off mid-exit (a monitor unplugged,
  nothing drawing) no longer leaves it open or brings it back on another monitor.
- A card dismissed before it finished appearing, by a script for one, no longer slides back in.
- A card folded away behind newer ones and back keeps its countdown instead of starting it over.
- Automatic update checks look at Flatpak apps again after the clock was set back, instead of waiting for it to catch
  up with the last check.
- After a long sleep, the menu's History count drops notifications past Keep history for as the menu opens.
- The clock no longer spins through the repeated hour when summer time ends, writing a warning to the journal every
  millisecond for that hour.
- After the laptop wakes, the battery's time left starts from the current draw instead of reading about 2.5 times off
  for five minutes, and Night Light catches up with the sun even when the laptop wakes offline.
- At a larger interface size, the bar's hover text (the battery estimate, device and network names) has room for as much
  as at 100% instead of a third less.
- Notification history is saved at least every two seconds while notifications keep coming, so a logout in a flood
  no longer loses everything since it began.
- A track you pause from the bar or Now Playing, or one paused as headphones disconnect, stays on the bar until you
  play again or step away, instead of folding after 15 seconds with nothing left to resume it.
- Right-click the clock to open notification history, where its missed-notification bell leads, and again to close
  it; the clock stays marked while History is open, as it does for the calendar.
- On a computer without Wi-Fi, clicking the network widget with the cable unplugged shows Ethernet as Disconnected
  instead of a Home page with no network row.
- On a desktop, hovering the battery pill for a low mouse or keyboard names the device.
- On a laptop without power modes (TLP, auto-cpufreq), clicking the battery opens its details in Home.
- With the OSD off, a low battery sends a notification instead of nothing; only the critical level used to.
- Two browser tabs recording read as one app listening on the microphone widget, not two.
- The microphone widget and the apps listed under Input show muted or live by the microphone each app records from,
  so they no longer read Muted while an app hears an unmuted microphone.
- `silere mic mute` shows the same Microphone · Muted OSD as the mute key, so the OSD keeps its width.
- On Hyprland with `workspace_back_and_forth`, jumping to a window on the current workspace (a notification click,
  Now Playing) no longer flips to the previous workspace and back.
- The `media-changed` hook reports `stopped` for a player that stopped with its track loaded, and runs when a paused
  player stops.
- A hyprsunset started outside Silere (its own unit) takes Night Light's temperature when Silere finds it running,
  instead of keeping its own temperature while the switch reads on.
- Behind a sign-in page or with no internet, the updates widget no longer calls the package check broken, and the
  check waits for the network to clear before trying again.
- A settings file owned by root (after running Silere under sudo) no longer turns notification history and hooks off
  for the session.
- Settings no longer marks Devices as changed for a custom lock command or a display list that is folded out of sight.
- Searching Settings for roundness finds the Roundness row.
- Let critical through is greyed while popup notifications are off, since nothing can pop up past them.
- Switch animation and Notification pulse say they are off while Reduce motion is on.
- Icon size says it sizes the tray and workspace app icons.
- Undoing a settings reset in the menu removes its backup, so `silere reset --undo` no longer puts the older settings
  back over yours later.
- Updates install where an older qmllint is present (Fedora's Qt tools, Qt 6.10), instead of being refused as an
  update that does not load.
- The hints that the updater, the installer, `silere try` and `repair.sh` print quote the checkout's path, so they
  paste into bash, zsh or fish even with spaces or accented letters in it.
- Shell completion offers `--yes` only after `repair --apply` or `--undo`, and `run`'s two flags in either order.
- A notification that times out while you are away with browser music playing counts on the bell as missed.
- The menu opened from its keybind puts the focus on its tab, so the arrow keys move at once, as in Quick Actions
  and tray menus.
- Wi-Fi or Bluetooth blocked by the hardware switch keeps its row readable in Home; only the switch dims.
- With a bar on each monitor, an open tray menu lights its app's icon only on the bar it opened from.
- Greyed tray menu entries follow High contrast like every other disabled row.
- With Reduce motion on, Clear history and the widget reset no longer show a ring that sits full and never drains, as
  the power actions already did.
- Restore default settings asks you to Press again, as the power actions do, not Tap again.
- A bar widget stays marked while the menu it opened is open, as the clock and the tray already were.
- Quick Actions lights Power Mode for Power Saver as well as Performance, as Home does.
- Without JetBrainsMono Nerd Font, opening Settings no longer switches the shell to the first font installed (often a
  serif); another Nerd Font stands in.
- Choosing Mix while the Auto accent is on starts from the wallpaper's accent on screen, not an older custom colour.
- Reload palette shows only while the palette is missing or broken; a working one is followed as it changes.
- On niri, the window title stays while a Silere popup or a launcher holds the keyboard instead of folding away.
- Opening niri's overview no longer resizes every window into the bar's space and back.
- On niri, the `workspace-changed` hook gets a named workspace's name, as documented, not its number.
- A hook that leaves a program running in the background, such as a sound, costs about a tenth of the CPU while
  Silere waits for it to finish.
- A Do Not Disturb, idle, media, network, power or workspace change that comes during a notification flood still runs
  its hook once the flood passes, instead of being dropped.
- On niri, the installer's closing "or bind it" hint prints a niri bind instead of a command that breaks the config
  when pasted.
- With one monitor, the bar's system, network and temperature readers rest while a fullscreen game or film covers the
  bar, as they do in the overview.
- A computer with no CPU sensor Silere can read stops scanning for one every minute after five minutes.
- On a network without internet (a LAN-only one), the bar stops rechecking every 30 seconds after five minutes;
  opening the menu, or keeping Home open, still rechecks.
- On Fedora with tuned-ppd, the installer no longer lists power-profiles-daemon as missing and puts it in its
  install command, where it conflicts with tuned-ppd.
- `silere doctor` warns when a Bluetooth adapter is present but bluetooth.service is not running, which hides
  Bluetooth everywhere, and `silere toggle bluetooth` asks whether it is running.
- On a computer without a keyboard light, the open menu no longer looks for one every 15 seconds.
- After you stop another notification daemon, the warning that it owns notifications clears with the first
  notification Silere receives, instead of at the next tool scan.

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
