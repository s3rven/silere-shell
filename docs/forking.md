# Forking Silere

Fork it, strip it, rebrand it. Most changes touch two or three files, and
`bash dev/check.sh` tells you if you missed one — you don't need to know the
whole shell to change part of it.

## Where things are

- `config/` — colours, durations, sizes
- `services/` — settings and system state, no UI
- `modules/` — one folder per surface: `bar/`, `menu/`, `notifications/`, `osd/`, …
- `scripts/` — what an installed copy runs: the `silere` command, install, update, repair,
  doctor and command completions
- `dev/` — checks, tests, probes and release tooling; none of it ships in the package
- `packaging/aur/` — the package recipe and its generated `.SRCINFO`
- `security/` — the release signer list used by installed updaters
- `docs/` — user guides and archived release notes

## Changing things

**Colours.** All of them live in `config/Theme.qml`. Change a token, the whole shell
follows. Don't paste a hex into a widget.

**A new setting** goes in four places:

1. a property in `services/ShellSettings.qml` — its value there is the default
2. an entry in that file's `_schema`, carrying a `sec:` that names a settings page
3. wherever you read it
4. a row on that same page under `modules/menu/settings/`

Saving is automatic. Put the row on the page the `sec:` names — that is what dots the
category once the value leaves its default, so a mismatch marks a page the setting
isn't on.

**A new component** must be listed in its folder's `qmldir`. Forget it and it fails
only when running, as `X is not a type` — that one confuses everybody once.

**A new bar widget** goes in four places, five if it can be hidden:

1. `modules/bar/widgets/MyThing.qml` — start from `Volume.qml`, it is the smallest
   complete one. A widget is a `Pill` exposing `show`, and `BarZone` reads that.
2. its line in `modules/bar/widgets/qmldir`
3. a `Component` in `modules/bar/BarContent.qml`, added to `_widgetComponents` under
   the key you want
4. an entry under that key in `barWidgetMeta` in `services/ShellSettings.qml` — glyph,
   label, group, the `zone` it ships in, and the `setting` name that hides it (empty
   string means it cannot be hidden)
5. that `setting` as a property plus a `_schema` entry whose `sec:` names the
   `widgets` page, if it is hideable

`barWidgetMeta` is the catalog: the key list and the default layout are read from it,
and an entry's position in it is the widget's default position within its zone.
Anyone with a saved layout gets the new widget at the end of its zone.

If it needs a backend that may be absent, gate it in `BarZone._widgetEnabled()` next to
the `battery` and `brightness` cases; returning false there hides the widget rather than
drawing a dead one.

**Less shell.** Surfaces don't import each other, so you can delete a `modules/`
folder along with its `import` and loader in `shell.qml` and the rest keeps working.

## Renaming your fork

The name appears a few hundred times, nearly all of it cosmetic. Four matter:

- the **layer-shell namespaces** (`silere-bar`, `silere-menu`, …) — compositor
  animation rules match those strings
- the **config and cache directories**, `"/silere-shell"` in `services/ConfigStore.qml`
  and `services/ShellUpdate.qml` — changing them leaves the old `settings.json` behind
- the **matugen palette** `matugen/silere-shell.json` in `config/MatugenPalette.qml`,
  which has to match the output path in the matugen template
- **`security/update-signers`** — swap in your own key, or your fork's updater will
  reject your own releases

`grep -rIl --exclude-dir=.git silere .` finds the rest, including the AUR files and update timer units.

## Before you push

`bash dev/check.sh` runs the type check, the probes and the structural rules, and
names anything it doesn't like. Two of those rules catch people out early: use
`MotionBehavior` rather than a bare `Behavior` (it carries the reduce-motion gate),
and size rows with `Metrics.rowHeightFor()` rather than a number.
