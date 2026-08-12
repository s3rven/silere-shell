# Forking Silere

Fork it, strip it, rebrand it. Most changes touch two or three files, and
`bash scripts/check.sh` tells you if you missed one — you don't need to know the
whole shell to change part of it.

## Where things are

- `config/` — colours, durations, sizes
- `services/` — settings and system state, no UI
- `modules/` — one folder per surface: `bar/`, `menu/`, `notifications/`, `osd/`, …
- `scripts/` — install, update, checks

## Changing things

**Colours.** All of them live in `config/Theme.qml`. Change a token, the whole shell
follows. Don't paste a hex into a widget.

**A new setting** goes in four places: a property in `services/ShellSettings.qml` (its
value there is the default), an entry in that file's `_schema`, wherever you read it,
and a row in the matching `modules/menu/settings/` page. Saving is automatic.

**A new component** must be listed in its folder's `qmldir`. Forget it and it fails
only when running, as `X is not a type` — that one confuses everybody once.

**Less shell.** Surfaces don't import each other, so you can delete a `modules/`
folder along with its `import` and loader in `shell.qml` and the rest keeps working.

## Renaming your fork

The name appears a few hundred times, nearly all of it cosmetic. Three matter:

- the **layer-shell namespaces** (`silere-bar`, `silere-menu`, …) — compositor blur
  and animation rules match those strings
- the **config directory** `"/silere-shell"` in `services/ConfigStore.qml` and
  `services/ShellUpdate.qml` — changing it leaves the old `settings.json` behind
- **`security/update-signers`** — swap in your own key, or your fork's updater will
  reject your own releases

`grep -rIl silere .` finds the rest, and the AUR files and systemd units are in there.

## Before you push

`bash scripts/check.sh` runs the type check, the probes and the structural rules, and
names anything it doesn't like. Two of those rules catch people out early: use
`MotionBehavior` rather than a bare `Behavior` (it carries the reduce-motion gate),
and size rows with `Metrics.rowHeightFor()` rather than a number.
