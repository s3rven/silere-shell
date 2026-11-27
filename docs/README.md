# Silere documentation

Start with [installation](install.md) if Silere is new to your desktop, or [troubleshooting](troubleshooting.md)
if something is broken.

## Deciding

| I want to… | Read |
|---|---|
| See what Silere is and whether it fits | [The README](../README.md) |
| Pick a launcher, lock screen and wallpaper tool to go with it | [Companions](companions.md) |
| Know why some things are left out | [Decisions](decisions.md) |

## Using

| I want to… | Read |
|---|---|
| Install it, try it first, or turn on crash recovery | [Installation](install.md) |
| Learn the controls and set up the bar | [Everyday use](usage.md) |
| Choose where the bar and popups appear | [Displays](usage.md#displays) |
| Add a keybind, change a setting from a script or use hooks | [Scripting](scripting.md) |
| Update Silere or restore the previous version | [Updates and recovery](updates.md) |
| Fix startup, notifications, fonts or graphics | [Troubleshooting](troubleshooting.md) |
| Set up brightness for external monitors | [External brightness](troubleshooting.md#external-monitor-brightness-is-missing-or-does-not-respond) |
| See what changed | [Changelog](../CHANGELOG.md) and [past releases](releases/) |

## Working on Silere

| I want to… | Read |
|---|---|
| Make a first change | [Contributing](../CONTRIBUTING.md) |
| Find where things live and what a change touches | [Code guide](forking.md) |
| Understand how the shell starts and how its parts depend on each other | [Architecture](architecture.md) |
| Add another compositor | [Backend contract](forking.md#another-compositor) |
| Check layouts, display scaling or compositor compatibility | [Testing and CI](testing.md) |
| Measure memory, CPU use or rendering | [Performance](performance.md) and [its history](perf-history.md) |
| Prepare a release | [Release process](releasing.md) |

## Paths

Commands assume the installer linked `silere` into `~/.local/bin`. If the command is missing, use
`/path/to/silere-shell/scripts/silere` in its place, or run `/path/to/silere-shell/scripts/silere link` to create
the link; `~/.local/bin` must also be on your `PATH`.

Settings live in `~/.config/silere-shell/settings.json` and notification history in
`~/.local/state/silere-shell/notifications.json`. An absolute `$XDG_CONFIG_HOME` or `$XDG_STATE_HOME` moves those
roots, as the [XDG directory rules](https://specifications.freedesktop.org/basedir/latest/) say.
