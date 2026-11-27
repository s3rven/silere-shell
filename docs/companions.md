# Companions

[All docs](README.md) · [Installation](install.md) · [Everyday use](usage.md)

Silere draws the bar, notifications, the OSD and its menus. Launching apps, the clipboard, locking, idling and
the wallpaper are other programs' jobs, and none of them is required. This page names some that work well beside
Silere and how to connect them. The examples use Hyprland's Lua config and niri's config; put niri binds inside
your `binds` block.

## Launcher

Silere has no launcher and no command to open one. Bind the one you like, such as fuzzel, rofi, walker or
Vicinae, in your compositor:

```lua
hl.bind("SUPER + R", hl.dsp.exec_cmd("fuzzel"))
```

```kdl
Mod+D { spawn "fuzzel"; }
```

If your launcher has a Matugen template, add it to the Matugen config the installer wrote to, and it follows the
same palette as Silere.

## Clipboard

Silere keeps no clipboard history. cliphist with wl-clipboard does, and some launchers, Vicinae among them, have
a clipboard view of their own:

```lua
hl.on("hyprland.start", function() hl.exec_cmd("wl-paste --watch cliphist store") end)
hl.bind("SUPER + V", hl.dsp.exec_cmd("cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"))
```

```kdl
spawn-at-startup "wl-paste" "--watch" "cliphist" "store"
Mod+V { spawn "sh" "-c" "cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"; }
```

## Lock screen and idle

Silere draws no lock screen. Its Lock action, in the menu's power list, runs the first locker it finds:
hyprlock, swaylock or gtklock (on niri, swaylock first). With none installed it asks `loginctl lock-session`,
which locks only if an idle daemon answers it. Settings › System › Devices picks a locker or a command of your
own.

Silere doesn't dim, lock or suspend when you are idle; an idle daemon does, such as hypridle on Hyprland or
swayidle on niri. Keep Awake and Presentation Mode hold the compositor's idle inhibitor while they are on, so
the idle daemon waits. A hypridle setup that locks after ten minutes and before every sleep:

```ini
# ~/.config/hypr/hypridle.conf
general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
}

listener {
    timeout = 600
    on-timeout = loginctl lock-session
}
```

On niri, the same with swayidle:

```kdl
spawn-at-startup "swayidle" "-w" "timeout" "600" "swaylock -f" "before-sleep" "swaylock -f"
```

Lock & sleep, in the power list, suspends only once the session confirms the lock: Hyprland reports it itself,
and niri sets logind's lock flag. If no confirmation comes within ten seconds, the sleep is cancelled. Sleep
suspends at once, so let the idle daemon lock first, as `before_sleep_cmd` does above.

## Wallpaper and colours

Silere doesn't set the wallpaper. Any wallpaper tool works, such as awww, swaybg or hyprpaper, and Silere can
take its colours from the same picture in two ways:

- With Matugen, choose Wallpaper under Settings › Appearance › Theme and run Matugen whenever the wallpaper
  changes. The installer adds Silere's template to Matugen's config, so Silere recolours as soon as Matugen
  writes its palette, along with GTK, Qt and anything else you theme through Matugen.
- Without Matugen, `silere theme <image>` takes the accent from the picture and switches to the neutral theme.

A wallpaper script can do either after it sets the picture:

```bash
#!/bin/sh
awww img "$1" && matugen image "$1"    # or: && silere theme "$1"
```

## Night light

Install hyprsunset (Hyprland only) or wlsunset. Silere starts and stops it from its Night Light switch in Home
and Quick actions, so it needs no line in your compositor config. Settings › System › Devices picks one when you
have both.

## Screenshots

Silere takes no screenshots; grim and slurp do, with an editor such as Satty if you want one. To have the bar's
underline flash when a screenshot is saved, open Settings › Bar › Underline, turn the underline on, set its Mode
to Reactive and turn on Screenshots. niri reports its own screenshots; on Hyprland, Silere watches your Pictures
and Screenshots folders with `inotifywait`. A script can also flash it with `silere ipc screenshot flash`.

## Apps the bar opens

| For | Silere opens |
|---|---|
| Sound settings (right-click volume or microphone) | pwvucontrol or pavucontrol |
| Network settings (right-click network) | nm-connection-editor, or nmtui in a terminal |
| Bluetooth settings (right-click Bluetooth) | blueman-manager; PIN pairing also needs an agent such as blueman-applet |
| System monitor (right-click the system monitor) | Mission Center, Resources, GNOME System Monitor or Plasma System Monitor, or btop or htop in a terminal |
| A terminal for those | xdg-terminal-exec, or the first of kitty, foot, ghostty, alacritty, wezterm and konsole |
| The audio visualizer | Cava, started only while the visualizer shows |
