# Changelog

Only work since the latest release is listed here. Completed notes move to
[`docs/releases`](docs/releases/) and stay linked at the bottom of this file.

Format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with entries
grouped by the part of the shell they touch once a section runs long. Versions follow
[Semantic Versioning](https://semver.org/) loosely while in `0.x`: minor versions
change features, patch versions fix them. The updater follows signed stable tags; the
settings file carries its own `__version` and migrates separately.

## [Unreleased]

### Added

- System Overview shows live device checks and can copy a diagnostic report without device names, addresses, or screen serials. `silere doctor --json` also works when the shell is stopped.
- Expand Battery in Home's system readings for health, stored energy, and charging or discharging power, including separate laptop batteries and UPS devices when UPower reports them.
- With Reveal values on hover off, the Bluetooth widget shows a connected device's charge beside its glyph, as volume and battery do. The glyph turns amber when that device drops below 20%.
- Battery details have a Charge limit switch on laptops where UPower can set one, such as Lenovo's conservation mode or ThinkPad charge thresholds. It shows a limit turned on in firmware or by another tool.
- Systems with multiple Bluetooth controllers can choose a controller for the session in the Bluetooth list or Settings › System › Devices.
- Compatible Bluetooth headsets offer Listening and Calls modes in Home's output choices. Volume controls pause during the change and recover if the headset or audio backend disappears.
- Bar visibility and popup placement follow a display across connector changes when its model and serial identify it uniquely. On Hyprland the serial comes from the compositor, since Quickshell reports none there.
- Supported keyboard lights get a discrete brightness slider in Home, including Off, with a light chooser under Settings › System › Devices that names each light when several are available.
- Notification history supports Enter or Down from search, arrows between messages, and Delete to remove the focused entry while keeping your place.
- Empty notification searches and app filters offer a button to clear the query or return to all notifications.
- Now Playing seeks in five-second increments with the arrow keys or scroll wheel, with larger steps on Shift+arrow or Page Up/Down. Dragging remains continuous.
- Click the brightness widget to open its slider in Home, with device choices on systems with multiple backlights.
- Click the battery widget to open Power Mode, or system readings when power profiles are unavailable.
- Hover the volume widget to see which output it controls alongside the volume.
- Bar shortcuts scroll their controls into view when Home is taller than the screen, and so do lists and battery details opened in Home itself.
- Reorder bar widgets from the keyboard in Show & order: Tab to a widget's grip and press Up or Down. Screen readers name each grip.
- Settings search still finds a setting through a typo or two swapped letters, such as "brigthness" or "worksapce".
- Press Delete twice on a saved Wi-Fi network or paired Bluetooth device to forget it, as right-click does.
- With weather on, Home's header shows today's temperature, and Show on bar under Widgets › Clock puts it beside the bar clock. The bar refreshes it every 30 minutes while you are active, and leaves it out while it can't; otherwise it is fetched only when the calendar or Home opens.
- Settings keeps one height and scrolls long pages instead of growing to the screen edge. It is a little wider, its navigation icons are larger, and each page names what it covers under its title.
- Right-click the network, Bluetooth or system monitor widget to open that subject's own app: nm-connection-editor or nmtui, blueman-manager, or your system monitor. The volume and microphone widgets already opened the mixer this way.
- In Now Playing, click the track's length to show the time left instead.
- With the audio visualizer on, Now Playing's seek wave swells and settles with the music.

### Changed

- Settings has a Devices page under System for displays, external brightness, keyboard lighting, the Bluetooth controller, and the screen lock and night light programs. Interface keeps text, scale and accessibility.
- The settings schema moves to 3 with nothing to convert, so a rollback to 1.6 keeps the display preferences and clock weather setting added since.
- Tray icons sit in cells padded like the bar's other icons, so the hover highlight frames each one and their spacing follows the widget gap. Apps that report themselves idle, as most do, are no longer dimmed.
- Tray menus widen to fit their longest entry, up to half again their usual width, and keep every label in one column when any entry has an icon or a check mark.
- A tray app's name on hover follows Reveal values on hover, as the clock's date and workspace names do.
- Show & order starts with the bar's widgets. Its drag hint and Reset button move below the last row, and Workspaces, the one widget without a switch, says it is always shown.

### Fixed

- The audio visualizer moves smoothly on every preset instead of flickering to its baseline between beats.
- The shell no longer restarts itself when Hyprland's events arrive a moment after a burst of focus changes.
- A reply you are typing on an older notification survives newer notifications arriving instead of being cleared.
- A VPN that connects after its request timed out, such as one waiting on a second factor, no longer keeps showing the failure.
- A Bluetooth device that fails to connect from Silere and then connects or pairs another way loses its failure mark.
- A sandboxed test shell no longer changes your brightness, Wi-Fi, Bluetooth or power mode. The preview's controls still act on your devices.
- Bluetooth controls recover when a hardware switch is released while the radio remains soft-blocked, and follow the selected controller on systems with multiple radios.
- An incomplete external-display brightness scan keeps the displays it already read usable and allows an immediate retry. A display that never answers DDC/CI is named in the warning and listed under Settings › System › Devices, where switching off its control ends the warning.
- On Quickshell 0.3.1, volume changes on a sound card's own outputs are no longer silently dropped; they go through `wpctl`, as Bluetooth volume already did.
- A click along a popup's far edge, such as the menu's Power button, no longer falls through and closes the popup on Hyprland 0.57.
- A tray submenu's background blur stays under the submenu after it slides open instead of sitting a few pixels to one side.
- A missing CPU temperature sensor's retry is no longer skipped for another minute when it lands while a scan is still running.
- A Bluetooth device whose name starts with a dash now gets its low-battery alert.
- `silere repair --undo` restores only a repair's own stash, never another stash whose message mentions silere-repair.
- Home no longer titles its card "Audio & Display" when every external display's brightness control is switched off.
- On niri with several monitors, a notification pulses its workspace only on the bar of the sender's monitor.
- An urgent workspace paged into view after another urgent one has settled still pulses.
- A window closed during a window-list refresh no longer comes back on the bar after many later windows close.
- Without `checkupdates`, updates found by paru or yay no longer count repository packages as AUR.
- Weather and Night Light's sunrise and sunset use your own time zone's city where the zone shares its clock with another country's: Europe/Stockholm, Europe/Oslo, Europe/Copenhagen and Europe/Amsterdam, among about a hundred, no longer get Berlin's or Brussels'.
- Closing the Bluetooth list in the instant it opens no longer leaves the adapter scanning for devices until the shell restarts.
- A long track title no longer stretches a player's row over several lines in Now Playing's Players list.
- In `silere try`, VPN connections and headset modes act on your real network and sound, as the preview's other network and sound controls do. Keyboard lighting and external brightness are hidden there instead of doing nothing.
- Memory or disk use sitting right at 75% or 90% no longer blinks the bar's system monitor and Home's readings between calm and warning on every update.
- The 12-hour clock no longer leaves a blank digit's space before 1 to 9 o'clock, so its margins match the rest of the bar.
- Older entries in notification history write AM and PM the same way as the bar and notification cards.
- A completely full disk reads Full in Home's system readings instead of losing its caption.
- Turning Reduce motion on or off while the menu is still resizing no longer logs a binding loop.
- The bar's window title no longer logs a binding loop as it closes, or stops a fraction of a pixel short of zero width.
- Tab, Shift+Tab, Up and Down in Show & order follow the order shown, not the default widget order, and the tray's app list opens from the keyboard.
- Show & order's switches and Reset button line up with the right edge every other settings page uses, and Now Playing no longer leaves extra space below its controls.
- Notification history shows the remove button on keyboard focus, and inactive rows and hidden media controls reject retained actions.
- A CPU holding at exactly 100% now triggers the sustained-load warning. The bar and Home share that warning across monitors, and separate spikes no longer add up to sustained load.
- A notification still sliding out when a newer one took the last visible place no longer disappears mid-exit and comes back later.
- The calendar takes keyboard focus the first time it opens, so Tab and the arrow keys work without a click.
- The whole height of the bar opens the calendar from the clock, like every other widget.
- `silere update --rollback` still works after the release it undoes was withdrawn upstream and a later check removed its tag.
- A shell that does not run as a service keeps its rollback until the updated shell is seen running, instead of losing it to the next daily check.
- An update stops instead of replacing an ignored file in the checkout, such as settings or notification history, if a release ever ships a file at the same path.
- Recovery from a silent Hyprland event socket restarts the service only while it is still running.
- Installing an update right after changing a setting no longer fails with "Settings could not be saved before the update" while the settings file is being read back.
- `silere reset` no longer starts a shell that was not running, or stops one it cannot bring back, because a service for the checkout is installed but stopped and disabled.
- An update keeps its rollback until this checkout's shell is seen running, even while a service for another checkout is up.
- The keyboard widget keeps showing your keyboard's layout while wtype, an emoji picker or remote input types, instead of "ER" or that tool's layout.
- The keyboard widget no longer falls back to an older layout read while you switched, and follows a layout changed by a Hyprland config reload.
- The keyboard widget labels every layout by its code, so Ukrainian reads UA and Estonian EE instead of UK and ES. English shows US or GB.
- A monitor plugged back in no longer shows its workspaces as if a special workspace were still open on it.
- The updates widget no longer counts AUR packages that pacman.conf's IgnorePkg holds back when paru checks the AUR.
- Brightness works on hybrid-graphics laptops in discrete GPU mode, and the GPU that isn't driving the screen is no longer offered as a brightness device.
- The brightness OSD no longer appears when an idle daemon dims the screen while you're away, or restores it as you come back.
- The calendar always shows six weeks, so changing the month no longer resizes it. With the bar at the bottom, that resize moved the arrows away from the pointer.
- The media title in the bar shows the same hover highlight as every other clickable widget.
- Notification history shows the icon a `notify-send -i` notification had in its popup, instead of the app's first letter.
- On Hyprland, clicking a notification goes to the window that sent it, not another window of the same app, and a button that opens the app brings its window forward. Both work with `focus_on_activate` off, Hyprland's default.
- Quick Actions' state chips follow Roundness like the rest of the menu.
- Tray, tray menu and workspace app icons are sharp at fractional scales. At 1.25 a theme icon was decoded at two and a half times its size and squeezed into place.
- Hovering a tray icon on the right of the bar no longer slides it out from under the pointer; its name grows to the left instead.

## Releases

- [1.6.0](docs/releases/1.6.0.md) — 2026-11-07
- [1.5.0](docs/releases/1.5.0.md) — 2026-11-03
- [1.4.4](docs/releases/1.4.4.md) — 2026-10-22
- [1.4.3](docs/releases/1.4.3.md) — 2026-10-18
- [1.4.2](docs/releases/1.4.2.md) — 2026-10-11
- [1.4.1](docs/releases/1.4.1.md) — 2026-10-10
- [1.4.0](docs/releases/1.4.0.md) — 2026-10-09
- [1.3.0](docs/releases/1.3.0.md) — 2026-10-05
- [1.2.0](docs/releases/1.2.0.md) — 2026-09-27
- [1.1.1](docs/releases/1.1.1.md) — 2026-09-17
- [1.1.0](docs/releases/1.1.0.md) — 2026-09-17
- [1.0.0](docs/releases/1.0.0.md) — 2026-09-07
- [0.9.0](docs/releases/0.9.0.md) — 2026-08-30
- [0.8.0](docs/releases/0.8.0.md) — 2026-08-22
- [0.7.0](docs/releases/0.7.0.md) — 2026-08-18
- [0.6.1](docs/releases/0.6.1.md) — 2026-08-16
- [0.6.0](docs/releases/0.6.0.md) — 2026-08-15
- [0.5.1](docs/releases/0.5.1.md) — 2026-08-13
- [0.5.0](docs/releases/0.5.0.md) — 2026-08-13
- [0.4.0](docs/releases/0.4.0.md) — 2026-08-12
- [0.3.0](docs/releases/0.3.0.md) — 2026-08-11
- [0.2.0](docs/releases/0.2.0.md) — 2026-08-10
- [0.1.0](docs/releases/0.1.0.md) — 2026-08-08
