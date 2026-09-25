#!/usr/bin/env bash
# the sourced scripts are linted on their own and read the globals set here
# shellcheck source=/dev/null disable=SC2034
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/silere-portability-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# No test may reach the live session's notification daemon. Individual stubs are
# still preferred, but a path that notifies from a helper cannot leak past this one.
mkdir -p "$TMP/suite-stubs"
printf '#!/bin/sh\nexit 0\n' > "$TMP/suite-stubs/notify-send"
chmod +x "$TMP/suite-stubs/notify-send"
PATH="$TMP/suite-stubs:$PATH"
export PATH

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    [ "$actual" = "$expected" ] || fail "$label (expected '$expected', got '$actual')"
}

# kill -0 succeeds on a zombie, and an orphan killed under a PID 1 that never reaps
# stays one — which is every container job, GitHub Actions included
_pid_running() { # $1 = pid
    local line
    # the redirect is what fails for a reaped pid, and it reports before a trailing
    # 2>/dev/null would apply, so silence stderr first
    IFS= read -r line 2>/dev/null < "/proc/$1/stat" || return 1
    line=${line##*) }
    [ "${line%% *}" != Z ]
}

_prepare_release_signer() {
    local repo="$1" key="$TMP/release-signing-key"
    if [ ! -f "$key" ]; then
        ssh-keygen -q -t ed25519 -N '' -C silere-test -f "$key" >/dev/null
    fi
    git -C "$repo" config gpg.format ssh
    git -C "$repo" config user.signingkey "$key"
    mkdir -p "$repo/security"
    printf 'silere-test namespaces="git" %s\n' "$(<"$key.pub")" \
        > "$repo/security/update-signers"
}

_sign_release() {
    local repo="$1" tag="$2"
    git -C "$repo" tag -s -m "$tag" "$tag"
}

_test_path_escape() {
    local LC_ALL=C s="$1" out="" ch oct i
    for ((i = 0; i < ${#s}; i++)); do
        ch="${s:i:1}"
        printf -v oct '%03o' "'$ch"
        out+="\\$oct"
    done
    printf '%s' "$out"
}

_mark_managed_install() {
    local checkout="$1" home="$2" state
    state="$home/.local/state/silere-shell"
    mkdir -p "$state"
    printf '%s\n' version=1 installMode=managed \
        "checkoutPath=$(_test_path_escape "$checkout")" > "$state/install-receipt"
    chmod 0600 "$state/install-receipt"
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
            'source "$1"; printf "%s|%s|%s" "$CACHE_DIR" "$SYSTEMD_USER_DIR" "$STATE_DIR"' \
            _ "$ROOT/scripts/update.sh"
    )"
    assert_eq "$home/.cache/silere-shell|$home/.config/systemd/user|$home/.local/state/silere-shell" "$actual" \
        "updater relative XDG fallbacks"

    actual="$(HOME="$home" bash -c 'source "$1"; _silere_xdg_home relative/data .local/share' \
        _ "$ROOT/scripts/lib/xdg.sh")"
    assert_eq "$home/.local/share" "$actual" "diagnostic relative XDG data fallback"

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

    mkdir -p "$DEFAULT_DIR" "$custom"
    chmod 0755 "$DEFAULT_DIR" "$custom"
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

    INSTALL_RECEIPT="$TMP/install-receipt"
    printf '%s\n' version=1 installMode=managed \
        'checkoutPath=\057\164\155\160\057\163\151\154\145\162\145' \
        > "$INSTALL_RECEIPT"
    assert_eq /tmp/silere "$(_receipt_path checkoutPath)" \
        "uninstaller receipt checkout path"
    assert_eq managed "$(_receipt_value installMode)" \
        "uninstaller receipt mode"
)

test_qml_module_lookup() (
    local imports="$TMP/qml-imports"
    mkdir -p "$imports/Silere/TestModule"
    printf 'module Silere.TestModule\n' > "$imports/Silere/TestModule/qmldir"

    # Import roots are resolved once at source time (not per call), so the
    # fake root must be in place before install.sh sources the QML-modules lib.
    export QML2_IMPORT_PATH="$imports"
    export QML_IMPORT_PATH=""
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
    local lint_help="--import --unused-imports --alias-cycle --assignment-in-condition --deprecated --duplicate-enum-entries --duplicate-inline-component --duplicate-property-binding --duplicated-name --eval --inheritance-cycle --invalid-lint-directive --missing-enum-entry --property-override --read-only-property --required --unreachable-code --unresolved-alias --missing-type --non-list-property --unterminated-case --unintentional-empty-block --access-singleton-via-object --comma --component-children-count --confusing-expression-statement --duplicate-import --enum-entry-matches-enum --equality-type-coercion --literal-constructor --multiline-strings --non-root-enum --prefer-non-var-properties --redundant-optional-chaining --stale-property-read --top-level-component --var-used-before-declaration --with"

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
    # the fixture is a .tar.xz, so without xz this reports a tar crash as a lint
    # failure. xz-utils is not installed by default on debian.
    if ! command -v xz >/dev/null 2>&1; then
        printf 'SKIP: xz not installed; font archive selection not tested\n'
        return 0
    fi
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

test_assume_yes_prompts() (
    local home="$TMP/assume-yes-home" expected out
    local detach=()
    mkdir -p "$home"
    expected="$home/.config/silere-shell"

    # setsid takes the controlling terminal away, which is what an automated install lacks
    if command -v setsid >/dev/null 2>&1; then
        detach=(setsid)
    fi

    out="$(HOME="$home" XDG_CONFIG_HOME='' SILERE_ASSUME_YES=1 \
        "${detach[@]}" bash -c '
            SILERE_SCRIPT_LIB_ONLY=1 source "$1"
            _ask "install?"   >/dev/null && printf "ask=yes "   || printf "ask=no "
            _ask_no "opt in?" >/dev/null && printf "askno=yes " || printf "askno=no "
            printf "path=%s" "$(_ask_path)"
        ' _ "$ROOT/scripts/install.sh" </dev/null)" \
        || fail "assumed-yes prompts failed without a controlling terminal"

    assert_eq "ask=yes askno=no path=$expected" "$out" "assumed-yes prompt answers"

    # without setsid the prompt below would find a real terminal and block on it
    if [ ${#detach[@]} -eq 0 ]; then
        printf 'SKIP: setsid unavailable; interactive prompt guard not tested\n'
        return 0
    fi

    if HOME="$home" XDG_CONFIG_HOME='' "${detach[@]}" bash -c '
            SILERE_SCRIPT_LIB_ONLY=1 source "$1"; _ask "install?"
        ' _ "$ROOT/scripts/install.sh" </dev/null >/dev/null 2>&1; then
        fail "a prompt answered itself with no controlling terminal and no assumed yes"
    fi
)

test_dry_run_writes_nothing() (
    local home="$TMP/dry-run-home" conf before out
    mkdir -p "$home/.config/hypr"
    conf="$home/.config/hypr/hyprland.conf"
    printf 'monitor=,preferred,auto,1\n' > "$conf"
    before="$(<"$conf")"

    out="$(HOME="$home" XDG_CONFIG_HOME="$home/.config" SILERE_HYPR_CONFIG="$conf" \
        bash "$ROOT/scripts/install.sh" --dry-run </dev/null 2>&1)" \
        || fail "dry run exited non-zero"

    assert_eq "$before" "$(<"$conf")" "dry run left the Hyprland config unchanged"
    [ ! -e "$home/.config/silere-shell" ] || fail "dry run created the install directory"
    [ ! -e "$home/.config/matugen" ] || fail "dry run created matugen config"

    case "$out" in
        *"append to $conf: exec-once = "*) ;;
        *) fail "dry run did not report the autostart line it would add" ;;
    esac
    case "$out" in
        *"nothing was written"*) ;;
        *) fail "dry run did not report that it wrote nothing" ;;
    esac
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

    printf '%s\n' before '# silere-shell begin' \
        '[templates.silere-shell]' 'output_path = "legacy.qml"' \
        '# silere-shell end' after > "$generic/managed-matugen.toml"
    _replace_matugen_block "$generic/managed-matugen.toml" \
        '"template.qml"' '"palette.json"' \
        || fail "managed Matugen block could not be migrated"
    grep -qF 'input_path  = "template.qml"' "$generic/managed-matugen.toml" \
        || fail "managed Matugen input path was not refreshed"
    grep -qF 'output_path = "palette.json"' "$generic/managed-matugen.toml" \
        || fail "managed Matugen output path was not refreshed"
    grep -qFx before "$generic/managed-matugen.toml" \
        && grep -qFx after "$generic/managed-matugen.toml" \
        || fail "managed Matugen migration lost surrounding config"
)

test_install_transaction_and_receipt() (
    local home="$TMP/install-transaction-home"
    local work="$TMP/install-transaction-work"
    local existing="$work/existing.conf"
    local new_file="$work/new.conf"
    local created_tree="$work/new-checkout"
    local replaced_tree="$work/replaced-checkout"
    local replaced_backup="$work/replaced-checkout.backup"
    mkdir -p "$home" "$work" "$replaced_tree"
    printf 'before\n' > "$existing"
    printf 'old checkout\n' > "$replaced_tree/value"

    HOME="$home" XDG_STATE_HOME="$home/state" SILERE_SCRIPT_LIB_ONLY=1 \
        source "$ROOT/scripts/install.sh"
    _dry_run=0
    _txn_begin
    _txn_before_file "$existing"
    _txn_before_file "$new_file"
    printf 'after\n' > "$existing"
    printf 'created\n' > "$new_file"
    mkdir -p "$created_tree"
    printf 'new checkout\n' > "$created_tree/value"
    _txn_tree_created "$created_tree"
    mv "$replaced_tree" "$replaced_backup"
    _txn_tree_replaced "$replaced_tree" "$replaced_backup"
    mkdir -p "$replaced_tree"
    printf 'replacement\n' > "$replaced_tree/value"
    _txn_rollback

    assert_eq before "$(cat "$existing")" "install transaction restored a file"
    [ ! -e "$new_file" ] || fail "install transaction retained a created file"
    [ ! -e "$created_tree" ] || fail "install transaction retained a created checkout"
    assert_eq "old checkout" "$(cat "$replaced_tree/value")" \
        "install transaction restored a replaced checkout"
    grep -q '^status=rolled-back$' "$TXN_JOURNAL" \
        || fail "install transaction did not record rollback"

    # install.sh's own clone-failure handler can restore the backup by hand
    # before _die triggers this same rollback a second time; the backup is
    # gone by then, and rollback must leave the hand-restored tree alone
    # rather than deleting it and finding nothing left to put back
    local reentrant_tree="$work/reentrant-checkout"
    local reentrant_backup="$work/reentrant-checkout.backup"
    mkdir -p "$reentrant_tree"
    printf 'original checkout\n' > "$reentrant_tree/value"
    _txn_begin
    mv "$reentrant_tree" "$reentrant_backup"
    _txn_tree_replaced "$reentrant_tree" "$reentrant_backup"
    mv "$reentrant_backup" "$reentrant_tree"
    _txn_rollback
    assert_eq "original checkout" "$(cat "$reentrant_tree/value")" \
        "rollback left a hand-restored tree-replaced backup in place"

    _txn_begin
    ROOT="$work/managed-checkout"
    mkdir -p "$ROOT"
    install_mode=managed
    receipt_compositor=hyprland
    receipt_autostart="$work/hyprland.conf"
    did_font=false did_cli=true did_tmpl=false did_toml=false
    did_autostart=true did_update=true
    _txn_commit || fail "install receipt did not commit"
    grep -q '^installMode=managed$' "$INSTALL_RECEIPT" \
        || fail "install receipt omitted the managed mode"
    grep -q '^compositor=hyprland$' "$INSTALL_RECEIPT" \
        || fail "install receipt omitted the compositor"
    grep -q '^status=committed$' "$TXN_JOURNAL" \
        || fail "install journal did not record commit"
    assert_eq 600 "$(stat -c '%a' "$INSTALL_RECEIPT")" "install receipt mode"

    local i kept
    for i in 1 2 3 4 5 6 7; do
        mkdir -p "$INSTALL_STATE_DIR/install-transactions/2026010${i}T000000Z-1"
    done
    _txn_begin
    kept="$(find "$INSTALL_STATE_DIR/install-transactions" -mindepth 1 -maxdepth 1 | wc -l)"
    assert_eq 5 "$kept" "install ledger keeps a bounded transaction history"
    [ -d "$TXN_DIR" ] || fail "install ledger pruned the transaction it just opened"
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
    local generated source_root="$ROOT" odd_root
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

    # Exercise both escaping layers with a legal custom checkout path. systemd
    # expands $ and %; its unit parser consumes the quote/backslash escapes.
    odd_root="$TMP/unit-\${HOME}-%-quote\"-slash\\-amp&-pipe|"
    mkdir -p "$odd_root/scripts" "$TMP/odd-units"
    cp "$source_root/scripts/$SERVICE_UNIT" "$source_root/scripts/$TIMER_UNIT" \
        "$odd_root/scripts/"
    ROOT="$odd_root"
    SYSTEMD_USER_DIR="$TMP/odd-units"
    generated="$(_systemd_execstart)"
    _write_update_units || fail "special-character unit writer failed"
    assert_eq "ExecStart=$generated" \
        "$(grep '^ExecStart=' "$SYSTEMD_USER_DIR/$SERVICE_UNIT")" \
        "generated service preserved its escaped ExecStart"
    [[ "$generated" == *'$${HOME}'* ]] \
        || fail "generated service did not preserve a literal dollar in the checkout path"
    [[ "$generated" == *'%%'* && "$generated" == *'quote\"'* \
        && "$generated" == *'slash\\'* ]] \
        || fail "generated service did not escape special checkout path characters"
)

test_atomic_update_cache() (
    local test_home="$TMP/update-cache-home"
    local victim="$TMP/update-cache-victim"
    HOME="$test_home"
    XDG_CACHE_HOME="$test_home/cache"
    SILERE_SCRIPT_LIB_ONLY=1 source "$ROOT/scripts/update.sh"

    umask 022
    _write_cache_file "$FLAG" "seed" || fail "update cache directory creation failed"
    assert_eq "700" "$(stat -c '%a' "$test_home/cache")" "fresh update cache parent mode"
    assert_eq "700" "$(stat -c '%a' "$CACHE_DIR")" "fresh update cache mode"
    chmod 0755 "$CACHE_DIR"
    _write_cache_file "$FLAG" "seed-again" || fail "update cache directory reharden failed"
    assert_eq "700" "$(stat -c '%a' "$CACHE_DIR")" "existing update cache mode"
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

    _record_update_error $'network\nfailure' || fail "update failure status was not written"
    sed -n '1p' "$ERROR_FLAG" | grep -qE '^[0-9]{10,}$' \
        || fail "update failure status has no timestamp"
    assert_eq "network failure" "$(sed -n '2p' "$ERROR_FLAG")" \
        "update failure status is single-line"
    _clear_update_error
    [ ! -e "$ERROR_FLAG" ] || fail "successful update state left the failure status behind"

    local real_cache="$TMP/update-cache-symlink-target"
    mkdir -m 0755 "$real_cache"
    CACHE_DIR="$TMP/update-cache-symlink"
    FLAG="$CACHE_DIR/update-pending"
    ln -s "$real_cache" "$CACHE_DIR"
    if _write_cache_file "$FLAG" "must not land"; then
        fail "updater accepted a symlink as its private cache directory"
    fi
    [ ! -e "$real_cache/update-pending" ] \
        || fail "updater followed its cache directory symlink"
    assert_eq "755" "$(stat -c '%a' "$real_cache")" "cache symlink target mode"
)

test_shared_launcher() (
    local stub_dir="$TMP/launcher-stubs"
    local capture="$TMP/launcher-default.out"
    local expected_args
    mkdir -p "$stub_dir"
    printf '%s\n' \
        '#!/bin/sh' \
        ': > "$SILERE_LAUNCH_CAPTURE"' \
        'printf "malloc=%s\nimages=%s\negl=%s\n" "$MALLOC_CONF" "$QSG_TRANSIENT_IMAGES" "${__EGL_VENDOR_LIBRARY_FILENAMES-}" >> "$SILERE_LAUNCH_CAPTURE"' \
        'for arg do printf "arg=%s\n" "$arg" >> "$SILERE_LAUNCH_CAPTURE"; done' \
        > "$stub_dir/qs"
    chmod +x "$stub_dir/qs"

    env -u MALLOC_CONF -u QSG_TRANSIENT_IMAGES \
        PATH="$stub_dir:$PATH" SILERE_LAUNCH_CAPTURE="$capture" \
        __EGL_VENDOR_LIBRARY_FILENAMES=/chosen/vendor.json \
        bash "$ROOT/scripts/silere" run --verbose
    grep -qF 'malloc=narenas:2,background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:0' "$capture" \
        || fail "shared launcher did not apply its allocator default"
    # the second window to draw a cached image gets an empty texture with it set
    grep -qFx 'images=' "$capture" \
        || fail "shared launcher set QSG_TRANSIENT_IMAGES"
    grep -qF 'egl=/chosen/vendor.json' "$capture" \
        || fail "shared launcher replaced an inherited EGL vendor"
    expected_args=$'arg=--no-duplicate\narg=-p\narg='"$ROOT"$'/shell.qml\narg=--verbose'
    assert_eq "$expected_args" "$(grep '^arg=' "$capture")" "shared launcher argv"
    assert_eq "600" "$(stat -c '%a' "$capture")" "shared launcher state umask"

    capture="$TMP/launcher-overrides.out"
    MALLOC_CONF='' \
        PATH="$stub_dir:$PATH" SILERE_LAUNCH_CAPTURE="$capture" \
        __EGL_VENDOR_LIBRARY_FILENAMES='' \
        bash "$ROOT/scripts/silere" run
    grep -qFx 'malloc=' "$capture" \
        || fail "shared launcher did not preserve an empty allocator override"
    grep -qFx 'egl=' "$capture" \
        || fail "shared launcher did not preserve an empty EGL override"

    capture="$TMP/launcher-package-name.out"
    ln -s "$ROOT/scripts/silere" "$stub_dir/silere-shell"
    MALLOC_CONF='' \
        PATH="$stub_dir:$PATH" SILERE_LAUNCH_CAPTURE="$capture" \
        __EGL_VENDOR_LIBRARY_FILENAMES='' \
        "$stub_dir/silere-shell" --verbose
    expected_args=$'arg=--no-duplicate\narg=-p\narg='"$ROOT"$'/shell.qml\narg=--verbose'
    assert_eq "$expected_args" "$(grep '^arg=' "$capture")" \
        "packaged launcher name dispatch"
)

test_interrupted_update_recovery() (
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_CONFIG_NOSYSTEM=1
    local repo="$TMP/update-transaction-repo"
    local test_home="$TMP/update-transaction-home"
    local old_rev new_rev head_before

    mkdir -p "$test_home"
    HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" \
        XDG_STATE_HOME="$test_home/state" SILERE_SCRIPT_LIB_ONLY=1 \
        source "$ROOT/scripts/update.sh"

    git init -q "$repo"
    git -C "$repo" config user.name "Silere test"
    git -C "$repo" config user.email "test@example.invalid"
    _prepare_release_signer "$repo"
    printf 'known good\n' > "$repo/tracked.qml"
    git -C "$repo" add security tracked.qml
    git -C "$repo" commit -qm "known good"
    old_rev="$(git -C "$repo" rev-parse HEAD)"
    printf 'signed update\n' > "$repo/tracked.qml"
    git -C "$repo" commit -qam "signed update"
    _sign_release "$repo" v1.0.1
    new_rev="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" reset --hard -q "$old_rev"

    ROOT="$repo"
    TRUSTED_SIGNERS="$repo/security/update-signers"
    ROOT_HEX="$(printf '%s' "$ROOT" | od -An -tx1 | tr -d ' \n')"
    ROOT_KEY="$(printf '%s' "$ROOT" | cksum | awk '{ print $1 "-" $2 }')"
    STATE_DIR="$test_home/state/silere-shell"
    APPLY_JOURNAL="$STATE_DIR/update-transaction-$ROOT_KEY"
    APPLY_TRUSTED_SIGNERS="$STATE_DIR/update-transaction-$ROOT_KEY.signers"
    REQUESTED_MODE=--apply

    # Interruption immediately after the merge still has a prepared journal.
    # Recovery must return to the old revision rather than assuming HEAD is good.
    _start_apply_transaction "$old_rev" "$new_rev" v1.0.1 \
        || fail "could not start apply transaction fixture"
    git -C "$repo" merge --ff-only -q "$new_rev"
    assert_eq "600" "$(stat -c '%a' "$APPLY_JOURNAL")" "apply journal mode"
    assert_eq "600" "$(stat -c '%a' "$APPLY_TRUSTED_SIGNERS")" "journal trust snapshot mode"
    assert_eq "700" "$(stat -c '%a' "$STATE_DIR")" "update state directory mode"
    _recover_interrupted_apply 2>/dev/null
    assert_eq "$old_rev" "$(git -C "$repo" rev-parse HEAD)" \
        "prepared interrupted update rollback"
    [ ! -e "$APPLY_JOURNAL" ] && [ ! -e "$APPLY_TRUSTED_SIGNERS" ] \
        || fail "prepared transaction recovery left state behind"

    # A durable validated phase is the commit point. Recovery keeps it even if
    # the updater lost power before deleting the journal or restarting Silere.
    _start_apply_transaction "$old_rev" "$new_rev" v1.0.1
    git -C "$repo" merge --ff-only -q "$new_rev"
    _write_apply_journal validated "$old_rev" "$new_rev" v1.0.1
    _recover_interrupted_apply 2>/dev/null
    assert_eq "$new_rev" "$(git -C "$repo" rev-parse HEAD)" \
        "validated interrupted update retained"
    [ ! -e "$APPLY_JOURNAL" ] || fail "validated transaction journal was not cleared"

    # --rollback consumes a retained validated journal to undo a release that
    # never came up in the live session. The stub answers as a unit running a
    # different checkout: the rollback must not restart whatever shell is live.
    local stub_dir="$TMP/update-rollback-stub"
    local calls="$TMP/update-rollback-calls"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/systemctl" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$calls"
case "\$*" in
    *" show "*) printf '{ path=/usr/bin/qs ; argv[]=/usr/bin/qs -p /elsewhere/shell.qml ; }\n' ;;
esac
EOF
    # the rollback path notifies; without a stub it reaches the live session's daemon
    printf '#!/bin/sh\nexit 0\n' > "$stub_dir/notify-send"
    chmod +x "$stub_dir/systemctl" "$stub_dir/notify-send"
    _start_apply_transaction "$old_rev" "$new_rev" v1.0.1
    _write_apply_journal validated "$old_rev" "$new_rev" v1.0.1
    PATH="$stub_dir:$PATH" _rollback_applied_update 2>/dev/null
    assert_eq "$old_rev" "$(git -C "$repo" rev-parse HEAD)" \
        "rollback restores the revision the update replaced"
    [ ! -e "$APPLY_JOURNAL" ] || fail "rollback left the update journal behind"
    grep -q 'restart silere-shell.service' "$calls" \
        && fail "rollback restarted a unit that runs another checkout"
    if ( _rollback_applied_update >/dev/null 2>&1 ); then
        fail "rollback accepted a missing journal"
    fi

    # Never turn a user-editable or damaged state file into a reset instruction.
    git -C "$repo" reset --hard -q "$old_rev"
    _start_apply_transaction "$old_rev" "$new_rev" v1.0.1
    git -C "$repo" merge --ff-only -q "$new_rev"
    printf 'not a journal\n' > "$APPLY_JOURNAL"
    head_before="$(git -C "$repo" rev-parse HEAD)"
    if ( _recover_interrupted_apply >/dev/null 2>&1 ); then
        fail "malformed update journal was accepted"
    fi
    assert_eq "$head_before" "$(git -C "$repo" rev-parse HEAD)" \
        "malformed journal leaves checkout untouched"
    git -C "$repo" reset --hard -q "$old_rev"
    _clear_apply_transaction

    # Likewise, an interrupted target edited after the crash needs a human
    # choice; automated rollback must preserve the edit byte-for-byte.
    _start_apply_transaction "$old_rev" "$new_rev" v1.0.1
    git -C "$repo" merge --ff-only -q "$new_rev"
    _write_apply_journal merged "$old_rev" "$new_rev" v1.0.1
    printf 'local edit\n' >> "$repo/tracked.qml"
    if ( _recover_interrupted_apply >/dev/null 2>&1 ); then
        fail "interrupted update recovery discarded local changes"
    fi
    grep -qF 'local edit' "$repo/tracked.qml" \
        || fail "interrupted update recovery changed the local edit"
    assert_eq "$new_rev" "$(git -C "$repo" rev-parse HEAD)" \
        "dirty interrupted update leaves HEAD untouched"
    git -C "$repo" reset --hard -q "$old_rev"
    _clear_apply_transaction

    # Refuse to chmod or populate an unexpected directory through the private
    # state leaf. XDG_STATE_HOME itself may legitimately be a symlink; Silere's
    # own child is the ownership boundary.
    local real_state="$TMP/update-state-symlink-target"
    rmdir "$STATE_DIR"
    mkdir -m 0755 "$real_state"
    ln -s "$real_state" "$STATE_DIR"
    if _start_apply_transaction "$old_rev" "$new_rev" v1.0.1; then
        fail "updater accepted a symlink as its private state directory"
    fi
    [ ! -e "$real_state/update-transaction-$ROOT_KEY" ] \
        || fail "updater followed its state directory symlink"
    assert_eq "755" "$(stat -c '%a' "$real_state")" "state symlink target mode"
)

test_installation_mode_detection() (
    local repo="$TMP/install-mode-repo"
    local home="$TMP/install-mode-home"
    local state="$home/.local/state/silere-shell"
    mkdir -p "$repo" "$state"

    HOME="$home" XDG_STATE_HOME="$home/.local/state" SILERE_SCRIPT_LIB_ONLY=1 \
        source "$ROOT/scripts/update.sh"
    ROOT="$repo"
    INSTALL_RECEIPT="$state/install-receipt"

    assert_eq managed "$(_installation_mode main)" "main without a receipt is managed"
    assert_eq development "$(_installation_mode feature/workspaces)" \
        "a working branch without a receipt is a development checkout"
    assert_eq development "$(_installation_mode HEAD)" \
        "a detached HEAD without a receipt is a development checkout"

    printf '%s\n' version=1 installMode=development \
        "checkoutPath=$(_test_path_escape "$repo")" > "$INSTALL_RECEIPT"
    assert_eq development "$(_installation_mode main)" \
        "the receipt outranks a clean main"

    printf '%s\n' version=1 installMode=managed \
        "checkoutPath=$(_test_path_escape "$repo")" > "$INSTALL_RECEIPT"
    assert_eq managed "$(_installation_mode feature/workspaces)" \
        "a managed receipt survives a branch switch"

    # a receipt describing a different checkout must never speak for this one
    printf '%s\n' version=1 installMode=managed \
        "checkoutPath=$(_test_path_escape "$repo-other")" > "$INSTALL_RECEIPT"
    assert_eq development "$(_installation_mode feature/workspaces)" \
        "another checkout's receipt is ignored"

    printf 'installMode=managed\ncheckoutPath=not-octal\n' > "$INSTALL_RECEIPT"
    assert_eq development "$(_installation_mode feature/workspaces)" \
        "a malformed receipt is ignored"
)

test_candidate_runtime_isolation() (
    local home="$TMP/candidate-runtime-home"
    local candidate="$TMP/candidate-runtime-tree"
    local runtime="$TMP/candidate-runtime-dir"
    local stubs="$TMP/candidate-runtime-stubs"
    local capture="$TMP/candidate-runtime-capture"
    mkdir -p "$home/config/silere-shell" "$candidate/config" "$runtime" "$stubs"
    printf '{"__version":1,"barHeight":40}\n' > "$home/config/silere-shell/settings.json"
    printf 'fallback\n' > "$candidate/config/MatugenPalette.qml"
    printf 'shell\n' > "$candidate/shell.qml"
    cat > "$stubs/qs" <<'EOF'
#!/usr/bin/env bash
printf '%s\n%s\n%s\n' "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" \
    > "${SILERE_RUNTIME_CAPTURE:?}"
cat "$XDG_CONFIG_HOME/silere-shell/settings.json" >> "$SILERE_RUNTIME_CAPTURE"
printf '{"candidate":"wrote here"}\n' > "$XDG_CONFIG_HOME/silere-shell/settings.json"
exit 0
EOF
    chmod +x "$stubs/qs"

    HOME="$home" XDG_CONFIG_HOME="$home/config" SILERE_SCRIPT_LIB_ONLY=1 \
        source "$ROOT/scripts/update.sh"
    WAYLAND_DISPLAY=wayland-test XDG_RUNTIME_DIR="$runtime" \
        SILERE_RUNTIME_CAPTURE="$capture" PATH="$stubs:$PATH" \
        _candidate_tree_starts "$candidate" \
        || fail "isolated candidate runtime was rejected"
    assert_eq '{"__version":1,"barHeight":40}' \
        "$(cat "$home/config/silere-shell/settings.json")" \
        "candidate runtime left live settings untouched"
    isolated_config="$(sed -n '1p' "$capture")"
    [ "$isolated_config" != "$home/config" ] \
        || fail "candidate runtime received the live config home"
    [ ! -e "${isolated_config%/config}" ] \
        || fail "candidate runtime sandbox was not removed"
    grep -qF '"barHeight":40' "$capture" \
        || fail "candidate runtime did not receive the copied settings shape"
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
    _prepare_release_signer "$seed"
    mkdir -p "$seed/scripts/lib"
    cp "$ROOT/scripts/update.sh" "$seed/scripts/update.sh"
    cp "$ROOT/scripts/lib/xdg.sh" "$seed/scripts/lib/xdg.sh"
    cp "$ROOT/scripts/lib/qml-modules.sh" "$seed/scripts/lib/qml-modules.sh"
    cp "$ROOT/scripts/lib/unit.sh" "$seed/scripts/lib/unit.sh"
    printf 'upstream v1\n' > "$seed/tracked.qml"
    git -C "$seed" add scripts security tracked.qml
    git -C "$seed" commit -qm "initial"
    git -C "$seed" branch -M main
    _sign_release "$seed" v1.0.0
    git -C "$seed" remote add origin "$remote"
    git -C "$seed" push -q -u origin main --tags

    git clone -q "$remote" "$client"
    git -C "$client" config user.name "Silere test"
    git -C "$client" config user.email "test@example.invalid"
    version_out="$(HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" \
        bash "$client/scripts/update.sh" --version)"
    assert_eq "tag=v1.0.0" "$(printf '%s\n' "$version_out" | grep '^tag=')" \
        "--version release tag"
    assert_eq "ahead=0" "$(printf '%s\n' "$version_out" | grep '^ahead=')" \
        "--version no-tag commit count"
    printf 'upstream v2\n' > "$seed/tracked.qml"
    git -C "$seed" commit -qam "upstream update"
    _sign_release "$seed" v1.0.1
    git -C "$seed" push -q origin main --tags

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
    assert_eq "mode=development" "$(HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" \
        PATH="$stub_dir:$PATH" bash "$client/scripts/update.sh" --version | grep '^mode=')" \
        "feature-branch installation mode"
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
    printf '%s\n' 1 "target $remote_head v1.0.1 verified" 'upstream update' \
        > "$test_home/cache/silere-shell/update-pending"
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
    local out target checked notes

    git init --bare -q "$remote"
    git --git-dir="$remote" symbolic-ref HEAD refs/heads/main
    git init -q "$seed"
    git -C "$seed" config user.name "Silere test"
    git -C "$seed" config user.email "test@example.invalid"
    _prepare_release_signer "$seed"
    mkdir -p "$seed/scripts/lib"
    cp "$ROOT/scripts/update.sh" "$seed/scripts/update.sh"
    cp "$ROOT/scripts/lib/xdg.sh" "$seed/scripts/lib/xdg.sh"
    cp "$ROOT/scripts/lib/qml-modules.sh" "$seed/scripts/lib/qml-modules.sh"
    cp "$ROOT/scripts/lib/unit.sh" "$seed/scripts/lib/unit.sh"
    printf 'v1\n' > "$seed/tracked.qml"
    git -C "$seed" add scripts security tracked.qml
    git -C "$seed" commit -qm "initial"
    git -C "$seed" branch -M main
    _sign_release "$seed" v9.9.0
    git -C "$seed" remote add origin "$remote"
    git -C "$seed" push -q -u origin main --tags

    printf 'installed revision\n' >> "$seed/tracked.qml"
    git -C "$seed" commit -qam "installed revision"
    git -C "$seed" tag scratch
    git -C "$seed" push -q origin main --tags

    git clone --depth 1 -q "file://$remote" "$client"
    _mark_managed_install "$client" "$test_home"
    assert_eq "true" "$(git -C "$client" rev-parse --is-shallow-repository)" \
        "reporting fixture starts shallow"
    printf 'v2\n' > "$seed/tracked.qml"
    mkdir -p "$seed/docs/releases"
    cat > "$seed/release.json" <<'EOF'
{
  "version": "9.9.1",
  "settingsSchema": 1,
  "quickshellMin": "0.3.1",
  "compositors": ["hyprland", "niri"]
}
EOF
    cat > "$seed/docs/releases/9.9.1.md" <<'EOF'
# Silere Shell 9.9.1

Released 2099-01-01.

**Upgrading:** nothing to do.

## Added

- A useful release summary that wraps onto
  one normalized cache row.

## Fixed

- A test fixture bug.
EOF
    git -C "$seed" add release.json docs/releases/9.9.1.md
    git -C "$seed" commit -qam "upstream update"
    _sign_release "$seed" v9.9.1
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
    printf '#!/bin/sh\n[ "${1:-}" = --version ] && echo "Quickshell 0.3.1"\n' > "$stub_dir/qs"
    chmod +x "$stub_dir/systemctl" "$stub_dir/notify-send" "$stub_dir/qs"

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

    mkdir -p "$cache"
    printf '%s\n' 1 'stale timer failure' > "$cache/update-error"
    _run >/dev/null
    [ ! -e "$cache/update-error" ] \
        || fail "successful update check left a stale failure status"
    assert_eq "false" "$(git -C "$client" rev-parse --is-shallow-repository)" \
        "update check expands an existing shallow clone"
    out="$(_run --version)"
    printf '%s\n' "$out" | grep -qE '^sha=[0-9a-f]{7,}$' || fail "--version omitted the commit sha"
    printf '%s\n' "$out" | grep -qE '^date=[0-9]{4}-[0-9]{2}-[0-9]{2}$' || fail "--version omitted the build date"
    assert_eq "tag=v9.9.0" "$(printf '%s\n' "$out" | grep '^tag=')" "--version tag"
    assert_eq "ahead=1" "$(printf '%s\n' "$out" | grep '^ahead=')" "--version commits since tag"
    assert_eq "branch=main" "$(printf '%s\n' "$out" | grep '^branch=')" "--version branch"
    assert_eq "dirty=0" "$(printf '%s\n' "$out" | grep '^dirty=')" "--version clean checkout"
    assert_eq "mode=managed" "$(printf '%s\n' "$out" | grep '^mode=')" \
        "--version receipt installation mode"

    printf 'local edit\n' >> "$client/tracked.qml"
    assert_eq "dirty=1" "$(_run --version | grep '^dirty=')" "--version dirty checkout"
    git -C "$client" checkout -q -- tracked.qml

    checked="$(cat "$cache/update-checked")"
    printf '%s' "$checked" | grep -qE '^[0-9]{10,}$' \
        || fail "update check did not record a usable timestamp"
    assert_eq "1" "$(sed -n '1p' "$cache/update-pending")" "pending update count"
    target="$(sed -n '2p' "$cache/update-pending")"
    printf '%s' "$target" | grep -qE '^target [0-9a-f]{7,} v9\.9\.1 verified$' \
        || fail "pending update flag has no resolvable target revision: $target"
    assert_eq "upstream update" "$(sed -n '3p' "$cache/update-pending" | cut -d' ' -f2-)" \
        "pending update summary"
    notes="$(cat "$cache/release-notes")"
    printf '%s\n' "$notes" | grep -qF 'target v9.9.1' \
        || fail "release notes cache does not name its verified target"
    printf '%s\n' "$notes" | grep -qF $'Added\tA useful release summary that wraps onto one normalized cache row.' \
        || fail "release notes cache did not normalize a wrapped Added entry"
    printf '%s\n' "$notes" | grep -qF $'Fixed\tA test fixture bug.' \
        || fail "release notes cache omitted a Fixed entry"

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

    sed -i 's/"quickshellMin": "0.3.1"/"quickshellMin": "99.0.0"/; s/"version": "9.9.1"/"version": "9.9.2"/' \
        "$seed/release.json"
    printf 'incompatible v3\n' > "$seed/tracked.qml"
    git -C "$seed" commit -qam "incompatible upstream"
    _sign_release "$seed" v9.9.2
    git -C "$seed" push -q --tags origin main
    if _run >/dev/null 2>&1; then
        fail "update check accepted a release requiring a newer Quickshell"
    fi
    assert_eq "v2" "$(<"$client/tracked.qml")" "incompatible release worktree"
    grep -qF 'requires Quickshell 99.0.0 or newer; installed: 0.3.1' "$cache/update-error" \
        || fail "incompatible release did not record an actionable requirement"
    [ ! -e "$cache/update-pending" ] \
        || fail "incompatible release left an installable update flag"
    [ ! -e "$cache/release-notes" ] \
        || fail "incompatible release left trusted-looking release notes"

    sed -i 's/"version": "9.9.2"/"version": "9.9.3"/' "$seed/release.json"
    printf 'untrusted v4\n' > "$seed/tracked.qml"
    git -C "$seed" commit -qam "untrusted upstream"
    git -C "$seed" tag -a -m "unsigned release" v9.9.3
    git -C "$seed" push -q --tags origin main
    if _run >/dev/null 2>&1; then
        fail "update check accepted an unsigned release"
    fi
    if _run --apply >/dev/null 2>&1; then
        fail "update apply accepted an unsigned release"
    fi
    assert_eq "v2" "$(<"$client/tracked.qml")" "unsigned release worktree"
    [ ! -e "$cache/update-pending" ] \
        || fail "unsigned release left an installable update flag"

    git -C "$seed" push -q origin :refs/tags/v9.9.3 :refs/tags/v9.9.2
    _run >/dev/null 2>&1 \
        || fail "a release withdrawn upstream still blocked the update check"
    [ -z "$(git -C "$client" tag -l v9.9.3)" ] \
        || fail "update check kept a release tag withdrawn upstream"

    printf '4242\n' > "$cache/update-checked"
    git -C "$client" remote set-url origin "$TMP/unavailable-report-origin.git"
    if _run >/dev/null 2>&1; then
        fail "update check unexpectedly succeeded against an unavailable origin"
    fi
    assert_eq "4242" "$(cat "$cache/update-checked")" \
        "failed fetch preserved the last successful check time"
    sed -n '1p' "$cache/update-error" | grep -qE '^[0-9]{10,}$' \
        || fail "failed update check did not record when it failed"
    assert_eq "git fetch failed (check network / connectivity)" \
        "$(sed -n '2p' "$cache/update-error")" \
        "failed update check records an actionable reason"
)

test_repair_workflow() (
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_CONFIG_NOSYSTEM=1
    local repo="$TMP/repair" linked="$TMP/repair-linked" preview
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

    git -C "$repo" worktree add -qb repair-linked "$linked"
    [ -f "$linked/.git" ] || fail "repair fixture did not create a linked worktree"
    printf 'linked customization\n' > "$linked/tracked.qml"
    preview="$(bash "$linked/scripts/repair.sh")"
    printf '%s\n' "$preview" | grep -qF 'Nothing was changed' \
        || fail "repair preview rejected a linked worktree"
    bash "$linked/scripts/repair.sh" --apply --yes >/dev/null
    assert_eq "shipped" "$(<"$linked/tracked.qml")" "linked repair apply tracked file"
    bash "$linked/scripts/repair.sh" --undo --yes >/dev/null
    assert_eq "linked customization" "$(<"$linked/tracked.qml")" "linked repair undo tracked file"

    if bash "$linked/scripts/repair.sh" --preview --yes unexpected >/dev/null 2>&1; then
        fail "repair accepted an unexpected third argument"
    fi

    mkdir -p "$linked/nested/scripts"
    cp "$linked/scripts/repair.sh" "$linked/nested/scripts/repair.sh"
    if bash "$linked/nested/scripts/repair.sh" --apply --yes >/dev/null 2>&1; then
        fail "repair accepted a directory nested inside another checkout"
    fi
    assert_eq "linked customization" "$(<"$linked/tracked.qml")" \
        "nested repair left its parent worktree untouched"
)

test_update_rejects_broken_stage() (
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_CONFIG_NOSYSTEM=1
    local remote="$TMP/rollback-remote.git"
    local seed="$TMP/rollback-seed"
    local client="$TMP/rollback-client"
    local test_home="$TMP/rollback-home"
    local stub_dir="$TMP/rollback-stubs"
    local good_head

    git init --bare -q "$remote"
    git --git-dir="$remote" symbolic-ref HEAD refs/heads/main
    git init -q "$seed"
    git -C "$seed" config user.name "Silere test"
    git -C "$seed" config user.email "test@example.invalid"
    _prepare_release_signer "$seed"
    mkdir -p "$seed/scripts/lib"
    cp "$ROOT/scripts/update.sh" "$seed/scripts/update.sh"
    cp "$ROOT/scripts/lib/xdg.sh" "$seed/scripts/lib/xdg.sh"
    cp "$ROOT/scripts/lib/qml-modules.sh" "$seed/scripts/lib/qml-modules.sh"
    cp "$ROOT/scripts/lib/unit.sh" "$seed/scripts/lib/unit.sh"
    # The gate runs whatever type-checker the staged tree ships, so the fixture
    # owns the verdict without ever replacing the live script mid-execution.
    printf '#!/bin/sh\nexit 0\n' > "$seed/scripts/test-qml-headless.sh"
    printf 'upstream v1\n' > "$seed/tracked.qml"
    git -C "$seed" add scripts security tracked.qml
    git -C "$seed" commit -qm "initial"
    git -C "$seed" branch -M main
    _sign_release "$seed" v1.0.0
    git -C "$seed" remote add origin "$remote"
    git -C "$seed" push -q -u origin main --tags

    git clone -q "$remote" "$client"
    git -C "$client" config user.name "Silere test"
    git -C "$client" config user.email "test@example.invalid"
    good_head="$(git -C "$client" rev-parse HEAD)"

    mkdir -p "$test_home" "$stub_dir"
    printf '#!/bin/sh\nexit 1\n' > "$stub_dir/systemctl"
    printf '#!/bin/sh\nexit 0\n' > "$stub_dir/notify-send"
    # the gate skips itself when qs is absent, so without this stub the rollback
    # assertions below would pass on a machine that never ran the check at all
    printf '#!/bin/sh\nexit 0\n' > "$stub_dir/qs"
    chmod +x "$stub_dir/systemctl" "$stub_dir/notify-send" "$stub_dir/qs"

    printf 'upstream v2\n' > "$seed/tracked.qml"
    printf '#!/bin/sh\nexit 1\n' > "$seed/scripts/test-qml-headless.sh"
    git -C "$seed" commit -qam "broken upstream"
    _sign_release "$seed" v1.0.1
    git -C "$seed" push -q origin main --tags

    HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" >/dev/null
    if HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
            bash "$client/scripts/update.sh" --apply >/dev/null 2>&1; then
        fail "an update that fails the load gate was applied anyway"
    fi
    assert_eq "$good_head" "$(git -C "$client" rev-parse HEAD)" "rolled back HEAD"
    assert_eq "upstream v1" "$(cat "$client/tracked.qml")" "untouched live worktree"
    [ -f "$test_home/cache/silere-shell/update-pending" ] \
        || fail "rollback cleared the pending update flag"

    # positive control: the same path must still apply when the merged tree loads,
    # or a gate that always failed would satisfy every assertion above
    cat > "$seed/scripts/test-qml-headless.sh" <<'EOF'
#!/usr/bin/env bash
candidate_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "$candidate_root" != "${SILERE_EXPECT_LIVE_ROOT:-}" ] || exit 81
[ "$(cat "$candidate_root/tracked.qml")" = "upstream v3" ] || exit 82
printf '%s\n' "$candidate_root" > "${SILERE_STAGE_CAPTURE:?}"
EOF
    printf 'upstream v3\n' > "$seed/tracked.qml"
    git -C "$seed" commit -qam "working upstream"
    _sign_release "$seed" v1.0.2
    git -C "$seed" push -q origin main --tags
    HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" >/dev/null
    stage_capture="$TMP/update-stage-path"
    HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        SILERE_EXPECT_LIVE_ROOT="$client" SILERE_STAGE_CAPTURE="$stage_capture" \
        bash "$client/scripts/update.sh" --apply >/dev/null
    assert_eq "upstream v3" "$(cat "$client/tracked.qml")" "applied a tree that loads"
    [ "$(cat "$stage_capture")" != "$client" ] \
        || fail "candidate validation ran in the live checkout"
    [ ! -e "$(cat "$stage_capture")" ] \
        || fail "successful validation left its staging worktree"
    assert_eq 1 "$(git -C "$client" worktree list --porcelain | grep -c '^worktree ')" \
        "staging worktree cleanup"

    # A user edit arriving during validation wins. Recheck after the gate and
    # refuse activation without discarding the edit or the pending release.
    cat > "$seed/scripts/test-qml-headless.sh" <<'EOF'
#!/usr/bin/env bash
printf 'local edit during staging\n' >> "${SILERE_EXPECT_LIVE_ROOT:?}/tracked.qml"
exit 0
EOF
    printf 'upstream v4\n' > "$seed/tracked.qml"
    git -C "$seed" commit -qam "racing upstream"
    _sign_release "$seed" v1.0.3
    git -C "$seed" push -q origin main --tags
    HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" >/dev/null
    before_race="$(git -C "$client" rev-parse HEAD)"
    if HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
            SILERE_EXPECT_LIVE_ROOT="$client" \
            bash "$client/scripts/update.sh" --apply >/dev/null 2>&1; then
        fail "update activated after the live checkout changed during staging"
    fi
    assert_eq "$before_race" "$(git -C "$client" rev-parse HEAD)" \
        "staging race HEAD"
    grep -qF 'local edit during staging' "$client/tracked.qml" \
        || fail "staging race discarded the live edit"
    [ -f "$test_home/cache/silere-shell/update-pending" ] \
        || fail "staging race cleared the pending release"
)

test_fresh_install_pins_release() (
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_CONFIG_NOSYSTEM=1
    local remote="$TMP/pin-remote.git"
    local seed="$TMP/pin-seed"
    local client="$TMP/pin-client"
    local test_home="$TMP/pin-home"
    local release_rev

    git init --bare -q "$remote"
    git --git-dir="$remote" symbolic-ref HEAD refs/heads/main
    git init -q "$seed"
    git -C "$seed" config user.name "Silere test"
    git -C "$seed" config user.email "test@example.invalid"
    _prepare_release_signer "$seed"
    mkdir -p "$seed/scripts/lib"
    cp "$ROOT/scripts/update.sh" "$seed/scripts/update.sh"
    cp "$ROOT/scripts/lib/xdg.sh" "$seed/scripts/lib/xdg.sh"
    cp "$ROOT/scripts/lib/qml-modules.sh" "$seed/scripts/lib/qml-modules.sh"
    cp "$ROOT/scripts/lib/unit.sh" "$seed/scripts/lib/unit.sh"
    printf 'release\n' > "$seed/tracked.qml"
    git -C "$seed" add scripts security tracked.qml
    git -C "$seed" commit -qm "initial"
    git -C "$seed" branch -M main
    _sign_release "$seed" v1.0.0
    release_rev="$(git -C "$seed" rev-parse "v1.0.0^{}")"
    printf 'unreleased\n' > "$seed/tracked.qml"
    git -C "$seed" commit -qam "unreleased work"
    git -C "$seed" remote add origin "$remote"
    git -C "$seed" push -q -u origin main --tags

    git clone -q "$remote" "$client"
    git -C "$client" config user.name "Silere test"
    git -C "$client" config user.email "test@example.invalid"
    [ "$(git -C "$client" rev-parse HEAD)" != "$release_rev" ] \
        || fail "fresh clone fixture is not ahead of the signed release"

    mkdir -p "$test_home"
    HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" \
        bash "$client/scripts/update.sh" --pin-release >/dev/null

    assert_eq "$release_rev" "$(git -C "$client" rev-parse HEAD)" \
        "fresh install pinned revision"
    assert_eq "v1.0.0" "$(git -C "$client" describe --tags)" \
        "fresh install release tag"
    assert_eq "release" "$(cat "$client/tracked.qml")" "fresh install worktree contents"

    printf 'local edit\n' >> "$client/tracked.qml"
    if HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" \
            bash "$client/scripts/update.sh" --pin-release >/dev/null 2>&1; then
        fail "dirty pin-release unexpectedly succeeded"
    fi
)

# timeout stops watching when its direct command exits, so the inner shell must stay
# until every ordinary background child has left the timeout-owned process group.
test_hook_timeout_contains_tree() (
    command -v timeout >/dev/null 2>&1 || {
        printf 'SKIP: hook containment (timeout unavailable)\n'
        return 0
    }
    local dir hook child
    dir="$(mktemp -d)"
    trap 'rm -rf "$dir"' RETURN
    hook="$dir/hook"
    cat > "$hook" <<EOF
#!/bin/sh
sh -c 'echo \$\$ > "$dir/child.pid"; exec sleep 600' &
exit 0
EOF
    chmod +x "$hook"

    # the same monitor Hooks.qml places between timeout and the hook
    local monitor='"$@"; code=$?; '
    monitor+='IFS= read -r own < /proc/self/stat || exit "$code"; '
    monitor+='self=${own%% *}; rest=${own##*) }; set -- $rest; group=$3; outer=$PPID; '
    monitor+='while :; do alive=false; for stat in /proc/[0-9]*/stat; do '
    monitor+='[ -r "$stat" ] || continue; IFS= read -r line < "$stat" || continue; '
    monitor+='pid=${line%% *}; rest=${line##*) }; set -- $rest; '
    monitor+='[ "${1:-}" != Z ] && [ "${3:-}" = "$group" ] '
    monitor+='&& [ "$pid" != "$self" ] && [ "$pid" != "$outer" ] '
    monitor+='&& { alive=true; break; }; done; $alive || exit "$code"; sleep 0.25; done'
    timeout --kill-after=1 1 bash -c "$monitor" silere-hook "$hook" >/dev/null 2>&1 &
    local wrapper=$!
    local waited=0
    while [ ! -s "$dir/child.pid" ] && [ "$waited" -lt 50 ]; do
        sleep 0.1
        waited=$((waited + 1))
    done
    child="$(cat "$dir/child.pid" 2>/dev/null || true)"
    [ -n "$child" ] || fail "hook containment: the test hook never reported its child"
    wait "$wrapper" 2>/dev/null || true
    sleep 1

    if _pid_running "$child"; then
        kill -KILL "$child" 2>/dev/null || true
        fail "a hook's background child outlived the hook's runtime bound"
    fi
)

# The updater serializes on an flock'd fd 9. Any child that inherits it holds the lock
# for as long as it lives, so a fetch that outlives its run wedges every later one --
# the failure _git_fetch's comment describes. Closing the fd for the child is what makes
# that impossible; a timeout alone does not, because the orphan is the case where it failed.
test_update_lock_survives_orphaned_child() (
    command -v flock >/dev/null 2>&1 || {
        printf 'SKIP: update lock orphan (flock unavailable)\n'
        return 0
    }
    local dir lock kid
    dir="$(mktemp -d)"
    trap 'rm -rf "$dir"' RETURN
    lock="$dir/update.lock"
    : > "$lock"

    # the redirect _git_fetch applies to its child, with the parent gone afterwards
    bash -c "
        exec 9>>'$lock'
        flock -n 9 || exit 1
        sleep 30 9>&- &
        echo \$! > '$dir/kid'
    " || fail "update lock orphan: could not take the lock"
    kid="$(cat "$dir/kid" 2>/dev/null || true)"
    [ -n "$kid" ] || fail "update lock orphan: no child was started"

    if flock -n "$lock" -c true 2>/dev/null; then
        kill -KILL "$kid" 2>/dev/null || true
    else
        kill -KILL "$kid" 2>/dev/null || true
        fail "an update child outliving its run still holds the update lock"
    fi

    grep -q 'git fetch --quiet "$@" 9>&-' "$ROOT/scripts/update.sh" \
        || fail "the update fetch no longer closes the lock fd for its child"
)

# The confirm screen names one release, and --apply resolves the newest signed tag on
# its own. A release published between the check and the press is trusted but was never
# shown to anyone, so applying it would install something nobody agreed to.
test_update_apply_binds_to_confirmed_release() (
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_CONFIG_NOSYSTEM=1
    local remote="$TMP/bind-remote.git"
    local seed="$TMP/bind-seed"
    local client="$TMP/bind-client"
    local test_home="$TMP/bind-home"
    local stub_dir="$TMP/bind-stubs" out head_before pending_flag confirmed_rev

    git init --bare -q "$remote"
    git --git-dir="$remote" symbolic-ref HEAD refs/heads/main
    git init -q "$seed"
    git -C "$seed" config user.name "Silere test"
    git -C "$seed" config user.email "test@example.invalid"
    _prepare_release_signer "$seed"
    mkdir -p "$seed/scripts/lib"
    cp "$ROOT/scripts/update.sh" "$seed/scripts/update.sh"
    cp "$ROOT/scripts/lib/xdg.sh" "$seed/scripts/lib/xdg.sh"
    cp "$ROOT/scripts/lib/qml-modules.sh" "$seed/scripts/lib/qml-modules.sh"
    cp "$ROOT/scripts/lib/unit.sh" "$seed/scripts/lib/unit.sh"
    printf 'upstream v1\n' > "$seed/tracked.qml"
    git -C "$seed" add scripts security tracked.qml
    git -C "$seed" commit -qm "initial"
    git -C "$seed" branch -M main
    _sign_release "$seed" v1.0.0
    git -C "$seed" remote add origin "$remote"
    git -C "$seed" push -q -u origin main --tags

    git clone -q "$remote" "$client"
    git -C "$client" config user.name "Silere test"
    git -C "$client" config user.email "test@example.invalid"

    mkdir -p "$test_home" "$stub_dir"
    printf '#!/bin/sh\nexit 1\n' > "$stub_dir/systemctl"
    printf '#!/bin/sh\nexit 0\n' > "$stub_dir/notify-send"
    chmod +x "$stub_dir/systemctl" "$stub_dir/notify-send"

    # the release the user sees and confirms
    printf 'upstream v2\n' > "$seed/tracked.qml"
    git -C "$seed" commit -qam "second"
    _sign_release "$seed" v1.0.1
    git -C "$seed" push -q origin main --tags
    HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" >/dev/null
    confirmed_rev="$(git -C "$client" rev-parse 'v1.0.1^{}')"
    grep -qF "target $confirmed_rev v1.0.1 verified" \
        "$test_home/cache/silere-shell/update-pending" \
        || fail "apply binding: the check did not record the full confirmed target"

    pending_flag="$test_home/cache/silere-shell/update-pending"
    cp "$pending_flag" "$pending_flag.good"
    printf '%s\n' 1 'summary without a target' > "$pending_flag"
    head_before="$(git -C "$client" rev-parse HEAD)"
    if out="$(HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
            bash "$client/scripts/update.sh" --apply 2>&1)"; then
        fail "apply accepted a pending update with no confirmed target"
    fi
    printf '%s\n' "$out" | grep -q 'confirmed release is missing or malformed' \
        || fail "apply binding: malformed-target refusal was unclear: $out"
    assert_eq "$head_before" "$(git -C "$client" rev-parse HEAD)" \
        "a malformed confirmed target leaves the checkout untouched"
    mv "$pending_flag.good" "$pending_flag"

    # a newer signed release lands before the press, and the client fetches it
    printf 'upstream v3\n' > "$seed/tracked.qml"
    git -C "$seed" commit -qam "third"
    _sign_release "$seed" v1.0.2
    git -C "$seed" push -q origin main --tags
    git -C "$client" fetch -q --tags origin main

    head_before="$(git -C "$client" rev-parse HEAD)"
    if out="$(HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
            bash "$client/scripts/update.sh" --apply 2>&1)"; then
        fail "apply installed v1.0.2 when v1.0.1 was the confirmed release"
    fi
    printf '%s\n' "$out" | grep -q 'is not the release that was confirmed' \
        || fail "apply binding: refusal did not name the confirmed release: $out"
    assert_eq "$head_before" "$(git -C "$client" rev-parse HEAD)" \
        "apply binding leaves the checkout untouched"

    # re-checking re-confirms the newest release, and then apply proceeds
    HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" >/dev/null
    HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" --apply >/dev/null 2>&1 || true
    assert_eq "upstream v3" "$(cat "$client/tracked.qml")" \
        "apply proceeds once the newest release has been confirmed"
)

test_menu_keybind_plan() (
    local home="$TMP/keybind-home" dir conf before out verdict
    dir="$home/.config/hypr"
    conf="$dir/hyprland.conf"
    mkdir -p "$dir"

    verdict() { # $1 = line under test, $2 = modifiers to offer
        printf '%s\n' "$1" > "$TMP/keybind-probe.conf"
        MENU_BIND_MODS="${2:-SUPER}" MENU_BIND_KEY=slash bash -c '
            SILERE_SCRIPT_LIB_ONLY=1 source "$1"
            _bind_taken "$2" && printf taken || printf free
        ' _ "$ROOT/scripts/install.sh" "$TMP/keybind-probe.conf"
    }
    assert_eq taken "$(verdict 'bind = SUPER, slash, exec, foot')" "literal modifier and key"
    assert_eq taken "$(verdict 'bind = $mainMod, slash, exec, foot')" "variable modifier"
    assert_eq taken "$(verdict 'bindd = SUPER, Slash, menu, exec, foot')" "bind variant and key case"
    assert_eq free "$(verdict '# bind = SUPER, slash, exec, foot')" "commented-out bind"
    assert_eq free "$(verdict 'bind = SUPER, S, exec, foot')" "different key"
    assert_eq free "$(verdict 'bind = SUPER SHIFT, slash, exec, foot')" "different modifiers"
    assert_eq taken "$(verdict 'bind = WIN, slash, exec, foot')" "a modifier synonym"
    assert_eq taken "$(verdict 'bind = mod4, slash, exec, foot')" "a lowercase modifier synonym"
    assert_eq taken "$(verdict 'bind = SHIFT_SUPER, slash, exec, foot' 'SUPER SHIFT')" "modifier order"
    assert_eq free "$(verdict 'bind = SUPER_SHIFT, slash, exec, foot' 'SUPER CTRL')" "one modifier apart"
    assert_eq "Mod+Shift+M" "$(bash -c 'SILERE_SCRIPT_LIB_ONLY=1 source "$1"; _niri_combo "SUPER SHIFT" m' \
        _ "$ROOT/scripts/install.sh")" "niri hint follows the configured keys"

    printf 'monitor=,preferred,auto,1\n' > "$conf"
    before="$(<"$conf")"
    out="$(HOME="$home" XDG_CONFIG_HOME="$home/.config" SILERE_HYPR_CONFIG="$conf" \
        bash "$ROOT/scripts/install.sh" --dry-run </dev/null 2>&1)" \
        || fail "keybind dry run exited non-zero"
    case "$out" in
        *"append to $conf: bind = SUPER, slash, exec, qs ipc -p "*"call menu toggle"*) ;;
        *) fail "dry run did not plan the menu keybind for a free key" ;;
    esac
    assert_eq "$before" "$(<"$conf")" "keybind dry run left the config unchanged"

    printf 'bind = $mainMod, slash, exec, foot\n' > "$dir/binds.conf"
    out="$(HOME="$home" XDG_CONFIG_HOME="$home/.config" SILERE_HYPR_CONFIG="$conf" \
        bash "$ROOT/scripts/install.sh" --dry-run </dev/null 2>&1)" \
        || fail "keybind dry run with a taken key exited non-zero"
    case "$out" in
        *"already bound in your Hyprland config"*) ;;
        *) fail "a key bound in a sourced file was not reported as taken" ;;
    esac
    case "$out" in
        *"append to $conf: bind = "*) fail "dry run planned a keybind over a taken key" ;;
    esac
    rm -f "$dir/binds.conf"

    printf -- '-- lua config\n' > "$dir/hyprland.lua"
    before="$(<"$dir/hyprland.lua")"
    out="$(HOME="$home" XDG_CONFIG_HOME="$home/.config" SILERE_HYPR_CONFIG="$dir/hyprland.lua" \
        bash "$ROOT/scripts/install.sh" --dry-run </dev/null 2>&1)" \
        || fail "keybind dry run with a Lua config exited non-zero"
    case "$out" in
        *"Lua config"*'hl.bind("SUPER + slash", hl.dsp.exec_cmd("qs ipc -p '*'call menu toggle"))'*) ;;
        *) fail "a Lua config was not offered a Lua bind to add" ;;
    esac
    assert_eq "$before" "$(<"$dir/hyprland.lua")" "Lua config left unchanged"
)

test_plain_copy_is_not_package_managed() (
    local copy="$TMP/plain-copy" home="$TMP/plain-copy-home" out
    mkdir -p "$copy" "$home"
    cp -R "$ROOT/scripts" "$copy/"
    cp "$ROOT/release.json" "$copy/"
    git -C "$copy" rev-parse --git-dir >/dev/null 2>&1 && fail "plain copy fixture sits inside a git checkout"

    run_update() {
        HOME="$home" XDG_STATE_HOME="$home/state" XDG_CONFIG_HOME="$home/config" \
            bash "$copy/scripts/update.sh" "$@" </dev/null 2>&1
    }
    out="$(run_update --version)" || fail "version query failed on a plain copy"
    case "$out" in
        *"packaged=1"*"mode=copy"*) ;;
        *) fail "a download without git or a package marker was reported as package-managed" ;;
    esac
    out="$(run_update)" && fail "an update check succeeded on a plain copy"
    case "$out" in
        *"reinstall with scripts/install.sh"*) ;;
        *) fail "a plain copy was not pointed at the installer" ;;
    esac

    printf '9.9.9\n' > "$copy/package-version"
    out="$(run_update --version)" || fail "version query failed on a packaged copy"
    case "$out" in
        *"version=9.9.9"*"mode=package"*) ;;
        *) fail "a copy carrying package-version was not reported as package-managed" ;;
    esac
    out="$(run_update)" && fail "an update check succeeded on a packaged copy"
    case "$out" in
        *"through your package manager"*) ;;
        *) fail "a packaged copy was not pointed at its package manager" ;;
    esac
)

test_unit_identity() (
    local root="$TMP/unit-root" stubs="$TMP/unit-stubs" link="$TMP/unit-bin/silere" exec_start
    mkdir -p "$root/scripts" "$stubs" "$TMP/unit-bin"
    printf '#!/bin/sh\n' > "$root/scripts/silere"
    chmod +x "$root/scripts/silere"
    ln -s "$root/scripts/silere" "$link"
    source "$ROOT/scripts/lib/unit.sh"
    unit_says() {
        printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$1" > "$stubs/systemctl"
        chmod +x "$stubs/systemctl"
    }
    for exec_start in "qs -p $root/shell.qml" "qs -n -p $root/shell.qml" "qs -p $root" \
            "$root/scripts/silere run" "$link run"; do
        unit_says "{ path=/usr/bin/x ; argv[]=$exec_start ; ignore_errors=no ; }"
        PATH="$stubs:$PATH" _silere_unit_runs_checkout "$root" \
            || fail "a unit running '$exec_start' was not recognised as this checkout"
    done
    for exec_start in "qs -p /elsewhere/shell.qml" "$root/scripts/silere status" \
            "qs -p $root/shell.qml.bak"; do
        unit_says "{ path=/usr/bin/x ; argv[]=$exec_start ; ignore_errors=no ; }"
        PATH="$stubs:$PATH" _silere_unit_runs_checkout "$root" \
            && fail "a unit running '$exec_start' was taken for this checkout"
    done
    return 0
)

if [ "${SILERE_TEST_LIB_ONLY:-0}" = 1 ]; then
    return 0 2>/dev/null || exit 0
fi

test_xdg_paths_and_timer_default
test_fresh_install_permissions
test_marker_removal
test_uninstall_targets_and_backups
test_qml_module_lookup
test_headless_qml_import_roots
test_font_archive_selection
test_assume_yes_prompts
test_install_path_safety
test_install_transaction_and_receipt
test_dry_run_writes_nothing
test_menu_keybind_plan
test_plain_copy_is_not_package_managed
test_unit_identity
test_hypr_discovery
test_niri_config_discovery
test_atomic_units
test_shared_launcher
test_hook_timeout_contains_tree
test_repair_workflow

printf 'portability regression tests passed\n'
