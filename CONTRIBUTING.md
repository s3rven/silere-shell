# Contributing

Any idea is fair game. A bug report, a typo fix, a whole new widget, a "what if the bar could…" question with no code attached — all of it is welcome, and you don't need to know QML to open one.

If you're not sure whether something fits, ask in [Discussions](https://github.com/s3rven/silere-shell/discussions) — no template, no required fields, and nothing gets turned away for being too small or too ambitious. Issues use templates because a bug is unfixable without your distro, compositor and Quickshell version; questions and half-formed ideas don't need any of that.

## What happens to your pull request

Nothing lands on `main` on its own. You fork, push a branch, and open a PR; it gets reviewed and merged by hand. CI runs the lint, the Quickshell-module probe, and a headless type-check on every PR, so you don't need to run anything locally — push and let it report back.

Reviews are about whether the change fits the shell, not about style-policing. Expect questions and sometimes a "let's not" — Silere stays deliberately small, so some good ideas still get turned down. That's not a judgment on the idea or the code.

## Bug reports

No scripts to run. Helpful things to include:

- your distro, compositor (Hyprland or niri), and Quickshell version;
- what you did, and what you expected instead;
- output from running `qs -p shell.qml` in a terminal, if there is any;
- whether it also happens on current `main`.

Please scrub usernames, window titles, network names, and anything else private out of logs and screenshots.

## Where things live

- `config/` — visual tokens and small shared helpers.
- `services/` — singleton state and system integration. No UI here.
- `modules/common/` — primitives used by more than one surface.
- `modules/bar/` — the bar, with its widgets in `widgets/`.
- `modules/menu/` — the menu window, plus `controls/` (reusable rows and inputs) and `settings/` (Settings-only content).
- other `modules/` folders — one shell surface each.
- `scripts/` — install, repair, validation, benchmarking.

Imports flow from a surface toward the shared pieces: menu code may use `controls/` and `settings/`, but `controls/` doesn't reach back into Settings or menu code. New types go in the `qmldir` next to the file, marked `internal` unless another directory imports them.

## How the existing code works

Not rules so much as the patterns you'll see everywhere — matching them keeps a change easy to review:

- reusable components set their own `implicitWidth`/`implicitHeight`, so callers only override size when layout demands it;
- properties are inputs, signals are intent — `toggled(nextChecked)` carries the new value rather than making callers invert stale state;
- state changes animate through `MotionBehavior` or `ColorFade`, and timers, loops, and helper processes stop while their surface is hidden or idle;
- keyboard activation and the matching `Accessible` role/name/state live in the component itself;
- one visual behavior lives in one place — extending a shared row usually beats copying its hover, focus, and animation code.

For anything visual, it helps to check keyboard focus, reduced motion, a narrow bar, and what happens when an optional tool is missing. A before/after screenshot is worth a lot when the diff doesn't show it.

Don't commit generated or personal files: `config/MatugenTheme.qml`, `settings.json`, `calendar-marks.json`.

## One last thing

Your branch doesn't have to be finished to start a conversation. If the problem and the rough shape of the fix are clear, that's plenty.
