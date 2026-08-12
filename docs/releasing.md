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
