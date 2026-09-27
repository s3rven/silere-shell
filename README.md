<p align="center">
  <picture>
    <source media="(prefers-color-scheme: light)" srcset="assets/banner-light.svg"/>
    <img src="assets/banner.svg" alt="silere shell - quiet by default." width="720"/>
  </picture>
</p>

<p align="center">
  <a href="https://github.com/s3rven/silere-shell/releases"><img src="https://img.shields.io/github/v/release/s3rven/silere-shell?style=flat-square&labelColor=0f1013&color=2a2d33&logo=github&logoColor=9a9ca1" alt="latest release"/></a>
  <a href="https://github.com/s3rven/silere-shell/actions/workflows/validate.yml"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fs3rven%2Fsilere-shell%2Fbadges%2Fchecks.json&style=flat-square" alt="checks passed on main"/></a>
  <a href="#performance"><img src="https://img.shields.io/badge/idle-under%201%25%20CPU-2a2d33?style=flat-square&labelColor=0f1013" alt="idle: under 1% CPU"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2a2d33?style=flat-square&labelColor=0f1013" alt="license: MIT"/></a>
  <a href="https://quickshell.org/"><img src="https://img.shields.io/badge/built%20on-Quickshell-2a2d33?style=flat-square&labelColor=0f1013" alt="built on Quickshell"/></a>
  <img src="https://img.shields.io/badge/runs%20on-Hyprland%20%C2%B7%20niri-2a2d33?style=flat-square&labelColor=0f1013&logo=hyprland&logoColor=9a9ca1" alt="runs on Hyprland and niri"/>
</p>

<p align="center">A desktop shell for Hyprland and niri, built on Quickshell.</p>

<p align="center">
  <img src="assets/shot-desktop.webp" alt="The floating Silere bar with the home page open and a notification" width="900"/>
</p>

Silere gives you a bar, notifications, an OSD, a calendar, a tray and a menu that holds
quick controls and every setting, all running in one Quickshell process. It's built to
cost almost nothing while you're not using it:

- It uses about 82 MB of memory with only the bar drawn, and about 93 MB once the menu
  has been opened ([how that's measured](#performance)).
- It idles at well under 1% of one CPU core. After 10 minutes without input, it also
  pauses its periodic readings and checks; the clock keeps updating once a minute.
- The media visualizer, package update checks, network speed, temperature alerts, seconds
  on the clock and the underline effects all start switched off.
- Quickshell is the only package it requires. Night light, the visualizer and the
  underline's screenshot feedback start their helper programs only while they're on.
- It has no plugin system. Hooks run your own scripts as separate processes, each with a
  time limit.

## Features

<details>
<summary>Bar, menu, notifications, OSD, calendar, night light, theming and more</summary>


- The bar can show workspaces, the focused window's title, what's playing, network,
  Bluetooth, volume, microphone, brightness, battery, the clock, the tray, and badges for
  package and Silere updates. It sits on the top or bottom edge, docked or floating, and
  you can drag its widgets between the left, centre and right.
- The menu has three pages. Home holds media controls, volume and brightness, Wi-Fi and
  Bluetooth, night light, Do Not Disturb, power mode, the lock button, and CPU, memory,
  disk and battery readouts. Settings holds every option, and the third page is your
  notification history.
- Notifications support actions, images, inline replies and progress bars. Do Not Disturb
  can follow a schedule, and the history can be searched, filtered by app and kept across
  restarts.
- The OSD shows volume, brightness and microphone mute, either as a popup or in the middle
  of the bar.
- Quick actions, opened by right-clicking the active workspace, switch Do Not Disturb,
  night light, power mode, Wi-Fi, Bluetooth and airplane mode.
- The calendar opens from the clock. It can show week numbers, start the week on Monday,
  Sunday or your locale's first day, and mark the dates you click.
- Night light uses hyprsunset on Hyprland and wlsunset on niri. In automatic mode it
  follows sunrise and sunset, estimated from your timezone instead of a location service.
- Colours come from your wallpaper through Matugen, or from an accent you pick, over three
  dark base tones. On Hyprland 0.56+ and niri 26.04+, a translucent bar blurs what's
  behind it.
- Settings include high contrast, reduced motion and interface scaling.
- With several screens, each one can have a bar or not, and notifications and the OSD
  either follow focus or stay on the screen you pick.

</details>

Silere doesn't include a launcher, dock, lock screen, wallpaper setter or clipboard
history, so keep the ones you already use. The lock button runs hyprlock, swaylock,
gtklock, `loginctl lock-session` or a command of your own.

<p align="center">
  <img src="assets/shot-surfaces.webp" alt="The home page, the settings rail, and the calendar" width="900"/>
</p>

<p align="center">
  <img src="assets/shot-popups.webp" alt="The floating bar, notification history, a notification, the OSD and quick actions" width="900"/>
</p>

<p align="center">
  <img src="assets/shot-themes.webp" alt="The home page in the neutral theme, and in colours taken from the wallpaper" width="900"/>
  <br/>
  <sub>Left: the neutral theme. Right: colours Matugen took from the wallpaper.</sub>
</p>

## Install

You need Hyprland or niri, `git`, and Quickshell 0.3.1 or newer, built against at least
Qt 6.9. On Arch, `sudo pacman -S --needed quickshell git` installs both. For other
distributions, see [Quickshell's install guide](https://quickshell.org/docs/v0.3.1/guide/install-setup/).

```bash
git clone https://github.com/s3rven/silere-shell
cd silere-shell
bash scripts/install.sh
```

The installer sets Silere up in `~/.config/silere-shell` unless you choose another folder.
It backs up every file it edits and asks before adding autostart. To see what it would do
without changing anything, run it with `--dry-run`.

It also offers to add a `silere` command to `~/.local/bin`. If you skip that, use
`~/.config/silere-shell/scripts/silere` wherever this README says `silere`; running it
with `link` adds the command later.

Then restart your compositor, or start Silere now with `silere run`.

A widget that needs a tool you don't have stays hidden. `silere doctor` lists the missing
tools and checks the install without changing anything. `silere log --follow` shows the
running shell's log, and `silere restart` restarts it.

[docs/install.md](docs/install.md) covers fonts, optional tools, unattended installs,
Matugen and removal, and [docs/troubleshooting.md](docs/troubleshooting.md) covers common
problems.

## Usage

Open the menu with **Super + /**, if you let the installer add that keybind, or by
clicking the active workspace. On niri, or with a Hyprland config written in Lua, the
installer prints the keybind for you to add yourself. niri runs keybind commands without a
shell, so use the full path:

```bash
qs ipc -p ~/.config/silere-shell/shell.qml call menu toggle
```

Everything else is done with the mouse. The keyboard is only used for Escape, Ctrl+F in
the notification history, and text fields.

<details>
<summary>Every widget's controls</summary>


| area | pointer |
|---|---|
| workspaces | **click** switches · on the active workspace, **click** opens the menu and **right-click** opens quick actions · **middle-click** sends the focused window there · **scroll** switches too, once you turn it on under Settings › Widgets › Workspaces |
| clock | **click** opens the calendar · **middle-click** cycles through adding seconds, the date, or both |
| calendar | **scroll** changes the month · **click** the header to jump back to today · **click** a date to mark it · choose week start and week numbers under Settings › Widgets › Clock |
| media | **click** plays or pauses · **scroll** changes track · **middle-click** jumps to the player |
| volume | **scroll** changes volume · **click** mutes · **middle-click** moves to the next output · **right-click** opens pwvucontrol or pavucontrol · in the menu, expand it for output, input and per-app levels |
| microphone | **click** mutes · **scroll** changes the input level · **middle-click** moves to the next input · **right-click** opens pwvucontrol or pavucontrol · it appears while an app is listening |
| brightness | **scroll** changes brightness |
| updates | **click** rechecks for packages |
| shell update | **click** opens Settings › System › Updates |
| tray | **click** jumps to the app's window, or activates the app when it has none · **right-click** opens its menu · **middle-click** runs the app's secondary action · **scroll** is passed through to the app |
| notifications | **click** runs the default action · **right-click** dismisses · **middle-click** jumps to the app that sent it · a reply action opens an inline text field when the sender supports one |
| wi-fi list | **click** joins a saved network, or opens a password field for a personal one · **right-click** or **middle-click** a saved network twice to forget it, unless you are connected to it |
| bluetooth list | **click** pairs or connects · **right-click** or **middle-click** a paired device twice to forget it, unless it is connected |
| menu | **Escape** steps back, then closes · **click** anywhere outside to close |
| history | **type** in Search, or press **Ctrl+F** to get there, to find an app or message · **click** an app in the rail to show only its notifications · **click** an entry to read it in full · **Clear** removes what is shown, after a second click to confirm · **Escape** clears search, then closes |

</details>

## Settings and scripting

Every setting is in the menu and applies as soon as you change it. Settings are saved to
`$XDG_CONFIG_HOME/silere-shell/settings.json`, usually `~/.config/silere-shell/settings.json`,
and the file holds only what you changed from the defaults. Silere checks every value's
type and range when it loads the file, and never overwrites a file it can't read.

To reset everything, use **Settings › System › Maintenance** or replace the file's
contents with `{ "__version": 1 }`. Deleting a single key resets that one setting.

Silere can also be scripted over Quickshell IPC, and it can run your own programs on
events such as `battery-critical` or `workspace-changed`:

```bash
silere ipc menu toggle
silere ipc calendar toggle
silere ipc quickActions dnd
silere ipc settings set osdTimeout 3000
```

Without the `silere` command, write `qs ipc -p ~/.config/silere-shell/shell.qml call`
followed by the same words. [docs/scripting.md](docs/scripting.md) lists every call, the
settings page names and the hooks.

## Updates

When a new release is out, Settings › System › Updates lists its commits and asks you to
confirm twice before installing it. Silere only accepts stable release tags signed with
the key that ships in your checkout. A valid signature proves who published a release,
not that its code is safe. `silere update --rollback` returns to the version you had
before.

Nothing installs on its own; the optional update timer only checks for releases. The
package badge in the bar counts pending system updates, and Silere never installs packages.

## Performance

Memory, measured as proportional set size (PSS) on the reference machine:

| state | memory |
|---|---|
| an empty Quickshell panel, for comparison | ~57 MB |
| Silere, before the menu is first opened | ~82 MB |
| Silere, after the menu has opened once | ~93 MB |

`top` and `htop` show resident memory (RSS) instead, about 180 to 195 MB for the same
session, because RSS counts shared Qt and GPU driver pages in full. The first time the menu
opens, it loads code and caches that stay in memory, so the number rises once and then
holds.

Idle CPU use is well under 1% of one core. Animations and the media visualizer use more
while they run.

To measure your own setup, run `bash scripts/bench.sh 30`, or `bash scripts/bench.sh 30 --warm`
for the number after the menu has opened. [docs/performance.md](docs/performance.md)
explains the method, and [docs/perf-history.md](docs/perf-history.md) lists the numbers
for each release.

## Documentation

- [install.md](docs/install.md): optional tools, fonts, Matugen, unattended installs, removal
- [scripting.md](docs/scripting.md): IPC calls, settings over IPC, page names, hooks
- [troubleshooting.md](docs/troubleshooting.md): symptom by symptom, starting with `silere doctor`
- [performance.md](docs/performance.md): how the numbers are measured, fonts, the animation driver
- [forking.md](docs/forking.md): the code layout, and what a change or a rename has to touch
- [releasing.md](docs/releasing.md): tags, signing and key rotation, for maintainers
- [CHANGELOG.md](CHANGELOG.md): changes since the last release, with older releases in [docs/releases](docs/releases/)

## Contributing

Pull requests of any size are welcome, from typo fixes to new widgets.
[CONTRIBUTING.md](CONTRIBUTING.md) has the details, and questions and ideas go in
[Discussions](https://github.com/s3rven/silere-shell/discussions). If you want to build
your own version, [docs/forking.md](docs/forking.md) maps the code.

## On AI assistance

I use AI tools to build Silere, and I think it makes the project better. It's just me
working on this. With the help, bugs get fixed the same day I find them instead of sitting
around for weeks.

I still decide what goes in, and I read every change myself. Silere is the only desktop I
use, so anything broken breaks my own machine first.

AI-assisted pull requests are welcome too. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT © s3rven
