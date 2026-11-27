# Testing and compatibility

[All docs](README.md) · [Contributing](../CONTRIBUTING.md) · [Code guide](forking.md)

## Before submitting a change

Run the required checks from the checkout root:

```bash
bash scripts/test-qml-headless.sh
bash dev/test-logic.sh
bash dev/check.sh
```

The first checks QML types and imports, the second checks behaviour, and the last runs the structural, service,
UI interaction and layout checks. Probes use private config folders and their own session bus when the tools for
that are installed. A skipped probe leaves that part of the change unverified.

`dev/check.sh` starts nested compositors and runs its probes in parallel, so it keeps every core busy for
minutes. Between edits, `bash dev/light-check.sh` runs the type check, the behaviour checks, the fit probe and
`dev/ci-lint.sh` one at a time at low priority, safe beside a desktop you are using.

Behaviour checks live in `dev/probe-logic.qml`, whose `_run()` calls one function per area in order, such as
`_checksNotificationHistory()`. Add a check to the function for its area, and put back any setting it changes
before that function returns: every area runs in the same shell.

## Display scaling and layouts

Interface size and display scale affect different parts of the layout. The fit probe covers interface sizes from
100% to 150%; for fractional display scaling, run:

```bash
QT_SCALE_FACTOR=1.25 bash dev/test-logic.sh
QT_SCALE_FACTOR=1.25 bash dev/test-ui-stress.sh
QT_SCALE_FACTOR=1.25 FIT_REQUIRE_FONT=1 bash dev/test-layout-fit.sh
```

Repeat with `QT_SCALE_FACTOR=1.5` for 150%. The fit probe needs JetBrainsMono Nerd Font so it measures the shipped
text. For a longer interaction run set `SILERE_UI_STRESS_CYCLES=360` (the default is 120), and to save a rendered
preview at the end set `SILERE_UI_STRESS_CAPTURE=/tmp/silere-ui.png`.

## Compositor checks

```bash
bash dev/test-compositors.sh hyprland
bash dev/test-compositors.sh niri
bash dev/test-compositors.sh kwin
```

These create private nested sessions and need KWin, `dbus-run-session` and the compositor under test. A nested
shell you start by hand should set `SILERE_SANDBOX=1`, as these runners do, so it never locks, suspends or ends
your real session, and never changes your brightness, Wi-Fi, Bluetooth or power mode. The Hyprland checks include
an already-open special workspace, named workspaces on a second output, and a window that opens while the shell
is busy; KWin hosts the output-removal and popup tests.

Hyprland needs a GPU render node even nested, so without one its runner skips, and the niri runner checks panels
and popups but skips full shell startup. Read the skip message when you judge coverage.

## Audio checks

```bash
bash dev/test-audio.sh
```

This starts its own PipeWire and WirePlumber with only null sinks, on a private runtime folder, state folder and
bus, so your audio is never touched. Volume and mute changes have to reach the OSD, a default device replaced
under its own name has to stay usable, a lost device must not claim a mute, and the shell has to come back when
WirePlumber or PipeWire restarts, or when PipeWire starts after the shell. It takes about ten seconds, and
`dev/check.sh` runs it when PipeWire and WirePlumber are installed.

## Tray keyboard

```bash
bash dev/test-tray-keys.sh
```

Two fake tray apps on a private bus inside a virtual KWin: one with a real DBus menu two submenus deep, one with
KDE's `/NoMenu`. Real key events walk the menus, open and close the submenus past the timer that closes one the
pointer has left, step between the apps, and press an entry, which the fake app must receive exactly once. It
takes about ten seconds and needs KWin, python-dbus and PyGObject; `dev/check.sh` runs it when they are
installed.

## Fault injection

```bash
bash dev/test-faults.sh
```

This runs a whole shell in a private nested session and tries to break it. Every external tool in turn hangs,
fails, returns garbage or returns nothing, and then notifications, a media player and a tray item send what no
well-behaved app would: 5 MB bodies, 60,000 combining marks on one character, wrong types in every field, cover
art URLs that try to run commands, thousands of signals a second. The shell has to stay up and responsive, throw
no script errors, keep `curl` to its https-only limits and leave no hung process behind.

It takes about two minutes and needs Hyprland, KWin and a GPU render node; the hostile input also needs
python-dbus and PyGObject. It is not part of `dev/check.sh`, so run it before a release.

A few inputs still crash Quickshell itself, and Silere can't stop them from QML: an `image-data` hint or a tray
`IconPixmap` claiming a size larger than its data, which a config with no Silere code reproduces too.
`SILERE_FUZZ_KNOWN=1` adds them, to see whether a fix has landed upstream. Huge media metadata after a
notification storm once crashed in `Qt::endPropertyUpdateGroup` while Silere kept `player.metadata` in a JS
variable, since Qt can free its watch on such a map in the middle of a grouped update; ci-lint's "reference
watch" rule keeps those maps out of variables.

## Preview and first login

```bash
bash dev/test-try.sh
bash dev/test-first-login.sh
```

The first runs `silere try` inside a virtual KWin, so no window reaches your desktop: the shell has to start, a
settings change in it must not reach the desktop's own files, and closing it must leave nothing behind. The
second takes the whole path a new user takes: Hyprland's own example config, the real installer on a throwaway
home, then a login. The bar has to come up with nobody starting it, the installed shortcut has to open the menu,
running the installer again must change nothing, and uninstalling has to leave the config clean. `dev/check.sh`
runs both when the compositors are installed.

## Measurements

`dev/bench-lab.sh` compares checkouts in a private nested session: startup, the latency of every panel, memory
over repeated menu opens, the optional settings, and a long soak.
[Performance](performance.md#measuring-a-whole-session) has the commands. It needs a GPU render node and is not
part of `dev/check.sh`.

## What CI runs

| Job | Coverage |
|---|---|
| Validate | Current Arch packages: structural checks, installer and updater fixtures, QML types, logic, UI stress, live settings and layout fit. |
| UI compatibility | Logic, UI stress and layout fit at 125% and 150% display scaling; each finishes even if the other fails. |
| Minimum Quickshell | Quickshell 0.3.2 built on a pinned Arch snapshot with Qt 6.10.2: QML types, logic and settings surfaces. |
| Compositor integration | Private KWin, Hyprland and niri sessions. KWin also checks output removal, tray keyboard navigation and audio changes. Without a GPU render node, niri checks panels and popups and Hyprland skips; see [compositor checks](#compositor-checks) to run the full probes yourself. |
| Distros | Debian sid and Fedora 43 containers with Quickshell installed as [the install guide](install.md#requirements) says, then the installer's dry run, `silere doctor` and the QML type-check. |

Validate gates releases and runs weekly against current Arch packages, so upstream changes show up between
releases; the pinned minimum job checks the supported floor. Distros runs on its own, weekly and when the
scripts or the install guide change, so a broken Debian or Fedora package never blocks a release. For workflow
changes, run `actionlint .github/workflows/*.yml`; CI requires actionlint and ShellCheck, and the local checks
say when either is missing.

## Diagnosing a CI failure

Open the failed job to find the failing probe. Its log artifact keeps the runtime versions and the build and test
logs for seven days, failures included, named by compositor or display scale and run attempt so reruns keep
their own. A new workflow needs a run on GitHub to prove its container setup and uploads; local lint checks only
its syntax.
