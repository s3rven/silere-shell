# Changelog

Notable changes to Silere Shell, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow
[Semantic Versioning](https://semver.org/) loosely while in `0.x`: minor versions
change features, patch versions fix them. The updater follows signed stable tags;
the settings file carries its own `__version` and migrates separately.

Only work since the latest release is listed here. Completed notes move to
[`docs/releases`](docs/releases/) and stay linked below.

## [Unreleased]

### Fixed

- The settings rail cut **Order & visibility** down to "Order & visib…". It is now
  **Show & order**, which fits, and a check keeps any future nav label inside the
  width the rail actually has.
- The Wi-Fi row could not say it was blocked by a hardware switch while Ethernet was
  connected, because the Ethernet note was checked first. The switch was disabled with
  nothing explaining why. The block now outranks a note about a different interface.
- `qs ipc call menu settings <name>` did nothing at all when the name was one a
  release had since renamed, so a keybind written against an older version stopped
  opening Settings without saying so. It now opens Settings on Theme, as the README
  already described, and still reports the unknown name and the valid ones.
- With Ethernet and Wi-Fi both connected, the network widget named the Wi-Fi
  network and sampled it for the traffic readout, while the machine was routing
  over the wired link — so a docked laptop reported an SSID and near-zero speeds
  during a download. The live wired link now wins, a wired device with no carrier
  loses to Wi-Fi, and disconnecting from the Wi-Fi list acts on the Wi-Fi radio
  rather than on whichever link is currently in front.
- A failed Night Light check left an already-running `hyprsunset` unnoticed, so
  the toggle read as off and turning it on would have started a second one. Night
  Light now says when it could not check, and adopts a running one on the exit
  code rather than only on what the check printed.
- Wi-Fi and Airplane Mode kept offering toggles that a hardware rfkill switch
  refuses, so every tap was a silent no-op. The Wi-Fi row now says it is blocked
  by the hardware switch, and Airplane Mode leaves out a radio it cannot reach.
- A palette file that stopped being readable was invisible: the shell kept the
  last good colors, which is right, but nothing said why new colors never
  arrived. Theme and Maintenance now say the file could not be read.
- Brightness writes were unbounded and their result discarded. A write that
  `brightnessctl` cannot perform now says so instead of letting the value snap
  back unexplained, and one that hangs can no longer wedge brightness for the
  rest of the session.
- Quick actions showed Power Mode as live when no daemon answers, where every tap
  did nothing, and reported a failed Night Light toggle as simply off.
- Acting on a notification lost it from history. Clicking an action told the
  sender, which closed the notification before the card's exit animation reached
  the archive step, so it was dropped — while dismissing the same notification
  kept it. Notifications a sender withdraws on its own are now kept too.
- A supervised process could retire on a signal that happened to share a number
  with an exit code it was told to give up on, because the crash/normal status
  beside the exit code was discarded.
- Settings › Bar › Underline says when screenshot feedback has stopped because
  there is no screenshot folder to watch, instead of showing the control as live.

## Releases

- [0.5.1](docs/releases/0.5.1.md) — 2026-08-13
- [0.5.0](docs/releases/0.5.0.md) — 2026-08-13
- [0.4.0](docs/releases/0.4.0.md) — 2026-08-12
- [0.3.0](docs/releases/0.3.0.md) — 2026-08-11
- [0.2.0](docs/releases/0.2.0.md) — 2026-08-10
- [0.1.0](docs/releases/0.1.0.md) — 2026-08-08
