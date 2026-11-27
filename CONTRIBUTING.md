# Contributing

Just open a PR: a bug fix, a typo, a whole new widget, or a half-finished idea to talk about. Anything's fair
game and I'll review it myself.

AI-assisted PRs are welcome, and so is hand-written code. Neither is better here. Just run what you send and
make sure it works. I build Silere the same way; see [On AI assistance](README.md#on-ai-assistance).

## Your first change in five minutes

1. Fork the repo and clone your fork.
2. Run `bash scripts/silere try` in the clone. Your copy opens in a window with its own settings, apart from your
   desktop; close the window and run it again to see an edit.
3. Make the change. [`docs/forking.md`](docs/forking.md) says where things live and what a change touches.
4. Run `bash scripts/test-qml-headless.sh` and `bash dev/test-logic.sh`.
5. Commit with a one-line, lowercase subject, such as `fix weather response validation`, and open the PR. CI runs
   the rest of the checks on it.

## Where help counts most

I use Silere every day on one laptop screen with Hyprland, so other setups get much less testing than mine. The
most useful help comes from whatever you run that I don't:

- niri, more than one monitor, mixed display scales, or an NVIDIA card driving the screen. Tell me what looks or
  acts wrong, with the output of `silere doctor`.
- A keyboard backlight, a desktop with no battery, or a Bluetooth or audio device that behaves oddly. Those paths
  have no hardware here.
- A package for your distribution. `packaging/aur/PKGBUILD` is a starting point for Arch-based ones; a Nix flake,
  a Fedora COPR or anything else would be new.
- A note in [`docs/troubleshooting.md`](docs/troubleshooting.md) for a problem you solved on your own setup, so
  the next person finds it.

Issues marked [help wanted](https://github.com/s3rven/silere-shell/labels/help%20wanted) or
[good first issue](https://github.com/s3rven/silere-shell/labels/good%20first%20issue) are open for anyone to
pick up. Say so in the issue and it's yours.

## Before you open it

Keep each change focused and preserve unrelated working tree edits. Before submitting code changes, run these
from the checkout root:

```bash
bash scripts/test-qml-headless.sh
bash dev/test-logic.sh
bash dev/check.sh
```

The first checks QML types and imports without a display, the second checks behaviour, and the last runs the
broader structural, runtime and layout checks. `dev/check.sh` keeps every core busy for minutes; between edits,
`bash dev/light-check.sh` runs the lighter checks one at a time at low priority. A skipped check does not verify
that part of the change, so include skips or failures in your PR.

The behaviour probe uses Qt's `QtTest` QML module to verify pointer input; install that module if your
distribution packages it separately. With `dbus-run-session` installed, each probe runs on a private session
bus, so a shell you restart during a run keeps its notifications.

For a longer UI pass, run `SILERE_UI_STRESS_CYCLES=360 bash dev/test-ui-stress.sh`. It exercises pointer drags,
dropdown lifetimes and choice-chip reflow while it cycles interface scale, contrast and theme; add
`QT_SCALE_FACTOR=1.25` for fractional scaling. `bash dev/test-audio.sh` checks audio against a private PipeWire
and WirePlumber with no hardware, and `bash dev/test-compositors.sh kwin` (or `hyprland`, `niri`) checks startup,
popups and IPC in a private session; it needs KWin and `dbus-run-session`, plus the compositor you test.
[Testing and compatibility](docs/testing.md) has the rest, including the display-scale matrix and CI's log
artifacts. Run `actionlint .github/workflows/*.yml` when you change a workflow.

If you're changing more than one file, [`docs/forking.md`](docs/forking.md) maps the tree and lists what a change
actually touches: a new setting, a new component and a new bar widget each have a chain to follow.

Split commits by concern. Use signed commits with a one-line, lowercase, imperative subject, such as
`fix weather response validation`.

## Questions and feedback

Loose ideas and questions are fine in [Discussions](https://github.com/s3rven/silere-shell/discussions). So is
plain feedback: if you tried Silere, tell me [how it went](https://github.com/s3rven/silere-shell/discussions/3),
even if it's only "it works" or "I switched to something else, and here's why". That's the one thing no test here
can tell me.

Everyone taking part is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).
