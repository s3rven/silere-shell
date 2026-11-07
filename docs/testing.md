# Testing and compatibility

[All docs](README.md) · [Contributing](../CONTRIBUTING.md)

## Before submitting a change

Run the required checks from the checkout root:

```bash
bash scripts/test-qml-headless.sh
bash dev/test-logic.sh
bash dev/check.sh
```

The first checks QML types and imports, the second checks behaviour, and the last
runs structural, service, UI interaction and layout checks. Probes use private
configuration directories and isolated session buses when the required tools are
installed. A skipped probe leaves that part of the change unverified.

## Display scaling and layouts

Interface size and display scale affect different parts of the layout. The fit
probe exercises interface sizes from 100% through 150%. To check fractional display
scaling as well, run:

```bash
QT_SCALE_FACTOR=1.25 bash dev/test-logic.sh
QT_SCALE_FACTOR=1.25 bash dev/test-ui-stress.sh
QT_SCALE_FACTOR=1.25 FIT_REQUIRE_FONT=1 bash dev/test-layout-fit.sh
```

Repeat with `QT_SCALE_FACTOR=1.5` for 150% display scaling. The fit probe needs
JetBrainsMono Nerd Font so it measures the shipped text metrics.

For a longer interaction run, set `SILERE_UI_STRESS_CYCLES=360`. To save a rendered
preview, set `SILERE_UI_STRESS_CAPTURE=/tmp/silere-ui.png` on the stress command.

## Compositor checks

```bash
bash dev/test-compositors.sh hyprland
bash dev/test-compositors.sh niri
bash dev/test-compositors.sh kwin
```

These create private nested sessions. The runner needs KWin, `dbus-run-session`,
and the selected compositor. A nested shell you start by hand should set `SILERE_SANDBOX=1`, as these
runners do, so it never locks, suspends or ends your real session. Hyprland checks include an already-open special
workspace and named workspaces on a second output. KWin also provides a test host
for output removal and popup interactions.

Without a GPU render node, the niri runner checks panels and popup interactions,
then explicitly skips full shell startup. Read the skip message when assessing
coverage.

## Audio checks

```bash
bash dev/test-audio.sh
```

This starts its own PipeWire and WirePlumber with no hardware, only null sinks, on a private runtime
dir, state dir and bus, so your audio is never touched. Volume and mute changes have to reach the OSD,
a default device replaced under its own name has to stay usable, a lost device must not claim a mute,
and the shell has to come back when WirePlumber or PipeWire restarts, or when PipeWire starts after the
shell. It takes about ten seconds. `dev/check.sh` runs it when PipeWire and WirePlumber are installed.

## Fault injection

```bash
bash dev/test-faults.sh
```

This runs a whole shell in a private nested session and tries to break it. Every external
tool in turn hangs forever, fails, returns garbage or returns nothing, and then notifications,
a media player and a tray item send what no well-behaved app would: 5 MB bodies, 60,000
combining marks on one character, wrong types in every field, cover art urls that try to
run commands, thousands of signals a second. The shell has to stay up and responsive, throw no
script errors, keep `curl` to its https-only limits and leave no hung process behind.

It takes about two minutes and needs Hyprland, KWin and a GPU render node. Hostile input also
needs python-dbus and PyGObject. It is not part of `dev/check.sh`; run it before a release.

A few inputs still crash the shell, and Silere can't stop them from QML. `SILERE_FUZZ_KNOWN=1`
adds them, to see whether a fix has landed upstream:

- An `image-data` hint or a tray `IconPixmap` claiming a size larger than its data. Quickshell
  trusts the size. A config with no Silere code reproduces both.

Huge media metadata after a notification storm crashed in `Qt::endPropertyUpdateGroup` while Silere
kept `player.metadata` in a JS variable: Qt watches a map kept that way and can free the watch in the
middle of a grouped update. `dev/ci-lint.sh` ("reference watch") keeps those maps out of variables.

Quickshell restarts the shell within about a second after a crash, with notification history intact.

## Preview

```bash
bash dev/test-try.sh
```

Runs `silere try` inside a virtual KWin, so no window reaches your desktop. The shell has to start,
a settings change in it must not reach the desktop's own files, and stopping it or closing its
window has to leave nothing behind. `dev/check.sh` runs it when the compositors are installed.

## First login

```bash
bash dev/test-first-login.sh
```

The whole path a new user takes: Hyprland's own example config, the real installer on a throwaway home,
then a login. The bar has to come up with nobody starting it, the installed shortcut has to open the menu,
running the installer again must change nothing, and uninstalling has to leave the config clean.
`dev/check.sh` runs it when the compositors are installed.

## Measurements

`dev/bench-lab.sh` compares checkouts in a private nested session: startup, the latency of every panel, memory
over repeated menu opens, the optional service settings, and a long soak.
[Performance](performance.md#measuring-a-whole-session) has the commands. It needs a GPU render node and is not
part of `dev/check.sh`.

## What CI runs

| Job | Coverage |
|---|---|
| Validate | Current Arch packages; structural checks, installer and updater fixtures, QML types, logic, UI stress, live settings and layout fit. |
| UI compatibility | Logic, UI stress and layout fit at 125% and 150% display scaling. Both variants finish independently if one fails. |
| Minimum Quickshell | Quickshell 0.3.1 on a pinned Arch snapshot with Qt 6.10.2; QML types, logic and settings surfaces. |
| Compositor integration | Private KWin, Hyprland and niri sessions, plus output removal under KWin. |

The same workflow gates releases and runs weekly against current Arch packages.
The pinned minimum job checks the supported floor; the rolling jobs help detect
upstream compatibility changes.

For workflow changes, run `actionlint .github/workflows/*.yml`. CI requires
actionlint and ShellCheck; local checks report when an optional tool is absent.

## Diagnosing a CI failure

Open the failed job to find the failing probe. Its log artifact keeps runtime
versions and the available build or test logs for seven days, including on failure.
Artifact names include the compositor or display scale and the run attempt, so
matrix jobs and reruns keep separate results.

The workflow captures probe output with `tee` under Bash's `pipefail`; saving a log
preserves the failing exit status. A new workflow needs a GitHub run to verify its
container setup and artifact uploads; local lint checks its syntax and action inputs.
