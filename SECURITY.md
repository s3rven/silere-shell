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
- Files the shell reads or writes under `$XDG_CONFIG_HOME` and `$XDG_STATE_HOME`.
- The installer and updater scripts under `scripts/`.

Out of scope: Quickshell, the compositor, and anything requiring an attacker who
already runs code as the user.
