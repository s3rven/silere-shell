# Contributing

Thanks for taking an interest in Silere. Ideas, bug reports, fixes, big features, tiny typo catches, all of it is welcome, and you don't need to be a QML expert to help out. Open an issue to talk about user-facing behavior, or send a pull request once a change feels ready. Not sure about something? Open the issue anyway and we'll figure it out together.

## Bug reports

No scripts to run. A useful report includes:

- distribution, Quickshell version/source, and compositor (Hyprland or niri) version;
- exact reproduction steps and what you expected instead;
- relevant foreground `qs -p shell.qml` output;
- whether it also happens on the current `main` branch.

Please strip usernames, window titles, network names, and anything else private from logs and screenshots.

## Project layout

- `config/` contains visual tokens and small shared runtime helpers.
- `services/` contains the singleton state and system-integration API. Services do not create UI.
- `modules/common/` contains primitives shared by more than one surface.
- `modules/bar/` contains the bar layout; its widgets live in `modules/bar/widgets/`.
- `modules/menu/` contains the menu window and Home-specific features.
- `modules/menu/controls/` contains reusable menu inputs, rows, and layout helpers.
- `modules/menu/settings/` contains Settings navigation content and Settings-only components.
- the remaining `modules/` folders each own one shell surface.
- `scripts/` contains installation, repair, validation, and benchmarking tools.

Keep dependencies flowing from a surface toward shared pieces. App-level `modules/menu/` code may use `settings/` or `controls/`, and Settings may use controls; neither lower layer may import app-level menu code, and controls must not import Settings. Add a type to the `qmldir` beside its file, and mark it `internal` unless another directory imports it.

## Component conventions

- Give reusable components useful `implicitWidth` and `implicitHeight` defaults so callers only override size when layout requires it.
- Treat properties as inputs and signals as user intent. Signals should carry the requested value, such as `toggled(nextChecked)`, instead of making every caller invert stale state.
- Use `MotionBehavior` or `ColorFade` for state changes, and stop timers, loops, loaders, and helper processes while their surface is hidden or idle.
- Include keyboard activation and the matching `Accessible` role, name, and state in the component itself.
- Keep one visual behavior in one component. Prefer extending a shared row or control over copying its hover, focus, animation, or accessibility code.

## Changes

Keep each change scoped to one behavior. Follow the existing QML component and service patterns, keep optional integrations dormant when unused, and leave a useful disabled or missing-tool state. Don't commit `config/MatugenTheme.qml`, `settings.json`, `calendar-marks.json`, or other generated and personal files.

CI runs the lint, required Quickshell-module probe, and headless type-check on every pull request, so you don't need to run anything yourself. Just push and let it validate. (The `scripts/` helpers are there if you like to check locally, but they're optional.)

For visual changes, test keyboard focus, reduced motion, narrow bar and menu layouts, and missing dependencies. A before/after screenshot or short clip helps when the difference isn't obvious from the code.

Your code doesn't need to be perfect before we talk. As long as the reproduction, the user impact, and the tradeoffs are clear enough to look at, that's plenty to start from.
