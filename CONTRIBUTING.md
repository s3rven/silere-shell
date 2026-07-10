# Contributing

Thanks for taking an interest in Silere. Ideas, bug reports, fixes, big features, tiny typo catches, all of it is welcome, and you don't need to be a QML expert to help out. Open an issue to talk about user-facing behavior, or send a pull request once a change feels ready. Not sure about something? Open the issue anyway and we'll figure it out together.

## Bug reports

No scripts to run. A useful report includes:

- distribution, Quickshell version/source, and compositor (Hyprland or niri) version;
- exact reproduction steps and what you expected instead;
- relevant foreground `qs -p shell.qml` output;
- whether it also happens on the current `main` branch.

Please strip usernames, window titles, network names, and anything else private from logs and screenshots.

## Changes

Keep each change scoped to one behavior. Follow the existing QML component and service patterns, keep optional integrations dormant when unused, and leave a useful disabled or missing-tool state. Don't commit `config/MatugenTheme.qml`, `settings.json`, or other generated and personal files.

CI runs the lint and headless type-check on every pull request, so you don't need to run anything yourself. Just push and let it validate. (The `scripts/` helpers are there if you like to check locally, but they're optional.)

For visual changes, test keyboard focus, reduced motion, narrow bar and menu layouts, and missing dependencies. A before/after screenshot or short clip helps when the difference isn't obvious from the code.

Your code doesn't need to be perfect before we talk. As long as the reproduction, the user impact, and the tradeoffs are clear enough to look at, that's plenty to start from.
