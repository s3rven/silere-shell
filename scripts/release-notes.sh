#!/usr/bin/env bash
# Print the CHANGELOG section for one released version.
#
# Usage: release-notes.sh 0.1.0      (a leading "v" is accepted and stripped)
#
# Exits non-zero when the version has no section, so a tag cannot be published
# with notes that were never written.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG="${SILERE_CHANGELOG:-$ROOT/CHANGELOG.md}"
PERFORMANCE="${SILERE_PERFORMANCE:-$ROOT/PERFORMANCE.md}"

version="${1-}"
if [ -z "$version" ]; then
    echo "usage: ${0##*/} <version>" >&2
    exit 2
fi
version="${version#v}"

if [ ! -f "$CHANGELOG" ]; then
    echo "release-notes: no changelog at $CHANGELOG" >&2
    exit 1
fi

if [ ! -f "$PERFORMANCE" ]; then
    echo "release-notes: no performance history at $PERFORMANCE" >&2
    exit 1
fi

if [ "$version" = "Unreleased" ] || [ "$version" = "unreleased" ]; then
    echo "release-notes: refusing to publish the Unreleased section" >&2
    exit 1
fi

# the bench stays manual: a headless CI runner cannot reproduce the reference session
if ! grep -qF "| $version |" "$PERFORMANCE"; then
    echo "release-notes: PERFORMANCE.md has no entry for $version" >&2
    echo "release-notes: measure the release candidate and add a $version table row before tagging" >&2
    exit 1
fi

# Keep a Changelog headings look like "## [0.1.0] - 2026-08-08"; take everything
# up to the next "## " heading, which is the previous release or Unreleased.
section="$(awk -v want="$version" '
    /^## / {
        if (taking) exit
        line = $0
        sub(/^## +\[?/, "", line)
        sub(/\].*$/, "", line)
        sub(/ +-.*$/, "", line)
        if (line == want) { taking = 1; next }
        next
    }
    taking { print }
' "$CHANGELOG")"

# strip leading and trailing blank lines without collapsing the body
section="$(printf '%s\n' "$section" | sed -e '/./,$!d')"
section="$(printf '%s\n' "$section" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"

if [ -z "$section" ]; then
    echo "release-notes: CHANGELOG.md has no entry for $version" >&2
    echo "release-notes: add a '## [$version] - <date>' section before tagging" >&2
    exit 1
fi

printf '%s\n' "$section"
