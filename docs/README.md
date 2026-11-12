# Silere documentation

Start with [installation](install.md) if Silere is new to your desktop, or
[troubleshooting](troubleshooting.md) if something is broken.

## Use

| I want to… | Read |
|---|---|
| Install, preview changes or enable crash recovery | [Installation](install.md) |
| Learn the controls and customise the bar | [Everyday use](usage.md) |
| Update Silere or restore the previous version | [Updates and recovery](updates.md) |
| Fix startup, notifications, fonts or graphics | [Troubleshooting](troubleshooting.md) |
| Add a keybind, change a setting from a script or use hooks | [Scripting](scripting.md) |
| Measure memory, CPU use or rendering | [Performance](performance.md) |
| See what changed | [Changelog](../CHANGELOG.md) and [past releases](releases/) |

## Work on Silere

| I want to… | Read |
|---|---|
| Change the code or build a fork | [Code guide](forking.md) and [contributing](../CONTRIBUTING.md) |
| Check layouts, display scaling or compositor compatibility | [Testing and CI](testing.md) |
| Prepare a release | [Release process](releasing.md) |

## Paths

Commands assume the installer linked `silere` into `~/.local/bin`. If the command
is missing, use `/path/to/silere-shell/scripts/silere` in its place. Run
`/path/to/silere-shell/scripts/silere link` to create the link; `~/.local/bin`
must also be on your `PATH`.

Settings live in `~/.config/silere-shell/settings.json`. Notification history
lives separately in `~/.local/state/silere-shell/notifications.json`.
Custom absolute `$XDG_CONFIG_HOME` and `$XDG_STATE_HOME` values change those roots.
Silere follows the [XDG directory rules](https://specifications.freedesktop.org/basedir/latest/).
