# Troubleshooting

Start here:

```bash
bash scripts/check.sh
```

It reports the runtime, the optional tools, the font, and whether Silere is set to start on
login, either from the compositor config or from a systemd user unit. A package install
does not carry it — clone the repository to run it.

To inspect startup errors directly, run `qs -p shell.qml`.

## It installed but nothing appears

Silere runs on Hyprland and niri only. On either of those it is nearly always the autostart
line — run `qs -p ~/.config/silere-shell/shell.qml` to check. If the bar comes up, add that
command to your compositor's startup (`exec-once` on Hyprland, `spawn-at-startup` on niri)
and restart it.

## It stopped working after a system update

A Qt update can leave the installed Quickshell unable to run, because it builds against
Qt's private API. Reinstall Quickshell to rebuild it against the new Qt; `bash
scripts/check.sh` reports this as its first failure.

## The shell does not come back after an update

The updater keeps the signed transaction journal until it sees the shell running on the
new revision. From a working terminal, `silere update --rollback` restores the previous
revision and restarts the shell.

## Notifications never appear

Another daemon already owns `org.freedesktop.Notifications`. Silere works out which one and
says so in an alert naming the process, a few seconds after start.

## Icons or text use the wrong font

Install a Nerd Font such as `ttf-jetbrains-mono-nerd`, then refresh the user font cache.

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
Interface.

## A shell update is blocked by local edits

Preview them with `bash scripts/repair.sh`. Running it with `--apply` saves the edits in a
reversible Git stash and restores the shipped files; `--undo` restores the latest saved
repair.
