# Security

## Reporting

Report a vulnerability privately through
[GitHub Security Advisories](https://github.com/s3rven/silere-shell/security/advisories/new).
Please don't open a public issue for anything exploitable.

Expect a first reply within a week. Fixes ship in the next patch release, credited
unless you'd rather not be.

## Scope

Silere runs as the user's own session, with their permissions. It has no daemon,
no network listener, and no privileged helper. What's in scope:

- Notification content reaching the shell over D-Bus, including icon and image paths.
- Anything the shell passes to a process it spawns.
- Files the shell reads or writes under `$XDG_CONFIG_HOME`, `$XDG_STATE_HOME` and
  `$XDG_CACHE_HOME`, and the `~/.local` paths the installer creates (the `silere`
  command and the bundled font).
- The installer and updater scripts under `scripts/`.

Out of scope: Quickshell, the compositor, and anything requiring an attacker who
already runs code as the user.

Notification images accept Quickshell's in-memory image provider, but not a filesystem
path supplied by the sender. Application icon names still resolve through the installed
icon theme.

## Update trust

Updates are verified: `scripts/update.sh` fast-forwards to an annotated tag signed by
a key in `security/update-signers`, using the copy of that key already in the installed
checkout, and only when the tag belongs to `origin/main`. Rolling back a completed
update (`--rollback`) and recovering an interrupted one also reset to a revision the
signed transaction journal names.
After signature verification and confirmation, the update gate runs the candidate
release's QML checker and starts its shell in smoke mode before switching revisions.

Remote cover art is optional. Enabling it sends requests to image hosts named by
players, which can reveal what you are playing; Qt's remote image loading has also
caused a shell crash on some systems.

The first install is a different matter. `git clone` followed by
`scripts/install.sh` runs code from `main` before any signature has been checked,
and a repository that shipped a tampered `install.sh` would also ship a tampered
signer list. Nothing inside the repository can close that gap — verifying a clone
needs a trust anchor obtained separately from it. Treat the initial clone as the
point where you decide to trust the source, and prefer a distribution package
where one is available.
