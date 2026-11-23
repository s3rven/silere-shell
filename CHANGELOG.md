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

- Short commands for the running shell: `silere menu`, `calendar`, `quick` and `tray` open their panels, `silere toggle dnd` (or `wifi`, `night-light`, any on/off setting) flips one, `silere volume up`, `mute`, `next` or `40` and `silere mic` change audio, `silere dismiss` clears popups, and `silere get`, `set` and `settings` read, change and list settings.
- Home shows an Ethernet row when a cable carries the connection, even on a desktop without Wi-Fi or Bluetooth, and the bar's network widget opens Home at it.
- In the calendar, Shift + Page Up and Shift + Page Down move by a year, and Home returns to today.
- With weather on, the calendar shows the next twelve hours under today's reading, three hours apart.
- A Command widget shows a script's output on the bar and reads waybar's custom-module output, plain lines or JSON, unchanged; a script that keeps running updates it with each line it prints. Turn it on under Settings › Widgets › Indicators.
- Keybinds can dismiss the newest notification, dismiss them all or act on the newest, as with dunstctl and makoctl: `silere ipc notifications dismiss`, `dismissAll` and `invoke`.
- Settings › System › Keybinds lists Hyprland's shortcuts with what each does, in your config's order, and filters them as you type. Binds without a description are named from what they run, and Silere's own actions can be copied as a line for your config, on keys still free.
- On Hyprland, the installer offers Silere's window motion (default no): windows, workspaces and focus move at the shell's pace, with two Hyprland 0.57 animation faults worked around. Anything your config sets after its line still wins.
- Workspace app icons can follow the theme accent in Settings › Widgets › Workspaces.
- The system monitor can draw each reading as a ring around its icon, under Style in Settings › Widgets › Indicators.
- On Hyprland, a submap you enter shows its name after the workspaces, also when the shell starts inside one; click it to leave.
- On Hyprland, the installer offers to turn off the compositor's fade for Silere's popups, which animate themselves, unless your config already sets one; uninstalling removes it.
- Automatic package and Silere release checks pause on metered NetworkManager connections, such as a marked phone hotspot. Check in Overview still runs on demand.

### Changed

- Scrolling the bar's brightness widget steps the selected backlight and all enabled external DDC/CI displays together, each on the same 5% steps. The widget also works on systems with only external displays, with its icon following the display's level.
- On niri, focusing a window and cycling the keyboard layout use the compositor socket directly, avoiding a new process for each action.
- `silere help` lists the commands that control the shell apart from the ones that run and maintain it, and `silere set` takes `on` and `off` for a true/false setting.
- `silere use` moves the shell completions to the checkout it switches to, as it does the command.
- `silere doctor --json` and Overview's diagnostic report say who holds the notification name, whether Silere starts at login, and which known bars or notification daemons run or start beside it, without paths, so a report from a shell that won't start is still useful.
- On niri, the installer checks its autostart line with `niri validate` before writing it, and leaves a config niri would reject as it was.
- The installer asks once whether to use the recommended setup, which takes the default answer to each question and shows it, instead of asking up to ten questions one by one. Answering no asks at each step as before.
- Without Quickshell, the installer prints the command that installs it: pacman on Arch, the COPR on Fedora, or Quickshell's guide elsewhere.
- Switching from another bar, the installer and `silere doctor` name each line of your Hyprland or niri config that still starts Waybar, mako, dunst or a similar bar or daemon at login, with its file and line number.
- `silere doctor` names a notification daemon such as mako or dunst that D-Bus can start on its own, which takes notifications from Silere at a later login, and how to keep it off.
- With notifications still on screen, the empty Notifications tab says they move there when they close, instead of All caught up.
- The Command widget in Show & order says when it is on without a command to run.
- At login the bar comes up about a second sooner: the launcher waits for the compositor's display socket instead of a fixed second, and asks Quickshell about its options once per version instead of at every start.
- On narrow displays, Settings gives its controls more room and opens categories from the Sections button.
- On narrow displays, History opens filters from the Apps button beside search and keeps the message list the same width when another app sends a notification.
- When a search in one app's notification history finds nothing, Search all apps keeps your words and searches every app.
- Clicking a Wi-Fi or Bluetooth widget while its radio is off takes you to its switch in Home.
- An enterprise Wi-Fi network you haven't joined, such as eduroam, reads Set up and opens your network editor, instead of Not supported with nothing to click.
- Menus open about a fifth sooner and take a quarter less CPU, with Mesa's GL threading off for the shell.
- Home's CPU row and the system monitor's hover name a busy process by its app as the launcher shows it, such as Firefox for a browser tab, or else by the program it runs, such as `next` instead of `node-MainThread`.
- A game Proton runs through Steam shows its own icon and name wherever Silere shows an app's, from what Steam installs for it.
- Choice chips stacked in one Settings card share a width, so their columns line up.
- Settings › Widgets › Media says when the visualizer runs its Eco preset on battery.
- The media widget keeps playback progress while Cava starts or fails. Media settings reports failures and lets you retry.
- Widget settings explain when the system monitor has no readings selected.
- A screen reader reads Now Playing's player choice, Automatic or a player you pin, as one set of options and says which is picked.
- Settings › Appearance › Theme's accent role applies to Wallpaper and to Neutral with an automatic accent, and the page says whether the wallpaper palette is missing, invalid or unreadable.
- Settings search answers faster when it corrects a typo, and notification history searches long messages faster.
- On niri, the underline's screenshot glow follows niri's own screenshots, clipboard-only ones too, without inotify-tools.
- A value in settings.json that Silere can't use, or a key it doesn't know, is named in `silere log` with what the setting accepts.
- The bar's CPU temperature and Home's CPU tile show a steadier reading, the average of the last 15 seconds; temperature warnings still react to each reading.
- The system monitor polls CPU and memory only while a visible view uses those readings.
- Battery time left and time to full follow the last five minutes of power use, so a burst of load no longer swings the estimate by half an hour.
- Under a charge limit, charging is timed to the level the battery stops at, as in "80% in 26m": the stop the kernel names, or the level Silere last saw it held at. Turning the limit off times charging to full again.
- Battery estimates weight each power reading by how long it lasts, so a burst of repeated updates counts only for the time it covers.
- Notification history spells an app as its launcher does, such as Discord where the app sends `discord`.
- The microphone's hover leads with its level, and the network's with a problem such as Sign in needed, so a pill cut short still shows them.
- Hovering over the speaker or microphone says Muted when it is muted. The battery hover says whether an estimate is time left, time to full, or time to the charge limit.
- Turning off Keep after restart in notification history removes only the notifications kept from earlier sessions, not this session's.
- `silere log` leaves out the warnings Quickshell logged each time a media player or tray app failed to answer, which made up nearly all of it.
- In notification history, an app without an icon shows its initial on a tile the size of an icon, as notification popups already do, instead of a lone letter.
- The bar clock's colon sits level with its digits, as do the times in Now Playing and notification history.
- Settings › System › Devices names displays as Built-in display or by their model with the port, as in "DELL U2723QE · DP-2", instead of the port alone, and Home's external brightness sliders name them the same way.
- On a laptop, Home keeps external displays' brightness under the brightness slider's arrow instead of adding a row for each, and the bar's brightness widget opens Home with them shown.

### Fixed

- Launch-failure alerts preserve titles that start with a dash. Diagnostics uses the same alert availability check as the delivery service.
- External brightness discovers monitors on drivers that omit the connector's DDC link, including NVIDIA.
- External display brightness steps apply about twice as fast, and starting or waking the shell reads each display once instead of twice, so on NVIDIA half as many ddcutil lines reach the journal.
- An external monitor still waking up, or just plugged in, is read again a few seconds later instead of losing its brightness control behind a warning.
- `silere -v` prints the version. A mistyped command is offered `uninstall` or `reset` only when it is one letter off, so `-install` is no longer answered with `uninstall`, and `silere install` names the service and installer commands.
- Menu pages wait for their controls to finish connecting before accepting input, so the Apps button in History can open its drawer on the first press.
- The Command widget starts a fresh reading when re-enabled while its previous command is still shutting down.
- IPC passes values beginning with a dash through to the shell, so `silere set` can save them.
- The Command widget follows up on a refresh requested while a one-shot script is still running.
- `silere doctor` finds compositor config paths locally even when the shell entry file is missing.
- A tray icon an app names from the icon theme, where the theme has none by that name, shows the app's initial instead of a magenta and black pattern.
- On Hyprland, a menu, calendar or Quick Actions opened from a keybind while the pointer rested on another open one no longer closes as it opens.
- Do Not Disturb until the end of quiet hours, chosen on the afternoon the clocks spring forward, ends that night instead of an hour early the next day.
- Settings › System › Overview no longer says No issues found while a device check right below it needs attention, such as sound output with PipeWire not running.
- Settings › System › Overview no longer reports a missing wallpaper palette as a problem while colors are Neutral; it is listed with the optional features until Wallpaper colors are chosen.
- Quick Actions, the calendar, and tray menus keep keyboard focus visible when their contents move or the popup shrinks.
- The bar's volume and microphone feedback shortens long device names to keep the level or Muted readable in a crowded bar.
- Network and Bluetooth hover details show signal or charge before long names, and the network widget keeps custom wired names such as Endpoint.
- Package tracking waits for a successful check before reporting that packages are up to date. A failed refresh keeps the last known update list and its check time in Overview.
- With the bar floating away from the screen edge, the gap belongs to the bar: pushing the pointer against the edge and clicking reaches the widget under it.
- In Settings and History, Tab moves through the rail's buttons before the section or app list beside them, and from the power button to its options.
- Status notes in pickers and settings rows, unselected choices, page descriptions, and switched-off widgets in Show & order are easier to read.
- Dates, times, counts, captions and chevrons in Home, History, the calendar, Now Playing, Quick Actions and tray menus are easier to read, most in high contrast and on translucent menus.
- When the shell starts, the bar fades in at its full width instead of stretching out from the middle.
- A notification arriving with no other popup showing, and the volume and brightness popup, fade and slide in from the start instead of appearing already half faded in.
- A menu opened from a bar icon, such as Network, Bluetooth or the system monitor, opens toward that icon instead of at the workspaces at the other end of the bar.
- Bluetooth headphones that report their charge in 10% steps warn at 20% instead of waiting for 10%, and warn once even if the reading flips between 20 and 30.
- A tray app asking for attention, a low battery and a hot CPU ease out of their pulse when it settles instead of jumping, and Home's CPU and battery readings fade between colours and no longer flicker while they pulse.
- Notifications that arrive during a fullscreen game or Do Not Disturb keep the bell beside the clock lit, with a badge once popups are back, until you open History.
- Night light's Follow sun position eases down to the temperature you pick, shown under it as Night temperature, instead of a fixed 3000 K, in finer steps with hyprsunset.
- Home's system readings and gauges stay in place when the busiest process changes. The bar's system monitor dims readings it hasn't received and describes them as unavailable to screen readers.
- Keyboard lighting keeps your latest change if an earlier one fails to apply. Sliders that apply on release, such as display brightness and seeking, settle on the real level when a change is refused.
- Clock settings let you switch weather units back to Auto. Time and date previews stay live with the bar clock hidden and retain keyboard focus when their labels change.
- Update recovery and release pinning protect ignored files when a revision changes a file into a directory or a directory into a file.
- Update validation rejects a staged shell that quits early and reports when a display connection prevents the startup check.
- Notification clicks use the launcher's registered window class and respect focus changes made while an action runs.
- History keeps notifications with different urgency or source apps even when their text matches.
- The busiest-process label uses CPU load from the same interval and keeps separate samples for processes that reuse a PID.
- Network speed keeps the bytes from closely spaced reads and clears old rates when interface counters restart. VPN discovery and traffic use the same read of the kernel counters.
- Workspace numbers can stay visible beside app icons, and opening another window of the same app updates its badge without reloading the icon.
- A named Hyprland workspace keeps its ringed marker visible and opens Quick Actions from the marked cell. Left-click the cell to return to its numbered workspace.
- Settings search scrolls to and highlights matching rows in Show & order and the muted apps list.
- A setting's config key in Settings search, such as `neutralAccent` or `barCompact`, opens that setting in any letter case. Five keys opened a similarly named one first, and none matched in another case.
- The window title drops an app's name that leads the title, as Discord's does, or carries a version, as Obsidian's does.
- Auto tighten no longer switches the bar's compact mode while a hover detail or a popup holds a widget open.
- Switching Wi-Fi off no longer sets off the underline's network-loss alarm; a dropped connection still does.
- The tray picks up apps that started before it under the `org.freedesktop.StatusNotifierItem` name, as Discord does, without listing any app twice.
- A tray app that registers and quits within a second, as an Electron app's second launch can, no longer risks crashing the shell.
- A notification icon, app icon or media cover that names one of the shell's own in-memory images shows nothing instead of another app's picture.
- When a panel fails to load because the shell's files changed while it ran, clicking the alert reloads Silere instead of asking for `silere restart` in a terminal.
- The CPU temperature shows on ARM laptops and boards whose sensors are named per core, such as Snapdragon X, ThinkPad X13s and MediaTek Chromebooks.
- Searching Settings for colour finds App icon color as well as the Theme page, and a typo keeps its first letter, so nighlight finds Night light, not Hover highlight.
- Escape and the close button return keyboard focus to the Settings search button.
- A pending scroll to a row in Settings or on Home is dropped when you change page or open the power options.
- Scrolling the menu while a picker opens above its row no longer pulls the page back to that row.
- Switching from one Home picker to another, such as Night Light to Wi-Fi, moves the menu's edge one way instead of shrinking it and growing it back.
- Release notes, commits and package lists in Settings › System › Overview fold away with their entries instead of emptying first.
- Sliders settle on the value that was applied when you let go, including brightness held at its 1% floor.
- External display brightness shows the level while you drag, and a change the display refuses no longer drops the ones after it.
- Home's external display sliders and their switches under Settings › System › Devices stay in place while the displays are read again, also after waking from idle, so a drag or keyboard focus on one is not lost.
- The volume and brightness popup widens smoothly when a device name appears in it, instead of jumping to the new width.
- With Ethernet and Wi-Fi both connected, Home keeps the Wi-Fi network and signal in the Wi-Fi row.
- Battery details update their readings without moving focus off the charge-limit switch, and a charge-limit read that succeeds clears an earlier read error.
- Home's system rows ignore clicks, keys and screen-reader actions once they are hidden.
- Quick Actions fits a small screen, wrapping long labels and scrolling when it must, and a row can no longer be toggled while the card closes.
- The calendar keeps its margins on a narrow screen, and a click anywhere in a day from the next or previous month selects it.
- The calendar uses the same locale for its date labels and screen-reader announcements, and Today includes the full date.
- Settings › Bar › Underline names a missing inotify-tools on the Screenshots row, which can still be turned off without it.
- On niri, clicking a notification focuses the window its app asked to raise when niri held the focus back, as it already did on Hyprland.
- On niri, workspace clicks target the chosen workspace even as its number changes, and moving a window to another monitor's workspace keeps focus on the original monitor.
- Removing the last notification of a filtered app in history returns keyboard focus to search.
- History's Clear button asks again when the notifications it would clear change.
- The floating OSD fits a narrow screen, and a long headset name no longer cuts off the level or Muted.
- Now Playing's seek preview, elapsed and remaining times stay together while you drag, scroll or use the keys.
- After a failed lookup, bar weather tries again even when the system clock has moved backward.
- A Matugen palette written after Silere started, into a folder that did not exist yet, applies without a restart.
- The theme-changed hook also runs when the applied colours change and the accent stays the same, such as a new base tone.
- `install.sh --repair-matugen` leaves a custom or malformed Matugen entry alone and skips a template that is already current.
- `silere restart` and `silere run` from a terminal opened before the current login, such as a tmux session kept across a logout or a compositor crash, start a shell that follows the compositor instead of one with frozen workspaces.
- Running the installer again keeps a `silere run --supervised --startup` autostart as it is, instead of offering to replace it with the unsupervised command.
- `silere doctor` and the installer no longer call network settings or terminal tools unavailable when nmtui or a common terminal such as kitty stands in.
- Without NetworkManager, as under iwd or systemd-networkd alone, the bar leaves the network widget out instead of showing you offline; Settings › Widgets and `silere doctor` say why.
- Home no longer shows a keyboard lighting error on a computer without UPower.
- Without libnotify's `notify-send`, Silere's own alerts reach its notifications through `busctl`: the welcome on first start, critical battery and temperature, a panel that failed to load and a cancelled sleep.
- A notification body full of square brackets, or text stuffed with combining marks, no longer freezes the shell while Silere cleans or shortens it.
- England, Scotland and Wales flags no longer turn into a plain black flag where a long label is cut.
- A notification Silere closes on its own, when a screen share starts, popups are switched off or a newer one replaces it, tells the app it expired, not that you dismissed it.
- Muting while the OSD names the output, as in "Speakers · 45%", no longer moves its icon and level. A muted microphone reads "Microphone · Muted".
- The Center and Underline visualizers keep showing track progress with the media widget off the bar.
- Now Playing no longer keeps the last track's cover beside a track whose cover can't be read.
- When the control you are on with the keyboard turns off or goes busy, as Check in Settings › System › Overview does while it runs, the keys keep working on that panel and the focus comes back to it after. A Wi-Fi network, Bluetooth device or VPN you press Enter on keeps the focus while it connects, and the Bluetooth picker keeps it on its device while others appear or re-sort.
- A screen reader names the power action waiting for its second press, as in "Press again to reboot".
- An open dropdown or a short list in Settings no longer moves the rows below it off whole pixels at 125% and 150%, or at UI scales from 1.1 to 1.4.
- The tray menu fits a narrow screen at large UI sizes, and a tray watcher that can't be read no longer has every app's icon registered again.
- Weather finds your city when /etc/localtime points into the posix or right zone tables.
- A package tool or update server that prints one enormous line or a flood of messages no longer makes the shell read all of it.
- With values on hover, the system monitor's readings close with its pill instead of vanishing at once.
- The system monitor uses shorter readings on crowded bars so its hover details leave room for neighboring widgets.
- Floating bar width follows changes in widget width sooner, and closing widgets keep their slots until their widths finish shrinking.
- `silere reset --undo` puts back the settings and edits of the same reset, even after a later restore in Settings or `silere repair`.
- A regular reset keeps notification history when its only copy is in the older location. Reset with `--history` clears both locations and any copy saved by a previous reset, so Undo leaves the history cleared.
- Terminal reset backs up and replaces an invalid settings file containing a JSON array or another non-object root.
- With `paru` or `yay` as the only checker, Settings › System › Overview offers Include AUR packages before package tracking is on, and an AUR helper is used only once you include AUR packages.
- An update keeps its rollback until the shell is seen running the new release, even while the service still runs the old one.
- Home's weather tries again after a reconnect and refreshes when the date or units change, and the forecast follows a move to another city in the same time zone offset.
- An open calendar showing this month moves to the next one at midnight.
- Notifications past the history's age limit no longer take room from current ones when history is restored or fills up.
- Turning on a soft-blocked Bluetooth adapter unblocks that adapter, not every Bluetooth radio.
- Scrolling volume, microphone or brightness on two bars no longer adds their partial notches together.
- Lock & sleep confirms the lock on the session it locked.
- Lock & sleep works with hyprlock on Hyprland. It waited for the login session to report the lock, which hyprlock never does, so since 1.5.0 it locked, then cancelled the sleep with an alert. Hyprland's own lock state now confirms it.
- A slider that can't be used, such as brightness on a screen Silere can't dim, keeps its dimmed handle solid instead of showing the track through it.
- A Settings dropdown with a long value keeps its own name whole and shortens the value instead, as Keyboard light does beside a long device name.
- A network, device or player name in Hebrew or Arabic stays beside its icon instead of drifting to the other end of its row. Notifications in those languages still read from the right, in popups and in history.
- Keyboard focus on an expand chevron, as on Home's volume or Wi-Fi row, draws a small circle like other icon buttons instead of a ring the height of the row.
- Several outputs of one sound card, such as an Intel laptop's speakers and HDMI ports, lead with what sets them apart, as in "HDMI / DisplayPort 3 Output · Tiger Lake-LP…", so the output picker no longer cuts them all to the same name.
- Now Playing keeps its seek bar and buttons in place when a track names no artist, so pressing Next through a mixed playlist no longer lands beside the button.
- When Sleep or Power off fails to start, the alert says "Sleep failed" or "Power off failed", the words on the button.

## Releases

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
