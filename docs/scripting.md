# Scripting

[All docs](README.md) · [Everyday use](usage.md) · [Companions](companions.md)

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
| `silere osd <glyph> <text> [0-100]` | shows your own message in the OSD: with a level it draws the bar volume uses, without one it stays up as long as a battery alert. Nothing shows while the OSD is off or the session is idle |
| `silere indicator set <name> <glyph> [text]` | shows your own mark in the bar until `silere indicator clear <name>` or a restart; a script pushes it, nothing polls. Up to six, named in lowercase letters, digits and dashes |
| `silere theme <image>` | takes the accent from a picture and switches to the neutral theme, for a desktop without Matugen; a grey picture changes nothing |
| `silere get <key>`, `silere set <key> <value>` | reads or writes a setting; `on` and `off` work for true/false. A value that cannot be saved still applies until a restart, and the command fails saying why |
| `silere settings [filter]` | lists settings with the values each takes; `--changed` lists only the ones you changed |

`close` after `menu`, `calendar`, `quick` or `tray` only closes, for a keybind that dismisses without opening.
Each command is one of the IPC calls below and prints its answer. The shell must be running; when this copy is
not the one running, such as a checkout beside an installed copy, the commands use the one other Silere that is
running and say so on stderr. With none running they exit 1.

From 2.0, no 2.x release removes or renames a command, an IPC call or a hook on this page, or changes what their
arguments mean; new ones can be added.

## Keybinds on Hyprland

Every `silere` command that reaches the shell starts a Quickshell process, about 150 ms on a 2015 laptop. On
Hyprland the shell also answers two global shortcuts, which a bind reaches without starting anything:

```lua
hl.bind("SUPER + slash", hl.dsp.global("silere:menu"), { description = "Open or close the Silere menu" })
hl.bind("SUPER + SHIFT + slash", hl.dsp.global("silere:tray"), { description = "Open the first tray app's menu" })
```

In a `.conf` config the first is `bind = SUPER, slash, global, silere:menu`. Hyprland lists a Lua bind without
its arguments, so the description is how Settings › System › Keybinds tells which shortcut a bind reaches. Only
the shell `silere run` starts answers them, so a preview or a test copy never takes them over.

Settings › System › Keybinds also copies these and a few other commands (`silere quick`, `silere calendar`,
`silere toggle dnd`, `silere dismiss`) as a line for your config, Lua or `.conf`, on keys none of your binds
hold. Paste it and save; once Hyprland reloads, the page shows the keys it is on. On niri, the installer prints
a menu bind for your `binds` block, and other commands bind the same way with `spawn`.

## IPC calls

`silere ipc` alone lists every call the shell answers, and `silere ipc <target>` one target's calls. To reach a
checkout directly with Quickshell:

```bash
SILERE_DIR="$HOME/.config/silere-shell"
qs ipc -p "$SILERE_DIR/shell.qml" call menu toggle
qs ipc -p "$SILERE_DIR/shell.qml" show
```

A call that fails answers with a line starting `error:`, so a script can test for it. `silere ipc` and the short
commands print that line to stderr and exit 1, as they do when Quickshell finds no such target or function or
cannot use the arguments.

### Surfaces

| call | opens | short form |
|---|---|---|
| `menu toggle` | the menu | `silere menu` |
| `menu tab <n>` | the menu on `0` Home, `1` Settings, `2` Notifications or `3` Now Playing, while the media widget shows a track | `silere menu home` |
| `menu settings <name>` | Settings on one page, named as below | `silere menu <name>` |
| `calendar toggle` | the calendar | `silere calendar` |
| `quickActions toggle` | quick actions | `silere quick` |
| `tray toggle` | the first tray app's menu, on its first entry; Left and Right move to the other apps' menus | `silere tray` |

`menu`, `calendar`, `quickActions` and `tray` each take `close` as well as `toggle`. `screenshot flash` opens
nothing: it lets a screenshot tool trigger the underline's flash without the folder watcher.

### Quick actions

Everything on the quick actions panel also answers on its own, so a keybind can flip one without the panel.
`silere toggle <name>` reaches each by its plain name.

| call | does |
|---|---|
| `quickActions dnd` | turns Do Not Disturb on or off |
| `quickActions presentation` | toggles Presentation Mode for this session; it hides popups and keeps the screen awake |
| `quickActions setPresentation <true/false>` | sets Presentation Mode without toggling |
| `quickActions keepAwake` | holds off idle dimming, locking and sleep until called again or the shell restarts |
| `quickActions nightLight` | turns Night Light on or off |
| `quickActions powerMode` | steps to the next power profile |
| `quickActions wifi` | turns Wi-Fi on or off |
| `quickActions bluetooth` | turns Bluetooth on or off |
| `quickActions airplane` | drops both radios, then restores the ones that were on |

Each prints the state it left behind, or why it could not act: no Bluetooth adapter, a Wi-Fi radio blocked in
hardware, or no night light tool. `powerMode` prints the profile it asked for, since the daemon answers later.

### Audio

These control the default output and microphone, even with their widgets hidden.

```bash
silere volume up      # silere ipc audio volumeUp
silere volume mute    # silere ipc audio toggleMute
silere volume next    # silere ipc audio cycleOutput
silere volume 40      # silere ipc audio setVolume 40
silere mic mute       # silere ipc audio toggleMicMute
silere mic next       # silere ipc audio cycleInput
silere volume         # the output level, such as 40% or 40% (muted)
```

| call | does |
|---|---|
| `volumeUp` / `volumeDown` | moves output volume to the next 5% step |
| `setVolume <percent>` | requests an output level from 0 to 100 |
| `toggleMute` | mutes or unmutes the output |
| `cycleOutput` | requests the next output device |
| `micUp` / `micDown`, `setMicVolume <percent>`, `toggleMicMute`, `cycleInput` | the same for the microphone |
| `status` | prints JSON with `output` and `input` objects: `ready`, `name`, `volume`, `muted` |

Raising a muted level unmutes it, lowering it keeps it muted, and setting a positive level unmutes. `status`
reports the level before mute as a whole percentage, so a muted device can have a nonzero `volume`. Actions
return the requested percentage, mute state or device name. A missing device or a percentage outside 0 to 100
returns an `error:` reply. During a headset mode change, changes return `error: audio device is changing`
rather than landing on a temporary fallback device.

### Notifications

These act on the popups on screen, as `dunstctl` and `makoctl` do. Each card leaves as its close button or a
click would make it leave, and counts as dismissed by you.

| call | does | short form |
|---|---|---|
| `notifications dismiss` | dismisses the newest popup | `silere dismiss` |
| `notifications dismissAll` | dismisses every popup; history keeps them | `silere dismiss all` |
| `notifications invoke` | acts on the newest popup as a click would: its default action, or the window it came from | |
| `notifications status` | prints JSON with `shown`, `missed`, `dnd`, `silenced` and `newest`, the id of the card `dismiss` and `invoke` act on (0 with none up) | |

With no popup on screen the first three reply `no notification on screen`. In Hyprland:
`hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd("silere dismiss"))`.

### Settings

`settings` reads and writes any setting the Settings pages expose.

```bash
silere get osdTimeout          # silere ipc settings get osdTimeout
silere set osdTimeout 3000     # silere ipc settings set osdTimeout 3000
silere toggle reduceMotion     # silere ipc settings toggle reduceMotion
silere settings clock          # silere ipc settings list clock
silere settings --changed      # silere ipc settings modified
```

| call | does |
|---|---|
| `get <key>` | prints one value |
| `set <key> <value>` | writes it, and echoes the value that landed |
| `toggle <key>` | flips a true/false setting |
| `list <filter>` | prints each key with its range or the values it takes |
| `modified` | prints only what differs from the defaults |

A rejected write names the values the key accepts, and a true/false setting also takes `on`, `off`, `yes` and
`no`. The `list` filter matches a page name as well as a key, so `list clock` reaches `showSeconds`; through
`silere ipc` the filter is required, and `""` lists every key. `silere set dnd on` and `silere set dnd off`
switch Do Not Disturb without toggling it, and `silere get dnd` reads it.

### Settings page names

For `silere menu <name>`, `silere settings <name>` and their `menu settings` and `settings list` calls, use a
page's label as Settings shows it, or its id:

`theme`, `interface`, `surface`, `underline`, `separators`, `widgets`, `workspaces`, `clock`, `media`,
`indicators`, `popups`, `history`, `osd`, `warnings`, `updates`, `devices`, `keybinds`

Six ids differ from their labels:

| label | id |
|---|---|
| Layout | `surface` |
| Spacing | `separators` |
| Show & order | `widgets` |
| Notifications | `popups` |
| Alerts | `warnings` |
| Overview | `updates` |

`maintenance`, `diagnostics` and `system` also open System › Overview. Names match without case, spaces or
punctuation, so `show-order` works. An unknown one falls back to `theme`, so an out-of-date keybind still opens
Settings. `silere menu notifications` opens the menu's Notifications tab; the Settings page of that name is
`silere menu popups`.

### Diagnostics

`silere doctor --json` prints a versioned report with `runtime`, `availability`, `integration` and `devices`. The
first three are collected even while the shell is stopped. `integration` holds what to check first when Silere
does not start, in fixed words: `notifications` (who holds the notification name: `silere`, `quickshell`, a
known daemon such as `mako`, `other`, `none` or `unknown`), `autostart` (`compositor`, `service` or `none`) and
`conflicts` (known bars and notification daemons running or started by your compositor config). Live device
state needs a running shell, `qs`, `timeout` and Python 3; otherwise `devices` is `null`.

`silere ipc diagnostics status` prints the live `devices` snapshot directly; its schema version is 1. It holds
counts, state flags, screen size and scale, but no names, addresses, network names or screen serials. Neither
command changes anything.

## Notifications from scripts

A script that reports a changing value can update one card instead of stacking a new one on every run. Tag its
notifications the way dunst, mako and swaync expect:

```bash
notify-send -a volume -h string:x-canonical-private-synchronous:volume -h int:value:40 "Volume" "40%"
```

A new notification replaces the card from the same app with the same tag; `x-dunst-stack-tag` works too, and
`int:value:` adds a progress bar. While popups are held back, history keeps only the latest one.

## Hooks

Silere runs a program of your own when something happens. Put an executable file in
`~/.config/silere-shell/hooks/`, named for the event:

| hook | arguments |
| --- | --- |
| `battery-critical` | percentage |
| `dnd-changed` | `on` or `off` |
| `idle-changed` | `idle` after ten minutes without input (an app holding the screen awake pauses it), `active` on return |
| `media-changed` | `playing`, `paused` or `stopped`, then the title and artist |
| `network-changed` | `connected` or `disconnected`, then the connection's name |
| `notification` | app name, summary, `critical` or `normal` |
| `power-source-changed` | `battery` or `ac`, then the percentage |
| `theme-changed` | accent colour, passed when the applied palette settles |
| `update-available` | count |
| `workspace-changed` | workspace number, or the name of a named workspace |

The `-changed` hooks run when that state changes, never for the state Silere finds when it starts or rescans.
`media-changed` runs once for a new track's title and artist together, and `network-changed` also runs on a
switch from one network to another. `update-available` runs when the count rises, and only while
Settings › System › Overview tracks package updates. `notification` runs only for notifications that show a
popup, not for ones held back by Do Not Disturb, a fullscreen window, a call or turned-off popups.

```bash
mkdir -p ~/.config/silere-shell/hooks
cat > ~/.config/silere-shell/hooks/battery-critical <<'EOF'
#!/bin/sh
notify-send "Battery at $1%"
EOF
chmod +x ~/.config/silere-shell/hooks/battery-critical
```

Hooks are found at startup; `silere ipc hooks rescan` picks up a new one without a restart, and
`silere ipc hooks list` shows which are active. An event with no hook file costs nothing. Hook arguments can
carry text from any application on the session bus, so quote them (`"$1"`) and never pass them to `eval`.

### Limits

Hooks run at most 20 times a second and 4 at a time, and one still running after 30 seconds is stopped. A run
past the rate cap is dropped, not queued. While all four runners are busy, further events wait, and repeats of
the same event collapse to the latest one. A `battery-critical` crossing still runs during a flood, up to twice a
second. The shell exiting does not stop a running hook by itself; with `timeout` installed, the 30-second limit
still ends it.
