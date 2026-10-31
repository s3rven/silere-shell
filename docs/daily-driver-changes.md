# Daily-driver improvements

This implements the first steps from the [daily-driver review](daily-driver-review.md).
The existing install and settings keep working. External brightness and the keyboard
widget stay off until enabled.

## Keyboard controls

Use Tab and Shift+Tab to move between controls, Enter or Space to activate them,
and arrows to move through lists. Sliders accept arrows, Page Up/Down, Home/End,
and Shift+arrow for larger steps. Inline dropdowns accept Enter, arrows, then Enter
to choose. Escape still steps back or closes a popup. Focused controls have an
outline and scroll into view.
Dropdowns start at the current choice and keep the keyboard selection visible as
they expand. List arrows skip disabled and busy action rows; moving focus elsewhere
cancels a pending search through offscreen rows.

## Presentation privacy

Quick Actions, and Home under Do Not Disturb's options, have a **Presentation Mode** switch. It hides every app
notification popup, including critical notifications and cards already visible.
Ending it does not replay old cards. Battery and temperature warnings can still
use the shell's hardware OSD.

```bash
silere ipc quickActions presentation
silere ipc quickActions setPresentation true
silere ipc quickActions setPresentation false
```

The manual mode lasts for the running shell session. Automatic detection works on
Hyprland and on niri versions providing cast events, such as 26.04. Older niri
versions can use the manual switch. Settings shows whether automatic detection is
available. Notification urgency can bypass DND/fullscreen quieting, but cannot
bypass sharing privacy.

## Connectivity

Expand **VPN** in Home to connect or disconnect saved NetworkManager VPN,
WireGuard, and tunnel profiles. Profiles use UUIDs internally, so duplicate names
do not select a different connection. Multiple active profiles appear separately.
Credentials are handled by the session's NetworkManager secret agent. If a
connection needs additional credentials or setup, use **Network settings**.
The expanded list refreshes while visible to pick up changes made elsewhere;
closing it or going idle stops that polling. Actions also refresh the bar's VPN
indicator. A refresh requested during another read runs after it finishes.

The Wi-Fi list also offers an advanced editor for hidden SSIDs, enterprise Wi-Fi,
certificates, and IP/DNS settings. Install `nm-connection-editor`, or provide
`nmtui` for a terminal handoff. Terminal apps open through `xdg-terminal-exec`
when it is installed, otherwise in the first of kitty, foot, Ghostty, Alacritty,
WezTerm or Konsole found.

The Bluetooth list offers **Pair with a passkey** before a pairing fails. This
opens `blueman-manager` for PIN entry and confirmation; install Blueman to enable
it. Discovery and ordinary pairing remain available in Silere. This handoff uses
an existing pairing agent rather than adding a native BlueZ agent to the shell.

## Locking and sleep

The power menu has **Lock & sleep** when a lock command and a readable logind lock
state are available. It requests the configured locker, waits for `LockedHint=yes`,
then requests suspend. Failure or timeout cancels the suspend. The ordinary Sleep
action still delegates directly to the session.
Readiness updates after tool checks. Losing required tools during confirmation
cancels the action; a late reply cannot trigger suspend afterward.

Settings > Interface explains readiness. `loginctl` accepting a lock request alone
is not treated as confirmation. Configure an idle daemon for lid-close and other
sleep requests too. For example, hypridle can use:

```ini
general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    inhibit_sleep = 3
}
```

For niri with swayidle and swaylock, configure `swayidle -w` with a `before-sleep`
action that invokes `swaylock -f`. The readiness action and an external sleep hook
serve different entry points; configuring one does not configure the other.

## Text and external displays

Settings > Interface offers 125% and 150% UI sizing and any installed text font;
icons always use an installed Nerd Font. The larger sizes expand the menu and allow
labels to wrap. Existing display scaling, high contrast, and reduced motion remain
available.
Opening Interface rescans fonts, so newly installed ones appear there. A failed scan
says so and keeps the last usable font choices.

Enable **External brightness** in Interface to use optional `ddcutil` support.
Readable DDC/CI displays gain their own sliders in Home. Enable DDC/CI in the
monitor's own menu and grant the usual I2C permissions if detection fails. Each
display can be disabled independently, and opening Interface retries discovery.
Discovery runs on demand; there is no continuous DDC polling.

Writes are coalesced and bounded. A queued write carries the connector, bus, and
EDID identity; the helper rechecks the identity after reading the monitor and
before writing. Discovery and writes run in sequence so they do not compete for
the display bus. A refresh keeps pending slider values, and disabling brightness
discards late results from earlier requests. Laptop brightness continues to use
`brightnessctl`.

An optional **Keyboard** bar widget shows the input language and Caps Lock when
the keyboard exposes a readable LED. Click it to switch to the next configured
layout. The Caps Lock read pauses during quiet idle and is off with the widget.

## Optional crash recovery

Preview and install the user service:

```bash
silere service install --dry-run
silere service install
```

Then replace the existing compositor startup invocation with:

```bash
silere run --supervised --startup
```

Use one startup owner. Installation writes the service and reloads unit metadata;
it does not enable it or replace compositor config automatically. The supervised
launcher imports the current session environment and starts the service. It uses
`Restart=on-failure` with a delay and a rate limit. A graphical-session target
stops it when the session manager provides that lifecycle; the rate limit also
bounds retries after a lost compositor connection.
Starting a stopped service clears old session endpoints and imports the caller's
tool path and locale. A deliberate start also clears a previous crash rate limit;
starting an already active owner leaves its environment intact.

`silere service status` inspects it. `silere service remove` stops and removes a
generated unit belonging to this installation. Unmanaged units are preserved.

## Validation and measurement

CI now runs private KWin, Hyprland, and niri sessions, including popup interaction,
startup, and menu IPC. KWin also exercises output removal. A separate job builds
the pinned minimum Quickshell 0.3.1 source and runs QML and logic checks against it.
That job uses an archived package set with Qt 6.9.2, covering the documented Qt 6.9
floor without mixing an older Quickshell with an incompatible newer Qt.

Run the isolated session checks locally with:

```bash
bash dev/test-compositors.sh kwin
bash dev/test-compositors.sh hyprland
bash dev/test-compositors.sh niri
```

The runner needs `kwin_wayland` and `dbus-run-session`, plus the selected compositor.
It uses private runtime/config/state directories and a private D-Bus session. It
does not start niri with `--session` or change the live session's service environment.

To collect cold, warm, and repeated-menu samples:

```bash
bash dev/test-compositors.sh kwin --bench /tmp/silere-bench
```

These short software-rendered development samples are separate from release
benchmarks. Media playback, visualizer load, real multi-monitor frame pacing, and
physical sleep/DDC/pairing still need deliberate hardware validation.
