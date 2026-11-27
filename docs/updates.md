# Updates and recovery

[All docs](README.md) · [Installation](install.md) · [Troubleshooting](troubleshooting.md)

## Install a release

Open Settings › System › Overview, check for a Silere release, read its notes, then choose Install and Confirm.
From a terminal:

```bash
silere update            # check
silere update --apply    # install
```

Silere verifies the release's signature and validates the new version before it replaces anything, and it
needs an internet connection to confirm the release is still published. The menu installs the release you
reviewed; if a background check finds a newer one before you confirm, review that one first.

The updater restarts the running shell, so a new release never runs beside the old one; with no shell running,
the next start uses it. `silere version` shows the installed version, and `silere status` which checkout is
running and the updater's state. If the release installs but the service manager refuses the restart, the
updater says so and keeps rollback available: run `silere restart` to retry, or roll back.

## Restore the previous version

```bash
silere update --rollback
```

This restores the revision the update replaced and restarts the running shell. It works from a terminal even
when the bar and menu will not open. Rollback clears the last release check, so run `silere update` when you are
ready to look at releases again.

## Local edits and development checkouts

The updater refuses to overwrite local edits. `silere repair` previews them, `silere repair --apply` saves them
in a Git stash and restores the shipped files, and `silere repair --undo` brings the latest saved edits back.

A checkout marked as a development install, or on a branch other than `main`, is yours to manage with Git, and
self-update stays off there. A package install is updated by its package manager.

## Automatic checks and package updates

The installer's optional timer checks for Silere releases once a day and marks one on the bar. It never installs
on its own. If turning the timer on or off fails, Settings shows the error and the switch follows the timer's
real state.

On a connection NetworkManager marks as metered, Silere skips the automatic package checks and the daily release
check. Package checks retry after a network change or within five minutes while the session is awake, the
release timer on its next daily run, and Check in Overview checks at once.

The bar's package update count covers your distribution, Flatpak and AUR packages, apart from Silere's own
releases; install those updates with your package manager. On Arch with `paru` or `yay` as the only checker,
turn on Include AUR packages in Settings › System › Overview before Track package updates.

## Interrupted updates

If power is lost or the updater is killed, the next update run reads its saved transaction and either keeps the
validated revision or restores the previous one. It stops instead if switching would replace local edits or
collide with an untracked file, ignored files and file-to-directory changes included. If it reports damaged
state, run `silere doctor`: the damaged journal is kept under your XDG state folder and its location reported.
That run leaves the checkout alone, and later checks can run again.

## How validation works

The updater checks out the signed release in a separate Git worktree, type-checks its QML and starts the staged
shell in a sandbox against a copy of your settings, all before it touches the live checkout. A staged shell that
exits early fails validation; if the display is unreachable, the updater says it skipped that start.

A private transaction journal records that validation passed, and recovery authenticates it against a snapshot of
the previously installed release key. The journal stays until the running shell reports the revision the update
installed, so rollback stays available until then.
