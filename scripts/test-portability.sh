#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/silere-portability-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    [ "$actual" = "$expected" ] || fail "$label (expected '$expected', got '$actual')"
}

test_marker_removal() (
    SILERE_SCRIPT_LIB_ONLY=1 source "$ROOT/scripts/uninstall.sh"
    local dir="$TMP/markers"
    mkdir -p "$dir"

    printf '%s\n' before '# silere-shell begin' managed '# silere-shell end' after > "$dir/valid.conf"
    _remove_block "$dir/valid.conf" '# silere-shell begin' '# silere-shell end' \
        || fail "valid marker pair was rejected"
    assert_eq $'before\nafter' "$(<"$dir/valid.conf")" "valid marker removal"

    local name
    for name in missing-end reversed duplicate-begin duplicate-pair; do
        case "$name" in
            missing-end)
                printf '%s\n' before '# silere-shell begin' valuable > "$dir/$name.conf"
                ;;
            reversed)
                printf '%s\n' before '# silere-shell end' middle '# silere-shell begin' valuable > "$dir/$name.conf"
                ;;
            duplicate-begin)
                printf '%s\n' before '# silere-shell begin' one '# silere-shell end' middle '# silere-shell begin' valuable > "$dir/$name.conf"
                ;;
            duplicate-pair)
                printf '%s\n' before '# silere-shell begin' one '# silere-shell end' middle '# silere-shell begin' two '# silere-shell end' valuable > "$dir/$name.conf"
                ;;
        esac
        cp "$dir/$name.conf" "$dir/$name.before"
        if _remove_block "$dir/$name.conf" '# silere-shell begin' '# silere-shell end'; then
            fail "$name markers were accepted"
        fi
        [ "$(<"$dir/$name.before")" = "$(<"$dir/$name.conf")" ] || fail "$name markers changed the file"
    done

    printf '%s\n' before '-- silere-shell begin' managed '-- silere-shell end' after > "$dir/target.lua"
    ln -s target.lua "$dir/link.lua"
    _remove_block "$dir/link.lua" '-- silere-shell begin' '-- silere-shell end' \
        || fail "symlinked config marker removal failed"
    [ -L "$dir/link.lua" ] || fail "marker removal replaced a config symlink"
    assert_eq $'before\nafter' "$(<"$dir/target.lua")" "symlink target marker removal"
)

test_uninstall_targets_and_backups() (
    SILERE_SCRIPT_LIB_ONLY=1 source "$ROOT/scripts/uninstall.sh"
    local config="$TMP/external/main.lua" live="$TMP/live.conf"
    AUTOSTART_FILES=()
    _append_hypr_config_targets "$config"
    assert_eq "$config" "${AUTOSTART_FILES[0]}" "custom Lua main target"
    assert_eq "$TMP/external/custom/execs.lua" "${AUTOSTART_FILES[1]}" "custom Lua custom/execs target"
    assert_eq "$TMP/external/hyprland/execs.lua" "${AUTOSTART_FILES[2]}" "custom Lua hyprland/execs target"
    assert_eq "$TMP/external/execs.lua" "${AUTOSTART_FILES[3]}" "custom Lua execs target"

    printf 'live\n' > "$live"
    printf 'old\n' > "${live}.bak"
    if _backup_restore_allowed "$live"; then
        fail "backup restore was allowed over a live edited file"
    fi
    rm -f "$live"
    _backup_restore_allowed "$live" || fail "backup restore was rejected for a missing live file"
)

test_qml_module_lookup() (
    local imports="$TMP/qml-imports"
    mkdir -p "$imports/Silere/TestModule"
    printf 'module Silere.TestModule\n' > "$imports/Silere/TestModule/qmldir"

    # Import roots are resolved once at source time (not per call), so the
    # fake root must be in place before install.sh sources the QML-modules lib.
    QML2_IMPORT_PATH="$imports"
    QML_IMPORT_PATH=""
    SILERE_SCRIPT_LIB_ONLY=1 source "$ROOT/scripts/install.sh"

    _qml_module_available Silere.TestModule \
        || fail "QML module in temporary import root was not found"
    if _qml_module_available Silere.AbsentModule; then
        fail "absent QML module was reported as available"
    fi
)

make_proc() {
    local root="$1" pid="$2" comm="$3" ppid="$4" cwd="$5"
    shift 5
    mkdir -p "$root/$pid"
    printf '%s\n' "$comm" > "$root/$pid/comm"
    printf '%s (%s) S %s 0 0 0\n' "$pid" "$comm" "$ppid" > "$root/$pid/stat"
    printf '%s\0' "$@" > "$root/$pid/cmdline"
    ln -s "$cwd" "$root/$pid/cwd"
}

test_hypr_discovery() {
    local proc="$TMP/proc" session="$TMP/session" other="$TMP/other"
    mkdir -p "$proc" "$session/configs" "$other"
    printf 'return {}\n' > "$session/configs/main.lua"
    printf 'misc {}\n' > "$other/other.conf"

    make_proc "$proc" 100 Hyprland 1 "$other" Hyprland -c other.conf
    make_proc "$proc" 200 bash 300 "$session" bash
    make_proc "$proc" 300 Hyprland 1 "$session" Hyprland --config configs/main.lua

    local actual
    actual="$(
        SILERE_PROC_ROOT="$proc" SILERE_PARENT_PID=200 \
        HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/config" \
        bash "$ROOT/scripts/install.sh" --hypr-config-path
    )"
    assert_eq "$session/configs/main.lua" "$actual" "ancestor session and relative config resolution"

    local unique="$TMP/proc-unique"
    mkdir -p "$unique"
    make_proc "$unique" 400 Hyprland 1 "$session" Hyprland -c configs/main.lua
    actual="$(
        SILERE_PROC_ROOT="$unique" SILERE_PARENT_PID=999 \
        HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/config" \
        bash "$ROOT/scripts/install.sh" --hypr-config-path
    )"
    assert_eq "$session/configs/main.lua" "$actual" "unique same-user Hyprland fallback"

    local ambiguous="$TMP/proc-ambiguous"
    mkdir -p "$ambiguous"
    make_proc "$ambiguous" 500 Hyprland 1 "$session" Hyprland -c configs/main.lua
    make_proc "$ambiguous" 600 Hyprland 1 "$other" Hyprland -c other.conf
    actual="$(
        SILERE_PROC_ROOT="$ambiguous" SILERE_PARENT_PID=999 \
        HOME="$TMP/no-home" XDG_CONFIG_HOME="$TMP/no-home/config" \
        bash "$ROOT/scripts/install.sh" --hypr-config-path
    )"
    assert_eq "" "$actual" "ambiguous sessions must not be guessed"

    local empty="$TMP/proc-empty" fallback_home="$TMP/fallback-home"
    mkdir -p "$empty" "$fallback_home/config/hypr"
    printf 'return {}\n' > "$fallback_home/config/hypr/hyprland.lua"
    actual="$(
        SILERE_PROC_ROOT="$empty" SILERE_PARENT_PID=999 \
        HOME="$fallback_home" XDG_CONFIG_HOME="$fallback_home/config" \
        bash "$ROOT/scripts/install.sh" --hypr-config-path
    )"
    assert_eq "$fallback_home/config/hypr/hyprland.lua" "$actual" \
        "no Hyprland process falls back to XDG_CONFIG_HOME hyprland.lua"
}

test_atomic_units() (
    SILERE_SCRIPT_LIB_ONLY=1 source "$ROOT/scripts/update.sh"
    SYSTEMD_USER_DIR="$TMP/units"
    mkdir -p "$SYSTEMD_USER_DIR"
    printf 'old service\n' > "$SYSTEMD_USER_DIR/$SERVICE_UNIT"
    printf 'old timer\n' > "$SYSTEMD_USER_DIR/$TIMER_UNIT"

    _write_update_units || fail "atomic unit writer failed"
    [ "$(<"$ROOT/scripts/$TIMER_UNIT")" = "$(<"$SYSTEMD_USER_DIR/$TIMER_UNIT")" ] \
        || fail "timer unit content mismatch"
    grep -qF '__ROOT__' "$SYSTEMD_USER_DIR/$SERVICE_UNIT" \
        && fail "service placeholder was not replaced"
    grep -qF "scripts/update.sh" "$SYSTEMD_USER_DIR/$SERVICE_UNIT" \
        || fail "service ExecStart was not generated"
    if find "$SYSTEMD_USER_DIR" -maxdepth 1 -name '.silere-update.*.??????' -print -quit | grep -q .; then
        fail "temporary unit file was left behind"
    fi
)

test_repair_workflow() (
    local repo="$TMP/repair" preview
    mkdir -p "$repo/scripts"
    cp "$ROOT/scripts/repair.sh" "$repo/scripts/repair.sh"
    cp "$ROOT/.gitignore" "$repo/.gitignore"
    printf 'shipped\n' > "$repo/tracked.qml"

    git -C "$repo" init -q
    git -C "$repo" config user.name "Silere test"
    git -C "$repo" config user.email "test@example.invalid"
    git -C "$repo" add scripts/repair.sh .gitignore tracked.qml
    git -C "$repo" commit -qm "fixture"

    printf 'customized\n' > "$repo/tracked.qml"
    printf 'new widget\n' > "$repo/custom.qml"
    printf '{"barHeight":40}\n' > "$repo/settings.json"

    preview="$(bash "$repo/scripts/repair.sh")"
    printf '%s\n' "$preview" | grep -qF 'Nothing was changed' \
        || fail "repair preview did not state that it was side-effect free"
    assert_eq "customized" "$(<"$repo/tracked.qml")" "repair preview tracked file"
    [ -f "$repo/custom.qml" ] || fail "repair preview removed an untracked file"

    bash "$repo/scripts/repair.sh" --apply --yes >/dev/null
    assert_eq "shipped" "$(<"$repo/tracked.qml")" "repair apply tracked file"
    [ ! -e "$repo/custom.qml" ] || fail "repair apply left an untracked source file"
    assert_eq '{"barHeight":40}' "$(<"$repo/settings.json")" "repair apply personal settings"
    [ -z "$(git -C "$repo" status --short --untracked-files=normal)" ] \
        || fail "repair apply did not produce a clean checkout"
    git -C "$repo" stash list | grep -qF 'silere-repair ' \
        || fail "repair apply did not create a named stash"

    bash "$repo/scripts/repair.sh" --undo --yes >/dev/null
    assert_eq "customized" "$(<"$repo/tracked.qml")" "repair undo tracked file"
    assert_eq "new widget" "$(<"$repo/custom.qml")" "repair undo untracked file"
    assert_eq '{"barHeight":40}' "$(<"$repo/settings.json")" "repair undo personal settings"
)

test_marker_removal
test_uninstall_targets_and_backups
test_qml_module_lookup
test_hypr_discovery
test_atomic_units
# repair.sh builds a git fixture; skip where git is absent (e.g. minimal CI runners)
if command -v git >/dev/null 2>&1; then
    test_repair_workflow
else
    printf 'SKIP: repair workflow (git unavailable)\n'
fi

printf 'portability regression tests passed\n'
