# Troubleshooting

Start here:

```bash
silere doctor
```

It reports the runtime, the optional tools, the font, which program owns notifications, and
whether Silere is set to start on login, either from the compositor config or from a
systemd user unit. It changes nothing.

`silere log --follow` prints the running shell's log as it grows, and `silere restart`
starts the shell again. A second `qs -p` next to a running shell brings its own bar and
notification server, so stop the first with `qs kill -p` on the same path before running
one in the foreground.

## It installed but nothing appears

Silere runs on Hyprland and niri only. On either of those it is nearly always the autostart
line — run `~/.config/silere-shell/scripts/silere run` to check. If the bar comes up, add
`~/.config/silere-shell/scripts/silere run --startup` to your compositor's startup
(`exec-once` on Hyprland, `spawn-at-startup` on niri) and restart it. Use the full path:
the compositor's `PATH` often lacks `~/.local/bin`.

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
reports it too. Stop that daemon and run `silere restart`.

Sandboxed tests skip this conflict alert because the desktop's running shell is expected
to own notifications. A warning from an older test instance does not mean that the live
shell lost its notification server. Check the current owner with `silere doctor`.

## Icons or text use the wrong font

Install a Nerd Font such as `ttf-jetbrains-mono-nerd`, then refresh the font cache with
`fc-cache -f` and run `silere restart`.

## Tray icons disappear when shown again

First check Settings › Widgets › Tray: the tray must be enabled and the app must say
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
Appearance › Theme › Bar opacity below 100%. Background blur then appears under it; when
that row is dimmed, it names what is stopping the blur, and `silere doctor` reports the same.

Silere tells the compositor where to blur, so it needs no layer rules, but Hyprland's
`decoration:blur:enabled = false` still turns blur off everywhere. How soft the blur looks
comes from the compositor: on Hyprland, `size` and `passes` under `decoration:blur`.
Notifications, the calendar, tray menus and quick actions blur too once Popups match bar
opacity is on.

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

## Special or named workspaces misbehave after a Hyprland update

Hyprland 0.57 changes how it names special and named workspaces, and Quickshell 0.3.1 reads
them all as the same workspace. Numbered workspaces are not affected. If you rely on the others,
stay on Hyprland 0.56 until a Quickshell release after 0.3.1 ships, or build Quickshell from its
main branch. `silere doctor` warns about this pairing.
