# Contributing

Just open a PR — bug fix, typo, a whole new widget, or a half-finished idea to talk about.
Anything's fair game and I'll review it myself.

AI-assisted PRs are welcome, and so is hand-written code. Neither is better here. Just run
what you send and make sure it works. I build Silere the same way — see
[On AI assistance](README.md#on-ai-assistance).

## Before you open it

Optional: `bash dev/check.sh` runs the same checks CI does, if you'd rather not wait on
a CI round-trip. The behavioral probe uses Qt's `QtTest` QML module to verify
pointer input; install that module if your distribution packages it separately.

For a longer UI pass, run `SILERE_UI_STRESS_CYCLES=360 bash dev/test-ui-stress.sh`.
It exercises pointer drags, dropdown lifetimes and choice-chip reflow while cycling
interface scale, contrast and theme settings. `QT_SCALE_FACTOR=1.25` also exercises
fractional display scaling. Set `SILERE_UI_STRESS_CAPTURE=/tmp/silere-ui.png` to
save a rendered preview at the end. The regular checks run a shorter 120-cycle version.

If you're changing more than one file, [`docs/forking.md`](docs/forking.md) maps the tree
and lists what a change actually touches — a new setting, a new component and a new bar
widget each have a chain to follow.

## Questions

Loose ideas and questions are fine in
[Discussions](https://github.com/s3rven/silere-shell/discussions).
