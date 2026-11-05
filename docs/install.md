# Installing Silere

[All docs](README.md) · [Everyday use](usage.md) · [Troubleshooting](troubleshooting.md)

## Requirements

You need Hyprland or niri, `git`, and Quickshell 0.3.1 or newer, built against at least
Qt 6.10. The one-line installer below also needs `curl`; installing from a clone does not.
On Arch and its derivatives, use `sudo pacman -S --needed quickshell git curl`.
For other distributions, see [Quickshell's install guide](https://quickshell.org/docs/v0.3.1/guide/install-setup/).

## Install

Run the installer as your normal user. You can also install from a TTY when your
Hyprland or niri configuration already exists:

```bash
curl -fsSL https://raw.githubusercontent.com/s3rven/silere-shell/main/scripts/install.sh | bash
```

Piped like this, the installer downloads a temporary copy of Silere, runs its installer and
deletes the copy afterwards. To read it first, run it from a clone instead:

```bash
git clone https://github.com/s3rven/silere-shell
cd silere-shell
bash scripts/install.sh
```

The installer:

- checks every QML module Silere imports and names any that are missing
- puts a checkout in your XDG config directory, or another path you choose
- backs up files before editing them, and asks before touching compositor autostart
- offers a key that opens the menu in a Hyprland `.conf`, and leaves a combination already in use alone;
  for niri and a Lua config it prints the line to add
- offers to leave the checkout on the latest signed release
- prints the final install path when it's done
- offers to start Silere right away in a Wayland session

The default path is `~/.config/silere-shell`, or `$XDG_CONFIG_HOME/silere-shell` if
you set an absolute config root. The interactive installer lets you choose another path.

## First start

Inside your Hyprland or niri session, stop your old bar and notification daemon,
such as waybar and mako or dunst, then run:

```bash
silere run
```

If `silere` is not found, use the path printed by the installer:

```bash
~/.config/silere-shell/scripts/silere run
```

For a custom install, replace `~/.config/silere-shell` with that path. The bar should
appear on your desktop. Click the active workspace to open the menu, or the clock
to open the calendar. [Everyday use](usage.md) covers the other controls.

Use `silere stop` to stop it and `silere restart` to start it again. If it does not
appear, run `silere doctor` and follow [troubleshooting](troubleshooting.md).

## Previewing the install

`bash scripts/install.sh --dry-run` lists every file the install would create or edit and
the autostart and keybind lines it would add, then exits without writing anything. It
answers the prompts the way an unattended install does, so it shows the fullest plan.

## Installation options

| Option | What it does |
|---|---|
| `--dry-run` | Preview the changes without writing files. |
| `--dir PATH` | Choose a directory; quote paths containing spaces. |
| `--yes` or `-y` | Accept the default answers without a terminal. |
| `--no-start` | Leave starting or restarting Silere for later. |

Options can be combined in any order. For example, preview a custom installation,
then install to the same place:

```bash
bash scripts/install.sh --dry-run --dir "$HOME/Desktop tools/silere-shell"
bash scripts/install.sh --dir "$HOME/Desktop tools/silere-shell" --no-start
```

Run `bash scripts/install.sh --help` for the full list. `--check` and
`--repair-matugen` are separate maintenance modes and must be used on their own.

## Maintenance command

The installer offers a link at `~/.local/bin/silere`. It runs the scripts in your
checkout. `~/.local/bin` must be on your `PATH`; run `scripts/silere link` from the
checkout if you skipped creating the link.

| Task | Command |
|---|---|
| Start, stop or restart | `silere run`, `silere stop`, `silere restart` |
| See which copy is running | `silere status` |
| Follow the running shell's log | `silere log --follow` |
| Diagnose setup problems | `silere doctor` |
| Show the installed version | `silere version` |
| Check, install or undo an update | [Update commands](updates.md) |
| Preview, apply or undo a repair | `silere repair`, `silere repair --apply`, `silere repair --undo` |
| Call a function from a keybind or script | `silere ipc <target> <function> [args]` — [scripting guide](scripting.md) |
| Remove installer integrations | `silere uninstall` |

`silere` alone lists its commands, and `silere ipc` alone lists the calls the running
shell answers. `silere --version` also prints the installed version. The link adds fish
and bash completions, down to setting names and their values.

`silere doctor` and `bash scripts/install.sh --check` are read-only. They check the
runtime, compositor IPC, required QML modules, which program owns notifications, the Nerd
Font, audio services, optional features, autostart, settings, update timer, and release
trust key. Missing optional packages are
reported with a command for the detected package family; Silere prints that command but
never runs it or elevates privileges.

See [updates and recovery](updates.md) for signed releases, rollback, timers and
development checkouts.

## Crash recovery

To restart Silere automatically after a crash, install its user service:

```bash
silere service install --dry-run
silere service install
```

Replace your compositor's existing Silere startup command with
`silere run --supervised --startup`. Keep only one startup command.

The service restarts failed runs with a delay and a retry limit.
`silere service status` shows its state; `silere service remove` stops and removes
the generated service. Installation does not edit compositor startup settings.
`silere stop` also stops the service, so it stays stopped until you start it again.
Use `silere run --supervised` to start through the service again. To switch a
currently unsupervised shell, run `silere stop` first, then `silere run --supervised`.

## Using another checkout

With an installed copy and a development clone, `silere status` shows which one is
running. To switch, run the target copy's command:

```bash
/path/to/other-copy/scripts/silere use --dry-run
/path/to/other-copy/scripts/silere use
```

This updates the command link, points an existing service at that copy through a
drop-in, and restarts the shell. Compositor startup lines keep their own paths;
follow the command's reminder to update yours. `silere use /path/to/copy` switches back.
Tab completes checkout directories in bash and fish, including paths containing spaces.
Before applying a switch, Silere checks the runtime, session and service override.
If these checks fail, it leaves the command link and service unchanged. The preview
still works without a live desktop session.

Normal launches keep the loaded QML steady during updates. For a development
checkout, `SILERE_WATCH_FILES=1 silere run` enables live QML reloads.

## Unattended installs

For a dotfiles script or another unattended setup, use:

```bash
bash scripts/install.sh --yes --dir "$HOME/.config/silere-shell" --no-start
```

`--yes` accepts the default answers and backs up edited files. Opt-in prompts keep
their default **No**, including the update timer and installing for an unsupported
compositor. Unattended installs leave the shell stopped until you choose to start it.

With the one-line installer, pass options to `bash`:

```bash
curl -fsSL https://raw.githubusercontent.com/s3rven/silere-shell/main/scripts/install.sh | bash -s -- --yes --no-start
```

Existing scripts using `SILERE_ASSUME_YES=1` continue to work.

## Fonts

Silere draws its glyphs from JetBrainsMono Nerd Font. When it is missing, the
installer offers to download it and skips the step if you decline. The release is pinned
to a version and checked against a known SHA-256, and a mismatch refuses the install. Fonts
go to `~/.local/share/fonts/JetBrainsMono`.

Any other Nerd Font you have installed appears in the picker under
Settings › Appearance › Interface.

## Optional tools

None of these are required. Installing one turns on the matching feature; skipping it
hides that widget or marks it unavailable.

| tool | enables |
|---|---|
| `pipewire` + `wireplumber` | volume, output picker |
| `upower` | battery |
| `nmcli` | VPN indicator, name and address (network and Wi-Fi use Quickshell directly) |
| `brightnessctl` | brightness |
| `ddcutil` | external monitor brightness over DDC/CI; enable **External brightness** in Settings › Appearance › Interface |
| `hyprsunset` / `wlsunset` | night light (`hyprsunset` on Hyprland, `wlsunset` elsewhere) |
| `matugen` | wallpaper theming |
| `cava` | media visualizer |
| `curl` | cover art from the web, when that setting is on |
| `wpctl` | Bluetooth volume on Quickshell 0.3.1 (part of WirePlumber) |
| `powerprofilesctl` | power profiles; a daemon on the same D-Bus API, such as `tuned-ppd`, works without it |
| `inotifywait` | screenshot feedback on the underline, and restarting the shell onto a restarted Hyprland when the systemd user service runs this checkout |
| `checkupdates` / `apt` / `dnf` / `zypper` / `xbps-install` | package update badge; `checkupdates` also needs `fakeroot` |
| `paru` / `yay` | AUR update count on Arch Linux |
| `hyprlock` / `swaylock` / `gtklock` / `loginctl lock-session` | lock action |
| `pwvucontrol` / `pavucontrol` | Sound settings, reached from the volume control |
| `nm-connection-editor` / `nmtui` | advanced network settings; `nmtui` opens in a terminal |
| `blueman-manager` + a Bluetooth pairing agent | passkey or PIN pairing; see [Bluetooth troubleshooting](troubleshooting.md#bluetooth-pairing-fails-for-a-passkey-device) |
| `systemctl` / `loginctl` | suspend, reboot, and shutdown actions |
| `hyprshutdown` | Log out on Hyprland closes your apps before it ends the session |
| `notify-send` | battery, temperature, and update notifications |
| `fc-list` (fontconfig) | installed Nerd Font detection and font picker |
| `ssh-keygen` | cryptographic verification of Silere release tags |

The installer also reports on `busctl`, `pgrep` and `timeout`. Those ship with
systemd, procps and coreutils, so they are listed only so a minimal system can see what
is missing.

## Matugen

The interactive installer configures Matugen when it is installed. It copies Silere's
template into Matugen's template directory and makes Matugen write
`$XDG_CONFIG_HOME/matugen/silere-shell.json`; the shell watches that user-writable
palette and reloads colours live. This works for both a Git checkout and a read-only
package under `/usr/share`. Packaged installs print the one-time command that does the
same thing, `install.sh --repair-matugen`.

## Cava

Cava needs no configuration step. Silere writes a private temporary raw-output profile
under `$XDG_RUNTIME_DIR`, starts Cava only while the visualizer is actually needed, and
leaves `~/.config/cava` untouched.

## Removing it

Run `bash scripts/uninstall.sh` from the installed checkout. That clears autostart, the
menu keybind, theme and update-timer integrations, but keeps the checkout, your settings,
your notification history and the installed font.

A package install has no `uninstall.sh`. Remove the package instead; it prints what is
left in your home directory to clean up by hand.
