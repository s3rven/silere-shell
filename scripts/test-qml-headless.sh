#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

on_interrupt() {
    exit 130
}
trap on_interrupt INT TERM

# qmlcachegen AOT-compiles each file to bytecode, which requires fully
# resolving every import and type — a thorough type-check with no Wayland
# display needed. It's part of qt6-declarative, a quickshell dependency, but
# isn't on PATH on most distros.
#
# Earlier attempt used `qs -p scripts/<probe>.qml` with a synthetic file that
# instantiated every exported component. That broke unpredictably: Quickshell
# derives its own project root from the entry file's directory, and probing
# from scripts/ (one level below files importing two levels up, e.g.
# modules/common/Pill.qml's `../../config`) made some otherwise-fine types
# fail to resolve. Per-file qmlcachegen with explicit -I roots has no such
# scoping and needs no component list to maintain.
find_qmlcachegen() {
    command -v qmlcachegen 2>/dev/null && return 0
    local candidate
    for candidate in \
        /usr/lib/qt6/qmlcachegen \
        /usr/lib64/qt6/qmlcachegen \
        /usr/lib/x86_64-linux-gnu/qt6/libexec/qmlcachegen \
        /usr/lib/qt6/libexec/qmlcachegen \
        /usr/local/lib/qt6/qmlcachegen
    do
        [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

find_qmllint() {
    command -v qmllint 2>/dev/null && return 0
    local candidate
    for candidate in \
        /usr/lib/qt6/bin/qmllint \
        /usr/lib64/qt6/bin/qmllint \
        /usr/lib/x86_64-linux-gnu/qt6/bin/qmllint \
        /usr/lib/qt6/qmllint \
        /usr/local/lib/qt6/bin/qmllint
    do
        [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

# Shared with install.sh/check.sh/CI: same QML2_IMPORT_PATH/qtpaths6-aware root
# list, instead of a fourth hardcoded copy of just the distro fallback paths.
source "$ROOT/scripts/lib/qml-modules.sh"
find_qml_import_root() {
    local candidate
    for candidate in "${_silere_qml_import_roots[@]}"; do
        [ -d "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

QMLCACHEGEN="$(find_qmlcachegen || true)"
if [ -z "$QMLCACHEGEN" ]; then
    echo "SKIP: qmlcachegen not found; headless QML type-check unavailable"
    exit 0
fi
QML_IMPORT_ROOT="$(find_qml_import_root || true)"
if [ -z "$QML_IMPORT_ROOT" ]; then
    echo "SKIP: Quickshell QML module directory not found; headless QML type-check unavailable"
    exit 0
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/silere-qmlcache.XXXXXX")"
seeded_theme=false
cleanup() {
    if $seeded_theme; then rm -f "$ROOT/config/MatugenTheme.qml"; fi
    rm -rf "$tmp"
}
trap cleanup EXIT

if [ ! -f "$ROOT/config/MatugenTheme.qml" ]; then
    if [ ! -f "$ROOT/config/MatugenTheme.default.qml" ]; then
        echo "FAIL: config/MatugenTheme.default.qml is missing" >&2
        exit 1
    fi
    cp "$ROOT/config/MatugenTheme.default.qml" "$ROOT/config/MatugenTheme.qml"
    seeded_theme=true
fi

had_failure=0
count=0
printf 'checking QML bytecode'
while IFS= read -r f; do
    count=$((count + 1))
    if [ $((count % 20)) -eq 0 ]; then printf '.'; fi
    out="$tmp/$count.qmlc"
    if err="$("$QMLCACHEGEN" --only-bytecode -I "$ROOT" -I "$QML_IMPORT_ROOT" -o "$out" "$f" 2>&1)"; then
        :
    else
        rc=$?
        [ "$rc" -eq 130 ] && exit 130
        printf '\nFAIL: %s\n%s\n' "${f#"$ROOT"/}" "$err" >&2
        had_failure=1
    fi
done < <(find "$ROOT" -name "*.qml" -not -path "*/.git/*")
printf '\n'

# qmlcachegen --only-bytecode emits bytecode without erroring on a type left
# unresolved by a missing import (RectangularShadow with no `import
# QtQuick.Effects` still compiles). qmllint with the import category promoted to
# an error catches exactly that, and is otherwise silent on the tree. Optional
# like qmlcachegen: a missing qmllint downgrades to a note, not a failure.
QMLLINT="$(find_qmllint || true)"
if [ -z "$QMLLINT" ]; then
    echo "note: qmllint not found; missing-import check skipped"
else
    printf 'checking QML imports'
    lint_count=0
    while IFS= read -r f; do
        lint_count=$((lint_count + 1))
        if [ $((lint_count % 20)) -eq 0 ]; then printf '.'; fi
        if err="$("$QMLLINT" --import error -I "$ROOT" -I "$QML_IMPORT_ROOT" "$f" 2>&1)"; then
            :
        else
            rc=$?
            [ "$rc" -eq 130 ] && exit 130
            printf '\nFAIL: %s\n%s\n' "${f#"$ROOT"/}" "$err" >&2
            had_failure=1
        fi
    done < <(find "$ROOT" -name "*.qml" -not -path "*/.git/*")
    printf '\n'
fi

if [ "$had_failure" -ne 0 ]; then
    echo "FAIL: headless QML type-check found broken imports/types" >&2
    exit 1
fi
echo "headless QML type-check passed ($count files)"
