# Installing

You need `git`, Hyprland or niri, and Quickshell 0.3.1 or newer.

```bash
git clone https://github.com/s3rven/silere-shell
cd silere-shell
bash scripts/install.sh
```

The installer:

- checks every QML module Silere imports and names any that are missing
- puts a checkout in your XDG config directory, or another path you choose
- backs up files before editing them, and asks before touching compositor autostart
- offers a key that opens the menu, and leaves a combination already in use alone
- offers to leave the checkout on the latest signed release
- prints the final install path when it's done

To start it, restart your compositor, or try it right away with `silere run`. Before the
optional maintenance-command link exists, use `/that/path/scripts/silere run`.

## Previewing the install

`bash scripts/install.sh --dry-run` lists every file the install would create or edit and
the autostart and keybind lines it would add, then exits without writing anything. It
answers the prompts the way an unattended install does, so it shows the fullest plan.

## Maintenance command

The installer offers a link at `~/.local/bin/silere`. It is a small dispatcher over the
same reviewed scripts in the checkout—there is no daemon:

```bash
silere run
silere status
silere doctor
silere update
silere update --apply
silere update --rollback
silere repair
silere repair --apply
silere repair --undo
silere version
silere uninstall
```

`silere doctor` and `bash scripts/install.sh --check` are read-only. They check the
runtime, compositor IPC, required QML modules, audio services, optional features,
autostart, settings, update timer, and release trust key. Missing optional packages are
reported with a command for the detected package family; Silere prints that command but
never runs it or elevates privileges.

`silere update --apply` stages the signed release in a detached worktree and validates it
there — headless type-check, then a sandboxed launch against a copy of your settings —
before the live checkout changes at all. It writes a private transaction journal recording
that validation passed, then fast-forwards. If power is lost or the updater is killed after
that point, the next update run authenticates the journal with a snapshot of the previously
installed release key and retains the validated revision, or restores the previous one.
Recovery refuses to reset a checkout that gained local edits after the interruption.

A checkout the installer marked as a development install — or any checkout not on
`main` — is left to Git; Updates shows its branch and state but self-update is disabled.

## Unattended installs

Bootstrapping from a dotfiles script or a container? `SILERE_ASSUME_YES=1` answers the
`[Y/n]` prompts and installs to the default path. It still backs up every file it edits,
and still stops on a compositor it does not support.

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
| `nmcli` | VPN name fallback (network and Wi-Fi use Quickshell directly) |
| `brightnessctl` | brightness |
| `hyprsunset` / `wlsunset` | night light (`hyprsunset` on Hyprland, `wlsunset` elsewhere) |
| `matugen` | wallpaper theming |
| `cava` | media visualizer |
| `powerprofilesctl` | power profiles |
| `inotifywait` | screenshot feedback on the underline, and restarting the shell onto a restarted Hyprland |
| `checkupdates` / `apt` / `dnf` / `zypper` / `xbps-install` | package update badge |
| `paru` / `yay` | AUR update count on Arch Linux |
| `hyprlock` / `swaylock` / `gtklock` | lock action |
| `pwvucontrol` / `pavucontrol` | Sound settings, reached from the volume control |
| `systemctl` / `loginctl` | suspend, reboot, and shutdown actions |
| `notify-send` | battery, temperature, and update notifications |
| `ssh-keygen` | cryptographic verification of Silere release tags |

The installer also reports on `busctl`, `pgrep`, `pkill` and `timeout`. Those ship with
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
and the installed font.

A package install has no `uninstall.sh`. Remove the package instead; it prints what is
left in your home directory to clean up by hand.
