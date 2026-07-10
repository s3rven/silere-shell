# Contributing

Suggestions, fixes, and new features are welcome. Open an issue for user-facing behavior or send a focused pull request when the change is ready.

## Bug reports

No scripts to run. A useful report includes:

- distribution, Quickshell version/source, and compositor (Hyprland or niri) version;
- exact reproduction steps and expected behavior;
- relevant foreground `qs -p shell.qml` output;
- whether the problem also happens on the current `main` branch.

Remove usernames, window titles, network names, and other private data from logs and screenshots.

## Changes

Keep work scoped to one behavior. Follow the existing QML component and service patterns, keep optional integrations dormant when unused, and preserve a useful disabled or missing-tool state. Do not commit `config/MatugenTheme.qml`, `settings.json`, or other generated and personal files.

CI runs the lint and headless type-check on every pull request, so you do not need to run anything yourself — just push and let it validate. (The `scripts/` helpers are there if you want to check locally, but they are optional.)

For visual changes, test keyboard focus, reduced motion, narrow bar/menu layouts, and missing dependencies. Include a before/after screenshot or short recording when the difference is not obvious from the code.

Code does not need to be perfect before discussion. The reproduction, user impact, and tradeoffs need to be clear enough to evaluate.
