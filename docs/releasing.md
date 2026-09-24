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

Before tagging, set `release.json`'s `version` to the exact tag version without the
leading `v`. Keep its Quickshell floor and settings schema in step with
`scripts/lib/qml-modules.sh` and `services/ShellSettings.qml`; structural lint checks
both, and the release workflow rejects a version/tag mismatch. On `main`, the next
planned version may carry the `-dev` suffix.

Bump `pkgver` in `packaging/aur/PKGBUILD` and `.SRCINFO` to the new version too. Lint fails
once a tag is newer than the `pkgver` it finds.

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

Keep sections in this order — Added, Changed, Fixed, Removed, Security. Once a
section passes a dozen entries, split it under `####` headings naming the part of
the shell each entry touches (Bar, Menu and settings, Notifications, Media,
Network, System, Install and updates) rather than leaving one flat run to read
through. Lint rejects a heading used twice in one file, so a part that appears
under two sections needs a distinguishing word — `Bar` under Changed, `Bar fixes`
under Fixed. Archived notes nest one level higher, under `###`.

## Performance numbers

Record a row in [`perf-history.md`](perf-history.md) as part of tagging. The README quotes
figures, and a per-release measurement on a known machine is what keeps them true.

```bash
systemctl --user restart silere-shell.service
sleep 30
bash scripts/bench.sh 30 --label <version>            # cold row
bash scripts/bench.sh 30 --warm --label <version>     # warm row
```

The restart is what makes the cold row cold; without it `bench.sh` reports `as-found`.

Both rows go in against the reference machine letter they came from. Hardware not already
in that table takes a new letter — rows from different machines are not comparable.

A few MB between releases is font and driver noise. Tens of MB, a descriptor count that no
longer settles, or a thread count past the core count holds the tag.

## Release archives

When tagging, move the completed notes to `docs/releases/<version>.md` and add
the version and date to the release index in `CHANGELOG.md`. The release
workflow publishes that archived body, and lint rejects missing, unlinked or
empty archives.

An archive reads:

1. `# Silere Shell <version>` — lint checks this line exactly
2. `Released <YYYY-MM-DD>.`
3. an **Upgrading:** line, even when it only says there is nothing to do
4. the changelog sections
5. a `[Compare with <previous>]` link to the GitHub compare view

Lines 1 and 2 are stripped before publishing, so everything below them is the
release body. The index entries in `CHANGELOG.md` are parsed as
`- [<version>](docs/releases/<version>.md) — <date>`; lint reads that shape, so
the list cannot become a table.
