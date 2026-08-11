#!/usr/bin/env bash
# Print the archived notes for one released version.
#
# Usage: release-notes.sh 0.1.0      (a leading "v" is accepted and stripped)
#
# Exits non-zero when the version has no section, so a tag cannot be published
# with notes that were never written.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG="${SILERE_CHANGELOG:-$ROOT/CHANGELOG.md}"
RELEASE_DIR="${SILERE_RELEASE_DIR:-$ROOT/docs/releases}"

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

if [ "$version" = "Unreleased" ] || [ "$version" = "unreleased" ]; then
    echo "release-notes: refusing to publish the Unreleased section" >&2
    exit 1
fi

extract_section() {
    awk -v want="$version" '
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
' "$1"
}

section="$(extract_section "$CHANGELOG")"

archive="$RELEASE_DIR/$version.md"
if [ -z "$section" ] && [ -f "$archive" ]; then
    section="$(awk '
        NR == 1 && /^# / { next }
        !started && /^Released [0-9]{4}-[0-9]{2}-[0-9]{2}\.$/ { next }
        { print; if ($0 ~ /[^[:space:]]/) started=1 }
    ' "$archive")"
fi

# strip leading and trailing blank lines without collapsing the body
section="$(printf '%s\n' "$section" | sed -e '/./,$!d')"
section="$(printf '%s\n' "$section" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"

if [ -z "$section" ]; then
    echo "release-notes: no notes found for $version" >&2
    echo "release-notes: add $RELEASE_DIR/$version.md before tagging" >&2
    exit 1
fi

printf '%s\n' "$section"
