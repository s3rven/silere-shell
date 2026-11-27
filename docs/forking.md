# Forking Silere

[All docs](README.md) · [Architecture](architecture.md) · [Testing](testing.md) · [Contributing](../CONTRIBUTING.md)

Fork it, strip it, rebrand it. Most changes touch two or three files, and the checks tell you if you missed one,
so you don't need to know the whole shell to change part of it.

## Where things are

- `config/`: colours, durations, sizes
- `services/`: settings and system state, no UI
- `modules/`: one folder per surface: `bar/`, `menu/`, `notifications/`, `osd/` and the rest
- `scripts/`: what an installed copy runs: the `silere` command, install, update, repair, doctor and completions
- `dev/`: checks, tests, probes and release tooling; none of it ships in the package
- `packaging/aur/`: the package recipe and its generated `.SRCINFO`
- `security/`: the release signer list installed updaters trust
- `docs/`: these guides and the archived release notes

## Changing things

Colours all live in `config/Theme.qml`. Change a token and the whole shell follows; don't paste a hex into a
widget.

Silere is drawn for fractional scales such as 1.25, where one logical pixel is 1.25 device pixels. Keep sizes and
positions on the 4 px grid (`Metrics.snap4()` and its siblings), which lands on whole device pixels. Anything
sized off that grid, like a 22 px swatch, takes `Metrics.devicePx()` for its size and a `PixelSnap` transform for
its place. Draw rounded outlines with `OutlineBorder` rather than `Rectangle.border`, which thickens the corners,
and give a new `Shape` `preferredRendererType: Shape.CurveRenderer`.

Take durations from `Motion` or `Motion.ms()`, which Reduce motion turns to zero, and animate through
`MotionBehavior` rather than a bare `Behavior`, since it carries the same gate. Anything retargeted while it
moves, like the workspace marker or a panel following its content, uses `SmoothGlide` (or `SpringGlide` for a
selection): a restarted ease loses its speed and kicks.

A new setting goes in four places:

1. a property in `services/ShellSettings.qml`, whose value there is the default
2. an entry in that file's `schema`, with a `sec:` naming a settings page
3. wherever you read it
4. a row on that same page under `modules/menu/settings/`

Saving is automatic. Put the row on the page the `sec:` names: that is what dots the page once the value leaves
its default, so a mismatch marks a page the setting isn't on.

A new component must be listed in its folder's `qmldir`. Forget it and it fails only when running, as
`X is not a type`, which confuses everybody once.

For layouts that stay readable at every text size, use `Metrics.rowHeightFor()` as a minimum and let text's
`implicitHeight` grow the space above a slider or beside a control; a fixed text container can cut off larger
glyphs even when nothing reports `truncated`. `dev/test-layout-fit.sh` checks horizontal overflow and clipped
text across the supported sizes. Leave scrolling viewports free to clip rows outside them.

Custom buttons, toggles and sliders use `KeyboardFocus` for guarded key actions, a focus ring and scrolling into
view. Native `TextInput` fields use `FocusScroll`, with their editing keys left on the input; set its
`revealTarget` to the enclosing field when its border and padding should scroll into view too.

Keep expensive surfaces behind loaders and release them when their retention time ends; reading a loading
`LazyLoader.item` forces the load to finish at once. Long lists use viewport-sized delegates that stop their
timers and animations and clear focus when pooled
([LazyLoader](https://quickshell.org/docs/v0.3.2/types/Quickshell/LazyLoader/),
[list reuse](https://doc.qt.io/qt-6/qml-qtquick-listview.html#reusing-items),
[profiling](https://doc.qt.io/qt-6/qtquick-performance.html#profiling)).

A control whose target can change under it splits the work: the service owns the confirmed value and its write
queue, and a slider owns only the unfinished gesture. Bind `interactionKey` to the actual device or track, so a
change of target cancels the old drag:

```qml
QuickSlider {
    wheelKey: "volume"
    interactionKey: Audio.sink ? String(Audio.sink.id) : ""
    value: Audio.uiVolume
    onMoved: next => Audio.setVolume(next)
}
```

`QuickSlider` folds that identity into its wheel key, and `SliderTrack` clears wheel state when its target
changes. A service resync must retire the old target's queued writes, processes and retry timers before it
adopts the new value. Test it in `dev/probe-logic.qml` with fixtures, never the user's hardware: start a gesture
or a write, change the target, then deliver a late drag, release or timer.

A new bar widget goes in four places, five if it can be hidden:

1. `modules/bar/widgets/MyThing.qml`. Start from `Volume.qml`, the smallest complete one: a widget is a `Pill`
   exposing `show`, and `BarZone` reads that.
2. its line in `modules/bar/widgets/qmldir`
3. a `Component` in `modules/bar/BarContent.qml`, added to `_widgetComponents` under the key you want
4. an entry under that key in `barWidgetMeta` in `services/ShellSettings.qml`: glyph, label, group, the `zone` it
   ships in, and the `setting` that hides it (an empty string means it cannot be hidden)
5. that `setting` as a property with a `schema` entry whose `sec:` names the `widgets` page, if it can be hidden

`barWidgetMeta` is the catalog: the key list and the default layout are read from it, and an entry's place in it
is the widget's default place in its zone. Someone with a saved layout gets the new widget just before the
widget that follows it in the catalog. If it needs a backend that may be absent, gate it in `BarZone._widgetEnabled()` beside the
`battery` and `brightness` cases; returning false there hides the widget rather than drawing a dead one.

For less shell: surfaces don't import each other, so you can delete a `modules/` folder along with its `import`
and loader in `shell.qml`, and the rest keeps working.

## Another compositor

Every widget reads the compositor through `services/Compositor.qml`, which loads one backend file
(`CompositorHyprland.qml` or `CompositorNiri.qml`) by its path when the session's socket variable is set. A new
compositor is a third file plus two lines in the facade: its socket variable in `backend`, and its file in the
`Loader`. Loaded by path, it costs nothing at start on the other compositors. [Decisions](decisions.md) has the
reasoning.

A backend provides these, and ci-lint fails one that lacks any. Lists are plain JavaScript arrays rebuilt on a
change, never changed in place:

| Member | Holds |
|---|---|
| `workspaces` | `{ wsId, name, output, active, urgent, occupied, ref }`: `wsId` the number the bar shows, `ref` the compositor's own id |
| `toplevels` | `{ appId, title, cls, initialClass, pid, ref, wsRef, wsId, output, focused, focusRank }`; a lower `focusRank` was focused more recently |
| `workspaceToplevels` | `{ appId, wsId, output }`, without titles, so a title changing every frame wakes no workspace icon |
| `activeToplevel` | the focused entry of `toplevels`, or `null` |
| `focusedMonitor`, `focusedWorkspaceRef` | the focused output's name and its workspace's `ref` |
| `overviewActive` | whether the compositor's own overview is open |
| `specialOutputs` | outputs showing a scratchpad or special workspace; `[]` where there is none |
| `popupGrab` | a `Component` that grabs focus for a popup, or `null` |
| `monitorName(screen)` | the compositor's name for a Quickshell screen |
| `focusWorkspace(wsId, output)`, `moveActiveToWorkspace(wsId, output)`, `focusToplevel(entry)`, `refreshToplevels()` | the actions the bar and menu take |
| `workspaceActivated(output)`, `overviewRaw(open)` | signals: a workspace was switched to on that output; the overview opened or closed |

Optional, read only when present: `urgentRefs`, `monitorSerials` (output name to EDID serial), `monitorScale(screen)`,
`keyboardLayout`, `keyboardLayoutCount` and `cycleKeyboardLayout()`, `submap` and `leaveSubmap()`,
`sharingSupported`, `activeFullscreen`, `blurBlocker` and `checkBlur()`, `globalShortcuts`, and the signals
`screencast(started)`, `sharingState(active)`, `screenshotTaken(path)` and `configReloaded()`. A backend without
one simply lacks that feature: no layout pill, no submap mark, no screen-share detection. `CompositorNiri.qml` is
the smaller of the two to start from; the pure model helpers it uses are in `services/NiriEvents.js`.

## Renaming your fork

The name appears a few hundred times, nearly all of it cosmetic. Four places matter:

- the layer-shell namespaces (`silere-bar`, `silere-menu` and the rest), which compositor animation rules match
- the config and cache folders, `"/silere-shell"` in `services/ConfigStore.qml` and `services/ShellUpdate.qml`;
  changing them leaves the old `settings.json` behind
- the Matugen palette `matugen/silere-shell.json` in `config/MatugenPalette.qml`, which has to match the output
  path in the Matugen template
- `security/update-signers`: swap in your own key, or your fork's updater rejects your own releases

`grep -rIl --exclude-dir=.git silere .` finds the rest, including the AUR files and update timer units.

## Before you push

`bash dev/check.sh` runs the type check, the probes and the structural rules, and names anything it doesn't
like; [CONTRIBUTING](../CONTRIBUTING.md) has the lighter checks to run between edits. Two rules catch people out
early: use `MotionBehavior` rather than a bare `Behavior`, and size rows with `Metrics.rowHeightFor()` rather than
a number.
