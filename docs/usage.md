# Using Silere

[All docs](README.md) · [Installation](install.md) · [Troubleshooting](troubleshooting.md)

## Open a panel

| Panel | Action |
|---|---|
| Main menu | Click the active workspace |
| Settings | Open the menu and choose **Settings** |
| Notification history | Open the menu and choose **Notifications** |
| Quick actions | Right-click the active workspace |
| Calendar | Click the clock |
| Now Playing | Right-click the media widget |
| Wi-Fi or Bluetooth list | Click its bar widget (reveals the power switch while the radio is off) |

Clicking outside a popup closes it. The installer offers **Super + /** for the menu on Hyprland, bound to the
[`silere:menu`](scripting.md#keybinds-on-hyprland) global shortcut, and prints the line to add on niri. Any
other keybind can run `silere menu`.

## The bar

| Widget | Click | Right-click | Middle-click | Scroll | Hover |
|---|---|---|---|---|---|
| Workspaces | Switch; on the active one, open the menu | Open Quick Actions on the marked workspace | Send the focused window there | Switch (turn on in Widgets › Workspaces) | |
| Clock | Calendar | | Add seconds, the date, or both | | The date, while it is off |
| Window title | | | | | Scroll a title that is cut short |
| System monitor | Home | Your system monitor app | | | Busiest process and its ID, while the CPU is busy |
| Media | Play or pause | Now Playing | Jump to the player | Change track | |
| Network | Ethernet status or Wi-Fi list | nm-connection-editor, or nmtui | | | Network, signal, VPN, problems, traffic |
| Bluetooth | Bluetooth list | blueman-manager | | | Connected device and its battery |
| Keyboard layout | Next layout on every keyboard | | | | Full layout name |
| Volume | Mute | pwvucontrol or pavucontrol | Next output | Volume | Volume level and low Bluetooth battery |
| Microphone | Mute | pwvucontrol or pavucontrol | Next input | Input level | Input level and listening apps |
| Brightness | Brightness sliders in Home | | | Step all controllable displays | |
| Battery | Power Mode in Home | | | | Time left or charging state; on a desktop it shows only while a receiver battery is low |
| Updates | Package details | Check again | | | Status, and the error of a failed check |
| Shell update | Settings › System › Overview | | | | |
| Tray | Open the app's menu or window | Its menu, with Hide from bar | The app's secondary action | Passed to the app | App name, unless widgets are compact |

- **Optional widgets:** the system monitor and the window title's app icon are under **Settings › Widgets › Indicators**, where the monitor's **Style** can draw each reading as a ring around its icon. The microphone appears while an app is listening.
- **Warnings in amber:** the system monitor turns amber or red while a reading stays high. Bluetooth charge at 20% or less turns the Bluetooth glyph amber while one device is connected, and the volume glyph for headphones it plays through when the Bluetooth widget doesn't show their charge.
- **Workspaces:** rings are empty workspaces and dots have windows. In **Settings › Widgets › Workspaces**, enable **Show app icons**. Turn on **Numbers** to show them alongside the icons. Choose **Line** to keep both visible on the active workspace. With icons on, `+N` counts the extra apps and an amber underline marks urgency. An arrow points to an urgent workspace on another page. On Hyprland, a submap you enter shows its name after the workspaces on the focused monitor; click it to leave.
- **Hover:** a widget shows the table's last column when the pointer rests on it. **Reveal values on hover** under **Bar › Layout**, on by default, also keeps plain readings such as the volume and battery percentages hidden until then; off, they show all the time. A detail stays open while the pointer moves on over the same part of the bar (left, centre or right), so the widgets beside it don't slide as you move along. It folds when the pointer rests on another widget, a moment after you leave that part of the bar, or when a menu opened from it closes.
- **Crowded bar:** window and media titles shorten first. **Compact widgets** and **Auto tighten** under **Bar › Spacing** set the density, and the bar grows when larger text needs it.
- **Reduced motion:** hover a shortened window or media title to read its ending without scrolling it.

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

Focus on a notification expands it and pauses its timeout, and every timeout waits while a panel is open. In **Settings › Widgets › Show & order**,
Tab to a widget's ⋮ grip and press Up or Down to move it.

On narrow displays, **Sections** in the Settings header opens the category list over the page.
Pick a section to return to the controls, or press Escape to close the list where you are.

The bar never takes the keyboard, so tray menus open from a keybind: `silere tray`
opens the first app's menu. Right or Enter opens a submenu, Left or Escape leaves it, and Left
and Right on the top level move between apps.

## Notifications

| On a popup | Result |
|---|---|
| Click | Run the default action |
| Right-click, or drag sideways | Dismiss |
| Middle-click | Jump to the sending app |
| Hover a grouped card | Show the earlier messages |

Messages from the same app and sender share one card. Turn this off with **Group conversations**
under **Feedback › Notifications**. A reply field appears when the sender supports replies.

### History

| Action | Result |
|---|---|
| Type in Search, or press Ctrl+F | Find an app, title or message |
| Click an app in the sidebar | Show only that app, until the menu closes |
| Open **Apps** beside search on a narrow display | Choose an app filter without resizing the message list |
| Click an entry | Read it in full |
| Right-click an entry, or press Delete | Remove it |
| Middle-click an entry | Jump to the sending app |
| Click Clear twice | Remove the entries shown |
| Click Mute | Hold back that app's popups |
| Up, Down | Move between entries and back to Search |

- Search ignores case and accents (`cafe` finds `Café`) and matches across sender, title and message.
- If a search in one app finds nothing, **Search all apps** keeps your query and searches the full history.
- A notification repeated word for word keeps one row, dated by its latest arrival.
- **Keep history for**, under **Feedback › History**, removes entries older than a day, week or month. **Until cleared** keeps them up to the history limit.
- When history is full, the app with the most entries loses its oldest one first, so one busy chat can't push the rest out.

### Quieting notifications

| To | Use |
|---|---|
| Hold back one app | **Mute** on its history page. Its popups go straight to history. Unmute there or under **Feedback › History › Muted apps**. |
| Hold back everything | **Do Not Disturb** in Home. Its options end it after an hour or at the end of quiet hours, and **Scheduled do not disturb** under **Feedback › Notifications** turns it on between the hours you choose. **Let critical through** decides about critical ones, for muted apps too. |
| Hide content while presenting | **Presentation Mode**, in Quick Actions or under Do Not Disturb's options. It hides notification content, critical ones and cards already on screen included, and keeps the screen awake until you turn it off. |
| Keep popups off a shared screen | On by default where Hyprland or niri send cast events. A red mark sits beside the clock while you share. Turn off with **Hide while sharing screen** under **Feedback › Notifications**. |

When a notification arrives while popups are held back, the bell beside the clock takes the accent colour and stays
until you open History, with a badge once popups are back, as after a fullscreen game.

## Home

### Connections

| Item | Actions |
|---|---|
| Wi-Fi network | Click a saved or open network to join. A personal network asks for its password. |
| Connected Wi-Fi | Click twice to disconnect |
| Saved Wi-Fi | Right-click, middle-click or press Delete twice to forget |
| Bluetooth device | Click to pair or connect; click a connected one twice to disconnect |
| Paired Bluetooth device | Right-click, middle-click or press Delete twice to forget |
| Active VPN | Click its address to copy it |

Confirmations expire after three seconds. Disconnect before forgetting a connected network or
device.

- **VPN:** expand it to connect saved NetworkManager profiles.
- **Advanced network settings**, at the top of the Wi-Fi list, opens `nm-connection-editor` (or `nmtui`) for hidden networks,
  enterprise Wi-Fi and IP or DNS settings. An enterprise network you haven't joined, such as eduroam, reads **Set up** and opens it too.
- **Pair with a passkey** opens `blueman-manager` for devices that need a PIN.
- **Controller** above the device list picks one of several Bluetooth adapters for this session.

### Sound, light and power

| Control | How it works |
|---|---|
| Output device | Expand Volume and choose **Output**. A Bluetooth headset gets **Listening** and **Calls** profiles (needs `wpctl` and `pw-dump`). |
| Several backlights | Expand the brightness slider, or set **Brightness display** under **Settings › System › Devices** |
| External monitors | Turn on **External brightness** under **Settings › System › Devices**. Needs `ddcutil` and DDC/CI switched on in the monitor's menu. Scrolling the bar's brightness widget adjusts each enabled display from its current level. On a laptop, Home's brightness arrow shows a slider for each one; on a desktop each has its own row. |
| Keyboard light | Appears when UPower exposes one. Its steps follow the hardware. |
| CPU row | Names the busiest process while the CPU is busy. Click to open your system monitor. |
| Battery | Click it in the system readings for health, stored energy and power draw, per battery or UPS |
| Charge limit | In the battery details when UPower supports it. Needs `busctl`; Lenovo needs UPower 1.90.10 or newer. |

None of these ask for administrator rights.

## Now Playing

| To seek | Use |
|---|---|
| Anywhere | Drag the slider |
| 5 seconds | Scroll on the slider, or the arrow keys |
| 50 seconds | Shift+arrow, or Page Up and Page Down |
| Start or end | Home, End |

Click the track length to show the time left instead. With several players open, choose one under
**Players** to pin it for the session. Choose **Automatic** to follow playback again.
If you pause playback in Now Playing, the page stays open after the bar hides the track.

The **Audio visualizer** under **Settings › Widgets › Media** uses Cava's PipeWire input.
The media widget keeps its playback progress line while Cava starts or if it fails. If a failure
appears in Media settings, use **Retry visualizer** after checking Cava and PipeWire.

When Bluetooth or USB headphones disconnect or run flat during playback, Silere pauses the player
instead of letting it carry on through the speakers. Switching outputs yourself never pauses.
Turn this off with **Pause when headphones disconnect** under **Settings › Widgets › Media**. The
headphone jack isn't covered.

## Calendar and weather

In the calendar, scroll or press **Page Up** or **Page Down** to change the month. Hold **Shift**
with either page key to jump a year. Press **Home** or click the header to return to today.
On short displays, scrolling moves through the calendar and forecast. Use the arrow buttons or
page keys to change the month there.
Click a date from the previous or next month to go there. An open calendar follows the date into
the next month if it was showing the current one. Week start, week numbers and weather are under
**Settings › Widgets › Clock**.

**Weather** is off by default. When on, the calendar and Home fetch today's forecast from
[Open-Meteo](https://open-meteo.com/) and reuse it for up to 30 minutes. Each refresh looks up the
current time zone's main city and sends coordinates rounded to about a kilometre. **Show on bar**
adds the temperature beside the clock. **Units** offers Auto, Celsius and Fahrenheit. With Auto, a
metric locale uses Celsius, and a US locale uses Fahrenheit where the forecast city uses it.
The calendar shows the next twelve hours under today's reading, three hours apart, from the same request.
After a failed refresh the calendar shows the previous reading, marked as old; click it to retry.

## Settings

Most changes apply at once. Only values that differ from the defaults are saved, in
`~/.config/silere-shell/settings.json`. A dot beside a page marks one you've changed.
Edits to the file apply as you save it. A value Silere can't use, or a key it doesn't know, stays at
its default and is named in `silere log`; Silere's next save drops it.

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
| | Keybinds | Hyprland's shortcuts and what each does, with a filter |

**Ctrl+F**, or the search icon beside the page title, finds a setting by its name, an everyday
word (`zoom`, `night light`) or its config key (`notifHistoryDays`). Exact keys work regardless
of case. Search also handles common typos such as `brigthness`. Enter opens the top result.

### Displays

With more than one screen, **Settings › System › Devices** chooses where popups and the OSD
appear and which displays have a bar. A laptop's own screen is listed as Built-in display, any other
by its model and connector, such as `DELL U2723QE · DP-2`. A display identified by model and serial
keeps its choices across dock changes; otherwise they stay with the connector.

### Screen lock

Under **Settings › System › Devices**, pick an installed lock program or **Custom command**, then
press Enter or **Save**.

- Custom commands run without a shell: quote arguments with spaces, use absolute paths instead of `~`, and use a script for pipes or variables.
- An empty command disables the lock action.
- **Lock & sleep** suspends only after the session reports it is locked. Set your idle daemon's own lock-before-sleep for lid close.

### Resetting

Delete a key from `settings.json` to reset one setting, or use **Restore default settings** in
**Settings › System › Overview** for all of them. **Undo restore** puts them back. Notification
history and wallpaper colours are kept.

When the menu won't open, reset from a terminal:

```bash
silere reset                    # show what would change, change nothing
silere reset --apply            # settings, edited files, leftovers and caches, then restart
silere reset --apply --history  # also clear notification history (can't be undone)
silere reset --undo             # put back what the last reset replaced
```

A terminal reset saves its settings and edited files together. If you also restored defaults
from Settings, the terminal undo restores its own backup first. A second undo can restore the
saved settings from the GUI. Git keeps the terminal reset's stash as a recovery copy.

A settings file that won't parse is saved, not discarded. Hooks, the Matugen palette, autostart
and the service are left alone. To reset by hand, stop Silere, back up `settings.json`, replace
its contents with `{ "__version": 5 }` and start Silere again.

[The scripting guide](scripting.md) lists IPC calls, setting names and hooks.

## Updates and diagnostics

**Settings › System › Overview** checks for releases, shows the notes and installs them. From a
terminal, `silere update` checks and `silere update --apply` installs. See
[updates and recovery](updates.md) for rollback and automatic checks.

**Device checks** in Overview show audio, lighting and radio state with fixes. **Copy diagnostic
report** collects versions, tools and device states, without names, addresses or serials.
`silere doctor --json` prints the same report in a terminal.
