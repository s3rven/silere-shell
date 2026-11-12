# Using Silere

[All docs](README.md) · [Installation](install.md) · [Troubleshooting](troubleshooting.md)

## Open a panel

| Panel | Action |
|---|---|
| Main menu | Click the active workspace. |
| Quick actions | Right-click the active workspace. |
| Calendar | Click the clock. |
| Now Playing | Right-click the media widget. |
| Wi-Fi or Bluetooth list | Click its bar widget; when the radio is off, this opens Home. |

Clicking outside a popup closes it. The installer offers **Super + /** as a menu shortcut
on Hyprland and prints the line to add on niri; any keybind can run `silere ipc menu toggle`.

## Keyboard

Use **Tab / Shift+Tab** to move between controls, **Enter / Space** to activate them,
and arrows to navigate lists or adjust sliders. Sliders also accept Home/End and
Page Up/Down. **Ctrl+Tab / Ctrl+Shift+Tab** move between the menu's pages, and **Ctrl+F**
searches notification history and Settings. Escape steps back through an open picker or
search, then closes the popup; the mouse back button does the same in the menu. Controls
expose the same actions to accessibility tools.

In an open dropdown, type to jump to a row, repeat an initial to cycle matches, and use
Backspace to correct the search. Home, End, Page Up and Page Down move further through the list.
Drag the scrollbar on long pages and lists; hovering it makes the handle wider.

Keyboard focus expands a notification and pauses its timeout. **Delete** dismisses the
focused notification, and edits text normally while you write a reply.

In Settings › Show & order, Tab to a widget's ⋮ grip and press Up or Down to move it
along the bar, into the next zone past either end.

The bar itself never takes the keyboard, so tray menus open from a keybind:
`silere ipc tray toggle` opens the first tray app's menu on its first entry. Right or Enter
opens a submenu, Left or Escape steps back out of one, and on the menu's own level Left and
Right move to the next app's menu.

## The bar

| Area | Pointer controls |
|---|---|
| workspaces | **click** switches · on the active workspace, **click** opens the menu and **right-click** opens quick actions · **middle-click** sends the focused window there · **scroll** switches too, once you turn it on under Settings › Widgets › Workspaces |
| clock | **click** opens the calendar · **middle-click** cycles through adding seconds, the date, or both |
| calendar | **scroll** changes the month · **click** the header to jump back to today · **click** an adjacent-month date to open that month · choose week start, week numbers and today's weather under Settings › Widgets › Clock |
| window title | **hover** a title that is cut short to scroll through the rest · turn on the app icon under Settings › Widgets › Indicators |
| system monitor | optional, under Settings › Widgets › Indicators · shows CPU, memory and temperature, amber or red while one stays high · **click** opens Home, where **click** on CPU or Memory opens your system monitor app · **right-click** opens that app directly |
| media | **click** plays or pauses · **scroll** changes track · **middle-click** jumps to the player · **right-click** opens Now Playing |
| network | **hover** shows the network and signal, an active VPN, a connection problem, and traffic while data flows · **click** opens the Wi-Fi list in Home, or Home when Wi-Fi is off · **right-click** opens nm-connection-editor, or nmtui in a terminal |
| bluetooth | **hover** shows the connected device and its battery, or how many are connected · with **Reveal values on hover** off, one device's charge sits beside its glyph, which turns amber below 20% · **click** opens the Bluetooth list in Home, or Home when Bluetooth is off · **right-click** opens blueman-manager |
| keyboard layout | **hover** shows the full layout name · **click** switches every keyboard to the next layout · CAPS appears while Caps Lock is on |
| volume | **hover** shows the active output · **scroll** changes volume · **click** mutes · **middle-click** moves to the next output · **right-click** opens pwvucontrol or pavucontrol · in the menu, expand it for output, input and per-app levels |
| microphone | **click** mutes · **scroll** changes the input level · **middle-click** moves to the next input · **right-click** opens pwvucontrol or pavucontrol · it appears while an app is listening |
| brightness | **scroll** changes brightness · **click** opens its slider in Home, with the device choices when more than one backlight drives a screen |
| battery | **hover** shows the time remaining or charging status · **click** opens Power Mode in Home, or system readings when power profiles are unavailable |
| updates | **click** opens package details in Settings › System › Overview · **right-click** rechecks for packages |
| shell update | **click** opens Settings › System › Overview |
| tray | **hover** names the app while **Reveal values on hover** is on · **click** opens a menu-only app's menu, otherwise jumps to its window or activates it · **right-click** opens its menu, with Hide from bar at the end · **middle-click** runs the app's secondary action · **scroll** is passed through to the app |

Empty workspaces use rings; filled dots have windows. With app icons enabled, `+N`
counts additional apps and an amber underline marks urgency. An arrow and workspace
number point to an urgent workspace outside the current page.

On a crowded bar, window and media titles shorten to leave room for controls.
**Compact widgets** and **Auto tighten** under **Bar › Spacing** control density, and
the bar grows when larger text needs more height.

## Notifications

On a popup, **click** runs the default action, **right-click** or **drag sideways**
dismisses, and **middle-click** jumps to the sending app. A reply action opens a text
field when the sender supports it. Messages from the same app and sender join one
card; **hover** shows the earlier lines. Turn off **Group conversations** under
**Feedback › Notifications** to give every message its own card again.

### History

| Action | Result |
|---|---|
| Type in Search, or press Ctrl+F | Find an app, title or message. |
| Click an app in the sidebar | Show only that app's notifications. |
| Click an entry | Read it in full. |
| Right-click an entry | Remove it from history. |
| Middle-click an entry | Jump to the sending app. |
| Click Clear twice | Remove the entries currently shown. |
| Click Mute | Hold back the selected app's popups. |
| Press Escape | Clear search, then close. |
| Press Enter or Down in Search | Focus the first matching notification. |
| Press Up or Down on a notification | Move between entries; Up from the first returns to Search. |
| Press Delete on a notification | Remove it and keep focus on the next entry, or the preceding entry at the end. |

Search ignores case and accents, so `cafe` finds `Café`, and its words can match across
the sender, title and message. Selecting an app in the rail narrows the results further.
With no results, **Clear search** keeps the field ready for another query, and an empty
app filter offers **Show all notifications**.

History keeps every message, grouped or not. A notification the same app repeats word
for word keeps one row, dated by its latest arrival. **Keep history for**, under
**Feedback › Notifications › History**, removes entries older than a day, week or month;
**Until cleared** keeps them, subject to the history count limit. Shortening the period
removes older entries at once and also applies when saved history is restored; popups
already on screen stay open.

### Quieting notifications

A muted app's notifications skip the popup and go straight to history, without counting
as missed. Critical ones follow **Let critical through**, as under Do Not Disturb. Unmute
an app from its history page or under **Feedback › Notifications › Muted apps**.

On Hyprland and niri versions that send cast events, popups wait in history while you
share or record your screen, and a red share mark sits beside the clock. Hyprland ignores
brief screenshot captures. Switch this off with **Hide while sharing screen** under
**Feedback › Notifications**.

**Presentation Mode**, in Quick Actions and under Do Not Disturb's options in Home, hides
notification content on every compositor, critical notifications and cards already on
screen included, and keeps the screen awake until you turn it off.

While popups are held back, the bell beside the clock takes the accent colour once one arrives.

## Home

### Connections

| Connection | Actions |
|---|---|
| Wi-Fi | Click a saved or open network to join. A personal network opens a password field; the eye button shows or hides the password. |
| Connected Wi-Fi | Click twice to disconnect. |
| Saved Wi-Fi | Right-click, middle-click or press Delete twice to forget it; disconnect first if it is connected. |
| Bluetooth | Click to pair or connect; click a connected device twice to disconnect. |
| Paired Bluetooth | Right-click, middle-click or press Delete twice to forget it; disconnect first if it is connected. |
| Active VPN | Click its address to copy IPv4, or IPv6 on an IPv6-only tunnel. |

Disconnect, forget and power confirmations expire after three seconds.

Expand **VPN** to connect or disconnect saved NetworkManager profiles. **Network settings**
in the Wi-Fi list opens `nm-connection-editor`, or `nmtui` in a terminal, for hidden
networks, enterprise Wi-Fi and IP/DNS configuration.

For Bluetooth devices needing a PIN or confirmation, **Pair with a passkey** opens
`blueman-manager`. Install Blueman to enable that action.

With several Bluetooth controllers, choose **Controller** above the device list or under
**Settings › System › Devices**. The choice lasts for this session; **Automatic** follows
the system default, and removing the selected controller falls back to an available one.

### Sound

Expand Volume and select **Output** to change the output device. A Bluetooth headset that
offers both profiles gets **Listening** for playback and **Calls** for its microphone; this
needs `wpctl` and `pw-dump`. Volume controls pause while the headset changes modes, and an
error restores them and offers sound settings.

### Brightness and lighting

On a laptop with several backlights, expand Home's brightness slider to choose the display
it controls. **Brightness display** under **Settings › System › Devices** is the same choice.

Turn on **External brightness** under **Settings › System › Devices** to control DDC/CI
monitors with `ddcutil`. Enable DDC/CI in the monitor's own menu first. Each display it finds
gets a slider in Home, and opening Devices retries the detection. A display that never answers
is named in the warning; switch off its control there to end the warning.

Home also shows **Keyboard light** when UPower exposes a controllable keyboard backlight.
Its steps follow the hardware, **Off** included. With several lights, choose one under
**Settings › System › Devices**. Changes use UPower's normal permissions; Silere does not
request administrative access.

### Battery

Click **Battery** in Home's system readings for battery health, stored energy, and power
use or charging power. With several batteries or a UPS, each is listed with its own charge,
and readings UPower cannot supply stay hidden.

Where UPower can limit charging, the details also show **Charge limit**. Turned on, the
battery stops short of full to slow its wear, and the row says where it stops when the
laptop reports that. It needs `busctl`, and Lenovo's conservation mode needs UPower 1.90.10
or newer. The switch also shows a limit set in firmware or by another tool.

## Now Playing

Drag the playback slider to seek precisely. After resting the pointer on it, scroll to
seek in five-second steps; the arrow keys do the same when it has keyboard focus.
Shift+arrow or Page Up/Down seeks 50 seconds, and Home/End jumps to the start or end.
Seeking works when the player supports it.

Click the track's length at the right of the slider to count down the time left instead,
and click again for the length. With the audio visualizer on, the slider's wave swells
with the music. With several players open, pick the one to control under **Players**.

## Calendar and weather

**Weather** under **Widgets › Clock** is off by default. When on, the calendar and Home ask
[Open-Meteo](https://open-meteo.com/) for today's forecast as they open and reuse the answer
for 30 minutes. It sends the coordinates of your time zone's main city, rounded to about a
kilometre, the place Night Light follows, and units follow your locale. Click the calendar
row to retry after a failure.

**Show on bar** puts the temperature beside the clock and refreshes it every 30 minutes
while you are active. While a refresh fails, the bar and Home leave the old reading out;
the calendar still shows it, marked as the previous reading.

## Settings

Open **Settings** in the menu. Most changes apply immediately and are saved to
`~/.config/silere-shell/settings.json`, or the corresponding `$XDG_CONFIG_HOME` path.
The file stores only values that differ from the defaults, and a dot beside a page
means that page has changes.

| Group | Pages |
|---|---|
| Appearance | **Theme** for colours, opacity, blur and shadows; **Interface** for text, scale and accessibility |
| Bar | **Layout**, **Underline** and **Spacing** |
| Widgets | **Show & order**, then each widget's own options |
| Feedback | **Notifications**, the **OSD** and **Alerts** |
| System | **Overview** for updates, diagnostics and recovery; **Devices** for displays, lighting, Bluetooth and the programs Silere runs |

Press **Ctrl+F**, or click the search icon beside the page title, to find a setting. It
matches each row's name, everyday words such as `zoom` or `night light`, configuration
names such as `notifHistoryDays`, and a typo such as `brigthness`. Enter opens the top
result, Up and Down walk the others, and Escape closes search before the menu. Search
resets when you leave Settings.

### Displays and docking

With more than one screen, **Settings › System › Devices** chooses where popups and the
OSD appear and turns the bar on or off per display. These choices follow a display across
dock connector changes when its model and serial identify it uniquely; otherwise they stay
with the connector.

### Screen lock

Under **Settings › System › Devices**, choose an installed lock program or **Custom command**,
then enter the program and its arguments and press Enter or **Save**. **Revert**, Escape or
leaving the page discards the draft, and saving does not lock the screen.

Custom commands run directly, without a shell: quote arguments that contain spaces, as in
`swaylock --image "/home/me/Lock screen.png"`, use an absolute path instead of `~`, and use
a script for shell operators or variables. An empty saved command disables the lock action.

**Lock & sleep** suspends only once the session confirms it is locked, and cancels sleep if
locking fails or times out. Set your idle daemon's lock-before-sleep action separately for
lid-close and other suspend requests.

### Resetting

To reset one setting, delete its key from `settings.json`. To reset them all, use
**Restore defaults** in Overview. It covers every setting, Do Not Disturb and night light
included, and keeps notification history and wallpaper colours. **Undo restore**, right
below it, puts them back.

When the menu won't open, or you want more than settings back to normal:

```bash
silere reset                    # shows what it would change, and changes nothing
silere reset --apply            # settings, edited files, leftovers and caches, then a restart
silere reset --apply --history  # also clears notification history; this part can't be undone
silere reset --undo             # puts back what the last reset replaced
```

It saves a settings file that won't parse rather than discarding it, and writes through a link
if you keep `settings.json` in a dotfiles repo. Hooks, the Matugen palette, autostart and the
service stay as they are. To do it by hand, stop Silere, back up `settings.json`, replace its
contents with `{ "__version": 3 }`, then start Silere again.

[The scripting guide](scripting.md) lists IPC calls, setting names and event hooks.

## Updates and diagnostics

Use **Settings › System › Overview** to check for Silere releases, review the notes
and confirm installation. From a terminal, `silere update` checks and
`silere update --apply` installs. See [updates and recovery](updates.md) for rollback,
automatic checks, local edits and development checkouts.

Overview's **Device checks** show audio, lighting and radio state with recovery actions.
**Copy diagnostic report** collects runtime versions, tool availability, and device counts
and states, without device names, addresses, network names or screen serials.
`silere doctor --json` prints the same report in a terminal; its device state is `null`
when no compatible shell is running or the optional Python parser is missing.
