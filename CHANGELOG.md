# Changelog

Notable changes to Silere Shell. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/) loosely while in `0.x`: minor versions
change features, patch versions fix them.

The updater tracks `main`, not tags, so a running install gets changes as they land
rather than when a version is published here. The settings file has its own
`__version` and migrates separately.

## [0.3.0] - 2026-08-11

**Upgrading:** settings carry over. A stored `barCornerStyle` of "flat" becomes a
Roundness of 0. A custom accent you already set is left exactly as it is. :D
A shadow depth above 160% or a dot opacity below 10% settles onto the new end of
its slider; both drew the same thing there already, so nothing looks different.

### Added

- Accent colours can be mixed by hand. A Custom swatch at the end of the accent row
  opens a hue strip and an intensity strip. Before this there was only a hue strip,
  and it silently reused the saturation of whatever colour was already set, so the
  first custom colour anyone picked inherited the palest preset and stayed there.
- An AUR package. `packaging/aur` carries the PKGBUILD, and an install with no git
  checkout hides the git-backed update controls instead of failing on them.
- Edge gap for a floating bar, adjustable from 0 to 24 px.
- Workspace urgent pulse is its own toggle.
- Night Light, the daily update check and Power Mode say why a switch flipped back
  rather than failing silently. `hyprsunset` exiting on its own reports its last
  output line, and a rejected `powerprofilesctl set` reports its own.
- Reset backups are stamped with the time, so a second reset no longer overwrites
  the record of the first. The five newest are kept.
- Hovering a notification stack holds the timer on every card in it. Cards used to
  expire out from under the pointer and reflow what you were reading.
- The settings category rail draws an edge line when there is more to scroll.
- Notification history animates. Dismissing one entry glides the rest up instead of
  snapping them, a newly archived notification fades in, and expanding a truncated
  body eases the row open.
- Notification history has privacy controls: its size is adjustable, and saved
  notification text can be cleared and kept only for the current session.
- A workspace app icon falls back to a lettered badge when the application ships no
  icon at all. Those windows used to be dropped from the row, so a workspace holding
  only unpackaged apps looked empty.
- A notification whose app icon is missing or fails to load shows the app's initial,
  in the popup and in the history list. The icon slot also keeps its width either
  way, so a notification with no icon no longer shifts its own header text.
- Release resource use now has a versioned performance table. Publishing a tag
  fails if its release has no matching entry.

### Changed

- The media visualizer now paints its small canvas immediately instead of
  handing CPU images through a dedicated render thread. Measured on the
  reference session, this cuts visualizer CPU by about a fifth without
  changing its look.

- Slider handles now use Silere's narrow rectangular control shape instead of
  circular knobs. Their rails have squarer ends, clearer hover/focus contrast,
  and inset endpoints that keep handles out of adjacent labels. The rail no
  longer changes thickness on hover, and Home, End, Page Up and Page Down work
  consistently on both regular and colour sliders.

- Compact widget and tray spacing is slightly tighter, and high-contrast focus
  rings are stronger against the rest of the high-contrast palette.

- Accent colours are mixed in LCh at a fixed lightness. In HSL, sweeping the hue
  swung lightness across 34 points of L\* while the built-in presets span 5, so a
  hand-picked colour came out either glaring or muddy depending on where you landed.
  Every hue now sits at the presets' own lightness and stays inside sRGB.
- Choice controls (Source, Date, Position and the rest) are separated chips, and the
  selected one carries an accent outline instead of a filled plate.
- Bar corner style folded into Roundness, where 0 is flat. The slider appears only
  for a floating bar, since a docked bar does not paint its own corners.
- Workspace settings are grouped under General, Content and Behavior.
- Marker opacity reads "Number opacity" or "Dot opacity" depending on which the
  marker is actually drawing.
- The widget arranger follows the interface scale and scrolls the settings page
  when a dragged row reaches an edge, so every lane stays reachable at large type.
- OSD settings are grouped, and a row that depends on a toggle now sits under it.
- The Battery settings section is hidden on systems with no battery instead of
  showing a disabled row.
- Base is one row for both theme sources. Switching Source recolours it in place
  instead of collapsing one row and expanding a near-identical one.
- Every scrolling surface rebounds the same way on a flick. The notification list
  and both tray menus had drifted to a hard stop.
- The Night Light panel builds when you open it, as the Wi-Fi and Bluetooth panels
  already did.
- "Fully-charged OSD" is now "Fully charged alert", and the desktop-notification
  timeout reads "Dismiss after" like the other two timeout rows.
- `update.sh` answers version and status queries on an install with no git checkout
  instead of treating it as a failure.
- Both "Dismiss after" rows are sliders rather than fixed buttons, and reach the
  range the settings file already allowed: 10 s for the OSD, 30 s for notifications.
  The button rows stopped at 5 s and 15 s, so most of the range was unreachable.
- The media visualizer fades out when playback stops. It holds its last frame for
  the length of the fade and drops the cava client immediately; before, it was
  destroyed in the same frame the fade began, so the fade played against nothing.
- README resource figures re-measured, separating Silere's own memory from the Qt
  and GPU driver floor.
- Popups stay attached to the widget that opened them. The menu, calendar, quick
  actions and a tray menu re-anchor when the bar reflows underneath them, and close
  if that widget goes away, rather than hanging off the position it had at open.
- Clicking a tray icon whose menu is already open closes it. It used to reopen the
  same menu in place, so the icon had no way to put it away.
- Every settings slider covers exactly the range its setting accepts, and a lint
  keeps the two from drifting again. The temperature warning slider was missing its
  bottom 20°, and the top fifth of the shadow depth slider rendered identically.

### Fixed

- Truncated client labels no longer split emoji, combining marks, flags or joined
  emoji sequences, and a tray icon with no usable image now uses a complete
  grapheme for its fallback badge.
- An urgent workspace outside the visible page no longer risks a transient QML
  binding loop while the bar is laying itself out.
- System maintenance now reports a missing `libnotify` dependency when battery
  and temperature alerts are configured but cannot be sent.
- Moving one accent strip no longer nudges the other. Both axes were read back out
  of the stored colour, so each one inherited the other's rounding, and the strip
  you were not touching animated the drift.
- The hue strip works at zero intensity. Every hue wrote the same grey, so the
  thumb snapped straight back and the strip did nothing at all.
- A custom colour keeps its hue near grey. An 8-bit near-grey carries no hue to
  recover, and the reading it produced was noise.
- A setting changed in the last fraction of a second before logout is no longer
  lost. Toggles and choices write immediately; sliders still settle first, and
  calendar day marks write the same way.
- A double-click can no longer arm and confirm a destructive action in one gesture.
  Affects the power actions, clearing notification history, and resetting settings.
- A row that disables itself while handling its own click no longer comes back
  looking keyboard-focused.
- Hidden controls stay out of the tab chain, and every control activates from the
  keyboard the same way.
- A track that reports no length no longer shows one.
- An app or notification whose name begins with an emoji gets a whole character in
  its initial badge. Reading the first UTF-16 unit split the pair and drew a blank
  box instead of a letter.
- "Always show speed" no longer appears underneath a Network speed row that is
  disabled for want of NetworkManager.
- The bar underline preview no longer reaches for an effect that is not built yet.
- The bar no longer holds width for a window title it is not drawing. With the title
  on but no room to draw it, the media text was squeezed and the bar latched into
  compact for a title that never appeared — easiest to hit with the visualizer
  centred, which competes for the same space.
- The OSD shows again while the menu is open on a page with no volume or brightness
  row. It was suppressed for the whole menu, not only the page that replaces it.
- The workspace missed-notification dot appears while a fullscreen window is
  silencing notifications, not only during Do Not Disturb.
- Notification popups follow the configured floating-bar edge gap instead of using
  the old fixed inset.
- Calendar mark read and save failures are shown inside the calendar, and fixing a
  malformed marks file re-enables writes without restarting the shell.
- The bundled AUR metadata reports a real VCS version and enforces the same
  Quickshell 0.3 minimum as the installer documentation.
- A track whose cover art goes away stops showing the previous track's cover. MPRIS
  sends metadata in separate updates, so the old art is held briefly to cover the
  gap, then dropped rather than kept forever.
- A tray menu that nests deeper than eight levels stops building submenus instead of
  descending without end, and an entry whose signal raises is reported rather than
  taking the whole menu down.
- The output device falls back to its nickname or node name when PipeWire reports no
  description. That row was simply blank before.
- A volume, track length or playback position that arrives as NaN or infinity is
  normalised at the service instead of reaching a label, an icon threshold or a
  progress bar.

### Removed

- The "Bar corner style" setting. Roundness 0 is flat.

### Security

- Persisted notification history is closed to other local users. Quickshell owns
  that state file and creates it with the session umask, commonly leaving
  notification text world-readable; its directory is now made `0700` and the file
  `0600`, which also covers a file written after the shell starts. The packaged
  launcher starts with a private umask as well.
- Single-line text supplied by clients now drops control and bidirectional
  override characters before layout and accessibility consume it. Raw network
  and device identifiers remain untouched for backend actions.
- The installer creates its config directory as 0700 for the whole path, not only
  the last segment.
- The updater creates and re-hardens its whole cache path with private permissions.
- Text that arrives from another program is length-bounded before anything binds to
  it: window titles and app ids, player metadata, tray labels and tooltips, audio
  device names, and updater output. A single enormous string could previously ask
  the shell to lay out a label as long as the string.
- Icon and image sources are matched against an allowlist — local files and Qt's own
  image providers — instead of a list of known-remote schemes. A sender can no
  longer hand the shell an unusual URL and make it fetch over the network. Media
  cover art keeps its deliberate exception, because MPRIS art genuinely is a URL.
- The update card bounds what it will render from `git log`: how many commits, and
  how long each subject may be.
- Every lookup keyed by a compositor-supplied window class is prototype-free, so a
  window named `constructor` cannot be mistaken for a cache hit, and the workspace
  icon cache has an upper bound.

## [0.2.0] - 2026-08-10

**Upgrading:** settings carry over untouched, nothing migrates. Mostly install and
update fixes.

### Added

- Update card shows the installed version by tag, plus commit, branch and build date.
- Pending updates expand into the commits they would install.
- Update checks remember when they last reached the remote, unattended runs included.
- The daily update check shows when it next runs.
- Keyboard focus works across the menu: buttons, rail, sliders, chips and swatches.
- Notifications get their own Wayland namespace, `silere-notifications`, so layer
  rules can target them without also hitting the bar.

### Changed

- The update card warns about a wrong branch, detached HEAD or local edits before
  you press Install, not after it fails.
- Pending commits moved into their own expandable list.
- The bar no longer rebuilds its workspace and window models when a layer opens or
  closes. Twenty menu cycles cost 43 rebuilds before, none now.
- Retimed panel, popup and toggle motion.
- The floating shadow is split into an ambient and a contact layer.
- The media widget sizes to its text instead of holding a fixed slot.
- Accents keep the chroma that sRGB blending used to cancel.
- The Hyprland Lua autostart snippet uses the native `hl.exec_cmd`.

### Fixed

- The installer no longer says "restart your compositor" when it never added an
  autostart line.
- Autostart prompts name the full path of the file they will write to.
- QML modules are found on Debian and Ubuntu (`/usr/lib/x86_64-linux-gnu/qt6/qml`).
  They were all reported missing there before.
- The installer checks for `xz` before downloading 30 MB of font it cannot extract.
- The installer detects a missing terminal properly instead of dying at the first
  prompt.
- The updater's `git fetch` is bounded. A dead network could wedge every later
  check behind an orphaned fetch holding the lock.
- Updates are type-checked after merging and rolled back if they do not load. A
  broken update used to leave the shell respawning every three seconds.
- `update.sh --apply` only restarts the shell that runs the checkout it was called
  from.
- On niri, the workspace strip no longer pads out with slots that do nothing.
- The niri event stream reconnects after a dropped socket instead of freezing.
- A pending Wi-Fi connection is cancelled when Wi-Fi goes off or the device leaves.
- Bluetooth battery percentages go through one validated conversion.
- Bar widgets fall back to empty models when a backend detaches.
- The update split header tolerates malformed counts.

### Removed

- The workspace marker trail.
- The media widget's "Track text width" setting. It sizes to its text now.
- Home, End, Page Up and Page Down in menu rows, pickers and sliders. Arrow keys,
  Escape and the calendar's jump-to-today still work.

### Security

- Stored notifications are guarded against prototype pollution.

## [0.1.0] - 2026-08-08

First tagged release. Silere had been in daily use for a while; this is just a
point to refer back to. Needs Quickshell 0.3 or newer and either Hyprland or niri.
Everything else is optional, and the README lists what each tool turns on.

Grouped by area rather than by change type, since a first release has nothing to
differ from.

### Shell

- Bar with left, centre and right zones, drag-to-reorder, per-monitor visibility,
  and compacting when space runs short.
- Widgets: workspaces, clock, media, tray, network, volume, brightness, battery,
  package updates, shell updates.
- Notification popups with urgency styling, inline actions, images, a countdown
  ring, do-not-disturb scheduling and a history page.
- On-screen display for volume and brightness, optionally drawn inside the bar.
- Control menu with a Now page, notification history, and 108 settings.
- Calendar with month marks, tray menus, and a quick-actions popup.

### Theming

- Wallpaper colours through matugen, or one of seven hand-picked accents.
- Three base tones with a depth axis, adjustable outline strength, high-contrast
  mode, and a reduce-motion mode that zeroes every animation.
- Font family and scale come from installed Nerd Fonts and are validated, so a
  removed font cannot leave the shell unreadable.

### Behaviour

- Background work stays off unless you turn it on. Timers are gated on idle,
  capability and menu visibility.
- A missing optional tool hides its widget. The rest keeps working.
- No plugin layer and no extra daemon.
- Notification icons and images never load over the network. A remote URL from a
  sender is ignored.

### Known limitations

- Special workspaces are Hyprland-only. On niri that state is absent.
- The updater only fast-forwards `main`. It refuses to run on a checkout with
  local changes or a diverged history, and says why instead of fixing it.

[0.3.0]: https://github.com/s3rven/silere-shell/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/s3rven/silere-shell/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/s3rven/silere-shell/releases/tag/v0.1.0
