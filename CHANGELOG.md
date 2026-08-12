# Changelog

Notable changes to Silere Shell. The active section follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/) loosely while in `0.x`: minor versions
change features, patch versions fix them.

The updater follows signed stable version tags. The settings file has its own
`__version` and migrates separately.

This file stays focused on work since the latest release. Completed notes move to
[`docs/releases`](docs/releases/) and remain linked below.

## [Unreleased]

- Removed keyboard navigation and the accessibility metadata that went with it. Tab
  order, arrow-key stepping, focus rings, the settings sidebar's keyboard cursor and
  every `Accessible` role, name and description are gone; the shell is pointer-driven.
  Escape still steps back and closes, scroll wheels still work everywhere they did, and
  the Wi-Fi password field still takes typed input. Screen readers can no longer
  describe the shell.
- Removed the code the keyboard layer was the last caller of: the item-tree, focus-visual
  and key-activation primitives, the workspace focus ring, and nine now-unreachable
  helpers. The checks now reject a re-added tab stop or accessibility role outright, and
  allow key handlers only in a file that hosts a text field.
- Trimmed nine configuration knobs off shared components that no caller ever set, so a
  primitive's real geometry reads at the point of use instead of behind a name.

- Made optional-tool and font detection refresh cleanly at runtime, with stable
  capability state and explicit backend failure tracking.
- Added reusable process retry/exit health and Cava runtime/config status so
  failed visualizer starts can be diagnosed without affecting the rest of the shell.
- Fixed the generated Cava profile's smoothing range and documented its
  runtime-only configuration lifecycle.
- Made Matugen palettes live-reload from a user-writable JSON file, which also
  makes read-only packaged installs work. **Re-run the installer after updating**:
  Matugen now writes `$XDG_CONFIG_HOME/matugen/silere-shell.json` instead of a file
  inside the checkout, and until its config points there, wallpaper colours stop
  changing and the shell falls back to its bundled palette. If your `config.toml`
  has an unpaired `# silere-shell` marker the installer will decline to touch it and
  say so — repair the pair, then re-run.
- Said so when wallpaper theming has nothing to work with: Settings › Theme and
  Settings › System › Maintenance now name whether Matugen is missing or has simply
  not written a palette yet, instead of presenting the bundled colors as if they came
  from the wallpaper.
- Changed the bundled fallback accent from white to Silere's own default accent, so a
  system without Matugen looks like a fresh install rather than a stark one.
- Added AUR packages to the update count through paru or yay when one is
  installed, with a new **Include AUR packages** toggle under Settings › System ›
  Updates. It is on by default, so an existing install with an AUR helper will
  start counting those updates. Checks stay read-only and never install anything.
- Gave buttons, pills, chips, toggles, media controls and slider handles one
  consistent hover and press response, quicker on the way in than on the way back
  out.
- Removed the stutter on the first settings section opened in a session, which had
  to compile every shared control before it could draw.
- Fixed dropdown options and the Wi-Fi and Bluetooth list placeholders sitting 4px
  shorter than every neighbouring row at any interface scale above 100%, which put
  their dividers off the shared rhythm.
- Marked the Wi-Fi password field as sensitive to input methods, so an IME or
  on-screen keyboard no longer capitalises the first character of a case-sensitive
  key or keeps it in predictive-text history.
- Fixed notification history mislabelling days on the day after a daylight-saving
  change, where a 23-hour day put every entry one bucket early — the day before
  yesterday read as **Yesterday**, under a second heading of the same name.
- Gave a settings row's name priority over its value when space runs short. A long
  value used to take its full width and squeeze the name to nothing; now the value
  shortens first and the name keeps a readable floor.
- Renamed the theme Source option from Neutral to Custom, and the accent picker's
  own custom swatch to Mix, so the two no longer share one name.
- Fixed the settings panel snapping to its new height when a category collapses
  instead of easing with it.
- Fixed the palette card bulging outward while switching theme Source between
  Custom and Wallpaper.
- Routed every process timeout through the shared bounded-process primitive, so a
  hung update check, package check or VPN lookup recovers the same way instead of
  through three separately hand-rolled timers.
- Gave scroll behaviour, list keyboard stepping, row heights and the interface font
  one definition each rather than a copy per call site, and made the checks fail on a
  new copy instead of letting it drift in.
- Added a check that every settings label still fits the panel width it ships at,
  across the whole interface-scale range, so an over-long one cannot quietly elide
  itself in a release.

## Releases

- [0.4.0](docs/releases/0.4.0.md) — 2026-08-12
- [0.3.0](docs/releases/0.3.0.md) — 2026-08-11
- [0.2.0](docs/releases/0.2.0.md) — 2026-08-10
- [0.1.0](docs/releases/0.1.0.md) — 2026-08-08
