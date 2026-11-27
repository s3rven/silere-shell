# How Silere fits together

[All docs](README.md) · [Code guide](forking.md) · [Testing](testing.md) · [Decisions](decisions.md)

Silere is one Quickshell config: `shell.qml` and the QML it reaches. This page follows a start from that file
outward, so you know which part of the tree a change belongs in and what it costs at login.

## What runs at start

`shell.qml` builds three things, plus a few small windows it needs only at times (Keep Awake's idle inhibitor,
the click-away catchers on other monitors):

- A bar per screen. A `Variants` over Quickshell's screens holds one `LazyLoader` per screen with
  `modules/bar/Bar.qml`; `barDisabledMonitors` and the monitor identities decide which screens get one. The bar's
  widgets are listed once in `barWidgetMeta` (`services/ShellSettings.qml`) and built by
  `modules/bar/BarContent.qml`.
- Popup loaders. The menu, calendar, tray menus, quick actions, notification popups and the OSD each sit in a
  `PopupLoader`. All but the OSD name their surface by path (`surfaceFile`), so their QML compiles off the GUI
  thread the first time they are wanted, not at login. A surface that fails to compile sends one alert with a
  reload click, and the bar stays up.
- The armed services. `Component.onCompleted` reads `armed` on the services that have to watch something from
  the first second (notifications, audio, hooks, the OSD state...). Quickshell builds a singleton the first time
  anything reads it, so a service nobody reads costs nothing.

`dev/startup-set.py` prints what compiles before the bar shows, following type names from `shell.qml`, and
ci-lint fails a release that grows it by more than 2%. A type named directly in a file compiles with that file,
opened or not, so load anything large or rare from a file when it is first wanted.

## Services

`services/` holds the system state, with no drawing: about 50 singletons and a few plain types, in three layers:

| Layer | Examples | May read |
|---|---|---|
| Base | `XdgPaths`, `ConfigStore`, `SafeText`, `ShellSettings`, `SystemTools`, `DateTime`, `Idle` | each other |
| Services | `Audio`, `Network`, `Bluetooth`, `Battery`, `Media`, `Notifications`, `Updates`, `Compositor`... | the base and each other |
| Surface state | `MenuState`, `CalendarState`, `TrayMenuState`, `QuickActionsState`, `OverlayCoordinator` | anything below |

A lower layer reading an upper one ties them into one cycle, where any of them can pull in all the others, so
keep new references pointing down; ci-lint fails a base service that reads above it. Data both sides need goes
in a `.pragma library` file, as the Settings rail does in `SettingsTree.js`, and a need that lives above is wired
in from there, as `ClockDemand` tells `DateTime` who shows the time. Another file reads only public members:
ci-lint fails a read of a singleton's `_private` member from outside its own file.

External commands run through `BoundedProcess`, which has a time limit and kills the whole process group. Values
from apps or the user go in as arguments (`"$1"`), never spliced into a shell script. Repeating timers stop while
the session is idle or their surface is closed.

## The compositor

Widgets read the compositor only through `services/Compositor.qml`. It picks a backend from the session's socket
variable and loads `CompositorHyprland.qml` or `CompositorNiri.qml` by path; the
[code guide](forking.md#another-compositor) lists what a backend provides, and [decisions](decisions.md) why it
is built this way. Hyprland dispatches go through `HyprDispatch`, one `hyprctl` per action.

## Settings

`ShellSettings` holds every setting as a property with a `schema` entry (type, range, page). The file is
`~/.config/silere-shell/settings.json`, sparse: only what differs from the default is written. A release that
adds a key bumps `_settingsVersion` and adds a step to `SettingsMigrations.js`, so a rollback keeps the keys it
cannot read. Settings pages bind rows by key, since the schema already states the type and range.

## Scripts

`scripts/` is what an installed copy runs: `silere` (the command, which talks to the running shell over
Quickshell's IPC), `install.sh`, `update.sh` (signed tags only, with a journal for rollback), `doctor.sh`,
`try.sh`, and the helpers they share in `scripts/lib/`. `dev/` holds the checks; none of it ships.

## Checks

`scripts/test-qml-headless.sh` type-checks every file, `dev/test-logic.sh` runs the behaviour probe, and
`dev/ci-lint.sh` holds the structural rules above. `dev/light-check.sh` runs those one at a time at low priority;
`dev/check.sh` adds the nested-compositor, screen and audio probes. See [Testing](testing.md).
