# Using Silere

[All docs](README.md) · [Installation](install.md) · [Companions](companions.md) · [Troubleshooting](troubleshooting.md)

## Open a panel

| Panel | How |
|---|---|
| Menu | Click the active workspace |
| Quick actions | Right-click the active workspace |
| Settings | Open the menu and choose Settings |
| Notification history | Right-click the clock, or open the menu and choose Notifications |
| Calendar | Click the clock |
| Now Playing | Right-click the media widget |
| Wi-Fi or Bluetooth list | Click its bar widget |

Clicking outside a popup closes it. On Hyprland the installer offers Super + / for the menu, bound to the
[`silere:menu`](scripting.md#keybinds-on-hyprland) global shortcut; on niri it prints the bind to add. Any
other keybind can run `silere menu`.

## The bar

| Widget | Click | Right-click | Middle-click | Scroll | Hover |
|---|---|---|---|---|---|
| Workspaces | Switch; on the active one, open the menu | Quick actions, on the marked workspace | Send the focused window there | Switch, once Scroll to switch is on | |
| Clock | Calendar | Notification history | Add seconds, the date, or both | | The date, while it is off |
| Window title | | | | | Scroll a title that is cut short |
| System monitor | System readings in Home | Your system monitor app | | | Busiest process and its ID, while the CPU is busy |
| Media | Play or pause | Now Playing | Jump to the player | Change track | |
| Network | Ethernet status or the Wi-Fi list | nm-connection-editor, or nmtui | | | Network, signal, VPN, problems, traffic |
| Bluetooth | Bluetooth list | blueman-manager | | | Connected device and its battery |
| Keyboard layout | Next layout on every keyboard | | | | Full layout name |
| Volume | Mute | pwvucontrol or pavucontrol | Next output | Volume | Level, and a low Bluetooth battery |
| Microphone | Mute | pwvucontrol or pavucontrol | Next input | Input level | Level, and the apps listening |
| Brightness | Brightness in Home | | | Every controllable display | |
| Battery | Power mode in Home, or the battery details where there are no power modes | | | | Time left or charging state |
| Script indicators | | | | | Shown only while a script has set one with `silere indicator set` |
| Package updates | Settings › System › Overview | Check again | | | Status, or why the last check failed |
| Shell update | Settings › System › Overview | | | | |
| Tray | The app's menu or window | Its menu, with Hide from bar | The app's secondary action | Passed to the app | App name, unless widgets are compact |

- Settings › Widgets › Show & order picks the widgets and their order. The window title, system monitor,
  Bluetooth, keyboard layout and package update widgets start off, and Settings › Widgets › Indicators sets what
  the first two show. The microphone appears while an app is listening; on a desktop the battery shows only
  while a wireless mouse or keyboard runs low, and names it.
- Hover a widget for the detail in the table's last column. With Reveal values on hover (Settings › Bar › Layout,
  on by default), plain readings such as the volume and battery percentages also wait for the pointer; turn it
  off to show them all the time. A detail stays open while the pointer moves along the same part of the bar, so
  the widgets beside it don't shift.
- Amber or red marks a problem: a system reading that stays high, or a Bluetooth device at 20% or less.
- Among the workspaces, rings are empty and dots have windows. Settings › Widgets › Workspaces adds app icons
  and numbers; with icons on, `+N` counts the extra apps and an amber underline marks a window that wants you. An
  arrow points to such a window on another page of workspaces, in the scratchpad, or on a monitor whose bar is
  off. On Hyprland, a submap you enter shows its name after the workspaces; click it to leave.
- A crowded bar shortens window and media titles first. Compact widgets and Auto tighten under
  Settings › Bar › Spacing set the density.

## Keyboard

| Keys | What they do |
|---|---|
| Tab, Shift+Tab | Move between controls |
| Enter, Space | Activate |
| Arrows | Move through lists, adjust sliders |
| Home, End, Page Up, Page Down | Jump further in lists and sliders |
| Ctrl+Tab, Ctrl+Shift+Tab | Next or previous menu page |
| Ctrl+F | Search notification history or Settings |
| Escape, or the mouse back button | Step back out of a picker or search, then close |
| Delete | Dismiss the focused notification |
| Letters in an open dropdown | Jump to a matching row; repeat the letter to cycle |

The bar never takes the keyboard, so tray menus open from a keybind: `silere tray` opens the first app's menu.
Right or Enter opens a submenu, Left or Escape leaves it, and Left and Right on the top level move between apps.
In Settings › Widgets › Show & order, Tab to a widget's ⋮ grip and press Up or Down to move it.

## Notifications

| On a popup | Result |
|---|---|
| Click | Run the default action |
| Right-click, or drag sideways | Dismiss |
| Middle-click | Jump to the sending app |
| Hover a grouped card | Show the earlier messages |

Messages from the same app and sender share one card; Group conversations, under
Settings › Feedback › Notifications, turns that off. A reply field appears when the sender supports replies.
Hovering or focusing a card pauses its timeout, and every timeout waits while a panel is open. A notification that arrives while you are away from the
keyboard and pointer waits for you to come back.

### History

| Action | Result |
|---|---|
| Type in Search, or press Ctrl+F | Find an app, title or message |
| Click an app in the sidebar | Show only that app, until the menu closes |
| Click an entry | Read it in full |
| Right-click an entry, or press Delete | Remove it |
| Middle-click an entry | Jump to the sending app |
| Click Clear twice | Remove the entries shown |
| Click Mute | Hold back that app's popups |

Search ignores case and accents (`cafe` finds `Café`), and Search all apps widens a search that found nothing in
one app. A notification repeated word for word keeps one row. Keep history for, under Settings › Feedback › History,
drops entries older than a day, a week or a month. When history is full, the app with the most entries loses its
oldest one first.

### Quieting notifications

| To | Use |
|---|---|
| Hold back one app | Mute on its history page. Its popups go straight to history. Unmute there or under Muted apps in Settings › Feedback › History. |
| Hold back everything | Do Not Disturb in Home or Quick actions, or `silere toggle dnd`. It can end after an hour or when quiet hours end, and Scheduled Do Not Disturb in Settings › Feedback › Notifications sets quiet hours. Let critical through decides whether critical ones still show. |
| Clear the popups at once | Clear all, shown with two or more popups, or `silere dismiss all`. History keeps them. |
| Hide content while presenting | Presentation Mode, in Quick actions or Do Not Disturb's options. It hides every notification's content, critical ones included, and keeps the screen awake until you turn it off. |
| Keep popups off a shared screen | On by default where the compositor reports screen sharing; a red mark sits beside the clock while you share. Hide while sharing screen turns it off. |
| Not be interrupted in a game or a call | On by default: popups wait in history while a window is fullscreen or an app is in a call. Hide in fullscreen and calls turns it off. |

When a notification arrives while popups are held back, the bell beside the clock takes the accent colour until
you open History.

## Home

### Connections

| Item | Actions |
|---|---|
| Wi-Fi network | Click a saved or open network to join; a personal one asks for its password |
| Connected Wi-Fi | Click twice to disconnect |
| Saved Wi-Fi | Right-click, middle-click or press Delete twice to forget |
| Bluetooth device | Click to pair or connect; click a connected one twice to disconnect |
| Paired Bluetooth device | Right-click, middle-click or press Delete twice to forget |
| Active VPN | Click its address to copy it |

A confirmation expires after three seconds. Disconnect a network or device before you forget it. Expand VPN to
connect a saved NetworkManager profile. Advanced network settings, at the top of the Wi-Fi list, opens
nm-connection-editor (or nmtui) for hidden networks, enterprise Wi-Fi and IP or DNS settings; an enterprise
network you haven't joined reads Set up and opens it too. Pair with a passkey opens blueman-manager for devices
that need a PIN, and Controller picks one of several Bluetooth adapters.

### Sound, light and power

| Control | How it works |
|---|---|
| Volume | Expand it for Output, Input and per-app volume. A Bluetooth headset gets Listening and Calls modes (needs `wpctl` and `pw-dump`). |
| Brightness | Expand it to pick one of several backlights, or set Brightness display under Settings › System › Devices. |
| External monitors | Turn on External brightness under Settings › System › Devices; it needs `ddcutil` and DDC/CI switched on in the monitor's menu. The bar's brightness widget then steps every enabled display from its own level, and Home has a slider for each. |
| Keyboard light | Appears when UPower exposes one. |
| CPU, memory and disk | The CPU row names the busiest process while the CPU is busy. Click any of the three to open your system monitor. |
| Battery | Click it for health, stored energy and power draw, per battery or UPS. |
| Charge limit | In the battery details when UPower supports it. Needs `busctl`; Lenovo's conservation mode needs UPower 1.90.10 or newer. |

None of these ask for administrator rights.

## Now Playing

Drag the slider to seek, or scroll on it or use the arrow keys for 5 seconds, Shift with an arrow or Page Up
and Page Down for 50 seconds, and Home or End for the start or end. Click the track length to show the time
left instead. With several players open, choose one under Players to keep it for the session, or Automatic to
follow playback.

A track you pause from the bar or Now Playing stays on the bar until you play again or step away; one paused
elsewhere folds away after 15 seconds. When Bluetooth or USB headphones disconnect or run flat, Silere pauses
the player instead of letting it carry on through the speakers; switching outputs yourself never pauses. Pause
when headphones disconnect, under Settings › Widgets › Media, turns that off. The headphone jack isn't covered.

The Audio visualizer under Settings › Widgets › Media needs Cava. If it fails, Media settings says so, and Retry
visualizer starts it again once Cava and PipeWire are fixed.

## Calendar and weather

Scroll, or press Page Up or Page Down, to change the month; Shift with a page key jumps a year. Home or a click
on the header returns to today, and a date from the next or previous month takes you there. On a short display,
scrolling moves through the calendar and forecast instead, and the arrow buttons change the month. Week start,
week numbers and weather are under Settings › Widgets › Clock.

Weather is off by default. When on, the calendar and Home fetch the forecast from
[Open-Meteo](https://open-meteo.com/) and reuse it for up to 30 minutes. Each request sends the coordinates of
your time zone's main city, rounded to about a kilometre. Show on bar adds the temperature beside the clock, and
the calendar shows the next twelve hours under today's reading. After a failed refresh the calendar shows the
previous reading, marked as old; click it to retry.

## Settings

Most changes apply at once. Only values that differ from the defaults are saved, in
`~/.config/silere-shell/settings.json`, and a dot beside a page marks one you changed. Edits to the file apply
when you save it. A value Silere can't use, or a key it doesn't know, stays at its default and is named in
`silere log`; Silere's next save drops it.

| Group | Page | Covers |
|---|---|---|
| Appearance | Theme | Colours, opacity, blur and shadows |
| | Interface | Text, scale and accessibility |
| Bar | Layout | Position, size, shape and hover |
| | Underline | Line and event glow |
| | Spacing | Gaps and dividers |
| Widgets | Show & order | Choose and reorder bar widgets |
| | Workspaces | Markers, labels and app icons |
| | Clock | Date, time, calendar and weather |
| | Media | Track details and visualizer |
| | Indicators | Window title, status and system |
| Feedback | Notifications | Popups and quiet hours |
| | History | Saved notifications and muted apps |
| | OSD | Volume and brightness feedback |
| | Alerts | Battery and temperature limits |
| System | Overview | Updates, diagnostics and recovery |
| | Devices | Displays, lighting, Bluetooth and programs |
| | Keybinds | Hyprland's shortcuts and what each does |

Ctrl+F, or the search icon beside the page title, finds a setting by its name, an everyday word (`zoom`,
`night light`) or its config key (`notifHistoryDays`), and copes with common typos. Enter opens the top result.
On a narrow display, Sections in the header opens the page list.

### Colours

Under Settings › Appearance › Theme, the source is Neutral, a dark theme with an accent you pick, or Wallpaper,
the palette Matugen writes from your wallpaper ([setup](install.md#matugen)). Neutral's Auto accent also takes
the wallpaper's accent. `silere theme <image>` sets the neutral accent from a picture instead.

### Displays

With more than one screen, Settings › System › Devices chooses which displays have a bar and where popups and
the OSD appear. A laptop's own screen is listed as the built-in display, any other by its model and connector,
as in `<model> · DP-2`. A display Silere can tell apart by model and serial keeps its choices across dock
changes; otherwise they stay with the connector.

### Screen lock

Under Settings › System › Devices, pick an installed lock program or Custom command, then press Enter or Save.
A custom command runs without a shell: quote arguments with spaces, use absolute paths instead of `~`, and use a
script for pipes or variables. An empty command turns the Lock action off. Lock & sleep suspends only after the
session reports it is locked; for a lid close, set your idle daemon to lock before sleep
([Companions](companions.md#lock-screen-and-idle)).

### Resetting

Delete a key from `settings.json` to reset one setting, or use Restore default settings in
Settings › System › Overview for all of them; Undo restore puts them back. Notification history and wallpaper
colours are kept. When the menu won't open, reset from a terminal:

```bash
silere reset                    # show what would change, change nothing
silere reset --apply            # settings, edited files, leftovers and caches, then restart
silere reset --apply --history  # also clear notification history (can't be undone)
silere reset --undo             # put back what the last reset replaced
```

A settings file that won't parse is saved aside, not discarded. A reset leaves hooks, the Matugen palette,
autostart and the service alone. To reset by hand, stop Silere, back up `settings.json`, replace its contents
with `{ "__version": 5 }` and start Silere again.

## Updates and diagnostics

Settings › System › Overview checks for releases, shows their notes and installs them; from a terminal,
`silere update` checks and `silere update --apply` installs ([updates and recovery](updates.md)). Device checks
in Overview show audio, lighting and radio state with fixes, and Copy diagnostic report collects versions, tools
and device states without names, addresses or serials. `silere doctor --json` prints the same report in a
terminal.
