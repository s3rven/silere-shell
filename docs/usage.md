# Using Silere

Click the active workspace to open the menu. Right-click it for quick actions, or
click the clock for the calendar. Escape steps back through an open picker or search,
then closes the popup. Clicking outside also closes it.

The installer offers **Super + /** as a menu shortcut on Hyprland. For niri or a
Hyprland configuration written in Lua, it prints the line to add. You can also use:

```bash
silere ipc menu toggle
```

## Controls

Use **Tab / Shift+Tab** to move between controls, **Enter / Space** to activate them,
and arrows to navigate lists or adjust sliders. Sliders also accept Home/End and
Page Up/Down. **Ctrl+F** searches notification history and Settings. Escape steps
back or closes the popup. Controls expose the same actions to accessibility tools.

In an open dropdown, repeat an initial to cycle matches; Backspace corrects the search.
Keyboard focus expands a notification and pauses its timeout. **Delete** dismisses
the focused notification; it edits text normally while writing a reply.

| area | pointer |
|---|---|
| workspaces | **click** switches · on the active workspace, **click** opens the menu and **right-click** opens quick actions · **middle-click** sends the focused window there · **scroll** switches too, once you turn it on under Settings › Widgets › Workspaces |
| clock | **click** opens the calendar · **middle-click** cycles through adding seconds, the date, or both |
| calendar | **scroll** changes the month · **click** the header to jump back to today · **click** an adjacent-month date to open that month · choose week start, week numbers and today's weather under Settings › Widgets › Clock |
| window title | **hover** a title that is cut short to scroll through the rest · turn on the app icon under Settings › Widgets › Indicators |
| system monitor | optional, under Settings › Widgets › Indicators · shows CPU, memory and temperature, amber or red while one stays high · **click** opens Home, where **click** on CPU or Memory opens your system monitor app |
| media | **click** plays or pauses · **scroll** changes track · **middle-click** jumps to the player · **right-click** opens Now Playing |
| volume | **scroll** changes volume · **click** mutes · **middle-click** moves to the next output · **right-click** opens pwvucontrol or pavucontrol · in the menu, expand it for output, input and per-app levels |
| microphone | **click** mutes · **scroll** changes the input level · **middle-click** moves to the next input · **right-click** opens pwvucontrol or pavucontrol · it appears while an app is listening |
| brightness | **scroll** changes brightness |
| network / bluetooth | **click** opens Home for connection and radio controls |
| updates | **click** opens package details in Settings › System › Overview · **right-click** rechecks for packages |
| shell update | **click** opens Settings › System › Overview |
| tray | **click** opens a menu-only app's menu, otherwise jumps to its window or activates it · **right-click** opens its menu, with Hide from bar at the end · **middle-click** runs the app's secondary action · **scroll** is passed through to the app |
| notifications | **click** runs the default action · **right-click** or **drag sideways** dismisses · **middle-click** jumps to the app that sent it · a reply action opens an inline text field when the sender supports one · a new message from the same app and sender joins its card, which shows the last few earlier lines; **hover** shows them all |
| wi-fi list | **click** joins a saved or open network, or opens a password field for a personal one; use the eye button to show or hide the password · **click** the connected network twice to disconnect · **right-click** or **middle-click** a saved network twice to forget it, unless you are connected to it |
| vpn | appears in Connectivity while a VPN is up · **click** copies its IPv4 address, or IPv6 address on an IPv6-only tunnel |
| bluetooth list | **click** pairs or connects · **click** a connected device twice to disconnect · **right-click** or **middle-click** a paired device twice to forget it, unless it is connected |
| menu | **Escape** or the mouse **back** button steps back, then closes · **click** anywhere outside to close |
| history | **type** in Search, or press **Ctrl+F** to get there, to find an app or message · **click** an app in the rail to show only its notifications · **click** an entry to read it in full, **right-click** removes it, **middle-click** jumps to the app that sent it · **Clear** removes what is shown, after a second click to confirm · **Mute** beside it holds back the selected app's popups · **Escape** clears search, then closes |

Disconnect, forget and power confirmations expire after three seconds. A later
click starts a fresh confirmation.

In an open dropdown, type to jump to a row, and use Home, End, Page Up and Page Down to
move further. A Settings page you've changed shows a dot in the sidebar.

Drag the scrollbar at the right of a long menu page, history or dropdown list to
scroll through it. Hovering it makes the handle wider and easier to grab.

History search ignores case and accents: `cafe` finds `Café`. Words can match across
the sender, title and message. Selecting an app in the rail further narrows the results.

## Connections

Expand **VPN** in Home to connect or disconnect saved NetworkManager profiles.
Use **Network settings** in the Wi-Fi list for hidden networks, enterprise Wi-Fi
and IP/DNS configuration. This opens `nm-connection-editor`, or `nmtui` in a terminal.

For Bluetooth devices needing a PIN or confirmation, **Pair with a passkey** opens
`blueman-manager`. Install Blueman to enable that action.

## Settings

Open **Settings** in the menu. Most changes apply immediately and are saved to
`~/.config/silere-shell/settings.json`, or the corresponding `$XDG_CONFIG_HOME` path.
The file stores only values changed from the defaults.

Click the **search icon** beside the section heading, or press **Ctrl+F**, to expand
**Find a setting…** and find the section for a feature.
Try `font`, `history retention`, `night light`, or `reset defaults`; configuration
names such as `notifHistoryDays` also work. Click a result to open its section.
When exactly one section matches, Enter opens it. The clear-query button keeps
search open for another query; the close button folds it away. Hover the compact
icon to see its label and Ctrl+F shortcut.
Escape collapses search first, then closes the menu. Search resets when you leave Settings.

On a crowded bar, window and media titles shorten to leave room for controls.
**Compact widgets** and **Auto tighten** under **Bar › Spacing** control density.
The bar grows when larger text needs more height.

Empty workspaces use rings; filled dots have windows. With app icons enabled,
`+N` counts additional apps and an amber underline marks urgency. An arrow and
workspace number point to an urgent workspace outside the current page.

- **Appearance**: colours, opacity, blur, font, interface scale and reduced motion.
- **Bar**: position, width, widget placement, spacing and underline effects.
- **Widgets**: individual widget options, calendar, media and system indicators.
- **Feedback**: notification history, Do Not Disturb, the OSD and alerts.
- **System › Overview**: updates, diagnostics, repairs and restore defaults.

Under **Appearance › Interface › Screen lock**, choose an installed lock program
or **Custom command**. Enter the lock program and its arguments, then click **Save**
or press Enter. **Revert** or Escape discards your draft; leaving the page also
discards unsaved edits. Saving does not lock the screen.

Quote arguments that contain spaces, for example `swaylock --image "/home/me/Lock screen.png"`.
Custom commands run directly: use an absolute path instead of `~`, and use a script
if you need shell operators or environment variable expansion. An empty saved command
disables the lock action.

**Lock & sleep** waits for the session to confirm it is locked before suspending.
If locking fails or times out, sleep is cancelled. Configure your idle daemon's
lock-before-sleep action separately for lid-close and other suspend requests.

To reset one setting, delete its key from `settings.json`. To reset preferences together,
use Restore defaults in Overview; it keeps notification history and wallpaper colours.

On Hyprland and niri versions providing cast events, popups wait in history while
you share your screen or record it, and a red share mark sits beside the clock.
Hyprland ignores brief screenshot captures. Switch automatic quieting off with
**Hide while sharing screen** under **Feedback › Notifications**. **Presentation Mode**
in Quick Actions, and in Home under Do Not Disturb's options, hides notification content on every compositor, including
critical notifications and cards already on screen.

A muted app's notifications skip the popup and go straight to history, without counting
as missed. Critical ones follow **Let critical through**, as under Do Not Disturb. Unmute
an app from its history page or under **Feedback › Notifications › Muted apps**. Turn off
**Group conversations** there to give every message its own card again; history keeps
every message either way.

Under **Feedback › Notifications › History**, **Keep history for** can remove entries older
than a day, week, or month. **Until cleared** keeps the existing behavior, subject to
the history count limit. Shortening the period removes older history immediately;
active popups stay open. The period also applies when saved history is restored.

**Weather** under **Widgets › Clock** is off by default. When on, the calendar asks
[Open-Meteo](https://open-meteo.com/) for today's forecast as it opens, and reuses the
answer for 30 minutes; nothing runs in the background. It sends the coordinates of your
time zone's main city, rounded to about a kilometre, the same place Night Light follows.
Units follow your locale. Click the row to retry after a failure.

Under **Appearance › Interface**, enable **External brightness** to control DDC/CI
monitors with `ddcutil`. Enable DDC/CI in the monitor's own menu. Available displays
get brightness sliders in Home; opening Interface retries detection.

The optional **Keyboard** bar widget shows the input language and, when available,
Caps Lock. Click it to switch to the next configured layout.

[The scripting guide](scripting.md) lists IPC calls, setting names and event hooks.

## Updates

Open **Settings › System › Overview** to check for Silere releases. Review the release
notes, then press Install and Confirm. The updater verifies the release signature.

From a terminal, `silere update` checks for a release, `silere update --apply` installs
it, and `silere update --rollback` restores the previously installed version.
Restart with `silere restart` after an update if your shell is not managed by the
systemd user service.

The optional timer checks for Silere releases. Installation still needs confirmation.
The package badge counts system updates; use your package manager to install those.
Development checkouts are managed with Git. [More about updates](install.md#maintenance-command).
