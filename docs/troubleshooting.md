# Troubleshooting

[All docs](README.md) · [Installation](install.md)

Start here:

```bash
silere doctor
```

It reports the runtime, the optional tools, the font, which program owns notifications, and
whether Silere is set to start on login, either from the compositor config or from a
systemd user unit. It changes nothing.

`silere log --follow` prints the running shell's log as it grows. Use `silere restart`
to restart it, or `silere stop` followed by `silere run` to watch a fresh start in
your terminal. Stop Silere before launching another `qs -p` instance.

| Problem | Start here |
|---|---|
| No bar after login | [Startup](#it-installed-but-nothing-appears) |
| Crashes after updating packages | [Qt and Quickshell](#it-stopped-working-after-a-system-update) |
| No notifications | [Notification daemon conflict](#notifications-never-appear) |
| Missing icons or the wrong font | [Fonts](#icons-or-text-use-the-wrong-font) |
| Blank tray icons | [Tray image cache](#tray-icons-disappear-when-shown-again) |
| A failed Silere update | [Rollback](#the-shell-does-not-come-back-after-an-update) |
| An update refuses local changes | [Repair](#a-shell-update-is-blocked-by-local-edits) |

## Starting and updating

### The silere command is not found

Run `~/.config/silere-shell/scripts/silere doctor`, replacing the checkout path
if you installed elsewhere. To create the command link, run that same script with
`link` instead of `doctor`, then make sure `~/.local/bin` is on your `PATH`.

### It installed but nothing appears

Silere runs on Hyprland and niri only. On either of those it is nearly always the autostart
line — run `~/.config/silere-shell/scripts/silere run` to check. If the bar comes up, run the
installer again, which adds it to a Hyprland config, or add this to your compositor's startup and
restart it. Use the full path: the compositor's `PATH` often lacks `~/.local/bin`.

```lua
-- ~/.config/hypr/hyprland.lua
hl.on("hyprland.start", function()
    hl.exec_cmd("$HOME/.config/silere-shell/scripts/silere run --startup")
end)
```

On niri it is `spawn-at-startup "sh" "-c" "$HOME/.config/silere-shell/scripts/silere run --startup"`.

### It stopped working after a system update

A Qt update can leave the installed Quickshell unable to run, because it builds against
Qt's private API. Reinstall Quickshell to rebuild it against the new Qt; `silere doctor`
reports this under Quickshell.

Silere is your notification daemon, so it cannot report its own failure to start. If the
shell is not up 20 seconds after login, Hyprland shows a message pointing at `silere doctor`.
niri has no equivalent, so there the message only appears if another notification daemon
can show it.

### The shell does not come back after an update

The updater keeps the signed transaction journal until it sees the shell running on the
new revision. From a working terminal, `silere update --rollback` restores the previous
revision, and restarts the shell when a systemd user unit runs it. Otherwise, run
`silere restart` afterwards. See [updates and recovery](updates.md).

### A shell update is blocked by local edits

`silere reset` covers this and the rest of what can go wrong at once: settings, edited files,
leftovers and caches, with `silere reset --undo` to put them back. To deal with the files alone,
preview them with `bash scripts/repair.sh`. Running it with `--apply` saves the edits in a
reversible Git stash and restores the shipped files; `--undo` restores the latest saved
repair.

### Special or named workspaces misbehave after a Hyprland update

Hyprland 0.57 changes how it names special and named workspaces, and Quickshell 0.3.1 reads
them all as the same workspace. Numbered workspaces are not affected. If you rely on the others,
update Quickshell to 0.3.2 or newer. `silere doctor` warns about this pairing.

## Display and speed

### The desktop feels slow on a high refresh panel

A compositor without VRR shows a frame that misses a refresh one refresh later, so a frame that
takes just over 4.17 ms at 240 Hz drops the whole desktop to 120. An integrated GPU can stay in
its lowest clock throughout, because at half rate it looks idle. Stop other apps redrawing to
check, and try VRR on the panel.

Lowering blur passes rarely helps, because each pass runs at a quarter of the size of the one
before. Check for a background job too: Steam's shader pre-caching runs `fossilize_replay` on
every core and can drag a desktop below 50 fps, even though it runs at idle priority.

### Popups and the OSD open sluggishly on Hyprland

Hyprland fades layers in on top of Silere's own animation. Turn that off for Silere's
layers only:

```lua
hl.layer_rule({ name = "silere-no-anim", match = { namespace = "^silere-.*$" }, no_anim = true })
```

Before Hyprland 0.57, the same rule in a `.conf` config:

```ini
layerrule = no_anim on, match:namespace ^silere-.*$
```

### Blur spreads past the bar and panels

Hyprland's `render:use_shader_blur_blend` skips the blur regions Silere declares, so each layer
blurs as a whole: a band under the bar, and a tall column behind notifications. Leave it off, or
limit blur to the cards by alpha:

```lua
hl.layer_rule({ name = "silere-blur-alpha", match = { namespace = "^silere-.*$" }, ignore_alpha = 0.3 })
```

Silere's bar opacity stops at 0.4, so 0.3 never cuts into a card.

### No blur behind the bar

Blur needs Hyprland 0.56 or niri 26.04 or newer, and a translucent bar: lower Settings ›
Appearance › Theme › Bar opacity below 100%. Background blur then appears under it; when
that row is dimmed, it names what is stopping the blur, and `silere doctor` reports the same.

Silere tells the compositor where to blur, so it needs no layer rules, but Hyprland's
`decoration:blur:enabled = false` still turns blur off everywhere. How soft the blur looks
comes from the compositor: on Hyprland, `size` and `passes` under `decoration:blur`.
Notifications, the calendar, tray menus and quick actions blur too once Popups match bar
opacity is on. Without blur they stay solid, since a window under them would show through sharp
and drown their text.

### Text has coloured fringes on a fractionally scaled display

Start Silere with `QSG_DISTANCEFIELD_ANTIALIASING=gray` in its environment.

### The desktop goes black in a virtual machine

Hyprland 0.57 turned on `quirks:skip_non_kms_dmabuf_formats`, which can leave apps inside a
virtual machine with no transparent surfaces, and Quickshell's windows are transparent. It has
been [reported on virtio-gpu](https://github.com/omacom/omarchy/issues/17061). Turn the quirk off:

```lua
hl.config({ quirks = { skip_non_kms_dmabuf_formats = false } })
```

## Notifications, icons and fonts

### Notifications never appear

Another daemon already owns `org.freedesktop.Notifications`. Silere names it in an alert a
few seconds after start and under Settings › System › Overview, and `silere doctor`
reports it too. Stop that daemon and run `silere restart`.

Sandboxed tests skip this conflict alert because the desktop's running shell is expected
to own notifications. A warning from an older test instance does not mean that the live
shell lost its notification server. Check the current owner with `silere doctor`.

### Icons or text use the wrong font

Install a Nerd Font such as `ttf-jetbrains-mono-nerd`, then refresh the font cache with
`fc-cache -f` and run `silere restart`.

### Tray icons disappear when shown again

First check Settings › Widgets › Show & order: the tray must be enabled and the app must say
Shown. Show all apps restores hidden apps without resetting the bar layout.

Older user services may set `QSG_TRANSIENT_IMAGES`. [Qt's texture factory](https://github.com/qt/qtdeclarative/blob/6.11/src/quick/util/qquickpixmapcache.cpp#L125-L131)
discards image data after its first texture upload with this variable present, even
when its value is `0` or empty.
Later windows can get a blank icon that still reports as loaded. `silere run` clears
this variable, and `silere doctor` warns about affected services.

If you use `silere-shell.service`, remove its `Environment=QSG_TRANSIENT_IMAGES=…`
line and set `ExecStart` to the absolute path of `scripts/silere` followed by `run`.
Then run `systemctl --user daemon-reload` and `silere restart`. A QML reload cannot
change the running process's environment.

## Devices and network

### Brightness controls the wrong screen

On hybrid laptops with several backlights, pick the right display under Settings ›
System › Devices, or expand Home's brightness slider.

### Night light is unavailable on niri

Install `wlsunset`. `hyprsunset` needs Hyprland and cannot control niri's display gamma.

### The screen is unlocked after sleep

Use **Lock & sleep** to wait for the session's lock confirmation before suspending.
The separate **Sleep** action suspends directly. Have your idle daemon lock first for other sleep requests, for
example `before_sleep_cmd = loginctl lock-session` in hypridle.

### Bluetooth pairing fails for a passkey device

Silere needs a separate Bluetooth pairing agent for PIN entry or confirmation. Start
`blueman-applet` or `bt-agent` in your session, then retry pairing.

### Headphones do not reconnect when switched on

BlueZ refuses a device that reconnects by itself unless it is trusted. Silere trusts a paired
device the first time it connects, so connect it once by any means, or run
`bluetoothctl trust <address>`.

### The network widget stops updating

With Quickshell 0.3.1, the network widget and Wi-Fi list can keep showing old devices after
NetworkManager restarts. Update Quickshell to 0.3.2 or newer, or restart Silere.

### The network icon warns of no internet while pages load

The warning comes from NetworkManager's connectivity check, which fetches one page, such as
`ping.archlinux.org` on Arch. If a firewall or DNS blocklist stops that page, NetworkManager
reports no internet. Allow the address, or turn the check off with `enabled=false` under
`[connectivity]` in a file in `/etc/NetworkManager/conf.d/`.

## Reporting a problem

Include the steps to reproduce it, your distribution and compositor version, and
the output of `silere version`, `qs --version` and `silere doctor` in your
[bug report](https://github.com/s3rven/silere-shell/issues/new?template=bug_report.yml).
Use `silere log` for a running shell. If a user service failed to start, read its log:

```bash
journalctl --user -u silere-shell.service -b -n 80 --no-pager
```

Include the relevant errors, with private window titles, network names and other
personal information removed.
