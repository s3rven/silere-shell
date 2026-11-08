# Updates and recovery

[All docs](README.md) · [Installation](install.md) · [Troubleshooting](troubleshooting.md)

## Install a release

Open **Settings › System › Overview**, check for a Silere release, read the release
notes, then choose **Install** and **Confirm**.

From a terminal:

```bash
silere update
silere update --apply
```

The first command checks; the second installs. Silere verifies the release signature
and validates the new version before replacing the installed files. Applying an
update needs an internet connection to confirm the release is still published.

The menu installs the release you reviewed. If a background check changes the
release before you confirm, review it again before installing.

The updater restarts the running shell, so a new release never runs beside the old one.
If no shell is running, the next start uses it. `silere version` shows the installed version;
`silere status` shows which checkout is running and the updater state.

If the release installs but the service manager rejects its restart, the updater
reports the failure and keeps rollback available. Run `silere restart` to retry, or
`silere update --rollback` to restore the previous revision.
Later update checks keep that rollback too; the old shell still running does not
prove the new release started.

## Restore the previous version

If an update breaks something, run:

```bash
silere update --rollback
```

This restores the revision the update replaced and restarts the running shell. You can run
rollback from a terminal even when the bar and menu will not open.

Rollback clears the previous release check. Run `silere update` when you're ready
to review available releases again.

## Local edits or development checkouts

The updater refuses to overwrite local edits. Preview them with:

```bash
silere repair
```

`silere repair --apply` saves the edits in a reversible Git stash and restores the
shipped files. `silere repair --undo` restores the latest saved repair. Review the
preview before applying it.

A checkout marked as a development install, or a checkout on a branch other than
`main`, is managed with Git. Self-update is disabled there. Package installations
are updated through the system package manager.

## Automatic checks and system packages

The installer's optional update timer checks for Silere releases. Installing one
still needs confirmation. It does not silently install a new shell version.
If a timer change fails, Settings shows the error and refreshes the switch to
match the timer's actual state.

The bar's package update badge counts distribution and AUR packages separately
from Silere releases. Use your package manager to install those updates.

## Interrupted updates

If power is lost or the updater is killed, the next update run checks its saved
transaction and either keeps the validated revision or restores the previous one.
It refuses to reset a checkout that gained local edits after the interruption.

If recovery reports damaged state, run `silere doctor`. Silere preserves the
damaged journal under your XDG state directory and reports its location. That
failed run leaves the checkout alone; later update checks can run again.

## How validation works

The updater stages the signed release in a separate, detached Git worktree. It
checks QML types and starts the staged shell in a sandbox against a copy of your
settings before changing the live checkout.

A private transaction journal records that validation passed. Recovery authenticates
it against a snapshot of the previously installed release key. The journal remains
until the shell is confirmed running on the new revision.
