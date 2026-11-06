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

- `dev/test-audio.sh` checks audio against a private PipeWire and WirePlumber with no hardware, including device replacement and daemon restarts. `dev/check.sh` runs it.
- `dev/test-faults.sh` runs a whole shell against tools that hang, fail or return garbage, and against hostile notifications, media players and tray items.
- Installer options `--yes`, `--dir PATH` and `--no-start` can be combined with previews, including through the piped installer.
- CI checks UI behaviour and layout at 125% and 150% display scaling, builds settings surfaces on the minimum supported Quickshell, and retains version, build and probe logs for seven days.
- `silere use` completes checkout directories in bash and fish, including paths containing spaces.
- `silere stop` stops the shell and its optional user service without triggering crash recovery. Bash and fish completions include it and `use`.
- A documentation index and a separate updates and recovery guide, with simpler setup, controls and scripting examples.
- The OSD shows the new power mode when it changes outside the menu, such as from a laptop's power mode key, or a remembered mode applying when the charger is plugged in or out.

- `silere try` opens the whole shell in a window on a private session, to see it before switching. The bar, notifications and settings already on the desktop are not touched, and closing the window removes it.
- `silere reset` goes back to a fresh install when the menu won't open or a change can't be found: settings, edited files, leftovers from older versions and caches. It previews first, and `silere reset --undo` puts everything but caches back.
- **Ctrl+Tab** and **Ctrl+Shift+Tab** move between the menu's pages.
- Each Settings page with changes has **Reset** in its header, pressed twice, which puts back what that page shows. Rows folded away behind a switch that is off keep their values.
- Down and Up walk the Settings search results from the search field, and Up from the first result goes back to it.
- `dev/bench-lab.sh` measures startup, the latency of every panel, memory over repeated menu opens, the optional service settings and a long soak in a private nested session, and compares checkouts.

### Changed

- The menu compiles in the background a few seconds after startup, so opening it from a keybind for the first time takes about 90 ms instead of 160 ms, the same as every later open.
- Restore default settings covers every setting, including Do Not Disturb, night light and remembered power modes. It could not even be pressed when those were all that had changed. It now keeps a copy, with an Undo restore row beneath it, and replaces a settings file that cannot be read instead of leaving saving blocked.
- The AUR package depends on JetBrainsMono Nerd Font, which the default bar and every icon in the UI need.
- The visualizer along the bar's underline takes about half the CPU it did, 8% of a core instead of 15% in a 1920x1200 session. Its line is drawn as stacked hairlines instead of outlining the whole curve every frame, and looks the same. `docs/performance.md` lists what each visualizer setting costs.

### Fixed

- The shell no longer crashes when the pointer leaves the active workspace while the menu is still being prepared for a click. Quickshell dropped that preparation part way through, which Qt cannot always survive while lists inside it are still loading.
- The installer sets up autostart and the menu shortcut on a stock Hyprland config. On Hyprland's Lua configs it looked only for an `execs.lua` that a stock install does not have, so the shell installed and then never started at login. It checks the result with `Hyprland --verify-config` and puts the file back if Hyprland rejects it, and `silere uninstall` takes both back out.
- `silere doctor` and `silere run` name another bar still running, including another Quickshell shell such as Noctalia on the same display, which would otherwise draw beside Silere's and read as Silere being broken.
- A light Matugen palette no longer leaves the shell unreadable. Its base stays light instead of sinking toward black under dark text, and high contrast, the accent, warnings and glass all follow it. As the accent source for the neutral base, its dark accent is lifted to stay readable.
- `silere update --apply` and `--rollback` restart a shell that does not run as a service, so a new release never runs beside the old one. Panels compile when first opened, so a shell left running could load the new release's panels against the old one's services.
- `silere update --rollback` works for a shell that does not run as a service. The record of what to restore was removed as soon as the update finished.
- A panel that fails to load suggests `silere restart` first.
- A test shell started with `SILERE_SANDBOX=1` no longer changes the desktop's power mode when the charger is plugged in or out.
- Settings search finds every row by the name it shows. "Format", "Mode", "Low battery warning" and others found nothing or opened another page first, and a row named exactly like the query now comes before pages that only share its words. Enter opens the top result, which the result count names, instead of doing nothing when more than one page matches. Search also knows the widget names on Show & order and everyday words such as "dark mode", "blue light", "padding" or "now playing".
- Auto tighten and Group conversations say what they do, since neither shows anything the moment it is turned on.
- The system monitor drops the temperature reading on a machine with no temperature sensor instead of showing a dash for good, and its setting says why it cannot be turned on.
- Screenshots taken about a second apart no longer add up to a screen share and flash the sharing indicator for two seconds.
- The power mode controls appear only when the power profiles daemon answers. With `powerprofilesctl` left installed beside a masked daemon, as with TLP or tuned, they showed a mode that could not be changed.
- Volume controls keep working when a default audio device is replaced under its own name, as a Bluetooth reconnect can do. They went dead until a restart (quickshell#1301).
- An audio output that goes away no longer shows a "Muted" OSD.
- A shell that starts before PipeWire connects when PipeWire arrives, instead of having no audio until a restart.
- Settings sections load asynchronously with reduced motion enabled, so switching sections leaves the interface free to handle input while controls build.
- Notification reply buttons follow the interface size and keep their targets inside narrow cards at larger text sizes.
- Switching checkouts checks the runtime, session and service override before redirecting the command link. Rejected overrides, dangling links, an unusable runtime and extra checkout arguments leave the current setup intact.
- Cancelling the initial Lock & sleep status read no longer launches the locker when the old read exits.
- Weather recognises Open-Meteo's heavy thunderstorm code and keeps the last reading when a response has an invalid day flag, condition code or daily temperature range.
- Portability tests isolate service-manager calls so a missing fixture cannot stop the desktop's live shell.
- A deleted settings file can be recreated by saving the same values, instead of treating its old contents as already saved.
- Updating the shell waits for migration backups and external settings reloads before confirming that settings are saved.
- VPN profile discovery recovers after a backend restart or idle transition, and keeps refreshes requested during a background read.
- A failed brightness write on one external display preserves queued changes for other displays.
- A system clock rollback no longer keeps sliders throttled or carries old wheel gestures into new input.
- The keyboard widget rediscovers its Caps Lock sensor after a keyboard is plugged in or reconnected, with retries paused while the widget is off or the session is quiet.
- Package checks catch up after an hour offline and cancel delayed startup checks when a manual check starts.
- A failed hook scan keeps the last known hooks and retries instead of silently disarming them.
- Volume and brightness chevrons line up with the rest of the Home page.
- Settings and notification history put the sidebar title and the page title on one line, and their page titles share a size.
- Quick action state pills stay sharp at fractional scaling.
- The bar's system monitor draws every reading's icon at the bar's icon size and color, keeps a one-digit reading next to its own icon instead of drifting toward the next one, and tints the icon of the reading that runs high rather than the CPU's.
- Volume, brightness, battery and system readings no longer widen by a pixel between one digit and two, which nudged every widget after them, and a one-digit reading sits next to its icon.
- The bar's battery rests neutral like every other reading and follows "pills follow theming", instead of always taking the accent; its colors stay readable over the bar, and the brightness and battery icons match the others' size.
- Home's system readings draw their bars at one shared width, so equal percentages read as equal lengths, and the CPU row uses the bar's CPU icon instead of a thermometer.
- A bar widget whose text shortens, such as the network speed shown on hover, keeps its icon and text in place while it holds its width, instead of jumping right and back.
- The system monitor shrinks back to its readings as soon as the pointer leaves, instead of keeping its hover width, with empty room after the readings, for over two seconds.
- Bar widgets settle at their new width as soon as a smaller interface scale or another font is chosen, instead of holding the old width for up to two seconds.
- The audio visualizer no longer halves PipeWire's buffer size while it runs. Cava asked for 512 frames, which doubled the audio graph's wakeups during playback and switched the buffer size whenever the visualizer started or stopped, a click on some outputs.
- The OSD settings page opens with a section heading like every other page.
- Clicking a slider's handle picks it up without moving it, so a volume another app left at 67% stays there instead of snapping to 65%, and a click on the accent hue handle no longer rewrites the accent.
- A connected Bluetooth device's battery reads "Name · 80%", like the shell's other details.
- Now Playing names a player by its app name, so Zen shows as Zen Browser rather than Mozilla zen.
- The power drawer shows its mode name whole at every UI scale, keeps its other labels whole above 100%, and opening it no longer leaves Home's uptime over the date.
- The Connectivity card shows a VPN's address as soon as the tunnel comes up.
- Night light turns back off with an error when its tool is gone at a restart, instead of showing as on.
- On a second monitor with named workspaces, the bar keeps its active workspace when focus moves there.
- Workspace occupancy follows a workspace whose id changes.
- A notification that arrives after the clock went back stays at the top of history.
- The calendar shades the locale's own weekend.
- The fully charged alert shows the final percentage.
- Now Playing ranks players that were already playing when the shell started.
- Wi-Fi no longer reports a failed connect as joined while a network of the same name stays linked.
- Tray menus draw unchecked checkboxes.
- A slider you scroll on right after moving onto it takes the wheel as soon as the pointer rests, instead of ignoring it for as long as the wheel keeps turning.
- A menu page that scrolls by itself, such as when it shrinks or reveals a setting, no longer passes the next wheel over the slider under the pointer.
- With "Remember per power source" on, a mode set with a laptop's power mode key is remembered for that source like one picked in the menu.
- `silere doctor` names a fontconfig failure instead of reporting that no Nerd Font is installed.
- On Hyprland, a scratchpad or other special workspace that was already open when the shell started shows on the bar.
- A notification its app closes, such as kitty's alert once you focus its window, slides out like a dismissed one instead of vanishing, and so does one closed by clicking it or one of its actions.
- Switching menu pages no longer draws both pages over each other halfway through: the old page fades out ahead of the new one.
- A notification's countdown rim fades out with its card when you dismiss it, instead of disappearing a frame before the card moves.
- A new notification opens its place in the stack, so the cards already shown glide down instead of jumping a card's height before it appears.
- The Bluetooth picker leaves out nearby devices that are known only by their address, such as phones and tags advertising a random one, until one is paired or connected.
- A built-in sound card is named without its profile, so "Ryzen HD Audio Controller Analog Stereo" reads "Ryzen HD Audio Controller" and fits the menu. Two outputs of one card keep their full names.
- Home's Power Mode row shows the mode under its title, so its chevron lines up with the rows above it.
- The volume menu's Apps tab shows each app's own icon in place of the same note glyph for every app.
- Tray icons that redraw themselves, such as an unread count or a sync spinner, no longer blink out while the next icon loads.
- With one monitor, the workspace bar keeps showing 1 to 5 after Hyprland drops the empty workspaces below the one you are on, instead of moving on to 4 to 8 when you switch to workspace 4.
- The brightness device list names each backlight for the hardware behind it, such as "AMD graphics" and "NVIDIA graphics", instead of "amdgpu_bl2 · raw".
- "Open" in Now Playing, and a middle-click on the bar's media widget, bring back a player that has closed to its tray, such as Spotify, instead of closing the menu and doing nothing.
- Clicking the bar's network or Bluetooth icon opens Home with that list already open, as macOS and KDE do, instead of Home with every drawer closed.
- Network, Bluetooth, keyboard, sound, brightness and battery share one divider group, so with "Groups" placement a lone Wi-Fi icon no longer sits between two dividers.
- Night light only finds and stops the tool of its own session, so a nested or second session can no longer adopt or turn off your real one.
- A panel that fails to load shows an alert instead of never opening, and the bar keeps working.
- A notification with a very long body no longer leaves the shell holding about 30 MB more memory for the rest of the session.
- The shell starts about 120 ms sooner and with about 7 MB less memory, and stays about 4 MB lighter after the menu has been opened, because popups and the menu's large pages compile the first time they are wanted instead of at startup. The first menu open of a session takes about 55 ms longer, and a broken popup file now leaves the bar running.

## Releases

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
