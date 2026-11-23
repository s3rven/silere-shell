# Scripting

[All docs](README.md) · [Everyday use](usage.md)

Control a running shell from a terminal, a compositor keybind or a script:

```bash
silere menu                  # open or close the menu
silere toggle dnd            # Do Not Disturb on or off
silere volume 40             # output volume to 40%
silere set osdTimeout 3000   # change a setting
```

| command | does |
|---|---|
| `silere menu [page]` | opens or closes the menu; `home`, `settings`, `notifications` or `playing` opens it on that tab, and any other word on that [Settings page](#settings-page-names) |
| `silere calendar`, `silere quick`, `silere tray` | open or close the calendar, quick actions, or the first tray app's menu |
| `silere toggle <name>` | flips `dnd`, `wifi`, `bluetooth`, `airplane`, `night-light`, `keep-awake`, `presentation` or `power-mode` (to the next profile), or any true/false setting; alone, it lists the names |
| `silere volume [up\|down\|mute\|next\|0-100]` | steps, mutes or sets the output volume, or moves to the next output; alone, it prints the level |
| `silere mic [up\|down\|mute\|next\|0-100]` | the same for the microphone |
| `silere dismiss [all]` | dismisses the newest notification popup, or every one |
| `silere get <key>`, `silere set <key> <value>` | reads or writes a setting; `on` and `off` work for true/false |
| `silere settings [filter]` | lists settings with the values each takes; `--changed` lists only the ones you changed |

`close` after `menu`, `calendar`, `quick` or `tray` only closes, for a keybind that dismisses without opening.
Each command is one of the `silere ipc` calls below and prints its answer. `silere ipc` reaches every call the
shell answers, and alone it lists them. The shell must already be running.
When this copy is not the one running, such as a checkout beside an installed copy, these commands
use the single other Silere that is running and say so on stderr. With none running they exit 1.

To target a specific checkout directly with Quickshell, set `SILERE_DIR` to its path:

```bash
SILERE_DIR="$HOME/.config/silere-shell"
qs ipc -p "$SILERE_DIR/shell.qml" call menu toggle
qs ipc -p "$SILERE_DIR/shell.qml" show
```

### Keybinds on Hyprland

Every `silere` command that reaches the shell, like a `qs ipc` call, starts a Quickshell process, about 150 ms on
a 2015 laptop.
On Hyprland the shell also answers two global shortcuts, which a bind reaches without starting
anything:

```lua
hl.bind("SUPER + slash", hl.dsp.global("silere:menu"))   -- open or close the menu
hl.bind("SUPER + SHIFT + slash", hl.dsp.global("silere:tray"))  -- the first tray app's menu
```

In a `.conf` config the first is `bind = SUPER, slash, global, silere:menu`. Super + period is the emoji
picker in many setups, so the tray stays off it. Only the shell `silere run` starts answers them, so a preview
or a test copy never takes them over.

**Settings › System › Keybinds** copies these and a few other commands (`silere quick`, `silere calendar`,
`silere toggle dnd`, `silere dismiss`) as a line for your config, Lua or `.conf`, on keys none of your binds hold. Paste it and
save; once Hyprland reloads, the page shows the keys it is on.

## Surfaces

| call | opens | short form |
|---|---|---|
| `menu toggle` | the menu | `silere menu` |
| `menu tab <n>` | the menu on `0` Home, `1` Settings, `2` Notifications or `3` Now Playing when its tab is available | `silere menu home` |
| `menu settings <name>` | Settings on one page — names below | `silere menu <name>` |
| `calendar toggle` | the calendar | `silere calendar` |
| `quickActions toggle` | Do Not Disturb, Presentation Mode, keep awake, night light, power mode, Wi-Fi, Bluetooth and airplane mode | `silere quick` |
| `tray toggle` | the first tray app's menu, on its first entry; Left and Right move to the other apps' menus | `silere tray` |

`menu`, `calendar`, `quickActions` and `tray` each take `close` as well as `toggle`, for a keybind
that dismisses without opening anything.

`screenshot flash` opens nothing: it lets a screenshot tool trigger the underline effect
directly, without the optional filesystem watcher.

## Actions

Everything on the quick actions panel also answers on its own, so a keybind can flip one
without a panel appearing. `silere toggle <name>` reaches each one by its plain name: `dnd`, `presentation`,
`keep-awake`, `night-light`, `power-mode`, `wifi`, `bluetooth`, `airplane`.

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
silere toggle dnd
```

## Audio

These calls control the default output and microphone, even with their widgets hidden.

```bash
silere volume up      # silere ipc audio volumeUp
silere volume mute    # silere ipc audio toggleMute
silere volume next    # silere ipc audio cycleOutput
silere volume 40      # silere ipc audio setVolume 40
silere mic mute       # silere ipc audio toggleMicMute
silere volume         # the output level, such as 40% or 40% (muted)
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
`integration` and `devices`. Runtime, tool availability and integration are collected
even if the shell is stopped. `integration` holds what to check first when Silere does
not start, in fixed words: `notifications` (who holds the notification name: `silere`,
`quickshell`, a known daemon such as `mako`, `other`, `none` or `unknown`), `autostart`
(`compositor`, `service` or `none`) and `conflicts` (known bars and notification daemons
running or started by your compositor config). Live device state requires a running
compatible shell, `qs`, `timeout`, and Python 3; otherwise `devices` is `null`.

`silere ipc diagnostics status` prints the live `devices` snapshot directly.
Its schema version is 1. The report includes counts, state flags, screen size and
scale, but excludes names, addresses, network names, and screen serials. Neither
command changes device state.

## Settings

`settings` reads and writes any setting the Settings pages expose.

```bash
silere set osdTimeout 3000     # silere ipc settings set osdTimeout 3000
silere toggle reduceMotion     # silere ipc settings toggle reduceMotion
silere settings clock          # silere ipc settings list clock
silere settings                # silere ipc settings list ""
silere settings --changed      # silere ipc settings modified
```

| call | does |
|---|---|
| `get <key>` | prints one value |
| `set <key> <value>` | writes it, and echoes the value that landed |
| `toggle <key>` | flips a boolean |
| `list <filter>` | prints each key with its own range or vocabulary |
| `modified` | prints only what differs from the defaults |

A call that fails answers with a line starting `error:`, so a script can test for it;
`silere ipc` and the short commands print that line to stderr and exit 1, as it does when Quickshell finds no such target
or function or cannot use the arguments. `silere ipc <target>` lists one target's calls. A
rejected write also names the values the key accepts. The `list` filter matches a page name as well as a key, so
`list clock` reaches `showSeconds`. Through `silere ipc` the filter is required; pass `""` to list every
key at once. A true/false setting also takes `on`, `off`, `yes` and `no`.

`silere set dnd on` and `silere set dnd off` switch Do Not Disturb without toggling it, and `silere get dnd`
reads it.

### Settings page names

For `silere menu <name>`, `silere settings <name>` and their `menu settings` and `settings list` calls, use a
page's label as Settings shows it, or its id:

`theme`, `interface`, `surface`, `underline`, `separators`, `widgets`, `workspaces`,
`clock`, `media`, `indicators`, `popups`, `history`, `osd`, `warnings`, `updates`, `devices`, `keybinds`

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
back to `theme`, so an out-of-date keybind still opens Settings. `silere menu notifications` opens the menu's
Notifications tab; the Settings page of that name is `silere menu popups`.

## Notifications from the keyboard

The verbs `dunstctl` and `makoctl` give, for the popups on screen. Each card leaves as its close button or a click
would have it leave, and counts as dismissed by you.

```bash
silere dismiss
```

| call | does |
|---|---|
| `dismiss` | dismisses the newest popup (`silere dismiss`) |
| `dismissAll` | dismisses every popup; history keeps them (`silere dismiss all`) |
| `invoke` | acts on the newest popup as a click would: its default action, or the window it came from |
| `status` | prints JSON with `shown`, `missed`, `dnd` and `silenced` |

With no popup on screen the first three reply `no notification on screen`. Bound in Hyprland:

```lua
hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd("silere dismiss"))
```

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
| `theme-changed` | accent colour, passed when the applied palette settles |
| `update-available` | count |
| `workspace-changed` | workspace number, or the name of a named workspace |

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

Hooks are read at startup; `silere ipc hooks rescan` picks up a new one without a restart, and
`silere ipc hooks list` shows which are active. An event with no executable file costs nothing.

Hook arguments can contain text supplied by any application on the session bus. Quote
arguments such as `"$1"` in hook scripts and never pass them to `eval`.

### Limits

Hook runs are capped at 20 a second and 4 at a time, and one still running after 30 seconds
is terminated. Anything past the rate cap is dropped rather than queued. While all four
runners are busy, further events wait, and repeats of the same event collapse to the most
recent one. A `battery-critical` crossing still runs during a flood, up to 2 a second. The shell
exiting does not stop a running hook by itself; with `timeout` installed, the 30-second limit
still ends it.
