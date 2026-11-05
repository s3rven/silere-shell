# Contributing

Just open a PR — bug fix, typo, a whole new widget, or a half-finished idea to talk about.
Anything's fair game and I'll review it myself.

AI-assisted PRs are welcome, and so is hand-written code. Neither is better here. Just run
what you send and make sure it works. I build Silere the same way — see
[On AI assistance](README.md#on-ai-assistance).

## Before you open it

Keep each change focused and preserve unrelated working tree edits. Before submitting
code changes, run these from the checkout root:

```bash
bash scripts/test-qml-headless.sh
bash dev/test-logic.sh
bash dev/check.sh
```

The first checks QML types and imports without a display, the second checks behaviour,
and the last runs the broader structural, runtime and layout checks. A skipped check
does not verify that part of the change; include skips or failures in your PR.

The behavioral probe uses Qt's `QtTest` QML module to verify
pointer input; install that module if your distribution packages it separately.
With `dbus-run-session` installed, each probe runs on a private session bus, so a
shell you restart during a run keeps its notifications.

For a longer UI pass, run `SILERE_UI_STRESS_CYCLES=360 bash dev/test-ui-stress.sh`.
It exercises pointer drags, dropdown lifetimes and choice-chip reflow while cycling
interface scale, contrast and theme settings. `QT_SCALE_FACTOR=1.25` also exercises
fractional display scaling. Set `SILERE_UI_STRESS_CAPTURE=/tmp/silere-ui.png` to
save a rendered preview at the end. The regular checks run a shorter 120-cycle version.
See [testing and compatibility](docs/testing.md) for the display-scale matrix,
compositor requirements and CI log artifacts. Run `actionlint .github/workflows/*.yml`
when changing workflows.

`bash dev/test-audio.sh` checks audio against a private PipeWire and WirePlumber with no hardware.
`bash dev/test-compositors.sh kwin` checks startup, popups and IPC in a private
session. Replace `kwin` with `hyprland` or `niri` to test those backends. The runner
needs KWin and `dbus-run-session`, plus the selected compositor.

If you're changing more than one file, [`docs/forking.md`](docs/forking.md) maps the tree
and lists what a change actually touches — a new setting, a new component and a new bar
widget each have a chain to follow.

Split commits by concern. Use signed commits with a one-line, lowercase, imperative
subject, such as `fix weather response validation`.

## Questions

Loose ideas and questions are fine in
[Discussions](https://github.com/s3rven/silere-shell/discussions).
