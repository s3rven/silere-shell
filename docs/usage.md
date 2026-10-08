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

Most controls use the pointer. The keyboard handles Escape, **Ctrl+F** in notification
history, and text fields. Controls also expose actions to accessibility tools.

| area | pointer |
|---|---|
| workspaces | **click** switches · on the active workspace, **click** opens the menu and **right-click** opens quick actions · **middle-click** sends the focused window there · **scroll** switches too, once you turn it on under Settings › Widgets › Workspaces |
| clock | **click** opens the calendar · **middle-click** cycles through adding seconds, the date, or both |
| calendar | **scroll** changes the month · **click** the header to jump back to today · **click** an adjacent-month date to open that month · choose week start and week numbers under Settings › Widgets › Clock |
| media | **click** plays or pauses · **scroll** changes track · **middle-click** jumps to the player · **right-click** opens Now Playing |
| volume | **scroll** changes volume · **click** mutes · **middle-click** moves to the next output · **right-click** opens pwvucontrol or pavucontrol · in the menu, expand it for output, input and per-app levels |
| microphone | **click** mutes · **scroll** changes the input level · **middle-click** moves to the next input · **right-click** opens pwvucontrol or pavucontrol · it appears while an app is listening |
| brightness | **scroll** changes brightness |
| updates | **click** opens package details in Settings › System › Overview · **right-click** rechecks for packages |
| shell update | **click** opens Settings › System › Overview |
| tray | **click** opens a menu-only app's menu, otherwise jumps to its window or activates it · **right-click** opens its menu, with Hide from bar at the end · **middle-click** runs the app's secondary action · **scroll** is passed through to the app |
| notifications | **click** runs the default action · **right-click** dismisses · **middle-click** jumps to the app that sent it · a reply action opens an inline text field when the sender supports one |
| wi-fi list | **click** joins a saved or open network, or opens a password field for a personal one; use the eye button to show or hide the password · **click** the connected network twice to disconnect · **right-click** or **middle-click** a saved network twice to forget it, unless you are connected to it |
| bluetooth list | **click** pairs or connects · **click** a connected device twice to disconnect · **right-click** or **middle-click** a paired device twice to forget it, unless it is connected |
| menu | **Escape** steps back, then closes · **click** anywhere outside to close |
| history | **type** in Search, or press **Ctrl+F** to get there, to find an app or message · **click** an app in the rail to show only its notifications · **click** an entry to read it in full · **Clear** removes what is shown, after a second click to confirm · **Escape** clears search, then closes |

## Settings

Open **Settings** in the menu. Changes apply immediately and are saved to
`~/.config/silere-shell/settings.json`, or the corresponding `$XDG_CONFIG_HOME` path.
The file stores only values changed from the defaults.

- **Appearance**: colours, opacity, blur, font, interface scale and reduced motion.
- **Bar**: position, width, widget placement, spacing and underline effects.
- **Widgets**: individual widget options, calendar, media and system indicators.
- **Feedback**: notification history, Do Not Disturb, the OSD and alerts.
- **System › Overview**: updates, diagnostics, repairs and restore defaults.

To reset one setting, delete its key from `settings.json`. To reset preferences together,
use Restore defaults in Overview; it keeps notification history and wallpaper colours.

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
