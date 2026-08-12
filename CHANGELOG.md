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
