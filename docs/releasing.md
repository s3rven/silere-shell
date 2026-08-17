# Releasing

Maintainer notes. Contributors don't need any of this.

## Cadence

Let `main` breathe. Ship fixes as patch releases — `0.4.1`, `0.4.2` — and save a minor
version for a batch worth announcing. A minor bump should read as "here is what changed",
not "here is Tuesday". Four minors in four days looks like an unstable API from the
outside, whatever the diff actually says.

## Tags

Release tags must be annotated `vMAJOR.MINOR.PATCH` tags signed by a key in
`security/update-signers`. Both the release workflow and the installed updater
reject anything else.

Repository rules should also restrict creation and deletion of matching `v*`
tags — signature checks complement access control rather than replacing it.

## AUR

`packaging/aur/` is the source of truth for `silere-shell-git`, and lint keeps
`.SRCINFO` in step with the `PKGBUILD`. **The package is not on the AUR yet**, so
these files are ready rather than live, and the README deliberately does not point
at a package that would fail to install. Publishing needs an AUR account; once one
exists it is a manual push, and only the first one really matters:

```bash
git clone ssh://aur@aur.archlinux.org/silere-shell-git.git /tmp/silere-aur
cp packaging/aur/{PKGBUILD,.SRCINFO,silere-shell-git.install} /tmp/silere-aur/
cd /tmp/silere-aur && git commit -am "<version>" && git push
```

Because the package tracks `git`, it rebuilds from `main` on the user's machine
and does not need a push per release — but the AUR copy still has to exist, and
the `depends` floor and `.install` message only reach users once it does.

## Key rotation

Ship the new public key in a release signed by the **existing** key first. Only
remove an old key after supported installations have had time to receive that
transition release.

## Changelog

Notable user-facing or operational changes go in `CHANGELOG.md` under
Unreleased. Routine refactors, tests and formatting don't need an entry unless
they change behaviour someone running Silere will notice.

When tagging, move the completed notes to `docs/releases/<version>.md` and add
the version and date to the release index in `CHANGELOG.md`. The release
workflow publishes that archived body, and lint rejects missing, unlinked or
empty archives.
