# Installing Silere

[All docs](README.md) · [Everyday use](usage.md) · [Companions](companions.md) · [Troubleshooting](troubleshooting.md)

## Requirements

You need Hyprland or niri, `git`, and Quickshell 0.3.2 or newer, built against at least Qt 6.10. The one-line
installer also needs `curl`.

```bash
sudo pacman -S --needed quickshell git curl ttf-jetbrains-mono-nerd   # Arch and its derivatives
sudo apt install quickshell qml6-module-qtquick-effects git curl      # Debian 14 and unstable, Ubuntu 27.04
sudo dnf copr enable errornointernet/quickshell && sudo dnf install quickshell git curl   # Fedora
sudo xbps-install -S quickshell git curl                               # Void
```

Debian and Ubuntu's `quickshell` package does not pull in `qml6-module-qtquick-effects`, which Silere needs.
Debian 13 backports and Ubuntu 26.10 ship Quickshell 0.3.0, which is too old, and Fedora's own package is older
still, hence the COPR. Elsewhere, follow [Quickshell's install guide](https://quickshell.org/docs/v0.3.2/guide/install-setup/).

## Try it without installing

```bash
git clone --depth 1 https://github.com/s3rven/silere-shell
bash silere-shell/scripts/silere try
```

This opens Hyprland or niri in a window, with Silere inside it on a private session bus and with its own
settings, state, cache and runtime folders. It needs `dbus-run-session` and `setsid`. Inside the window, Alt+1
to Alt+5 change workspace, Alt+Return opens a terminal and Alt+/ opens the menu. Sound, network and Bluetooth
are your real ones, so their controls work. The preview can't lock or suspend your session, and it leaves
keyboard lighting, external monitor brightness and the battery's charge limit alone. Closing the window ends it
and deletes its files. Once Silere is installed, the same preview is `silere try`.

## Install

Run the installer as your normal user, inside your Hyprland or niri session or from a TTY once their config
exists:

```bash
curl -fsSL https://raw.githubusercontent.com/s3rven/silere-shell/main/scripts/install.sh | bash
```

Piped like this, it downloads a temporary copy of Silere, runs that copy's installer and deletes it afterwards.
To read the installer first, run it from a clone:

```bash
git clone https://github.com/s3rven/silere-shell
cd silere-shell
bash scripts/install.sh
```

After its checks, the installer asks once whether to use the recommended setup. Yes takes the default answer to
each question that follows and prints it; no asks at every step. It:

- checks every QML module Silere imports and names any that are missing
- offers to download JetBrainsMono Nerd Font when no copy is installed
- puts a checkout in `~/.config/silere-shell` (or `$XDG_CONFIG_HOME/silere-shell`), or a path you choose, and
  offers to leave it on the latest signed release
- offers to link the `silere` command into `~/.local/bin`, with bash and fish completions
- offers to wire Silere's template into Matugen's config, if Matugen is installed
- backs up each file before it edits it
- offers the autostart line: `hl.on("hyprland.start", ...)` in `hyprland.lua` (`exec-once` in a `.conf`), or
  `spawn-at-startup` in niri's config. A Lua edit is checked with `Hyprland --verify-config` and taken back if
  Hyprland rejects it; niri's edit is checked with `niri validate` before it is written. A Lua config ending in
  `return` gets the line to add yourself
- on Hyprland, offers Super + / for the menu unless that key is taken, and offers to turn off Hyprland's fade on
  Silere's popups, which animate themselves, unless your config already sets how Silere's layers animate. On
  niri it prints the menu bind to put inside your `binds` block
- with a Lua config, offers Silere's window motion (default no): `hyprland/silere-motion.lua` sets the window,
  workspace and focus animations to the shell's pace and works around two Hyprland 0.57 animation faults.
  Anything your config sets after that line wins
- names each line of your Hyprland or niri config that still starts another bar or notification daemon
- offers a daily update-check timer (default no)
- offers to start Silere, when it runs inside a Wayland session

## First start

Stop your old bar and notification daemon (waybar and mako or dunst, for example, or another Quickshell shell),
then run:

```bash
silere run
```

`silere run` names any other bar it finds still running. The installer and `silere doctor` also name the lines
in your compositor config that start one at login, and a notification daemon D-Bus would start on its own, with
the command that keeps it off.

If `silere` is not found, run it by its full path, `~/.config/silere-shell/scripts/silere run`, or the path the
installer printed. The bar should appear; click the active workspace for the menu, or the clock for the
calendar. [Everyday use](usage.md) covers the rest. `silere stop` stops it and `silere restart` starts it again.
If it does not appear, run `silere doctor` and see [troubleshooting](troubleshooting.md).

## Installer options

| Option | What it does |
|---|---|
| `--dry-run` | Lists every file it would create or edit and every line it would add, then exits without writing anything. It answers as an unattended install does, so it shows the fullest plan. |
| `--dir PATH` | Installs to another directory. Quote a path with spaces. |
| `--yes` or `-y` | Accepts the default answers without a terminal. |
| `--no-start` | Leaves starting Silere for later. |
| `--check` | Runs the read-only diagnostics, as `silere doctor` does. Use it alone. |
| `--repair-matugen` | Rewires Matugen without reinstalling, writing only Silere's template and its marked block in `config.toml`. Use it alone. |

For a dotfiles script or another unattended setup:

```bash
bash scripts/install.sh --yes --dir "$HOME/.config/silere-shell" --no-start
curl -fsSL https://raw.githubusercontent.com/s3rven/silere-shell/main/scripts/install.sh | bash -s -- --yes --no-start
```

`--yes` still backs up what it edits. Questions that default to no stay no, including the update timer and
installing on a session that is neither Hyprland nor niri, and an unattended install never starts the shell.
`SILERE_ASSUME_YES=1` works the same as `--yes`. `bash scripts/install.sh --help` lists the environment
variables, such as `SILERE_MENU_BIND_KEY` for another menu key.

## Fonts

Silere draws its glyphs from JetBrainsMono Nerd Font. If it is missing, the installer offers to download a
pinned release, checks it against a known SHA-256 and refuses a mismatch. The font goes to
`~/.local/share/fonts/JetBrainsMono`. Any other Nerd Font you have shows up in the font picker under
Settings › Appearance › Interface.

## Optional tools

None of these are required. Installing one turns on its feature; without it, that widget or control is hidden
or marked unavailable, and `silere doctor` prints the install command for your distribution (it never runs it).
[Companions](companions.md) covers the launcher, lock screen, idle and wallpaper tools.

| Tool | Enables |
|---|---|
| `pipewire` + `wireplumber` | volume, outputs and inputs, per-app volume |
| `upower` | battery details, the charge limit and keyboard lighting where supported; the last two also use `busctl` |
| NetworkManager | the network widget and Wi-Fi controls; Quickshell reads networks only through it, so iwd or systemd-networkd alone hide them |
| `nmcli` | the VPN indicator and saved VPN connections |
| `brightnessctl` | brightness |
| `ddcutil` | external monitor brightness over DDC/CI; turn on External brightness under Settings › System › Devices |
| `hyprsunset` or `wlsunset` | Night Light (`hyprsunset` on Hyprland only) |
| `matugen` | colours from the wallpaper |
| `cava` | the audio visualizer; Silere writes its own temporary profile and leaves `~/.config/cava` alone |
| `curl` | cover art from the web, when that setting is on |
| `wpctl` + `pw-dump` | Listening and Calls modes on Bluetooth headsets |
| `powerprofilesctl` | power modes; a daemon on the same D-Bus API, such as `tuned-ppd`, works without it |
| `inotifywait` | the underline's screenshot flash (niri reports its own screenshots), and restarting a supervised shell onto a restarted Hyprland |
| `checkupdates`, `apt`, `dnf`, `zypper` or `xbps-install` | the package update count; `checkupdates` also needs `fakeroot` |
| `paru` or `yay` | AUR updates in that count |
| `hyprlock`, `swaylock` or `gtklock` | the Lock action; without one, Lock asks `loginctl lock-session`, which locks only if an idle daemon answers it |
| `pwvucontrol` or `pavucontrol` | sound settings, from a right-click on the volume widget |
| `nm-connection-editor` or `nmtui` | advanced network settings; `nmtui` opens in a terminal |
| `blueman-manager` and a pairing agent | PIN and passkey pairing; see [Bluetooth pairing](troubleshooting.md#bluetooth-pairing-fails-for-a-passkey-device) |
| `systemctl` or `loginctl` | sleep, hibernate, reboot and power off |
| `hyprshutdown` | Log out on Hyprland closes your apps before the session ends |
| `notify-send` | the updater's notifications; the shell's own alerts also go through `busctl` |
| `fc-list` (fontconfig) | finding installed Nerd Fonts for the font picker |
| `ssh-keygen` | verifying signed release tags; without it the installer stays on `main` and updates stop |

The installer also checks for `busctl`, `pgrep` and `timeout`. They ship with systemd, procps and coreutils,
and are listed only so a minimal system can see what is missing.

## Matugen

When Matugen is installed, the installer copies Silere's template into Matugen's templates folder and adds an
entry to `~/.config/matugen/config.toml` that writes `~/.config/matugen/silere-shell.json`. Silere watches that
file and recolours as it changes. Choose Wallpaper under Settings › Appearance › Theme, then run Matugen on your
wallpaper as usual. If the file breaks, Silere keeps the last good colours, and Reload palette on the Theme page
reads it again. A package install prints the one command that sets this up, `install.sh --repair-matugen`.

## The silere command

The installer links `~/.local/bin/silere` to `scripts/silere` in your checkout, with bash and fish completions
down to setting names and values. `~/.local/bin` must be on your `PATH`; if you skipped the link, run
`scripts/silere link` from the checkout. `silere` alone lists every command, and `silere ipc` alone lists every
call the running shell answers. The [scripting guide](scripting.md) covers the commands that control the shell,
and [updates and recovery](updates.md) the ones that update it. `silere doctor`, the same check as
`bash scripts/install.sh --check`, looks over the whole setup and changes nothing.

## Crash recovery

To have Silere restarted after a crash, install its user service:

```bash
silere service install --dry-run
silere service install
```

Then replace the Silere line in your compositor's startup with `silere run --supervised --startup`, so only one
start line remains; installing the service does not edit your compositor config. The service restarts a failed
run after a short delay, up to three times a minute. `silere service status` shows its state and
`silere service remove` stops and removes it. `silere stop` stops the service too, and it stays stopped until
`silere run --supervised`. To move a shell you started by hand under the service, run `silere stop`, then
`silere run --supervised`.

## Using another checkout

With an installed copy and a development clone side by side, `silere status` shows which one is running. To
switch, run the other copy's command:

```bash
/path/to/other-copy/scripts/silere use --dry-run
/path/to/other-copy/scripts/silere use
```

This moves the command link and its completions to that copy, points an existing service at it through a
drop-in, and restarts the shell. It checks the runtime, the session and the service first and changes nothing
if one fails. Your compositor's start line keeps its own path, so update it as the command reminds you.
`silere use /path/to/copy` switches back. A normal start keeps the loaded QML as it is while files change;
`SILERE_WATCH_FILES=1 silere run` reloads on every save, for development.

## Removing it

Run `silere uninstall`, or `bash scripts/uninstall.sh` from the checkout. It asks before removing each thing
the installer added: the blocks in your compositor config, the Matugen wiring, the update timer and the
`silere` command. Your checkout, settings, notification history and the font stay. A package install has no
uninstaller: remove the package, and it prints what is left in your home folder to delete by hand.
