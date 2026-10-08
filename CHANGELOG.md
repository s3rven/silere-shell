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

- Wi-Fi password entry has a show/hide control that preserves the typed key and masks it again when changing networks, submitting, or closing the picker.
- Keep Awake on the Home page and in quick actions holds off idle dimming, locking and sleep, with a cup beside the bar clock while it is on. It lasts until switched off or the shell restarts, and `silere ipc quickActions keepAwake` toggles it.
- The network icon in the bar shows a warning mark when NetworkManager finds no internet or a sign-in page, its hover text and the Wi-Fi row say which, and a Sign in row on the Home page opens the login page.
- Settings › Theme › Background blur turns blur off or on for the bar and translucent popups, and names what is stopping it when Hyprland is older than 0.56 or has blur turned off. `silere doctor` reports the same.

### Changed

- Notification history skips grouping work when filtered results stay unchanged and computes changed groups in one pass. The app rail shares a sender index for its count and icon lookups.
- Home reads disk usage directly from `df`, avoiding a shell and an `awk` process on each refresh while preserving cached readings and reserved-block accounting.
- The README describes Silere’s quiet defaults, presents installation in three steps, and keeps detailed controls in a separate usage guide. Its previews show the desktop, Home / Now Playing / Settings panels, and themes as still images.
- Remote cover art downloads wait until the media widget or menu is visible and pause during quiet idle. Hidden Now Playing pages stop cover decoding and retries.
- Menu width, sidebar, and padding now glide together and keep momentum through quick tab reversals. Pages use their destination layout width instead of wrapping their text again on every resize frame.
- Cold Home and Now Playing pages load asynchronously during tab switches, and revealing a preloaded Settings drawer no longer forces its remaining construction onto the first animation frame.
- System › Overview reports No issues found when only optional extras are missing. Font checks open Interface, and restore-defaults explains which preferences it resets and which wallpaper colors and notification history it keeps.
- Menu, calendar, quick-action, and tray-menu height changes retain their velocity when their content reflows or a transition reverses, and the settings sidebar moves at fractional pixels for smoother panel resizing.
- Settings groups screen lock and night light program choices under Interface. System › Overview combines updates, health checks, repairs, and reset, with optional features folded away; the former Updates and Diagnostics page names still work over IPC.
- Menu descriptions and dependency notes use palette-derived colors with at least 4.5:1 contrast against solid menu surfaces, preserving colors that already meet that contrast.
- Popups that match a very translucent bar stop at the opacity their text needs over bright windows and wallpapers, and the setting shows where they are held.
- With Popups match bar opacity on and a translucent bar, the menu turns to glass too: its pane, cards and controls let the blur through like the calendar and notifications.
- With nothing blurring behind them, because Background blur is off or Hyprland has blur turned off, the menu, popups and OSD stay solid instead of showing the window under them sharp. Popups match bar opacity waits for blur.
- Workspace app icons show in their own colours instead of grey until hovered.
- The edge gap of a floating bar now only spaces it from the screen edge, so windows sit as far below it as below a docked bar.
- Notification history is saved in `~/.local/state/silere-shell` instead of the config folder, so a dotfiles repo that tracks `~/.config` no longer picks up message text. An existing history moves there on the next start.
- Cover art from the web downloads Spotify's 300 px cover, about a third the size of the 640 px one, and fetches a second size only when the first fails.
- While something plays, a Now Playing page joins the menu below Settings, its rail button showing the cover. It holds a large cover, the track and album, a seek bar with the elapsed and total time, shuffle and repeat when the player supports them, and a list to switch players. The Home page no longer has a media card, so it keeps its layout when music starts.
- A track title too long for the Now Playing page scrolls through once while the pointer rests on it.
- Right-clicking the bar's media widget opens the Now Playing page, and `menu tab 3` opens it over IPC.
- The Home page's system readings and the Now Playing seek bar draw their level as a soft wavy line. The readings grow in each time the page opens, and the seek bar's wave flows while music plays and flattens when it pauses. Waves stay flat at low levels and hold still with Reduce motion.
- The Now Playing rail button fades in and out with playback, dims its cover while paused, and keeps the last cover until the next one loads. The page's title and artist fade to the next track.
- Switching back to the Home page within a few seconds reuses it instead of rebuilding it, so the switch starts on time.
- A battery held by a charge limit, such as Lenovo's conservation mode, reads Charge limit instead of Not charging.
- The Home page's system readings are rows like the controls above them: CPU, memory, disk and battery each show their percentage with a bar, and their temperature, memory used, free space or battery time under the name.
- Row dividers on the Home page start where the text does, leaving the icons a clean column, and the date lines up with the section labels.
- Lock is no longer on the Home page; it stays in the Power menu.
- Tray menus animate with far fewer dropped frames on high refresh rate displays, like the menu and calendar.
- On Hyprland, opening and closing the menu and popups takes about a fifth less GPU time.
- The selected accent swatch is ringed in its own colour, like the Base swatches are in the accent, instead of near white, and colour swatches no longer carry a grey rim that dulled their edges.

### Fixed

- Home's system-reading captions take space before their progress bars, preventing battery time estimates from being clipped at narrow widths or larger text sizes.
- Keep Awake's transparent helper surface stays above the wallpaper, avoiding delayed frame callbacks that slowed animations in other shell windows.
- Validation probes leave process shutdown to their harness so Quickshell 0.3.2 teardown warnings cannot turn completed checks into failures. Runtime failures retain their QML filename and line number.
- Output, microphone and per-app mute buttons announce Unmute while their audio is muted, matching the action they perform.
- Calendar weekday labels use the system locale, and weekend shading follows its working week instead of always treating Saturday and Sunday as days off. Long labels stay within their cells and expose their full names to accessibility tools.
- Enabling Reduce motion settles a pending calendar month change immediately, and a closed calendar rejects month and Today actions.
- Calendar month controls grow with the interface scale; long month names leave room for the previous and next buttons and keep their full accessible label.
- Leaving Now Playing or entering quiet idle stops unfinished text, cover and playback-icon animations and settles the current track's display.
- Changing the media track or player, hiding its page, or losing seek support cancels an unfinished seek instead of applying its release to a different track. New tracks also refresh the playback position immediately.
- Hidden power rows disarm their confirmations and reject activation; enabling Reduce motion stops a running confirmation countdown animation.
- Wi-Fi password entry stops accepting edits while its connection is in progress and shows Connecting instead of an empty password prompt.
- Bluetooth's Cancel pairing action stays usable when the device also reports Connecting; ordinary connection attempts still block repeat actions.
- Battery notifications treat the first valid reading as a quiet login baseline, including a late UPower response. Later low and critical crossings still warn, and fully charged alerts require an observed charge cycle instead of appearing at startup or repeating around 99%.
- Plugging in at a low battery level rearms desktop warnings even when the percentage stays unchanged, and a jump straight to critical produces one warning across the notification and OSD paths.
- A completed charge while idle can be announced on wake; fully charged alerts show the reported percentage instead of always claiming 100%.
- Settings and notification pages wait for their body before starting a tab reveal. A late load cannot restart the reveal after switching away, and Reduce motion settles a pending reveal immediately.
- Departing menu pages keep their layout while fading out, avoiding rewrapping controls as the next page resizes the panel. Interrupted height holds also preserve their fractional position.
- Switching menu tabs preserves the departing page's visible scroll position during its fade. Opening a page or returning to its top cancels old flick momentum before it can move the new content.
- Leaving Home or enabling Reduce motion stops its unfinished system-reading intros. Hidden, unrevealed, or flat waves stop ticking, and flat wave levels use one straight path segment.
- Bottom-anchored popups keep their bottom edge fixed during resizing instead of stepping in 4 px jumps; their final outline still lands on the shared pixel grid.
- Returning to a settings section during its fade-out reverses the reveal and keeps its existing controls instead of rebuilding the section.
- The overlay display picker stays available when a saved monitor is disconnected and only one display remains, so it can be switched back to Follow focus.
- Diagnostics flags an explicitly selected lock or night light program that cannot run and links to Interface to choose another; missing optional programs stay informational.
- Leaving Settings disarms restore-defaults and update-install confirmations, including while their page remains cached. Switching settings sections cancels an armed update too.
- Unavailable settings keep their explanations readable and wrap long dependency notes while their labels and switches remain visibly disabled.
- The accent picker keeps its selected swatch visible after the menu resizes and clamps its horizontal scroll position when all swatches fit again.
- Persistent notifications and default critical alerts survive the session becoming idle, while an abandoned inline reply releases keyboard focus.
- Notification action identifiers stay case-sensitive, so an action named Default is not hidden or substituted for the default click action.
- Menu audio and brightness sliders stop accepting changes when their device is unavailable, while their device pickers remain usable.
- Album covers that failed to download while offline retry after the network reconnects, including a reconnect during an unfinished download.
- Notification action buttons wrap into more rows when their labels would not fit side by side, including on narrow screens and at larger interface scales.
- A Wi-Fi password draft survives its row being recycled while scrolling and is cleared when submitted or when the network picker closes.
- Wi-Fi and Bluetooth connection progress stays readable while repeat actions are disabled.
- Notification empty-state messages wrap inside narrow panes and at larger interface scales.
- A Wi-Fi network that cannot be reached while connecting shows Out of range instead of Failed.
- Power-mode changes without powerprofilesctl report errors and timeouts instead of failing silently.
- The Bluetooth IPC toggle reports a hardware-blocked radio instead of saying no adapter is present.
- A Wi-Fi connection can finish successfully when a rescan replaces its access-point object, instead of staying on Connecting and reporting a timeout.
- Scrolling down on a muted microphone or audio output keeps it muted while lowering its level.
- A floating bar at 100% width keeps the edge gap at its sides too, instead of pressing its rounded corners against the screen sides.
- A floating bar with no edge gap squares the corners against the screen edge instead of leaving notches beside them.
- A bar height or edge gap set over IPC or by hand rounds to the 4 px steps the menu uses, so the bar outline stays sharp at fractional scaling.
- Notification popups keep the same side gap as a full-width floating bar instead of touching the screen edge.
- The workspace marker no longer restarts its slide while the first workspace changes width, and quick repeated switches no longer snap its bounce back.
- A workspace leaving the bar no longer shows -1 while it fades, and opening or closing a window no longer reloads the app icons of other workspaces.
- Workspace app icons stay sharp at fractional scales such as 125%.
- An app with no icon shows its own initial in the workspace bar instead of a version digit, such as Minecraft's 1.
- Toggles, sliders, colour swatches, notification count badges and the menu rail's selection sit on whole device pixels at fractional scales such as 125%, so their edges stay sharp and even on both sides, and hovering a toggle no longer blurs its outline.
- Hovering a menu rail button draws its square on whole device pixels like the selected one, and the Settings drawer's rows and selection keep the same margin on both sides.
- Pressing a slider's handle slightly off centre no longer nudges its value.
- A nested tray submenu keeps opening on the side its parent opened to, instead of turning back over the tray menu.
- With Popups match bar opacity on, tray submenus blur what is behind them like the tray menu itself, instead of showing it sharp.
- A window that closes while the bar is refreshing its window list no longer stays behind as an app icon or a lit workspace until the shell restarts.
- Turning Background blur on or off with Popups match bar opacity on no longer flashes the menu's sliders and switches light grey.
- The selected colour swatch sits evenly inside its ring at fractional scales such as 125%, where it sat a pixel to one side.
- With Popups match bar opacity on, a switch that is off keeps its knob visible over a light wallpaper instead of fading into its track.
- Notification history keeps messages that arrive together in the order they came, instead of listing the ones that waited behind other popups as the newest.
- With more than one media player open, the Now Playing page and bar show the one you used last, the same one the media keys control, instead of whichever opened first.
- The lock screen and the sound mixer opened from Silere keep running when the shell restarts, updates or crashes, instead of closing with it.

## Releases

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
