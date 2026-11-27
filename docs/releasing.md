# Releasing

Maintainer notes. Contributors don't need any of this.

## Cadence

Let `main` breathe. Ship fixes as patch releases (`0.4.1`, `0.4.2`) and save a minor version for a batch worth
announcing. A minor bump should read as "here is what changed", not "here is Tuesday". Four minors in four days
looks like an unstable API from the outside, whatever the diff says.

## Before tagging

Run `bash dev/test-faults.sh` on a machine with a render node. CI has none, so nothing else covers broken tools
and hostile input.

Then, after `silere restart`, ten minutes by hand on the daily paths no probe sees (Lock & sleep under hyprlock
was broken from 1.5.0 to 1.8.0 while every check passed):

- Lock & sleep with hyprlock, then suspend and resume
- volume and brightness keys, with the OSD
- a notification click raising its window; Do Not Disturb on and off
- a notification arriving over a fullscreen window
- a tray menu; Wi-Fi off and on
- plug in a second monitor
- `silere update` (check only)

## Tags

Release tags must be annotated `vMAJOR.MINOR.PATCH` tags signed by a key in `security/update-signers`. Both the
release workflow and the installed updater reject anything else.

Before tagging, set `release.json`'s `version` to the tag's version without the leading `v`. Keep its Quickshell
floor and settings schema in step with `scripts/lib/qml-modules.sh` and `services/ShellSettings.qml`; structural
lint checks both, and the release workflow rejects a version that doesn't match the tag. On `main`, the next
planned version may carry a `-dev` suffix.

Bump `pkgver` in `packaging/aur/PKGBUILD` and `.SRCINFO` to the new version too. Lint fails once a tag is newer
than the `pkgver` it finds, and the release workflow runs lint on the tagged commit, so tag the commit that
carries the bump; a tag on the commit before it fails the release and publishes nothing.

Repository rules should also restrict who can create and delete `v*` tags: the signature checks add to access
control, they don't replace it.

## AUR

`packaging/aur/` is the source of truth for `silere-shell-git`, and lint keeps `.SRCINFO` in step with the
`PKGBUILD`. **The package is not on the AUR yet**, so these files are ready rather than live, and the README
deliberately does not point at a package that would fail to install. It tracks `main`, so what is pushed to
`main` reaches its users on their next rebuild. Publishing needs an AUR account; once one exists it is a manual
push, and only the first one really matters:

```bash
git -c init.defaultBranch=master clone ssh://aur@aur.archlinux.org/silere-shell-git.git /tmp/silere-aur
cp packaging/aur/{PKGBUILD,.SRCINFO,silere-shell-git.install,LICENSE} /tmp/silere-aur/
cd /tmp/silere-aur && git add . && git commit -m "<version>" && git push
```

`LICENSE` is 0BSD and covers the package files only; Arch does not promote a package to its official
repositories without one. Because the package tracks `git`, it rebuilds from `main` on the user's machine and
needs no push per release, but the AUR copy still has to exist before the `depends` floor and the `.install`
message reach anyone.

## Key rotation

Ship the new public key in a release signed by the existing key first. Remove an old key only after supported
installations have had time to receive that transition release.

## Changelog

Notable user-facing or operational changes go in `CHANGELOG.md` under Unreleased. Routine refactors, tests and
formatting need no entry unless they change behaviour someone running Silere will notice.

Keep sections in this order: Added, Changed, Fixed, Removed, Security. Once a section passes a dozen entries,
split it under `####` headings naming the part of the shell each entry touches (Bar, Menu and settings,
Notifications, Media, Network, System, Install and updates) rather than leaving one flat run to read through.
Lint rejects a heading used twice in one file, so a part that appears under two sections needs a distinguishing
word, such as `Bar` under Changed and `Bar fixes` under Fixed. Archived notes nest one level higher, under `###`.

## Performance numbers

Record a row in [`perf-history.md`](perf-history.md) as part of tagging, and quote both states in the reference
table of [`performance.md`](performance.md) (ci-lint checks it). The README quotes those figures, and a
per-release measurement on a known machine is what keeps them true.

```bash
silere restart
sleep 30
bash scripts/bench.sh 30 --label <version>            # cold row
bash scripts/bench.sh 30 --warm --label <version>     # warm row
```

`bench.sh` labels every run without `--warm` as `as-found`, since it cannot tell a fresh process from an old one;
the restart is what makes that row the cold one. Check that nothing else is busy first
(`ps -eo pcpu,comm --sort=-pcpu | head`): another program holding the CPU skews both PSS and CPU.

Both rows go in under the reference machine they came from. Hardware not already in that table takes a new
letter, since rows from different machines are not comparable. A new release needs its own measured values;
never assign numbers from another revision to it. Record only a run the report calls `steady`, with a
per-second median near zero; `noisy` means input landed mid-sample.

A few MB between releases is font and driver noise. Tens of MB, a descriptor count that no longer settles, or a
thread count past the core count holds the tag.

## Release archives

When tagging, move the completed notes to `docs/releases/<version>.md` and add the version and date to the
release index in `CHANGELOG.md`. The release workflow publishes that archived body, and lint rejects missing,
unlinked or empty archives.

An archive reads:

1. `# Silere Shell <version>`, a line lint checks exactly
2. `Released <YYYY-MM-DD>.`
3. an `**Upgrading:**` line, even when it only says there is nothing to do
4. the changelog sections
5. a `[Compare with <previous>]` link to the GitHub compare view

Lines 1 and 2 are stripped before publishing, so everything below them is the release body. The index entries in
`CHANGELOG.md` are parsed as `- [<version>](docs/releases/<version>.md) — <date>`; lint reads that shape, so the
list cannot become a table.
