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

test_xdg_paths_and_timer_default() (
    local home="$TMP/xdg-home" actual
    mkdir -p "$home"

    actual="$(
        HOME="$home" XDG_CONFIG_HOME=relative/config SILERE_SCRIPT_LIB_ONLY=1 \
            bash -c 'source "$1"; printf "%s" "$CONFIG_HOME"' _ "$ROOT/scripts/install.sh"
    )"
    assert_eq "$home/.config" "$actual" "installer relative XDG config fallback"

    actual="$(
        HOME="$home" XDG_CONFIG_HOME=/absolute/config SILERE_SCRIPT_LIB_ONLY=1 \
            bash -c 'source "$1"; printf "%s" "$CONFIG_HOME"' _ "$ROOT/scripts/uninstall.sh"
    )"
    assert_eq "/absolute/config" "$actual" "uninstaller absolute XDG config"

    actual="$(
        HOME="$home" XDG_CONFIG_HOME=relative/config XDG_CACHE_HOME=relative/cache \
            SILERE_SCRIPT_LIB_ONLY=1 bash -c \
            'source "$1"; printf "%s|%s" "$CACHE_DIR" "$SYSTEMD_USER_DIR"' \
            _ "$ROOT/scripts/update.sh"
    )"
    assert_eq "$home/.cache/silere-shell|$home/.config/systemd/user" "$actual" \
        "updater relative XDG fallbacks"

    HOME="$home" XDG_CONFIG_HOME=relative/config SILERE_SCRIPT_LIB_ONLY=1 \
        source "$ROOT/scripts/install.sh"
    _answered_yes y || fail "lowercase yes was rejected"
    _answered_yes Yes || fail "mixed-case yes was rejected"
    if _answered_yes "" || _answered_yes n; then
        fail "daily update timer was not default-off"
    fi
)

test_fresh_install_permissions() (
    local home="$TMP/install-mode-home" custom="$TMP/custom-install"
    HOME="$home" XDG_CONFIG_HOME=relative SILERE_SCRIPT_LIB_ONLY=1 \
        source "$ROOT/scripts/install.sh"

    mkdir -m 0755 -p "$DEFAULT_DIR" "$custom"
    _secure_fresh_default_install "$DEFAULT_DIR"
    assert_eq "700" "$(stat -c '%a' "$DEFAULT_DIR")" "fresh default install mode"

    _secure_fresh_default_install "$custom"
    assert_eq "755" "$(stat -c '%a' "$custom")" "custom install mode"
)

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

test_headless_qml_import_roots() (
    local stubs="$TMP/qml-tool-stubs"
    local first="$TMP/qml-import-first"
    local second="$TMP/qml-import-second"
    local lint_help="--import --unused-imports --alias-cycle --assignment-in-condition --deprecated --duplicate-enum-entries --duplicate-inline-component --duplicate-property-binding --duplicated-name --eval --inheritance-cycle --invalid-lint-directive --missing-enum-entry --property-override --read-only-property --required --unreachable-code --unresolved-alias --missing-type --non-list-property --unterminated-case --unintentional-empty-block"

    mkdir -p "$stubs" "$first" "$second"
    printf '%s\n' \
        '#!/bin/sh' \
        'if [ "${1:-}" = --version ]; then echo "fixture 6.0.0"; exit 0; fi' \
        'if [ "${1:-}" = --help ]; then printf "%s\n" "$SILERE_QMLLINT_HELP"; exit 0; fi' \
        'found=0' \
        'previous=' \
        'for argument do' \
        '    if [ "$previous" = -I ] && [ "$argument" = "$SILERE_EXPECTED_IMPORT_ROOT" ]; then found=1; fi' \
        '    previous=$argument' \
        'done' \
        '[ "$found" = 1 ] || { echo "missing secondary QML import root" >&2; exit 2; }' \
        'exit 0' > "$stubs/qmlcachegen"
    cp "$stubs/qmlcachegen" "$stubs/qmllint"
    chmod +x "$stubs/qmlcachegen" "$stubs/qmllint"

    if ! PATH="$stubs:$PATH" QML2_IMPORT_PATH="$first:$second" QML_IMPORT_PATH="" \
            SILERE_EXPECTED_IMPORT_ROOT="$second" SILERE_REQUIRE_QML_TOOLS=1 \
            SILERE_QMLLINT_HELP="$lint_help" \
            bash "$ROOT/scripts/test-qml-headless.sh" >/dev/null; then
        fail "headless QML tools did not receive every configured import root"
    fi
)

test_font_archive_selection() (
    SILERE_SCRIPT_LIB_ONLY=1 source "$ROOT/scripts/install.sh"
    local source="$TMP/font-archive" destination="$TMP/font-install" archive="$TMP/fonts.tar.xz"
    local name
    local expected=(
        JetBrainsMonoNerdFont-Regular.ttf
        JetBrainsMonoNerdFont-Medium.ttf
        JetBrainsMonoNerdFont-SemiBold.ttf
        JetBrainsMonoNerdFont-Bold.ttf
    )

    mkdir -p "$source" "$destination"
    for name in "${expected[@]}" \
            JetBrainsMonoNerdFont-Italic.ttf \
            JetBrainsMonoNerdFont-ExtraBold.ttf \
            JetBrainsMonoNerdFontMono-Regular.ttf; do
        printf 'fixture: %s\n' "$name" > "$source/$name"
    done
    tar -cJf "$archive" -C "$source" .
    _extract_silere_fonts "$archive" "$destination" \
        || fail "selected font extraction failed"

    for name in "${expected[@]}"; do
        [ -f "$destination/$name" ] || fail "required font was not extracted: $name"
    done
    set -- "$destination"/*.ttf
    assert_eq "4" "$#" "selected font file count"
    [ ! -e "$destination/JetBrainsMonoNerdFont-Italic.ttf" ] \
        || fail "unused italic font was extracted"
    [ ! -e "$destination/JetBrainsMonoNerdFontMono-Regular.ttf" ] \
        || fail "unused Mono font was extracted"
)

test_install_path_safety() (
    SILERE_SCRIPT_LIB_ONLY=1 source "$ROOT/scripts/install.sh"
    local source="$TMP/existing-install" generic="$TMP/generic-repo" backup actual

    actual="$(_normalized_install_path "$source")"
    assert_eq "$source" "$actual" "normalized safe install path"
    if (_normalized_install_path / >/dev/null 2>&1); then
        fail "filesystem root was accepted as an install path"
    fi
    if (_normalized_install_path "$HOME" >/dev/null 2>&1); then
        fail "home directory was accepted as an install path"
    fi
    if (_normalized_install_path "$CONFIG_HOME" >/dev/null 2>&1); then
        fail "config root was accepted as an install path"
    fi

    mkdir -p "$source"
    printf 'keep me\n' > "$source/user-file"
    backup="$(_move_aside_path "$source")" || fail "existing install path was not preserved"
    [ ! -e "$source" ] || fail "move-aside left the original path in place"
    assert_eq "keep me" "$(<"$backup/user-file")" "move-aside preserved existing content"

    _is_silere_checkout "$ROOT" || fail "Silere checkout fingerprint was rejected"
    mkdir -p "$generic/.git"
    if _is_silere_checkout "$generic"; then
        fail "generic Git repository passed the Silere checkout fingerprint"
    fi

    printf '%s\n' '[templates.silere-shell]' > "$generic/matugen.toml"
    _matugen_table_present "$generic/matugen.toml" \
        || fail "unmanaged Matugen table was not detected"
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

test_niri_config_discovery() {
    local empty="$TMP/proc-no-niri" session="$TMP/niri-session"
    mkdir -p "$empty" "$session/configs"
    printf 'layout {}\n' > "$session/configs/config.kdl"

    local actual
    actual="$(
        SILERE_PROC_ROOT="$empty" SILERE_PARENT_PID=999 \
        HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/config" \
        NIRI_CONFIG="$TMP/niri/custom.kdl" \
        bash "$ROOT/scripts/install.sh" --niri-config-path
    )"
    assert_eq "$TMP/niri/custom.kdl" "$actual" "NIRI_CONFIG path"

    local proc="$TMP/proc-niri"
    mkdir -p "$proc"
    make_proc "$proc" 700 niri 1 "$session" niri --config configs/config.kdl
    make_proc "$proc" 710 bash 700 "$session" bash
    actual="$(
        SILERE_PROC_ROOT="$proc" SILERE_PARENT_PID=710 \
        HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/config" \
        NIRI_CONFIG="$TMP/niri/ignored.kdl" \
        bash "$ROOT/scripts/install.sh" --niri-config-path
    )"
    assert_eq "$session/configs/config.kdl" "$actual" "running niri --config beats NIRI_CONFIG"

    actual="$(
        SILERE_PROC_ROOT="$proc" SILERE_PARENT_PID=710 \
        HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/config" \
        NIRI_CONFIG="$TMP/niri/ignored.kdl" SILERE_NIRI_CONFIG="$TMP/niri/override.kdl" \
        bash "$ROOT/scripts/install.sh" --niri-config-path
    )"
    assert_eq "$TMP/niri/override.kdl" "$actual" "Silere niri config override"

    local plain="$TMP/proc-niri-plain"
    mkdir -p "$plain"
    make_proc "$plain" 720 niri 1 "$session" niri --session
    actual="$(
        SILERE_PROC_ROOT="$plain" SILERE_PARENT_PID=999 \
        HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/config" \
        NIRI_CONFIG="$TMP/niri/custom.kdl" \
        bash "$ROOT/scripts/install.sh" --niri-config-path
    )"
    assert_eq "$TMP/niri/custom.kdl" "$actual" "flagless niri falls back to NIRI_CONFIG"
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
    grep -qF 'TimeoutStartSec=5min' "$SYSTEMD_USER_DIR/$SERVICE_UNIT" \
        || fail "generated update service has no bounded start timeout"
    if find "$SYSTEMD_USER_DIR" -maxdepth 1 -name '.silere-update.*.??????' -print -quit | grep -q .; then
        fail "temporary unit file was left behind"
    fi
)

test_atomic_update_cache() (
    local test_home="$TMP/update-cache-home"
    local victim="$TMP/update-cache-victim"
    HOME="$test_home"
    XDG_CACHE_HOME="$test_home/cache"
    SILERE_SCRIPT_LIB_ONLY=1 source "$ROOT/scripts/update.sh"

    umask 022
    _write_cache_file "$FLAG" "seed" || fail "update cache directory creation failed"
    assert_eq "700" "$(stat -c '%a' "$CACHE_DIR")" "fresh update cache mode"
    rm -f "$FLAG"
    printf 'do not replace\n' > "$victim"
    ln -s "$victim" "$FLAG"

    _write_cache_file "$FLAG" "2" $'first change\nsecond change' \
        || fail "atomic update cache writer failed"
    assert_eq $'2\nfirst change\nsecond change' "$(<"$FLAG")" \
        "atomic update cache content"
    assert_eq "do not replace" "$(<"$victim")" \
        "atomic update cache symlink target"
    [ ! -L "$FLAG" ] || fail "atomic update cache left the stale symlink in place"
    if find "$CACHE_DIR" -maxdepth 1 -name '.update-pending.??????' -print -quit | grep -q .; then
        fail "temporary update cache file was left behind"
    fi
)

test_update_refuses_dirty_apply() (
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_CONFIG_NOSYSTEM=1
    local remote="$TMP/update-remote.git"
    local seed="$TMP/update-seed"
    local client="$TMP/update-client"
    local test_home="$TMP/update-home"
    local old_head remote_head version_out stub_dir="$TMP/update-stubs"
    local lock_stub_dir="$TMP/update-lock-stubs"

    git init --bare -q "$remote"
    git --git-dir="$remote" symbolic-ref HEAD refs/heads/main
    git init -q "$seed"
    git -C "$seed" config user.name "Silere test"
    git -C "$seed" config user.email "test@example.invalid"
    mkdir -p "$seed/scripts/lib"
    cp "$ROOT/scripts/update.sh" "$seed/scripts/update.sh"
    cp "$ROOT/scripts/lib/xdg.sh" "$seed/scripts/lib/xdg.sh"
    printf 'upstream v1\n' > "$seed/tracked.qml"
    git -C "$seed" add scripts tracked.qml
    git -C "$seed" commit -qm "initial"
    git -C "$seed" branch -M main
    git -C "$seed" remote add origin "$remote"
    git -C "$seed" push -q -u origin main

    git clone -q "$remote" "$client"
    git -C "$client" config user.name "Silere test"
    git -C "$client" config user.email "test@example.invalid"
    version_out="$(HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" \
        bash "$client/scripts/update.sh" --version)"
    assert_eq "tag=" "$(printf '%s\n' "$version_out" | grep '^tag=')" \
        "--version no-tag fallback"
    assert_eq "ahead=0" "$(printf '%s\n' "$version_out" | grep '^ahead=')" \
        "--version no-tag commit count"
    printf 'upstream v2\n' > "$seed/tracked.qml"
    git -C "$seed" commit -qam "upstream update"
    git -C "$seed" push -q

    mkdir -p "$test_home" "$stub_dir" "$lock_stub_dir"
    printf '#!/bin/sh\nexit 1\n' > "$stub_dir/systemctl"
    printf '#!/bin/sh\nexit 0\n' > "$stub_dir/notify-send"
    chmod +x "$stub_dir/systemctl" "$stub_dir/notify-send"
    HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" >/dev/null
    remote_head="$(git -C "$client" rev-parse origin/main)"
    printf '#!/bin/sh\nexit 1\n' > "$lock_stub_dir/flock"
    chmod +x "$lock_stub_dir/flock"
    if HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" \
            PATH="$lock_stub_dir:$stub_dir:$PATH" \
            bash "$client/scripts/update.sh" >/dev/null 2>&1; then
        fail "concurrent update check unexpectedly acquired the update lock"
    fi
    [ -f "$test_home/cache/silere-shell/update-pending" ] \
        || fail "lock contention cleared the pending update flag"

    printf 'local customization\n' >> "$client/tracked.qml"
    old_head="$(git -C "$client" rev-parse HEAD)"

    if HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" --apply >/dev/null 2>&1; then
        fail "dirty update apply unexpectedly succeeded"
    fi
    assert_eq "$old_head" "$(git -C "$client" rev-parse HEAD)" "dirty update apply HEAD"
    grep -qF 'local customization' "$client/tracked.qml" \
        || fail "dirty update apply changed the local edit"
    [ -z "$(git -C "$client" stash list)" ] \
        || fail "dirty update apply created a stash"

    git -C "$client" restore tracked.qml
    git -C "$client" checkout -qb feature
    assert_eq "branch=feature" "$(HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" \
        PATH="$stub_dir:$PATH" bash "$client/scripts/update.sh" --version | grep '^branch=')" \
        "feature-branch version reporting"
    if HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" --apply >/dev/null 2>&1; then
        fail "feature-branch update apply unexpectedly succeeded"
    fi
    assert_eq "feature" "$(git -C "$client" symbolic-ref --quiet --short HEAD)" \
        "feature-branch update apply branch"
    assert_eq "$old_head" "$(git -C "$client" rev-parse HEAD)" \
        "feature-branch update apply HEAD"
    [ -f "$test_home/cache/silere-shell/update-pending" ] \
        || fail "feature-branch apply cleared the pending update flag"

    git -C "$client" checkout -q main
    git -C "$client" checkout -q --detach "$old_head"
    assert_eq "branch=HEAD" "$(HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" \
        PATH="$stub_dir:$PATH" bash "$client/scripts/update.sh" --version | grep '^branch=')" \
        "detached-HEAD version reporting"
    if HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" --apply >/dev/null 2>&1; then
        fail "detached-HEAD update apply unexpectedly succeeded"
    fi
    [ -z "$(git -C "$client" symbolic-ref --quiet --short HEAD || true)" ] \
        || fail "detached-HEAD update apply attached the checkout"
    assert_eq "$old_head" "$(git -C "$client" rev-parse HEAD)" \
        "detached-HEAD update apply HEAD"
    [ -f "$test_home/cache/silere-shell/update-pending" ] \
        || fail "detached-HEAD apply cleared the pending update flag"

    git -C "$client" checkout -q main
    git -C "$client" update-ref -d refs/remotes/origin/main
    mkdir -p "$test_home/cache/silere-shell"
    printf '1\nupstream update\n' > "$test_home/cache/silere-shell/update-pending"
    if HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" --apply >/dev/null 2>&1; then
        fail "update apply succeeded without origin/main"
    fi
    [ -f "$test_home/cache/silere-shell/update-pending" ] \
        || fail "missing origin/main cleared the pending update flag"
    assert_eq "$old_head" "$(git -C "$client" rev-parse HEAD)" "missing origin/main apply HEAD"

    git -C "$client" update-ref refs/remotes/origin/main "$remote_head"
    git -C "$client" remote set-url origin "$TMP/unavailable-update-origin.git"
    if ! HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" \
            PATH="$stub_dir:$PATH" \
            bash "$client/scripts/update.sh" --apply >/dev/null 2>&1; then
        fail "update apply contacted origin instead of using its fetched ref"
    fi
    assert_eq "$remote_head" "$(git -C "$client" rev-parse HEAD)" "offline update apply HEAD"
    [ ! -e "$test_home/cache/silere-shell/update-pending" ] \
        || fail "successful offline apply left the pending update flag"
)

test_update_reporting() (
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_CONFIG_NOSYSTEM=1
    local remote="$TMP/report-remote.git"
    local seed="$TMP/report-seed"
    local client="$TMP/report-client"
    local test_home="$TMP/report-home"
    local stub_dir="$TMP/report-stubs"
    local cache="$test_home/cache/silere-shell"
    local out target checked

    git init --bare -q "$remote"
    git --git-dir="$remote" symbolic-ref HEAD refs/heads/main
    git init -q "$seed"
    git -C "$seed" config user.name "Silere test"
    git -C "$seed" config user.email "test@example.invalid"
    mkdir -p "$seed/scripts/lib"
    cp "$ROOT/scripts/update.sh" "$seed/scripts/update.sh"
    cp "$ROOT/scripts/lib/xdg.sh" "$seed/scripts/lib/xdg.sh"
    printf 'v1\n' > "$seed/tracked.qml"
    git -C "$seed" add scripts tracked.qml
    git -C "$seed" commit -qm "initial"
    git -C "$seed" branch -M main
    git -C "$seed" tag v9.9.0
    git -C "$seed" remote add origin "$remote"
    git -C "$seed" push -q -u origin main --tags

    printf 'installed revision\n' >> "$seed/tracked.qml"
    git -C "$seed" commit -qam "installed revision"
    git -C "$seed" tag scratch
    git -C "$seed" push -q origin main --tags

    git clone --depth 1 -q "file://$remote" "$client"
    assert_eq "true" "$(git -C "$client" rev-parse --is-shallow-repository)" \
        "reporting fixture starts shallow"
    printf 'v2\n' > "$seed/tracked.qml"
    git -C "$seed" commit -qam "upstream update"
    git -C "$seed" tag v9.9.1
    git -C "$seed" push -q --tags origin main

    mkdir -p "$test_home" "$stub_dir"
    printf '%s\n' \
        '#!/bin/sh' \
        'mode=${SILERE_TIMER_MODE:-unsupported}' \
        'case "$*" in' \
        '  *"show-environment"*) [ "$mode" != unsupported ];;' \
        '  *"is-enabled --quiet silere-update.timer"*) [ "$mode" != disabled ] && [ "$mode" != unsupported ];;' \
        '  *"NextElapseUSecRealtime"*)' \
        '    case "$mode" in enabled) echo "@1700000000";; empty) echo;; *) exit 1;; esac;;' \
        '  *) exit 1;;' \
        'esac' > "$stub_dir/systemctl"
    printf '#!/bin/sh\nexit 0\n' > "$stub_dir/notify-send"
    chmod +x "$stub_dir/systemctl" "$stub_dir/notify-send"

    _run() { HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" "$@"; }

    assert_eq $'supported=0\nenabled=0' "$(_run --timer-status)" \
        "timer status without a user manager"
    assert_eq $'supported=1\nenabled=0' "$(SILERE_TIMER_MODE=disabled _run --timer-status)" \
        "disabled timer status"
    assert_eq $'supported=1\nenabled=1\nnext=1700000000' \
        "$(SILERE_TIMER_MODE=enabled _run --timer-status)" "scheduled timer status"
    assert_eq $'supported=1\nenabled=1\nnext=' \
        "$(SILERE_TIMER_MODE=empty _run --timer-status)" "empty timer schedule status"
    assert_eq $'supported=1\nenabled=1\nnext=' \
        "$(SILERE_TIMER_MODE=legacy _run --timer-status)" "legacy timer status"

    _run >/dev/null
    assert_eq "false" "$(git -C "$client" rev-parse --is-shallow-repository)" \
        "update check expands an existing shallow clone"
    out="$(_run --version)"
    printf '%s\n' "$out" | grep -qE '^sha=[0-9a-f]{7,}$' || fail "--version omitted the commit sha"
    printf '%s\n' "$out" | grep -qE '^date=[0-9]{4}-[0-9]{2}-[0-9]{2}$' || fail "--version omitted the build date"
    assert_eq "tag=v9.9.0" "$(printf '%s\n' "$out" | grep '^tag=')" "--version tag"
    assert_eq "ahead=1" "$(printf '%s\n' "$out" | grep '^ahead=')" "--version commits since tag"
    assert_eq "branch=main" "$(printf '%s\n' "$out" | grep '^branch=')" "--version branch"
    assert_eq "dirty=0" "$(printf '%s\n' "$out" | grep '^dirty=')" "--version clean checkout"

    printf 'local edit\n' >> "$client/tracked.qml"
    assert_eq "dirty=1" "$(_run --version | grep '^dirty=')" "--version dirty checkout"
    git -C "$client" checkout -q -- tracked.qml

    checked="$(cat "$cache/update-checked")"
    printf '%s' "$checked" | grep -qE '^[0-9]{10,}$' \
        || fail "update check did not record a usable timestamp"
    assert_eq "1" "$(sed -n '1p' "$cache/update-pending")" "pending update count"
    target="$(sed -n '2p' "$cache/update-pending")"
    printf '%s' "$target" | grep -qE '^target [0-9a-f]{7,} v9\.9\.1$' \
        || fail "pending update flag has no resolvable target revision: $target"
    assert_eq "upstream update" "$(sed -n '3p' "$cache/update-pending" | cut -d' ' -f2-)" \
        "pending update summary"

    _run --apply >/dev/null
    [ ! -e "$cache/update-pending" ] || fail "apply left the pending update flag"
    assert_eq "$checked" "$(cat "$cache/update-checked")" "apply discarded the last-checked time"
    assert_eq "tag=v9.9.1" "$(_run --version | grep '^tag=')" "--version tag after apply"

    printf '1\nstale pending entry\n' > "$cache/update-pending"
    printf '1\n' > "$cache/update-checked"
    _run >/dev/null
    [ ! -e "$cache/update-pending" ] \
        || fail "already-current check did not clear a stale pending flag"
    [ "$(cat "$cache/update-checked")" -gt 1 ] \
        || fail "already-current check did not refresh its timestamp"

    printf '4242\n' > "$cache/update-checked"
    git -C "$client" remote set-url origin "$TMP/unavailable-report-origin.git"
    if _run >/dev/null 2>&1; then
        fail "update check unexpectedly succeeded against an unavailable origin"
    fi
    assert_eq "4242" "$(cat "$cache/update-checked")" \
        "failed fetch preserved the last successful check time"
)

test_repair_workflow() (
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_CONFIG_NOSYSTEM=1
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

test_xdg_paths_and_timer_default
test_fresh_install_permissions
test_marker_removal
test_uninstall_targets_and_backups
test_qml_module_lookup
test_headless_qml_import_roots
test_font_archive_selection
test_install_path_safety
test_hypr_discovery
test_niri_config_discovery
test_atomic_units
test_atomic_update_cache
# These workflows build git fixtures. Local minimal environments may skip them;
# CI opts into making an accidental missing dependency a hard failure.
if command -v git >/dev/null 2>&1; then
    test_update_refuses_dirty_apply
    test_update_reporting
    test_repair_workflow
else
    if [ "${SILERE_REQUIRE_GIT_TESTS:-0}" = 1 ]; then
        fail "git is required for updater and repair workflow tests"
    fi
    printf 'SKIP: updater and repair workflows (git unavailable)\n'
fi

printf 'portability regression tests passed\n'
