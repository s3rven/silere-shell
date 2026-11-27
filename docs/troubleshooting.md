# Troubleshooting

[All docs](README.md) · [Installation](install.md) · [Updates and recovery](updates.md)

Start here:

```bash
silere doctor
```

It reports the runtime, the optional tools, the font, which program owns notifications, and whether Silere starts
at login, from the compositor config or a systemd user unit. It changes nothing.

`silere log --follow` prints the running shell's log as it grows. To watch a fresh start, run `silere stop`, then
`silere run` in a terminal; stop Silere before you launch another `qs -p` instance. `silere run` hides the
warnings Quickshell logs when a media player or tray app fails to answer a property read; set
`QT_LOGGING_RULES=` (empty) before it to see them.

| Problem | Start here |
|---|---|
| No bar after login | [Nothing appears](#it-installed-but-nothing-appears) |
| Crashes after a package update | [Qt and Quickshell](#it-stopped-working-after-a-system-update) |
| A widget or control is missing | [Missing widgets](#a-widget-or-control-is-missing) |
| No notifications | [Another daemon](#notifications-never-appear) |
| Boxes instead of icons | [Fonts](#icons-or-text-use-the-wrong-font) |
| External monitor brightness | [DDC/CI](#external-monitor-brightness-is-missing-or-does-not-respond) |
| A failed Silere update | [Rollback](#the-shell-does-not-come-back-after-an-update) |

## Starting and updating

### The silere command is not found

Run `~/.config/silere-shell/scripts/silere doctor`, with your checkout's path if you installed elsewhere. To
create the command, run the same script with `link` instead of `doctor`, and make sure `~/.local/bin` is on your
`PATH`.

### It installed but nothing appears

Silere runs on Hyprland and niri only. There, the cause is nearly always the autostart line. Run
`~/.config/silere-shell/scripts/silere run`; if the bar comes up, run the installer again or add the line to your
compositor's startup yourself. Use the full path, since the compositor's `PATH` often lacks `~/.local/bin`:

```lua
-- ~/.config/hypr/hyprland.lua
hl.on("hyprland.start", function()
    hl.exec_cmd("$HOME/.config/silere-shell/scripts/silere run --startup")
end)
```

On niri it is `spawn-at-startup "sh" "-c" "$HOME/.config/silere-shell/scripts/silere run --startup"`.

### It stopped working after a system update

Quickshell builds against Qt's private API, so a Qt update can leave it unable to run. Reinstall or rebuild
Quickshell against the new Qt; `silere doctor` reports this under Quickshell.

Silere is your notification daemon, so it cannot report its own failure to start. If the shell is not up 20
seconds after login, Hyprland shows a message pointing at `silere doctor`. niri has no equivalent, so there the
message appears only if another notification daemon can show it.

### The shell does not come back after an update

From a terminal, `silere update --rollback` restores the previous release, and restarts the shell when a systemd
user unit runs it; otherwise run `silere restart` afterwards. See [updates and recovery](updates.md).

### A menu page or panel says it couldn't load

Panels load from disk the first time they open, so files that changed under a running shell (a package upgrade,
a `git pull`, a local edit) can fail against the version still running. Press Reload on the page, click the
"A Silere panel could not load" notification, or run `silere restart`. If it fails again, `silere log` shows the
error.

### A shell update is blocked by local edits

`silere repair` previews the edited files. `silere repair --apply` saves the edits in a Git stash and restores the
shipped files, and `silere repair --undo` brings the latest saved edits back. `silere reset` goes further:
settings, edited files, leftovers and caches at once, with `silere reset --undo` to put them back.

## Display and speed

### The desktop feels slow on a high refresh panel

Without VRR, a frame that misses a refresh waits for the next one, so a frame that takes just over 4.17 ms at
240 Hz drops the whole desktop to 120. An integrated GPU can then stay in its lowest clock, because at half rate
it looks idle. Stop other apps redrawing to check, and try VRR. A background job can do the same: Steam's shader
pre-caching (`fossilize_replay`) runs on every core even at idle priority. Fewer blur passes rarely help, because
each pass runs at a quarter of the size of the one before.

### Popups and the OSD open sluggishly on Hyprland

Hyprland fades layers in on top of Silere's own animation. The installer offers to turn that off for Silere's
layers only; to add it yourself:

```lua
hl.layer_rule({ name = "silere-no-anim", match = { namespace = "^silere-.*$" }, no_anim = true })
```

Before Hyprland 0.57, the same rule in a `.conf` config is `layerrule = no_anim on, match:namespace ^silere-.*$`.

### No blur behind the bar

Blur needs Hyprland 0.56 or niri 26.04 or newer, and a translucent bar: under Settings › Appearance › Theme,
set Bar opacity below 100%. Silere tells the compositor where to blur, so no layer rules are needed, but Hyprland's
`decoration:blur:enabled = false` still turns blur off everywhere, and how soft it looks is Hyprland's `size` and
`passes` under `decoration:blur`. On Hyprland, a dimmed Background blur row names what is stopping it, as
`silere doctor` does; neither checks niri's version. Notifications, the calendar, tray menus and quick actions blur too once
Popups match bar opacity is on; without blur they stay solid, since a window under them would drown their text.

### Blur spreads past the bar and panels

Hyprland's `render:use_shader_blur_blend` skips the blur regions Silere declares, so each layer blurs as a whole: a
band under the bar and a tall column behind notifications. Leave it off, or limit blur to the cards by alpha:

```lua
hl.layer_rule({ name = "silere-blur-alpha", match = { namespace = "^silere-.*$" }, ignore_alpha = 0.3 })
```

Silere's bar opacity stops at 0.4, so an alpha of 0.3 never cuts into a card.

### Text has coloured fringes on a fractionally scaled display

Silere draws its text in greyscale unless `QSG_DISTANCEFIELD_ANTIALIASING` is already set in its environment. If
you see orange or blue edges, remove that variable or set it to `gray`.

### The desktop goes black in a virtual machine

Hyprland 0.57.0 turned on `quirks:skip_non_kms_dmabuf_formats`, which can leave Quickshell's transparent windows
painting black ([reported on virtio-gpu](https://github.com/omacom/omarchy/issues/17061)). 0.57.1 turned it off
again; on 0.57.0, add `hl.config({ quirks = { skip_non_kms_dmabuf_formats = false } })`.

## Notifications, icons and fonts

### Notifications never appear

Another daemon already owns `org.freedesktop.Notifications`. Silere names it in an alert a few seconds after it
starts and under Settings › System › Overview, and `silere doctor` reports it too. Stop that daemon and run
`silere restart`.

If it is back after the next login, D-Bus started it: mako, dunst and swaync start themselves when an app sends a
notification before Silere is up. `silere doctor` names any that can, and
`systemctl --user mask mako.service` (or `dunst.service`, `swaync.service`) keeps one off.

### Icons or text use the wrong font

Install a Nerd Font such as `ttf-jetbrains-mono-nerd`, refresh the font cache with `fc-cache -f` and run
`silere restart`.

### Tray icons disappear when shown again

First check Settings › Widgets › Show & order: the tray must be on and the app must say Shown. Show all apps
brings hidden apps back without resetting the bar layout.

Otherwise an old user service probably sets `QSG_TRANSIENT_IMAGES`, which makes
[Qt drop image data](https://github.com/qt/qtdeclarative/blob/6.11/src/quick/util/qquickpixmapcache.cpp#L125-L131)
after the first window uses it, whatever its value; `silere doctor` warns about it. Remove the
`Environment=QSG_TRANSIENT_IMAGES=…` line from `silere-shell.service`, set `ExecStart` to the absolute path of
`scripts/silere` followed by `run`, then run `systemctl --user daemon-reload` and `silere restart`.

## Devices and network

### A widget or control is missing

Some widgets start off: the window title, the system monitor, Bluetooth, the keyboard layout and package updates.
Turn them on under Settings › Widgets › Show & order. Others hide while their service is missing: the network
widget needs NetworkManager (iwd or systemd-networkd alone are not enough), Bluetooth needs `bluetooth.service`
running, and battery details need UPower. `silere doctor` names each one that is missing, and
[optional tools](install.md#optional-tools) lists what turns on what.

### Brightness controls the wrong screen

If your laptop exposes several backlights, pick its panel with Brightness display under
Settings › System › Devices, or expand Home's brightness slider and choose it there.

### External monitor brightness is missing or does not respond

1. Turn on DDC/CI in the monitor's own settings menu and install `ddcutil`.
2. Under Settings › System › Devices, turn on External brightness, and check that Control ‹monitor name› is on for
   each monitor you want to adjust.
3. Scroll the bar's brightness widget to step every enabled display from its own level, or adjust one at a time
   in Home.

If a monitor is missing or does not respond, run these as the same user that runs Silere, with your monitor's bus
number from `detect` in place of `7` (as in `/dev/i2c-7`):

```bash
ddcutil detect --brief
ddcutil --bus 7 getvcp 10 --brief
```

- A permissions error means your distribution's `ddcutil` udev rules or I²C access need fixing
  ([ddcutil device permissions](https://www.ddcutil.com/i2c_permissions/)).
- If the monitor is absent or the brightness read fails, check DDC/CI in its menu again, and try a direct
  connection instead of a dock or adapter ([ddcutil troubleshooting](https://www.ddcutil.com/faq/)).
- If both commands work but Silere still misses the monitor, include their output and the connector name in a
  [bug report](#reporting-a-problem).

### Night Light is unavailable on niri

Install `wlsunset`. `hyprsunset` needs Hyprland and cannot set niri's display gamma.

### The screen is unlocked after sleep

Use Lock & sleep, which waits for the session to confirm the lock before suspending; Sleep suspends at once. For
lid closes and other sleep requests, have your idle daemon lock first, for example
`before_sleep_cmd = loginctl lock-session` in hypridle ([Companions](companions.md#lock-screen-and-idle)).

### Bluetooth pairing fails for a passkey device

Pairing with a PIN or a confirmation needs a separate Bluetooth agent. Start `blueman-applet` or `bt-agent` in
your session, then pair again.

### Headphones do not reconnect when switched on

BlueZ refuses a device that reconnects by itself unless it is trusted. Silere trusts a paired device the first
time it connects, so connect it once by any means, or run `bluetoothctl trust <address>`.

### The network icon warns of no internet while pages load

The warning comes from NetworkManager's connectivity check, which fetches one page, such as
`ping.archlinux.org` on Arch. If a firewall or DNS blocklist stops that page, NetworkManager reports no internet.
Allow the address, or turn the check off with `enabled=false` under `[connectivity]` in a file in
`/etc/NetworkManager/conf.d/`.

## Reporting a problem

Include the steps to reproduce it, your distribution and compositor version, and the output of
`silere version`, `qs --version` and `silere doctor` in your
[bug report](https://github.com/s3rven/silere-shell/issues/new?template=bug_report.yml). `silere log` has the
running shell's log; if the user service failed to start, read its log instead:

```bash
journalctl --user -u silere-shell.service -b -n 80 --no-pager
```

Remove private window titles, network names and other personal details from what you paste.
