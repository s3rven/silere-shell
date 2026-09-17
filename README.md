<p align="center">
  <img src="assets/banner.svg" alt="silere shell - quiet by default." width="720"/>
</p>

<p align="center"><em>silere</em>, from Latin: to be silent.</p>

<p align="center">
  <a href="https://github.com/s3rven/silere-shell/releases"><img src="https://img.shields.io/github/v/release/s3rven/silere-shell?style=flat-square&labelColor=17181d&color=747a98" alt="latest release"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-747a98?style=flat-square&labelColor=17181d" alt="license: MIT"/></a>
  <a href="https://quickshell.org/"><img src="https://img.shields.io/badge/built%20on-Quickshell-747a98?style=flat-square&labelColor=17181d" alt="built on Quickshell"/></a>
  <img src="https://img.shields.io/badge/runs%20on-Hyprland%20%C2%B7%20niri-747a98?style=flat-square&labelColor=17181d" alt="runs on Hyprland and niri"/>
</p>

Silere is a Quickshell desktop shell for Hyprland and niri built around one idea: nothing
runs without a reason.

Bar, notifications, OSD, calendar and tray, all in one process — and it sits under 1% of a
CPU core when you are not touching it.

<p align="center">
  <img src="assets/shot-desktop.webp" alt="The Silere bar with the menu panel open" width="900"/>
</p>

## Install

You need `git`, Hyprland or niri, and Quickshell 0.3.1 or newer.

```bash
git clone https://github.com/s3rven/silere-shell
cd silere-shell
bash scripts/install.sh
```

Restart your compositor, or start it right away with `silere run`. Before the optional
maintenance-command link exists, use `scripts/silere run` from the checkout.

Then **click the active workspace diamond**. That is the way into the menu and every
setting, so bind a key to it early:

```bash
qs ipc -p ~/.config/silere-shell/shell.qml call menu toggle
```

Preview it first with `bash scripts/install.sh --dry-run`. After installation,
`silere doctor` checks the runtime and integrations without changing them. Fonts, optional tools,
the maintenance command, unattended installs, Matugen wiring and removal:
[`docs/install.md`](docs/install.md).

## Why Silere

- **Work starts when there is work.** Every timer and poll runs only while something needs
  it, and animations end on their own once the session goes idle.
- **One process, not a stack.** No separate bar, notification daemon or OSD helper to
  install, theme, and keep in step with each other.
- **Settings live in the shell.** A panel with every option, applying the moment you
  change it — no restart, no reload.
- **Nothing third-party runs inside it.** There is no plugin system. Hooks run your own
  commands as separate, time-bounded processes.

## What you get

- **Bar** — workspaces, window title, media, network, bluetooth, volume, microphone,
  brightness, battery, clock, tray, package updates and shell updates.
  Drag them between left, centre and right.
- **Menu** — live controls, every setting, and notification history in one panel.
- **Notifications** — actions, images, history filtered by app, quiet hours, source-window jumping.
- **Theming** — Matugen from your wallpaper or a hand-picked accent, over three dark base
  tones.
- **Calendar** from the clock, **OSD** for volume and brightness, and **quick actions** for
  night light, power profiles and airplane mode.

<p align="center">
  <img src="assets/shot-surfaces.webp" alt="The menu panel, the settings rail, and the calendar" width="900"/>
</p>

## Controls

Silere is pointer-driven: Escape and text fields are its keyboard paths. Every widget's
controls are listed below.

| area | pointer |
|---|---|
| workspaces | **click** switches · on the active diamond, **click** opens the menu and **right-click** opens quick actions · **middle-click** sends the focused window there · on the trailing **+**, **click** opens the next empty workspace · **scroll** switches too, once you turn it on under Settings › Workspaces |
| clock | **click** opens the calendar · **middle-click** cycles seconds and date |
| calendar | **scroll** changes the month · **click** the header to jump back to today |
| media | **click** plays or pauses · **scroll** changes track · **middle-click** jumps to the player |
| volume | **scroll** changes volume · **click** mutes · **middle-click** moves to the next output · **right-click** opens Sound settings · in the menu, expand it for output, input and per-app levels |
| microphone | **click** mutes · **scroll** changes the input level · **middle-click** moves to the next input · **right-click** opens Sound settings · it appears while an app is listening |
| brightness | **scroll** changes brightness |
| updates | **click** rechecks for packages |
| shell update | **click** opens Settings › Updates |
| tray | **click** jumps to the app · **right-click** opens its menu · **middle-click** runs the app's secondary action · **scroll** is passed through to the app |
| notifications | **click** runs the default action · **right-click** dismisses · **middle-click** jumps to the app that sent it · a reply action opens an inline text field when the sender supports one |
| wi-fi list | **click** joins a saved network, or opens a password field for a personal one · **middle-click** a saved network to forget it |
| bluetooth list | **click** pairs or connects · **middle-click** a paired device to forget it |
| menu | **Escape** steps back, then closes · **click** anywhere outside to close |
| history | **click** an entry to read it in full |

## Configuration

Settings live in the shell and save themselves. If you want the file, it is
`$XDG_CONFIG_HOME/silere-shell/settings.json`, wherever the checkout sits, and it holds
only what differs from the defaults. Values are type-checked and numeric ranges clamped on
load, and a file Silere cannot read is left alone rather than overwritten.

To start over, use **Settings › System › Maintenance**, or replace the file with
`{ "__version": 1 }`. Deleting a single key resets that one option.

## Scripting

Every surface is scriptable over Quickshell IPC, and Silere can run an executable of your
own on events like `battery-critical` or `workspace-changed`.

```bash
SILERE_DIR="$HOME/.config/silere-shell"
qs ipc -p "$SILERE_DIR/shell.qml" call menu toggle
qs ipc -p "$SILERE_DIR/shell.qml" call calendar toggle
qs ipc -p "$SILERE_DIR/shell.qml" call settings set osdTimeout 3000
```

The full IPC surface, the settings section names, and hooks:
[`docs/scripting.md`](docs/scripting.md).

## Updates

Nothing installs on its own. Shell updates follow stable tags, accept only releases signed
by the key bundled in the checkout, and show you the pending commits behind a two-step
confirmation. A signature proves where a release came from, not that its code is harmless.
Package updates only move the badge.

## Performance

Idle use on a reference session measured about 87 MB PSS before the menu is first opened
and about 96 MB after, at well under 1% of one CPU core — much of that the Qt and GPU
driver floor rather than Silere. The menu builds its pages on first open
and keeps them: a one-time cost, not a leak. Measure your own checkout with
`bash scripts/bench.sh 30`, or `--warm` for the post-menu number. Full numbers and the
animation-driver note: [`docs/performance.md`](docs/performance.md). Per-release history:
[`docs/perf-history.md`](docs/perf-history.md).

## Troubleshooting

```bash
bash scripts/check.sh
```

That runs the dependency, autostart and configuration checks. For startup errors, run
`qs -p shell.qml` directly. Common problems: [`docs/troubleshooting.md`](docs/troubleshooting.md).

## Docs

| page | what's in it |
|---|---|
| [install.md](docs/install.md) | doctor/maintenance command, optional tools, Matugen, removal |
| [scripting.md](docs/scripting.md) | the IPC surface, settings over IPC, section names, hooks |
| [troubleshooting.md](docs/troubleshooting.md) | symptom by symptom, starting with `check.sh` |
| [performance.md](docs/performance.md) | reference numbers, how to measure, fonts, the animation driver |
| [perf-history.md](docs/perf-history.md) | per-release numbers, reference machines, how to record a row |
| [forking.md](docs/forking.md) | the tree, what a change touches, what a rename has to get right |
| [releasing.md](docs/releasing.md) | maintainer notes: cadence, tags, AUR, key rotation |
| [CHANGELOG.md](CHANGELOG.md) | unreleased work, and every release archived under [docs/releases](docs/releases/) |

## Contributing

Ideas, fixes, and new features are all welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) to
get started. Forking or making it your own? [`docs/forking.md`](docs/forking.md) maps the
tree, lists what a change actually touches, and names the few things a rename has to get
right.

## On AI assistance

I use AI tools to build Silere, and I think it makes the project better. It's just me
working on this. With the help, bugs get fixed the same day I find them instead of sitting
around for weeks.

I still decide what goes in, and I read every change myself. Silere is the only desktop I
use, so anything broken breaks my own machine first.

AI-assisted pull requests are welcome too. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT (c) s3rven
