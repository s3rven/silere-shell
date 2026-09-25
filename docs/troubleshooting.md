# Troubleshooting

Start here:

```bash
silere doctor
```

It reports the runtime, the optional tools, the font, which program owns notifications, and
whether Silere is set to start on login, either from the compositor config or from a
systemd user unit. It changes nothing.

A running shell's log is in `qs log -p ~/.config/silere-shell/shell.qml --follow`. A second
`qs -p` next to a running shell brings its own bar and notification server, so stop the
first with `qs kill -p` on the same path before running one in the foreground.

## It installed but nothing appears

Silere runs on Hyprland and niri only. On either of those it is nearly always the autostart
line — run `qs -p ~/.config/silere-shell/shell.qml` to check. If the bar comes up, add that
command to your compositor's startup (`exec-once` on Hyprland, `spawn-at-startup` on niri)
and restart it.

## It stopped working after a system update

A Qt update can leave the installed Quickshell unable to run, because it builds against
Qt's private API. Reinstall Quickshell to rebuild it against the new Qt; `silere doctor`
reports this under Quickshell.

## The shell does not come back after an update

The updater keeps the signed transaction journal until it sees the shell running on the
new revision. From a working terminal, `silere update --rollback` restores the previous
revision, and restarts the shell when a systemd user unit runs it.

## Notifications never appear

Another daemon already owns `org.freedesktop.Notifications`. Silere names it in an alert a
few seconds after start and under Settings › System › Maintenance, and `silere doctor`
reports it too. Stop that daemon and restart Silere.

## Icons or text use the wrong font

Install a Nerd Font such as `ttf-jetbrains-mono-nerd`, then refresh the user font cache.

## Bluetooth pairing fails for a passkey device

Silere needs a separate Bluetooth pairing agent for PIN entry or confirmation. Start
`blueman-applet` or `bt-agent` in your session, then retry pairing.

## Night light is unavailable on niri

Install `wlsunset`. `hyprsunset` needs Hyprland and cannot control niri's display gamma.

## Text has coloured fringes on a fractionally scaled display

Start Silere with `QSG_DISTANCEFIELD_ANTIALIASING=gray` in its environment.

## Popups and the OSD open sluggishly on Hyprland

Hyprland fades layers in on top of Silere's own animation. Turn that off for Silere's
layers only:

```ini
layerrule = no_anim on, match:namespace ^silere-.*$
```

In a Lua config:

```lua
hl.layer_rule({ name = "silere-no-anim", match = { namespace = "^silere-.*$" }, no_anim = true })
```

## No blur behind the bar

Blur needs Hyprland 0.56 or niri 26.04 or newer, and a translucent bar: lower Settings ›
Bar › Layout › Opacity below 100%.

## Brightness controls the wrong screen

On hybrid laptops with several backlights, pick the right display under Settings ›
Appearance › Interface.

## A shell update is blocked by local edits

Preview them with `bash scripts/repair.sh`. Running it with `--apply` saves the edits in a
reversible Git stash and restores the shipped files; `--undo` restores the latest saved
repair.

## The screen is unlocked after sleep

Sleep in the power menu suspends without locking. Have your idle daemon lock first, for
example `before_sleep_cmd = loginctl lock-session` in hypridle.

## The network widget stops updating

With Quickshell 0.3.1, the network widget and Wi-Fi list can keep showing old devices after
NetworkManager restarts. Restart Silere.

## A tray icon opens an empty menu

Some apps publish a tray icon with no menu, which Quickshell 0.3.1 still offers as one. Click
outside the card to close it.
