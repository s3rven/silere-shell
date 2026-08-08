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
is_qt6_tool() {
    local version
    version="$("$1" --version 2>&1 || true)"
    [[ "$version" =~ (^|[[:space:]])6\. ]]
}

find_qmlcachegen() {
    local candidate
    candidate="$(command -v qmlcachegen 2>/dev/null || true)"
    if [ -n "$candidate" ] && is_qt6_tool "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
    fi
    for candidate in \
        /usr/lib/qt6/qmlcachegen \
        /usr/lib64/qt6/qmlcachegen \
        /usr/lib/x86_64-linux-gnu/qt6/libexec/qmlcachegen \
        /usr/lib/qt6/libexec/qmlcachegen \
        /usr/local/lib/qt6/qmlcachegen
    do
        if [ -x "$candidate" ] && is_qt6_tool "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

find_qmllint() {
    local candidate
    candidate="$(command -v qmllint 2>/dev/null || true)"
    if [ -n "$candidate" ] && is_qt6_tool "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
    fi
    for candidate in \
        /usr/lib/qt6/bin/qmllint \
        /usr/lib64/qt6/bin/qmllint \
        /usr/lib/x86_64-linux-gnu/qt6/bin/qmllint \
        /usr/lib/qt6/qmllint \
        /usr/local/lib/qt6/bin/qmllint
    do
        if [ -x "$candidate" ] && is_qt6_tool "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

# Shared with install.sh/check.sh/CI: same QML2_IMPORT_PATH/qtpaths6-aware root
# list, instead of a fourth hardcoded copy of just the distro fallback paths.
source "$ROOT/scripts/lib/qml-modules.sh"

QMLCACHEGEN="$(find_qmlcachegen || true)"
if [ -z "$QMLCACHEGEN" ]; then
    if [ "${SILERE_REQUIRE_QML_TOOLS:-0}" = "1" ]; then
        echo "FAIL: Qt 6 qmlcachegen not found" >&2
        exit 1
    fi
    echo "SKIP: Qt 6 qmlcachegen not found; headless QML type-check unavailable"
    exit 0
fi
qml_import_args=()
for qml_import_root in "${_silere_qml_import_roots[@]}"; do
    [ -d "$qml_import_root" ] && qml_import_args+=(-I "$qml_import_root")
done
unset qml_import_root
if [ "${#qml_import_args[@]}" -eq 0 ]; then
    if [ "${SILERE_REQUIRE_QML_TOOLS:-0}" = "1" ]; then
        echo "FAIL: Quickshell QML module directory not found" >&2
        exit 1
    fi
    echo "SKIP: Quickshell QML module directory not found; headless QML type-check unavailable"
    exit 0
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/silere-qmlcache.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

CHECK_ROOT="$tmp/source"
mkdir -p "$CHECK_ROOT"
cp -R "$ROOT/assets" "$ROOT/config" "$ROOT/modules" "$ROOT/services" "$CHECK_ROOT/"
cp "$ROOT/shell.qml" "$CHECK_ROOT/shell.qml"
if [ ! -f "$CHECK_ROOT/config/MatugenTheme.qml" ]; then
    if [ ! -f "$CHECK_ROOT/config/MatugenTheme.default.qml" ]; then
        echo "FAIL: config/MatugenTheme.default.qml is missing" >&2
        exit 1
    fi
    cp "$CHECK_ROOT/config/MatugenTheme.default.qml" "$CHECK_ROOT/config/MatugenTheme.qml"
fi

had_failure=0
count=0
printf 'checking QML bytecode'
while IFS= read -r f; do
    count=$((count + 1))
    if [ $((count % 20)) -eq 0 ]; then printf '.'; fi
    out="$tmp/$count.qmlc"
    if err="$("$QMLCACHEGEN" --only-bytecode -I "$CHECK_ROOT" "${qml_import_args[@]}" -o "$out" "$f" 2>&1)"; then
        :
    else
        rc=$?
        [ "$rc" -eq 130 ] && exit 130
        printf '\nFAIL: %s\n%s\n' "${f#"$CHECK_ROOT"/}" "$err" >&2
        had_failure=1
    fi
done < <(find "$CHECK_ROOT" -name "*.qml" -not -path "*/.git/*")
printf '\n'

# qmllint catches unresolved and unused imports that qmlcachegen accepts
QMLLINT="$(find_qmllint || true)"
if [ -z "$QMLLINT" ]; then
    if [ "${SILERE_REQUIRE_QML_TOOLS:-0}" = "1" ]; then
        echo "FAIL: Qt 6 qmllint not found" >&2
        had_failure=1
    else
        echo "note: Qt 6 qmllint not found; missing-import check skipped"
    fi
else
    # Promote high-signal diagnostics that have a clean baseline. Categories
    # dominated by third-party qmltypes noise stay warnings until that metadata
    # can describe the Quickshell APIs accurately.
    qmllint_args=(
        --import error
        --unused-imports error
        --alias-cycle error
        --assignment-in-condition error
        --deprecated error
        --duplicate-enum-entries error
        --duplicate-inline-component error
        --duplicate-property-binding error
        --duplicated-name error
        --eval error
        --inheritance-cycle error
        --invalid-lint-directive error
        --missing-enum-entry error
        --missing-type error
        --non-list-property error
        --property-override error
        --read-only-property error
        --required error
        --unreachable-code error
        --unterminated-case error
        --unintentional-empty-block error
        --unresolved-alias error
    )
    qmllint_help="$("$QMLLINT" --help 2>&1 || true)"
    unsupported_lint_args=()
    for ((i = 0; i < ${#qmllint_args[@]}; i += 2)); do
        if ! grep -Fq -- "${qmllint_args[i]}" <<< "$qmllint_help"; then
            unsupported_lint_args+=("${qmllint_args[i]}")
        fi
    done
    if [ "${#unsupported_lint_args[@]}" -gt 0 ]; then
        printf 'FAIL: installed qmllint is too old for required diagnostics: %s\n' \
            "${unsupported_lint_args[*]}" >&2
        echo "      update the Qt declarative tooling, or remove this older qmllint from PATH" >&2
        had_failure=1
    else
        printf 'checking QML imports'
        lint_count=0
        while IFS= read -r f; do
            lint_count=$((lint_count + 1))
            if [ $((lint_count % 20)) -eq 0 ]; then printf '.'; fi
            if err="$("$QMLLINT" "${qmllint_args[@]}" -I "$CHECK_ROOT" "${qml_import_args[@]}" "$f" 2>&1)"; then
                :
            else
                rc=$?
                [ "$rc" -eq 130 ] && exit 130
                printf '\nFAIL: %s\n%s\n' "${f#"$CHECK_ROOT"/}" "$err" >&2
                had_failure=1
            fi
        done < <(find "$CHECK_ROOT" -name "*.qml" -not -path "*/.git/*")
        printf '\n'
    fi
fi

if [ "$had_failure" -ne 0 ]; then
    echo "FAIL: headless QML type-check found broken imports/types" >&2
    exit 1
fi
echo "headless QML type-check passed ($count files)"
