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

- Hooks run a command of your own on battery, notification, theme, update and workspace events.
- Every setting the Settings pages expose can be read and written over IPC.
- A Bluetooth device that refuses to connect or pair now says so on its row.
- Quick actions carries Wi-Fi and Bluetooth toggles alongside airplane mode.
- Appearance › Interface sets the size of tray and workspace app icons.

### Changed

- Theme settings groups source, accent, and base under Colors, with surface styling in its own card.
- The bundled accent palette uses eight balanced, equal-lightness colors and a clearer Iris default.
- The custom accent mixer keeps two full-width, uncluttered color rails.
- Buttons, toggles, sliders, rows, navigation, chips, and swatches share one visible state hierarchy.
- Interactive controls expose names, states, and actions to accessibility tools without changing Silere's pointer-driven navigation.
- Failures and warnings keep their semantic color in Home-page status text instead of looking like normal active states.
- Both update cards say how long ago they last checked.
- Disconnecting the current Wi-Fi network takes a second tap to confirm.
- The Mix accent swatch shows a colour wheel.
- Disabled controls dim to one depth, and high contrast lifts them.
- Notification popups widen with the interface scale.
- The notification list grows with the history it holds, up to the room the screen has.

### Fixed

- Animations no longer fall back to roughly 60 FPS when a bar and popup are visible together on a high-refresh display.
- A docked bar casts a shadow when Shell shadows is on.
- Bar Roundness is reachable while the bar is docked, named and read out for the widget highlights it shapes there.
- The low-battery and high-temperature thresholds stay reachable with their warnings off.
- The Opacity slider under Dividers appears while the window title draws a separator.
- The centre visualiser can be aligned without the window title switched on.
- The bar Opacity readout matches what high contrast renders.
- Keybinds open the menu, calendar and quick actions under the widget that opens them, not at the screen edge.
- Notification history no longer holds read-state for notifications it has already dropped.
- A double-click on a connected Bluetooth device no longer disconnects it in one gesture.
- Bluetooth pairing closes the pairable window when the attempt finishes or is cancelled.
- Turning notification popups off retires the cards already on screen instead of reviving them later.
- Notifications and the OSD sit at the edge of a monitor whose bar is turned off, rather than clearing a bar that is not on it.
- Popup borders draw at the same weight on every side.
- The Home page's power tile says when the active profile is throttled.
- The power rail's mode value no longer crowds out its label at larger font sizes.
- The AUR toggle in Updates settings stays hidden until the updates widget itself is on.
- OSD settings no longer labels a lone section GENERAL when Feedback isn't shown beside it.
- A track with an unknown length shows --:-- instead of LIVE.
- Switching media players skips a browser session that has already stopped.
- The media card sits evenly in its padding.
- Small slider handles keep the shell's squared-off shape.
- Clicking anywhere on the media art jumps to the player.
- The bar clears the window title on an empty workspace.
- Leaving a fullscreen window for an empty workspace lets notifications through again.
- A Wi-Fi password stays in the field while new scan results arrive.
- The Wi-Fi password field scrolls into view when it opens near the bottom of the list.
- The Wi-Fi list refills after the adapter drops out and comes back.
- Silere Shell says it has not been checked yet rather than claiming to be up to date.
- A package check that keeps failing raises a warning in the bar.

## Releases

- [0.7.0](docs/releases/0.7.0.md) — 2026-08-18
- [0.6.1](docs/releases/0.6.1.md) — 2026-08-16
- [0.6.0](docs/releases/0.6.0.md) — 2026-08-15
- [0.5.1](docs/releases/0.5.1.md) — 2026-08-13
- [0.5.0](docs/releases/0.5.0.md) — 2026-08-13
- [0.4.0](docs/releases/0.4.0.md) — 2026-08-12
- [0.3.0](docs/releases/0.3.0.md) — 2026-08-11
- [0.2.0](docs/releases/0.2.0.md) — 2026-08-10
- [0.1.0](docs/releases/0.1.0.md) — 2026-08-08
