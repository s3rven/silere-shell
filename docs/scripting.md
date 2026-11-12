# Scripting

[All docs](README.md) · [Everyday use](usage.md)

Use `silere ipc` to control a running shell from a terminal, compositor keybind or script.
For example:

```bash
silere ipc menu toggle
silere ipc settings set osdTimeout 3000
silere ipc
```

The first opens or closes the menu, the second changes a setting, and the third lists
all available calls. The shell must already be running.
When this copy is not the one running, such as a checkout beside an installed copy, `silere ipc`
uses the single other Silere that is running and says so on stderr. With none running it exits 1.

To target a specific checkout directly with Quickshell, set `SILERE_DIR` to its path:

```bash
SILERE_DIR="$HOME/.config/silere-shell"
qs ipc -p "$SILERE_DIR/shell.qml" call menu toggle
qs ipc -p "$SILERE_DIR/shell.qml" show
```

## Surfaces

| call | opens |
|---|---|
| `menu toggle` | the menu |
| `menu tab <n>` | the menu on `0` Home, `1` Settings, `2` Notifications or `3` Now Playing (only while something plays) |
| `menu settings <name>` | Settings on one page — names below |
| `calendar toggle` | the calendar |
| `quickActions toggle` | Do Not Disturb, keep awake, night light, power mode, Wi-Fi, Bluetooth and airplane mode |
| `tray toggle` | the first tray app's menu, on its first entry; Left and Right move to the other apps' menus |

`menu`, `calendar`, `quickActions` and `tray` each take `close` as well as `toggle`, for a keybind
that dismisses without opening anything.

`screenshot flash` opens nothing: it lets a screenshot tool trigger the underline effect
directly, without the optional filesystem watcher.

## Actions

Everything on the quick actions panel also answers on its own, so a keybind can flip one
without a panel appearing.

| call | does |
|---|---|
| `quickActions dnd` | turns Do Not Disturb on or off |
| `quickActions presentation` | toggles Presentation Mode for this session; it hides popups and keeps the screen awake |
| `quickActions setPresentation <true/false>` | sets Presentation Mode without toggling |
| `quickActions keepAwake` | holds off idle dimming, locking and sleep until called again or the shell restarts |
| `quickActions nightLight` | turns night light on or off |
| `quickActions powerMode` | steps to the next power profile |
| `quickActions wifi` | turns Wi-Fi on or off |
| `quickActions bluetooth` | turns Bluetooth on or off |
| `quickActions airplane` | drops both radios, then restores the ones that were on |

Each prints the state it left behind, or says why it could not act — a machine with no
Bluetooth adapter, a Wi-Fi radio blocked in hardware, or a missing night light tool.
`powerMode` prints the profile it asked for, since the daemon answers afterwards.

```bash
silere ipc quickActions dnd
```

## Audio

These calls control the default output and microphone, even with their widgets hidden.

```bash
silere ipc audio volumeUp
silere ipc audio toggleMute
silere ipc audio cycleOutput
silere ipc audio setVolume 40
```

| call | does |
|---|---|
| `volumeUp` / `volumeDown` | moves output volume to the next 5% step |
| `setVolume <percent>` | requests an output level from 0 to 100 |
| `toggleMute` | mutes or unmutes the output |
| `cycleOutput` | requests the next output device |
| `micUp` / `micDown` | moves microphone volume to the next 5% step |
| `setMicVolume <percent>` | requests a microphone level from 0 to 100 |
| `toggleMicMute` | mutes or unmutes the microphone |
| `cycleInput` | requests the next input device |
| `status` | prints JSON with `output` and `input` objects: `ready`, `name`, `volume`, `muted` |

Increasing a muted level unmutes it; decreasing it preserves mute. Setting a
positive level also unmutes. `status` reports the level before mute, as an integer
percentage, so a muted device can have a nonzero `volume`.

Actions return the requested percentage, mute state or device name. Missing devices
and percentages outside 0–100 return `error:` replies and exit 1.
During a headset mode change, mutations return `error: audio device is changing`;
they are not queued onto a temporary fallback device.

## Diagnostic reports

`silere doctor --json` prints a versioned report with `runtime`, `availability`,
and `devices`. Runtime and tool availability are collected even if the shell is
stopped. Live device state requires a running compatible shell, `qs`, `timeout`,
and Python 3; otherwise `devices` is `null`.

`silere ipc diagnostics status` prints the live `devices` snapshot directly.
Its schema version is 1. The report includes counts, state flags, screen size and
scale, but excludes names, addresses, network names, and screen serials. Neither
command changes device state.

## Settings

`settings` reads and writes any setting the Settings pages expose.

```bash
silere ipc settings set osdTimeout 3000
silere ipc settings toggle reduceMotion
silere ipc settings list clock
silere ipc settings list ""
```

| call | does |
|---|---|
| `get <key>` | prints one value |
| `set <key> <value>` | writes it, and echoes the value that landed |
| `toggle <key>` | flips a boolean |
| `list <filter>` | prints each key with its own range or vocabulary |
| `modified` | prints only what differs from the defaults |

A call that fails answers with a line starting `error:`, so a script can test for it;
`silere ipc` prints that line to stderr and exits 1, as it does when Quickshell finds no such target
or function or cannot use the arguments. `silere ipc <target>` lists one target's calls. A
rejected write also names the values the key accepts. The `list` filter matches a page name as well as a key, so
`list clock` reaches `showSeconds`. The filter is required; pass `""` to list every key at
once.

`set dnd true` and `set dnd false` switch Do Not Disturb without toggling it, and `get dnd`
reads it.

### Settings page names

For `menu settings <name>` and `settings list <name>`, use a page's label as Settings shows
it, or its id:

`theme`, `interface`, `surface`, `underline`, `separators`, `widgets`, `workspaces`,
`clock`, `media`, `indicators`, `popups`, `osd`, `warnings`, `updates`, `devices`

Six ids differ from their labels:

| label | id |
|---|---|
| Layout | `surface` |
| Spacing | `separators` |
| Show & order | `widgets` |
| Notifications | `popups` |
| Alerts | `warnings` |
| Overview | `updates` |

System › Overview combines updates and diagnostics. The former `maintenance` id and
Diagnostics label still open this page; `system` works too.

Names match without case, spaces or punctuation, so `show-order` works. An unknown one falls
back to `theme`, so an out-of-date keybind still opens Settings.

## Notifications from scripts

A script that reports a changing value can update one card instead of stacking a new one on
every run. Tag its notifications the way dunst, mako and swaync expect:

```bash
notify-send -a volume -h string:x-canonical-private-synchronous:volume -h int:value:40 "Volume" "40%"
```

A new notification replaces the card from the same app with the same tag; `x-dunst-stack-tag`
works too, and `int:value:` adds a progress bar. While popups are silenced, history keeps only
the latest one.

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

`update-available` fires when the count rises, and only while Settings › System › Overview tracks package updates.
`notification` fires only for notifications that show a popup, not for ones silenced by
Do Not Disturb, a fullscreen window or turned-off popups.

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

Hook arguments can contain text supplied by any application on the session bus. Quote
arguments such as `"$1"` in hook scripts and never pass them to `eval`.

### Limits

Hook runs are capped at 20 a second and 4 at a time, and one still running after 30 seconds
is terminated. Anything past the rate cap is dropped rather than queued. While all four
runners are busy, further events wait, and repeats of the same event collapse to the most
recent one. A `battery-critical` crossing still runs during a flood, up to 2 a second. The shell
exiting does not stop a running hook by itself; with `timeout` installed, the 30-second limit
still ends it.
