# Scripting

Every surface is scriptable over Quickshell IPC, so compositor keybinds and scripts can
open them without simulating a click. Set `SILERE_DIR` to the path the installer printed.

```bash
SILERE_DIR="$HOME/.config/silere-shell"
qs ipc -p "$SILERE_DIR/shell.qml" call menu toggle
```

Run `qs ipc -p "$SILERE_DIR/shell.qml" show` for the current list.

## Surfaces

| call | opens |
|---|---|
| `menu toggle` | the menu |
| `menu tab <n>` | the menu on `0` Home, `1` Settings or `2` Recent |
| `menu settings <name>` | Settings on one page — names below |
| `calendar toggle` | the calendar |
| `quickActions toggle` | Do Not Disturb, night light, power mode and airplane mode |

`menu`, `calendar` and `quickActions` each take `close` as well as `toggle`, for a keybind
that dismisses without opening anything.

`screenshot flash` opens nothing: it lets a screenshot tool trigger the underline effect
directly, without the optional filesystem watcher.

## Actions

Everything on the quick actions panel also answers on its own, so a keybind can flip one
without a panel appearing.

| call | does |
|---|---|
| `quickActions dnd` | turns Do Not Disturb on or off |
| `quickActions nightLight` | turns night light on or off |
| `quickActions powerMode` | steps to the next power profile |
| `quickActions wifi` | turns Wi-Fi on or off |
| `quickActions bluetooth` | turns Bluetooth on or off |
| `quickActions airplane` | drops both radios, then restores the ones that were on |

Each prints the state it left behind, or says why it could not act — a machine with no
Bluetooth adapter, a Wi-Fi radio blocked in hardware, or a missing night light tool.
`powerMode` prints the profile it asked for, since the daemon answers afterwards.

```bash
qs ipc -p "$SILERE_DIR/shell.qml" call quickActions dnd
```

## Settings

`settings` reads and writes any setting the Settings pages expose.

```bash
qs ipc -p "$SILERE_DIR/shell.qml" call settings set osdTimeout 3000
qs ipc -p "$SILERE_DIR/shell.qml" call settings toggle reduceMotion
qs ipc -p "$SILERE_DIR/shell.qml" call settings list clock
qs ipc -p "$SILERE_DIR/shell.qml" call settings list ""
```

| call | does |
|---|---|
| `get <key>` | prints one value |
| `set <key> <value>` | writes it, and echoes the value that landed |
| `toggle <key>` | flips a boolean |
| `list <filter>` | prints each key with its own range or vocabulary |
| `modified` | prints only what differs from the defaults |

A rejected write names the values the key accepts. The `list` filter matches a section name
as well as a key, so `list clock` reaches `showSeconds`. The filter is required; pass `""` to
list every key at once.

### Settings section names

For `menu settings <name>`:

`theme`, `interface`, `surface`, `underline`, `separators`, `widgets`, `workspaces`,
`clock`, `media`, `indicators`, `popups`, `osd`, `warnings`, `updates`, `maintenance`

Names match without case. An unknown one falls back to `theme`, so an out-of-date keybind
still opens Settings.

## Hooks

Silere runs a command of your own when something happens. Drop an executable file in
`~/.config/silere-shell/hooks/`, named for the event:

| hook | arguments |
| --- | --- |
| `battery-critical` | percentage |
| `notification` | app name, summary, `critical` or `normal` |
| `theme-changed` | accent colour |
| `update-available` | count |
| `workspace-changed` | workspace id |

```bash
mkdir -p ~/.config/silere-shell/hooks
cat > ~/.config/silere-shell/hooks/battery-critical <<'EOF'
#!/bin/sh
notify-send "Battery at $1%"
EOF
chmod +x ~/.config/silere-shell/hooks/battery-critical
```

Hooks are read at startup; `qs ipc -p "$SILERE_DIR/shell.qml" call hooks rescan` picks up a
new one without a restart, and `hooks list` shows which are active. An event with no
executable file costs nothing.

### Limits

Hook runs are capped at 20 a second and 4 at a time, and one still running after 30 seconds
is terminated. Anything past the rate cap is dropped rather than queued. While all four
runners are busy, further events wait, and repeats of the same event collapse to the most
recent one. Hooks are children of the shell, so they stop when it does.
