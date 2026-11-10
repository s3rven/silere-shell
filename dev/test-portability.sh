#!/usr/bin/env bash
# the sourced scripts are linted on their own and read the globals set here
# shellcheck source=/dev/null disable=SC2034
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/silere-portability-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# No test may reach the live session's notification daemon or service manager.
# Individual stubs provide fixture state; defaults keep unhandled calls isolated.
mkdir -p "$TMP/suite-stubs"
printf '#!/bin/sh\nexit 0\n' > "$TMP/suite-stubs/notify-send"
printf '#!/bin/sh\nexit 1\n' > "$TMP/suite-stubs/systemctl"
chmod +x "$TMP/suite-stubs/notify-send" "$TMP/suite-stubs/systemctl"
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
        HOME="$home" XDG_CONFIG_HOME=relative/config XDG_CACHE_HOME=relative/cache XDG_STATE_HOME=relative/state \
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
    local linked_home="$TMP/install-linked-home" linked_default="$TMP/linked-default" actual
    HOME="$home" XDG_CONFIG_HOME=relative SILERE_SCRIPT_LIB_ONLY=1 \
        source "$ROOT/scripts/install.sh"

    mkdir -p "$DEFAULT_DIR" "$custom"
    chmod 0755 "$DEFAULT_DIR" "$custom"
    _secure_fresh_default_install "$DEFAULT_DIR"
    assert_eq "700" "$(stat -c '%a' "$DEFAULT_DIR")" "fresh default install mode"

    _secure_fresh_default_install "$custom"
    assert_eq "755" "$(stat -c '%a' "$custom")" "custom install mode"

    _secure_config_home "$home/fresh-config/nested"
    assert_eq "700|700" "$(stat -c '%a' "$home/fresh-config")|$(stat -c '%a' "$home/fresh-config/nested")" \
        "fresh config home mode"
    mkdir -p "$home/kept-config" "$home/shared-config"
    chmod 0755 "$home/kept-config"; chmod 0777 "$home/shared-config"
    _secure_config_home "$home/kept-config"
    _secure_config_home "$home/shared-config"
    assert_eq "755|755" "$(stat -c '%a' "$home/kept-config")|$(stat -c '%a' "$home/shared-config")" \
        "existing config home keeps its read access and loses shared write"

    mkdir -p "$linked_home/.config" "$linked_default"
    ln -s "$linked_default" "$linked_home/.config/silere-shell"
    chmod 0755 "$linked_default"
    actual="$(HOME="$linked_home" XDG_CONFIG_HOME="$linked_home/.config" \
        SILERE_SCRIPT_LIB_ONLY=1 bash -c '
            source "$1"
            _secure_fresh_default_install "$DEFAULT_DIR"
            printf "%s|%s" "$DEFAULT_DIR" "$(stat -c %a "$DEFAULT_DIR")"
        ' _ "$ROOT/scripts/install.sh")"
    assert_eq "$linked_default|700" "$actual" "symlinked default install mode"
)

test_existing_checkout_installer_update() (
    local home="$TMP/install-update-home" checkout="$TMP/install-update-checkout"
    local calls="$TMP/install-update-calls"
    mkdir -p "$checkout/scripts" "$home"
    cat > "$checkout/scripts/update.sh" <<'EOF'
#!/usr/bin/env bash
set -e
mkdir -p "$XDG_CACHE_HOME/silere-shell"
if [ "${1:-}" = --apply ]; then
    printf 'apply\n' >> "$SILERE_TEST_CALLS"
    rm -f "$XDG_CACHE_HOME/silere-shell/update-pending"
else
    printf 'check\n' >> "$SILERE_TEST_CALLS"
    if [ "${SILERE_TEST_PENDING:-0}" = 1 ]; then
        printf '1\n' > "$XDG_CACHE_HOME/silere-shell/update-pending"
    else
        rm -f "$XDG_CACHE_HOME/silere-shell/update-pending"
    fi
fi
EOF
    export HOME="$home" XDG_CACHE_HOME="$home/cache" SILERE_TEST_CALLS="$calls"
    SILERE_SCRIPT_LIB_ONLY=1 source "$ROOT/scripts/install.sh"

    : > "$calls"
    SILERE_TEST_PENDING=1 \
        _install_checked_release "$checkout" || fail "installer could not apply a pending release"
    assert_eq $'check\napply' "$(cat "$calls")" "installer applies a pending release"

    : > "$calls"
    SILERE_TEST_PENDING=0 \
        _install_checked_release "$checkout" || fail "installer rejected an up-to-date checkout"
    assert_eq check "$(cat "$calls")" "installer leaves an up-to-date checkout alone"
)

test_lua_exec_return_guard() (
    SILERE_SCRIPT_LIB_ONLY=1 source "$ROOT/scripts/install.sh"
    local dir="$TMP/lua-return"
    mkdir -p "$dir"
    printf 'local M = {}\nfunction M.f()\n    return 1\nend\nreturn M\n' > "$dir/module.lua"
    printf 'hl.exec_cmd("a")\nlocal function f()\n    return 1\nend\nlocal returned = f()\n' > "$dir/plain.lua"
    _lua_ends_in_return "$dir/module.lua" \
        || fail "installer would append autostart after a Lua module's top-level return"
    ! _lua_ends_in_return "$dir/plain.lua" \
        || fail "an indented return or a name starting with return blocked the Lua autostart"
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
        if _remove_block "$dir/$name.conf" '# silere-shell begin' '# silere-shell end' >/dev/null; then
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

test_uninstall_empty_optional_paths() (
    local fixture="$TMP/uninstall-optional" mode home out
    mkdir -p "$fixture/scripts/lib" "$fixture/stubs"
    cp "$ROOT/scripts/uninstall.sh" "$ROOT/scripts/service.sh" "$fixture/scripts/"
    cp "$ROOT/scripts/lib/"*.sh "$fixture/scripts/lib/"
    # Discovery and service commands must stay within this fixture.
    printf '#!/bin/sh\nexit 0\n' > "$fixture/scripts/install.sh"
    # the generated shell service runs this fixture, so service.sh may remove it
    printf '#!/bin/sh\ncase "$*" in *"-p ExecStart"*) echo "{ path=%s/scripts/silere ; argv[]=%s/scripts/silere run ; ignore_errors=no }" ;; esac\nexit 0\n' \
        "$fixture" "$fixture" > "$fixture/stubs/systemctl"
    chmod +x "$fixture/stubs/systemctl"

    for mode in absent managed; do
        home="$fixture/$mode"
        mkdir -p "$home/.config/hypr" "$home/.config/systemd/user" "$home/.local/state"
        printf '%s\n' before '# silere-shell begin' owned '# silere-shell end' after \
            > "$home/.config/hypr/hyprland.conf"
        printf 'keep\n' > "$home/.config/hypr/unrelated.conf"
        : > "$home/.config/systemd/user/silere-update.timer"
        : > "$home/.config/systemd/user/silere-update.service"
        if [ "$mode" = managed ]; then
            _mark_managed_install "$fixture" "$home"
            printf '%s\n' '# generated by silere-shell' '[Service]' "ExecStart=$fixture/scripts/silere run" \
                > "$home/.config/systemd/user/silere-shell.service"
        fi
        if ! out="$(HOME="$home" XDG_CONFIG_HOME="$home/.config" \
                XDG_STATE_HOME="$home/.local/state" XDG_DATA_HOME="$home/.local/share" \
                SILERE_ASSUME_YES=1 PATH="$fixture/stubs:$PATH" \
                bash "$fixture/scripts/uninstall.sh" 2>&1)"; then
            fail "uninstaller with $mode receipt and empty optional paths failed: $out"
        fi
        assert_eq $'before\nafter' "$(<"$home/.config/hypr/hyprland.conf")" \
            "uninstaller $mode receipt removes owned block"
        assert_eq keep "$(<"$home/.config/hypr/unrelated.conf")" \
            "uninstaller $mode receipt preserves unrelated config"
        [ ! -e "$home/.config/systemd/user/silere-update.timer" ] \
            && [ ! -e "$home/.config/systemd/user/silere-update.service" ] \
            || fail "uninstaller $mode receipt stopped before timer cleanup"
        [ ! -e "$home/.config/systemd/user/silere-shell.service" ] \
            || fail "uninstaller $mode receipt left the generated shell service"
    done
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

test_quickshell_version_after_qt_warning() (
    local stub="$TMP/qs-version-stub"
    mkdir -p "$stub"
    printf '#!/bin/sh\n%s\n%s\n' \
        'echo "Detected locale \"C\" with character encoding \"ANSI_X3.4-1968\", which is not UTF-8." >&2' \
        'echo "Quickshell 0.3.1 (revision , distributed by Arch Linux)"' > "$stub/qs"
    chmod +x "$stub/qs"
    PATH="$stub:$PATH"
    source "$ROOT/scripts/lib/qml-modules.sh"
    assert_eq 0.3.1 "$(_silere_quickshell_version)" "the Quickshell version is read past Qt's locale warning"
)

test_quickshell_qt_drift() (
    local stub="$TMP/qs-log-stub"
    mkdir -p "$stub"
    printf '#!/bin/sh\n[ "$1" = log ] || exit 2\nprintf "%%b\\n" "$SILERE_TEST_QS_LOG"\n' > "$stub/qs"
    chmod +x "$stub/qs"
    PATH="$stub:$PATH"
    source "$ROOT/scripts/lib/qml-modules.sh"
    export SILERE_TEST_QS_LOG='  INFO: Launching config\n\033[33m  WARN\033[0m: \033[31mQuickshell was built against Qt 6.11.2 but the system has updated to Qt 6.12.0 without rebuilding the package.'
    assert_eq "6.11.2 6.12.0" "$(_silere_quickshell_qt_drift "$ROOT/shell.qml")" \
        "a Quickshell build for an older Qt is read from its colored log line"
    export SILERE_TEST_QS_LOG='  INFO: Configuration Loaded'
    assert_eq "" "$(_silere_quickshell_qt_drift "$ROOT/shell.qml")" "a log without the warning reports no drift"
)

test_qml_type_floor() (
    local older="$TMP/qml-qt68" newer="$TMP/qml-qt69" bare="$TMP/qml-bare" rc
    mkdir -p "$older/QtQuick/Effects" "$newer/QtQuick/Effects" "$bare/QtQuick/Effects"
    printf 'module QtQuick.Effects\n' | tee "$older/QtQuick/Effects/qmldir" \
        "$newer/QtQuick/Effects/qmldir" "$bare/QtQuick/Effects/qmldir" >/dev/null
    printf 'exports: ["QtQuick.Effects/MultiEffect 6.5"]\n' > "$older/QtQuick/Effects/plugins.qmltypes"
    printf 'exports: ["QtQuick.Effects/RectangularShadow 6.9"]\n' > "$newer/QtQuick/Effects/plugins.qmltypes"

    export QML_IMPORT_PATH=""
    export QML2_IMPORT_PATH="$older:$newer"
    SILERE_SCRIPT_LIB_ONLY=1 source "$ROOT/scripts/install.sh"
    rc=0; _qml_type_exported QtQuick.Effects RectangularShadow || rc=$?
    assert_eq 1 "$rc" "a Qt 6.8 QtQuick.Effects first on the path is below the floor"

    _silere_qml_import_roots=("$newer" "$older")
    rc=0; _qml_type_exported QtQuick.Effects RectangularShadow || rc=$?
    assert_eq 0 "$rc" "a Qt 6.9 QtQuick.Effects meets the floor"

    _silere_qml_import_roots=("$bare")
    rc=0; _qml_type_exported QtQuick.Effects RectangularShadow || rc=$?
    assert_eq 2 "$rc" "a module without qmltypes is unknown, not a failure"

    local shapes="$TMP/qml-qt610"
    mkdir -p "$shapes/QtQuick/Shapes"
    printf 'module QtQuick.Shapes\n' > "$shapes/QtQuick/Shapes/qmldir"
    printf 'name: "QQuickShapePath"\n' > "$shapes/QtQuick/Shapes/plugins.qmltypes"
    _silere_qml_import_roots=("$shapes")
    rc=0; _qt_floor_met || rc=$?
    assert_eq 1 "$rc" "a Qt without ShapePath trim is below the floor"
    printf 'name: "QQuickShapeTrim"\n' >> "$shapes/QtQuick/Shapes/plugins.qmltypes"
    rc=0; _qt_floor_met || rc=$?
    assert_eq 0 "$rc" "ShapePath trim meets the floor"
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
            SILERE_QMLLINT_HELP="${lint_help// / <level> } <level>" \
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

test_installer_options() (
    local home="$TMP/installer-options" conf target out code args stubs
    mkdir -p "$home/config/hypr"
    conf="$home/config/hypr/hyprland.conf"
    target="$home/custom copy"
    printf 'monitor=,preferred,auto,1\n' > "$conf"
    installer() {
        HOME="$home" XDG_CONFIG_HOME="$home/config" XDG_STATE_HOME="$home/state" \
            XDG_CACHE_HOME="$home/cache" XDG_DATA_HOME="$home/data" SILERE_HYPR_CONFIG="$conf" \
            SILERE_SANDBOX=1 bash "$ROOT/scripts/install.sh" "$@" </dev/null
    }
    out="$(installer --yes --no-start --dir "$target" --dry-run 2>&1)" \
        || fail "installer options cannot preview a custom path without a terminal"
    [[ "$out" == *"clone "*"$target"* ]] || fail "custom install path is missing from the preview"
    [[ "$out" == *"$target/scripts/silere"* ]] || fail "the custom preview did not carry its path into integrations"
    [ ! -e "$target" ] && [ ! -e "$home/state" ] || fail "an installer preview wrote files"
    out="$(installer --dry-run --dir="$target" -y --no-start 2>&1)" \
        || fail "installer options depend on argument order"
    [[ "$out" == *"$target/scripts/silere"* ]] || fail "--dir= lost the custom install path"
    for args in missing-dir empty-dir unknown duplicate-dir mixed-check unsafe-dir; do
        code=0
        case "$args" in
            missing-dir) installer --dir >/dev/null 2>&1 || code=$? ;;
            empty-dir) installer --dir= >/dev/null 2>&1 || code=$? ;;
            unknown) installer --dry-run --unknown >/dev/null 2>&1 || code=$? ;;
            duplicate-dir) installer --dir "$target" --dir "$target" >/dev/null 2>&1 || code=$? ;;
            mixed-check) installer --check --yes >/dev/null 2>&1 || code=$? ;;
            unsafe-dir) installer --yes --dir "$home/config" >/dev/null 2>&1 || code=$? ;;
        esac
        [ "$code" -ne 0 ] || fail "installer accepted invalid options: $args"
        [ ! -e "$target" ] && [ ! -e "$home/state" ] || fail "invalid installer options wrote files: $args"
    done

    # Run the complete unattended path against a private checkout and helpers.
    stubs="$home/bin"
    mkdir -p "$stubs" "$target/.git" "$target/services" "$target/scripts" "$target/assets"
    : > "$target/shell.qml"
    : > "$target/services/qmldir"
    printf '#!/bin/sh\nexit 0\n' > "$target/scripts/update.sh"
    printf '#!/bin/sh\ntouch "$HOME/unexpected-launch"\n' > "$target/scripts/silere"
    chmod +x "$target/scripts/silere"
    cp "$ROOT/assets/matugen-theme.json" "$target/assets/"
    printf '#!/bin/sh\n[ "$1" = -C ] && [ "$3" = status ]\n' > "$stubs/git"
    printf '#!/bin/sh\nprintf "JetBrainsMono Nerd Font\\n"\n' > "$stubs/fc-list"
    chmod +x "$stubs/git" "$stubs/fc-list"
    out="$(PATH="$stubs:$PATH" SILERE_ASSUME_YES=0 installer --yes --dir "$target" --no-start 2>&1)" \
        || fail "the unattended custom install failed: $out"
    assert_eq "$target/scripts/silere" "$(readlink "$home/.local/bin/silere")" \
        "an unattended custom install links its selected checkout"
    [ -f "$home/state/silere-shell/install-receipt" ] || fail "the unattended install wrote no receipt"
    [ ! -e "$home/unexpected-launch" ] || fail "the unattended installer launched the shell"
    grep -qF '# silere-shell begin' "$conf" || fail "the unattended install omitted autostart"
    [ ! -e "$home/config/systemd/user/silere-update.timer" ] || fail "--yes opted into an update timer"
)

test_piped_installer_bootstraps() (
    local src="$TMP/bootstrap-src" stubs="$TMP/bootstrap-stubs" tmp="$TMP/bootstrap-tmp" out
    mkdir -p "$src/scripts" "$stubs" "$tmp"
    cp -a "$ROOT/scripts/install.sh" "$ROOT/scripts/lib" "$src/scripts/"
    : > "$src/shell.qml"
    # never the network: a clone copies the fixture checkout
    printf '%s\n' '#!/bin/sh' \
        '[ "$1" = clone ] && [ -z "${SILERE_TEST_CLONE_FAILS-}" ] || exit 128' \
        'for dest do :; done' \
        'cp -a "$SILERE_TEST_SRC" "$dest"' > "$stubs/git"
    chmod +x "$stubs/git"

    out="$(cd "$tmp" && env TMPDIR="$tmp" PATH="$stubs:$PATH" SILERE_TEST_SRC="$src" \
        bash -s -- --help < "$ROOT/scripts/install.sh" 2>&1)" || fail "piped installer exited non-zero"
    case "$out" in
        *"Fetching the Silere installer"*"Usage:"*) ;;
        *) fail "piped installer did not run the fetched copy: $out" ;;
    esac
    [ -z "$(find "$tmp" -mindepth 1 -maxdepth 1 -name 'silere-install.*')" ] \
        || fail "piped installer left its download behind"

    mkdir -p "$tmp/home/config/hypr"
    printf 'monitor=,preferred,auto,1\n' > "$tmp/home/config/hypr/hyprland.conf"
    out="$(cd "$tmp" && env HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/config" \
        XDG_STATE_HOME="$tmp/home/state" XDG_CACHE_HOME="$tmp/home/cache" \
        XDG_DATA_HOME="$tmp/home/data" SILERE_HYPR_CONFIG="$tmp/home/config/hypr/hyprland.conf" \
        TMPDIR="$tmp" PATH="$stubs:$PATH" SILERE_TEST_SRC="$src" SILERE_SANDBOX=1 \
        bash -s -- --yes --dir "$tmp/chosen copy" --no-start --dry-run < "$ROOT/scripts/install.sh" 2>&1)" \
        || fail "piped installer lost combined options"
    [[ "$out" == *"$tmp/chosen copy/scripts/silere"* ]] \
        || fail "piped installer did not preserve a custom path containing spaces"
    [ ! -e "$tmp/chosen copy" ] || fail "a piped preview created its install directory"
    [ -z "$(find "$tmp" -mindepth 1 -maxdepth 1 -name 'silere-install.*')" ] \
        || fail "a piped preview left its download behind"

    # curl reports whatever part of the script it could not hand over, so the bootstrap reads the pipe to its end;
    # the rest arrives after the block has run, as it does over a network
    (cd "$tmp" && { head -c 2000 "$ROOT/scripts/install.sh"; sleep 0.3; tail -c +2001 "$ROOT/scripts/install.sh"
        echo "$?" > "$tmp/writer-rc"; } | env TMPDIR="$tmp" PATH="$stubs:$PATH" SILERE_TEST_SRC="$src" \
        SILERE_TEST_CLONE_FAILS=1 bash >/dev/null 2>&1) || true
    assert_eq "0" "$(cat "$tmp/writer-rc" 2>/dev/null)" "piped installer reads the whole script it was sent"

    if out="$(cd "$tmp" && env TMPDIR="$tmp" PATH="$stubs:$PATH" SILERE_TEST_SRC="$src" \
            SILERE_TEST_CLONE_FAILS=1 bash -s < "$ROOT/scripts/install.sh" 2>&1)"; then
        fail "piped installer claimed success without a download"
    fi
    case "$out" in
        *"could not download Silere"*) ;;
        *) fail "piped installer hid a failed download: $out" ;;
    esac
    [ -z "$(find "$tmp" -mindepth 1 -maxdepth 1 -name 'silere-install.*')" ] \
        || fail "a failed download left its directory behind"
)

test_autostart_line_runs() (
    local home line out stub
    for home in "$TMP/autostart home" "$TMP/autostart-plain"; do
        mkdir -p "$home/.config/hypr" "$home/.config/silere-shell/scripts"
        printf 'monitor=,preferred,auto,1\n' > "$home/.config/hypr/hyprland.conf"
        out="$(HOME="$home" XDG_CONFIG_HOME="$home/.config" \
            SILERE_HYPR_CONFIG="$home/.config/hypr/hyprland.conf" \
            bash "$ROOT/scripts/install.sh" --dry-run </dev/null 2>&1)" \
            || fail "autostart dry run exited non-zero"
        line="$(printf '%s\n' "$out" | sed -n 's/.*: exec-once = //p' | head -n 1)"
        case "$home" in
            *" "*) case "$line" in *"printf '%b'"*) ;;
                   *) fail "an install path with a space was written without byte encoding" ;; esac
                   case "$line" in *"$home"*) fail "an install path with a space was written raw" ;; esac ;;
            *) assert_eq "exec \"$home/.config/silere-shell/scripts/silere\" run --startup" "$line" \
                   "an ordinary install path is written readably" ;;
        esac
        stub="$home/.config/silere-shell/scripts/silere"
        printf '#!/bin/sh\nprintf "%%s\\n" "$*"\n' > "$stub"
        chmod +x "$stub"
        assert_eq "run --startup" "$(sh -c "$line")" "the planned autostart line launches silere run"
    done
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
    _txn_rollback >/dev/null

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
    _txn_rollback >/dev/null
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

test_update_timer_failures() (
    local test_home="$TMP/update-timer-home" stub_dir="$TMP/update-timer-stubs" out
    mkdir -p "$test_home" "$stub_dir"
    cat > "$stub_dir/systemctl" <<'EOF'
#!/bin/sh
case "$*" in
    *"disable --now silere-update.timer"*)
        [ "${SILERE_TIMER_FAILURE:-}" != disable ] || exit 1 ;;
    *daemon-reload*)
        [ "${SILERE_TIMER_FAILURE:-}" != reload ] || exit 1 ;;
esac
exit 0
EOF
    chmod +x "$stub_dir/systemctl"

    _disable_timer() {
        XDG_CONFIG_HOME="$test_home/config" XDG_CACHE_HOME="$test_home/cache" \
            XDG_STATE_HOME="$test_home/state" PATH="$stub_dir:$PATH" \
            bash "$ROOT/scripts/update.sh" --timer-disable
    }
    if out="$(SILERE_TIMER_FAILURE=disable _disable_timer 2>&1)"; then
        fail "a failed timer disable was reported as successful"
    fi
    grep -qF 'could not disable silere-update.timer' <<<"$out" \
        || fail "a failed timer disable did not explain what failed"
    if out="$(SILERE_TIMER_FAILURE=reload _disable_timer 2>&1)"; then
        fail "a failed timer daemon reload was reported as successful"
    fi
    grep -qF 'systemctl daemon-reload failed' <<<"$out" \
        || fail "a failed timer daemon reload did not explain what failed"
    _disable_timer >/dev/null || fail "disabling the timer could not recover after a failure"
)

test_shared_launcher() (
    local stub_dir="$TMP/launcher-stubs"
    local capture="$TMP/launcher-default.out"
    local expected_args
    umask 022
    mkdir -p "$stub_dir"
    printf '%s\n' \
        '#!/bin/sh' \
        'for arg do [ "$arg" = "${SILERE_STUB_REJECT-}" ] && exit 109; done' \
        ': > "$SILERE_LAUNCH_CAPTURE"' \
        'printf "malloc=%s\nimages=%s\negl=%s\nlocale=%s\numask=%s\nwatch=%s\npipewire=%s\n" "${MALLOC_CONF-}" "${QSG_TRANSIENT_IMAGES-}" "${__EGL_VENDOR_LIBRARY_FILENAMES-}" "${LC_ALL-<unset>}" "$(umask)" "${SILERE_WATCH_FILES-}" "${QS_PIPEWIRE_IMMEDIATE_RECONNECT-}" >> "$SILERE_LAUNCH_CAPTURE"' \
        'for arg do printf "arg=%s\n" "$arg" >> "$SILERE_LAUNCH_CAPTURE"; done' \
        > "$stub_dir/qs"
    chmod +x "$stub_dir/qs"

    env -u MALLOC_CONF -u QSG_TRANSIENT_IMAGES -u LC_ALL -u SILERE_WATCH_FILES \
        PATH="$stub_dir:$PATH" SILERE_LAUNCH_CAPTURE="$capture" \
        __EGL_VENDOR_LIBRARY_FILENAMES=/chosen/vendor.json \
        bash "$ROOT/scripts/silere" run --verbose
    grep -qFx 'malloc=' "$capture" \
        || fail "shared launcher added an allocator override"
    # the second window to draw a cached image gets an empty texture with it set
    grep -qFx 'images=' "$capture" \
        || fail "shared launcher set QSG_TRANSIENT_IMAGES"
    grep -qF 'egl=/chosen/vendor.json' "$capture" \
        || fail "shared launcher replaced an inherited EGL vendor"
    grep -qFx 'locale=<unset>' "$capture" \
        || fail "shared launcher leaked its parser locale"
    grep -qFx 'umask=0022' "$capture" \
        || fail "shared launcher changed the user's umask"
    grep -qFx 'watch=0' "$capture" \
        || fail "shared launcher did not disable reload during managed updates"
    grep -qFx 'pipewire=1' "$capture" \
        || fail "shared launcher did not ask Quickshell to wait for a late PipeWire"
    expected_args=$'arg=--no-duplicate\narg=--no-detailed-logs\narg=-p\narg='"$ROOT"$'/shell.qml\narg=--verbose'
    assert_eq "$expected_args" "$(grep '^arg=' "$capture")" "shared launcher argv"
    # a quickshell without the hidden flag must still start
    env PATH="$stub_dir:$PATH" SILERE_LAUNCH_CAPTURE="$capture" SILERE_STUB_REJECT=--no-detailed-logs \
        bash "$ROOT/scripts/silere" run --verbose
    expected_args=$'arg=--no-duplicate\narg=-p\narg='"$ROOT"$'/shell.qml\narg=--verbose'
    assert_eq "$expected_args" "$(grep '^arg=' "$capture")" "shared launcher argv without --no-detailed-logs"
    assert_eq "644" "$(stat -c '%a' "$capture")" "shared launcher state umask"

    capture="$TMP/launcher-overrides.out"
    MALLOC_CONF='' SILERE_WATCH_FILES=1 QSG_TRANSIENT_IMAGES=1 \
        LC_ALL=C PATH="$stub_dir:$PATH" SILERE_LAUNCH_CAPTURE="$capture" \
        __EGL_VENDOR_LIBRARY_FILENAMES='' \
        bash "$ROOT/scripts/silere" run
    grep -qFx 'images=' "$capture" \
        || fail "shared launcher inherited QSG_TRANSIENT_IMAGES from a legacy service"
    grep -qFx 'malloc=' "$capture" \
        || fail "shared launcher did not preserve an empty allocator override"
    grep -qFx 'egl=' "$capture" \
        || fail "shared launcher did not preserve an empty EGL override"
    grep -qFx 'locale=C' "$capture" \
        || fail "shared launcher did not preserve an inherited locale"
    grep -qFx 'watch=1' "$capture" \
        || fail "shared launcher did not preserve the user's hot reload choice"

    capture="$TMP/launcher-package-name.out"
    ln -s "$ROOT/scripts/silere" "$stub_dir/silere-shell"
    MALLOC_CONF='' \
        PATH="$stub_dir:$PATH" SILERE_LAUNCH_CAPTURE="$capture" \
        __EGL_VENDOR_LIBRARY_FILENAMES='' \
        "$stub_dir/silere-shell" --verbose
    expected_args=$'arg=--no-duplicate\narg=--no-detailed-logs\narg=-p\narg='"$ROOT"$'/shell.qml\narg=--verbose'
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
    printf 'old release\n' > "$repo/old-only"
    printf 'new-only\n' > "$repo/.gitignore"
    git -C "$repo" add security tracked.qml old-only .gitignore
    git -C "$repo" commit -qm "known good"
    old_rev="$(git -C "$repo" rev-parse HEAD)"
    printf 'signed update\n' > "$repo/tracked.qml"
    git -C "$repo" rm -q old-only
    printf 'new release\n' > "$repo/new-only"
    git -C "$repo" add -f new-only
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

    # Git's reset --keep still overwrites ignored paths. The updater's own
    # revision switch must preserve both ignored and ordinary untracked files.
    printf 'personal ignored data\n' > "$repo/new-only"
    if ( _reset_preserving_user_files "$new_rev" >/dev/null 2>&1 ); then
        fail "revision switch overwrote an ignored file"
    fi
    assert_eq "personal ignored data" "$(cat "$repo/new-only")" \
        "ignored file survives a blocked revision switch"
    assert_eq "$old_rev" "$(git -C "$repo" rev-parse HEAD)" \
        "ignored collision leaves HEAD untouched"
    rm -f "$repo/new-only"
    git -C "$repo" reset --hard -q "$new_rev"
    printf 'personal untracked data\n' > "$repo/old-only"
    if ( _reset_preserving_user_files "$old_rev" >/dev/null 2>&1 ); then
        fail "revision switch overwrote an untracked file"
    fi
    assert_eq "personal untracked data" "$(cat "$repo/old-only")" \
        "untracked file survives a blocked revision switch"
    rm -f "$repo/old-only"
    git -C "$repo" reset --hard -q "$old_rev"

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
    local stub_dir="$TMP/update-rollback-stub"
    local calls="$TMP/update-rollback-calls"
    mkdir -p "$stub_dir"
    printf '#!/bin/sh\ncase "$*" in *" show "*) echo "{ path=%s/scripts/silere ; argv[]=%s/scripts/silere run ; }" ;; esac\nexit 0\n' \
        "$repo" "$repo" > "$stub_dir/systemctl"
    chmod +x "$stub_dir/systemctl"
    _start_apply_transaction "$old_rev" "$new_rev" v1.0.1
    git -C "$repo" show-ref --quiet --verify refs/silere/update-transaction \
        || fail "an apply transaction did not pin its release tag"
    git -C "$repo" merge --ff-only -q "$new_rev"
    _write_apply_journal validated "$old_rev" "$new_rev" v1.0.1
    PATH="$stub_dir:$PATH" _recover_interrupted_apply 2>/dev/null
    assert_eq "$new_rev" "$(git -C "$repo" rev-parse HEAD)" \
        "validated interrupted update retained"
    [ ! -e "$APPLY_JOURNAL" ] || fail "validated transaction journal was not cleared"
    git -C "$repo" show-ref --quiet --verify refs/silere/update-transaction \
        && fail "a cleared transaction left its release pin behind"

    # --rollback consumes a retained validated journal to undo a release that
    # never came up in the live session. The stub answers as a unit running a
    # different checkout: the rollback must not restart whatever shell is live.
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
    PATH="$stub_dir:$PATH" _rollback_applied_update >/dev/null 2>&1
    assert_eq "$old_rev" "$(git -C "$repo" rev-parse HEAD)" \
        "rollback restores the revision the update replaced"
    [ ! -e "$APPLY_JOURNAL" ] || fail "rollback left the update journal behind"
    grep -q 'restart silere-shell.service' "$calls" \
        && fail "rollback restarted a unit that runs another checkout"
    if ( _rollback_applied_update >/dev/null 2>&1 ); then
        fail "rollback accepted a missing journal"
    fi

    # The optional supervised service is started rather than enabled. When an update
    # leaves it failed the journal has to stay, or --rollback has nothing to restore.
    cat > "$stub_dir/systemctl" <<EOF
#!/bin/sh
case "\$*" in
    *" show "*) echo "{ path=$repo/scripts/silere ; argv[]=$repo/scripts/silere run ; }" ;;
    *is-failed*) exit 0 ;;
    *) exit 1 ;;
esac
EOF
    _start_apply_transaction "$old_rev" "$new_rev" v1.0.1
    git -C "$repo" merge --ff-only -q "$new_rev"
    _write_apply_journal validated "$old_rev" "$new_rev" v1.0.1
    PATH="$stub_dir:$PATH" _recover_interrupted_apply 2>/dev/null
    [ -e "$APPLY_JOURNAL" ] || fail "a failed service that was never enabled lost its recovery journal"
    PATH="$stub_dir:$PATH" _rollback_applied_update >/dev/null 2>&1
    assert_eq "$old_rev" "$(git -C "$repo" rev-parse HEAD)" \
        "rollback restores an update whose service failed without being enabled"

    # An update check prunes a tag withdrawn upstream. A release pulled because it broke is the one
    # that most needs --rollback, so the journal's own pin has to prove it once the tag is gone
    _start_apply_transaction "$old_rev" "$new_rev" v1.0.1
    git -C "$repo" merge --ff-only -q "$new_rev"
    _write_apply_journal validated "$old_rev" "$new_rev" v1.0.1
    git -C "$repo" tag -d v1.0.1 >/dev/null
    ( PATH="$stub_dir:$PATH" _rollback_applied_update >/dev/null 2>&1 ) \
        || fail "rollback could not prove a release whose tag an update check pruned"
    assert_eq "$old_rev" "$(git -C "$repo" rev-parse HEAD)" \
        "rollback restores a release whose tag an update check pruned"
    git -C "$repo" show-ref --quiet --verify refs/silere/update-transaction \
        && fail "rollback left its release pin behind"
    git -C "$repo" tag -s -m v1.0.1 v1.0.1 "$new_rev"

    # With no unit in use, a shell running this checkout is what shows the update came up;
    # a daily check after a login whose shell never returned must not take --rollback away
    printf '#!/bin/sh\nexit 1\n' > "$stub_dir/systemctl"
    printf '#!/bin/sh\nexit 0\n' > "$stub_dir/qs"
    chmod +x "$stub_dir/systemctl" "$stub_dir/qs"
    _start_apply_transaction "$old_rev" "$new_rev" v1.0.1
    git -C "$repo" merge --ff-only -q "$new_rev"
    _write_apply_journal validated "$old_rev" "$new_rev" v1.0.1
    PATH="$stub_dir:$PATH" _recover_interrupted_apply 2>/dev/null
    [ -e "$APPLY_JOURNAL" ] || fail "an update whose unsupervised shell never came back lost its recovery journal"
    printf '#!/bin/sh\nprintf "Instance probe:\\n  Process ID: 4242\\n"\n' > "$stub_dir/qs"
    PATH="$stub_dir:$PATH" _recover_interrupted_apply 2>/dev/null
    [ ! -e "$APPLY_JOURNAL" ] || fail "an update whose unsupervised shell came back kept its recovery journal"

    # a unit that is up for another checkout says nothing about this one: only this checkout's shell counts
    cat > "$stub_dir/systemctl" <<EOF
#!/bin/sh
case "\$*" in
    *" show "*) printf '{ path=/usr/bin/qs ; argv[]=/usr/bin/qs -p /elsewhere/shell.qml ; }\n' ;;
esac
exit 0
EOF
    printf '#!/bin/sh\nexit 0\n' > "$stub_dir/qs"
    _start_apply_transaction "$old_rev" "$new_rev" v1.0.1
    git -C "$repo" merge --ff-only -q "$new_rev"
    _write_apply_journal validated "$old_rev" "$new_rev" v1.0.1
    PATH="$stub_dir:$PATH" _recover_interrupted_apply 2>/dev/null
    [ -e "$APPLY_JOURNAL" ] || fail "a unit running another checkout counted as this update's shell coming back"
    printf '#!/bin/sh\nprintf "Instance probe:\\n  Process ID: 4242\\n"\n' > "$stub_dir/qs"
    PATH="$stub_dir:$PATH" _recover_interrupted_apply 2>/dev/null
    [ ! -e "$APPLY_JOURNAL" ] || fail "this checkout's shell beside another checkout's unit kept the recovery journal"
    rm -f "$stub_dir/qs"

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
    local -a quarantines=( "$STATE_DIR"/update-quarantine-"$ROOT_KEY".* )
    [ -f "${quarantines[0]}/journal" ] \
        || fail "malformed journal was not preserved for inspection"
    assert_eq "not a journal" "$(cat "${quarantines[0]}/journal")" \
        "quarantined journal keeps its original bytes"
    [ ! -e "$APPLY_JOURNAL" ] \
        || fail "malformed journal still blocks the next update run"
    rm -rf -- "${quarantines[@]}"
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
printf '%s\n%s\n%s\n%s\n' "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$SILERE_SMOKE_TEST" \
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
    assert_eq 1 "$(sed -n '4p' "$capture")" "candidate starts in smoke mode"
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
    printf 'shipped\n' > "$seed/notes.json"
    git -C "$seed" add notes.json
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
    if HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" \
            PATH="$stub_dir:$PATH" \
            bash "$client/scripts/update.sh" --apply >/dev/null 2>&1; then
        fail "offline update apply accepted a release it could not recheck upstream"
    fi
    assert_eq "$old_head" "$(git -C "$client" rev-parse HEAD)" "offline update apply HEAD"
    [ -e "$test_home/cache/silere-shell/update-pending" ] \
        || fail "offline update apply cleared the pending update flag"

    git -C "$client" remote set-url origin "$remote"
    # settings and history live ignored in the checkout; a release shipping a file at one of their paths stops
    printf 'notes.json\n' >> "$client/.git/info/exclude"
    printf 'personal\n' > "$client/notes.json"
    if HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
            bash "$client/scripts/update.sh" --apply >/dev/null 2>&1; then
        fail "update apply replaced an ignored file the release ships"
    fi
    assert_eq "personal" "$(cat "$client/notes.json")" "an ignored file survives a blocked update"
    assert_eq "$old_head" "$(git -C "$client" rev-parse HEAD)" "ignored collision apply HEAD"
    rm -f "$client/notes.json"
    HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" --apply >/dev/null 2>&1 \
        || fail "apply did not recover after the origin returned"
    assert_eq "$remote_head" "$(git -C "$client" rev-parse HEAD)" "reconnected update apply HEAD"
    [ ! -e "$test_home/cache/silere-shell/update-pending" ] \
        || fail "successful apply left the pending update flag"
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
    grep -qE '^sha=[0-9a-f]{7,}$' <<<"$out" || fail "--version omitted the commit sha"
    grep -qE '^date=[0-9]{4}-[0-9]{2}-[0-9]{2}$' <<<"$out" || fail "--version omitted the build date"
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
    grep -qF 'target v9.9.1' <<<"$notes" \
        || fail "release notes cache does not name its verified target"
    grep -qF $'Added\tA useful release summary that wraps onto one normalized cache row.' <<<"$notes" \
        || fail "release notes cache did not normalize a wrapped Added entry"
    grep -qF $'Fixed\tA test fixture bug.' <<<"$notes" \
        || fail "release notes cache omitted a Fixed entry"

    _run --apply >/dev/null 2>&1
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

    git -C "$seed" update-ref refs/tags/v9.9.5 "$(git -C "$seed" rev-parse v9.9.0)"
    git -C "$seed" push -q origin refs/tags/v9.9.5
    if _run >/dev/null 2>&1; then
        fail "update check accepted an old signed release under a newer name"
    fi
    grep -qF 'v9.9.5 carries the signature of a different release' "$cache/update-error" \
        || fail "a renamed release did not record why it was refused"
    git -C "$seed" push -q origin :refs/tags/v9.9.5
    git -C "$seed" tag -d v9.9.5 >/dev/null
    _run >/dev/null 2>&1 \
        || fail "a renamed release withdrawn upstream still blocked the update check"

    # git picks the checker from the signature, so a PGP key in the user's own keyring must not stand in for the
    # release key. Every other gate passes here, which is what makes the signature the one being tested
    if command -v gpg >/dev/null 2>&1; then
        local fpr accepted=0
        mkdir -m 700 "$test_home/.gnupg"
        GNUPGHOME="$test_home/.gnupg" gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
            --quick-gen-key 'Not Silere <pgp@example.invalid>' ed25519 sign never 2>/dev/null
        fpr="$(GNUPGHOME="$test_home/.gnupg" gpg --batch --with-colons --list-keys 2>/dev/null \
            | awk -F: '/^fpr/ { print $10; exit }')"
        sed -i 's/"quickshellMin": "99.0.0"/"quickshellMin": "0.3.1"/; s/"version": "9.9.3"/"version": "9.9.6"/' \
            "$seed/release.json"
        printf 'pgp v5\n' > "$seed/tracked.qml"
        git -C "$seed" commit -qam "pgp-signed upstream"
        GNUPGHOME="$test_home/.gnupg" git -C "$seed" -c gpg.format=openpgp -c user.signingkey="$fpr" \
            tag -s -m v9.9.6 v9.9.6
        git -C "$seed" push -q --tags origin main
        _run >/dev/null 2>&1 && accepted=1
        # the agent this started outlives the fixture otherwise
        GNUPGHOME="$test_home/.gnupg" gpgconf --kill all 2>/dev/null || true
        [ "$accepted" = 0 ] || fail "update check accepted a release signed by a PGP key in the user's keyring"
        grep -qF 'v9.9.6 is not signed by the trusted Silere release key' "$cache/update-error" \
            || fail "a PGP-signed release did not record why it was refused"
        [ ! -e "$cache/update-pending" ] \
            || fail "a PGP-signed release left an installable update flag"
        git -C "$seed" push -q origin :refs/tags/v9.9.6
        git -C "$seed" tag -d v9.9.6 >/dev/null
    fi

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
    grep -qF 'Nothing was changed' <<<"$preview" \
        || fail "repair preview did not state that it was side-effect free"
    assert_eq "customized" "$(<"$repo/tracked.qml")" "repair preview tracked file"
    [ -f "$repo/custom.qml" ] || fail "repair preview removed an untracked file"

    bash "$repo/scripts/repair.sh" --apply --yes >/dev/null
    assert_eq "shipped" "$(<"$repo/tracked.qml")" "repair apply tracked file"
    [ ! -e "$repo/custom.qml" ] || fail "repair apply left an untracked source file"
    assert_eq '{"barHeight":40}' "$(<"$repo/settings.json")" "repair apply personal settings"
    [ -z "$(git -C "$repo" status --short --untracked-files=normal)" ] \
        || fail "repair apply did not produce a clean checkout"
    grep -qF 'silere-repair ' <<<"$(git -C "$repo" stash list)" \
        || fail "repair apply did not create a named stash"

    bash "$repo/scripts/repair.sh" --undo --yes >/dev/null
    assert_eq "customized" "$(<"$repo/tracked.qml")" "repair undo tracked file"
    assert_eq "new widget" "$(<"$repo/custom.qml")" "repair undo untracked file"
    assert_eq '{"barHeight":40}' "$(<"$repo/settings.json")" "repair undo personal settings"

    git -C "$repo" worktree add -qb repair-linked "$linked"
    [ -f "$linked/.git" ] || fail "repair fixture did not create a linked worktree"
    printf 'linked customization\n' > "$linked/tracked.qml"
    preview="$(bash "$linked/scripts/repair.sh")"
    grep -qF 'Nothing was changed' <<<"$preview" \
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

    printf '#!/bin/sh\nexit 127\n' > "$stub_dir/qs"
    if out="$(HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
            bash "$client/scripts/update.sh" --apply 2>&1)"; then
        fail "an update was applied while qs cannot start"
    fi
    case "$out" in
        *"Quickshell cannot start"*) ;;
        *) fail "an update with a qs that cannot start blamed something else: $out" ;;
    esac
    printf '#!/bin/sh\nexit 0\n' > "$stub_dir/qs"

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
        bash "$client/scripts/update.sh" --apply >/dev/null 2>&1
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

# panels compile when first opened, so a shell left running would read a new release's panels against old services
test_update_restarts_running_shell() (
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_CONFIG_NOSYSTEM=1
    local remote="$TMP/restart-remote.git"
    local seed="$TMP/restart-seed"
    local client="$TMP/restart-client"
    local test_home="$TMP/restart-home"
    local stub_dir="$TMP/restart-stubs"
    local restarts="$TMP/restart-calls"
    local notices="$TMP/restart-notices"
    local tag_n=1

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
    printf '#!/bin/sh\nexit 0\n' > "$seed/scripts/test-qml-headless.sh"
    # the shell it starts outlives the updater: holding the updater's lock would block every later check
    cat > "$seed/scripts/silere" <<'EOF'
#!/bin/sh
[ -e /proc/$$/fd/9 ] && printf 'holds the update lock\n' >> "$SILERE_RESTART_LOG"
printf '%s\n' "$*" >> "$SILERE_RESTART_LOG"
EOF
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
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$notices" > "$stub_dir/notify-send"
    cat > "$stub_dir/qs" <<'EOF'
#!/bin/sh
[ "$1" = list ] && [ -n "${SILERE_FAKE_SHELL:-}" ] && printf '  Process ID: 4242\n'
exit 0
EOF
    chmod +x "$stub_dir/systemctl" "$stub_dir/notify-send" "$stub_dir/qs"

    apply_release() { # "$@" = extra environment for the apply
        local expect_failure=0 code=0
        if [ "${1:-}" = --expect-failure ]; then expect_failure=1; shift; fi
        tag_n=$((tag_n + 1))
        printf 'upstream v%s\n' "$tag_n" > "$seed/tracked.qml"
        git -C "$seed" commit -qam "release $tag_n"
        _sign_release "$seed" "v1.0.$((tag_n - 1))"
        git -C "$seed" push -q origin main --tags
        : > "$restarts"; : > "$notices"
        HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
            bash "$client/scripts/update.sh" >/dev/null
        env "$@" HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
            SILERE_RESTART_LOG="$restarts" bash "$client/scripts/update.sh" --apply >"$TMP/apply.out" 2>&1 \
            || code=$?
        if [ "$expect_failure" = 1 ]; then
            [ "$code" -ne 0 ] || fail "an update with a failed restart was reported as successful"
        elif [ "$code" -ne 0 ]; then
            cat "$TMP/apply.out" >&2
            fail "the release did not apply"
        fi
    }
    await_restart() { # the restart is detached, so it lands a moment after the updater exits
        local _
        for _ in $(seq 1 50); do [ -s "$restarts" ] && return 0; sleep 0.1; done
        return 1
    }

    apply_release WAYLAND_DISPLAY=lab SILERE_FAKE_SHELL=1
    await_restart || fail "an update left a running shell on the old release"
    assert_eq "restart" "$(cat "$restarts")" "update restarts through the checkout's own command"
    if grep -qF 'restart the shell' "$notices"; then fail "an update that restarted the shell still asked for a restart"; fi

    apply_release WAYLAND_DISPLAY=lab
    sleep 0.3
    if [ -s "$restarts" ]; then fail "an update started a shell that was not running"; fi
    grep -qF 'restart the shell' "$notices" || fail "the update notice lost its restart hint with no shell to restart"

    # outside the session there is nothing to bring a shell back onto
    apply_release -u WAYLAND_DISPLAY SILERE_FAKE_SHELL=1
    sleep 0.3
    if [ -s "$restarts" ]; then fail "an update restarted a shell from outside the Wayland session"; fi
    grep -qF 'restart the shell' "$notices" || fail "an update it could not restart after did not ask for one"

    : > "$restarts"
    env HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" SILERE_RESTART_LOG="$restarts" \
        WAYLAND_DISPLAY=lab SILERE_FAKE_SHELL=1 bash "$client/scripts/update.sh" --rollback >/dev/null 2>&1 \
        || fail "the rollback failed"
    await_restart || fail "a rollback left a running shell on the replaced release"

    # a rejected service restart leaves the files installed but the old shell running;
    # report the failure and retain enough state to undo the update from a terminal
    cat > "$stub_dir/systemctl" <<'EOF'
#!/bin/sh
case "$*" in
    *"is-active --quiet silere-shell.service"*) exit 0 ;;
    *" show silere-shell.service "*)
        printf '{ path=%s/scripts/silere ; argv[]=%s/scripts/silere run ; }\n' \
            "$SILERE_TEST_CHECKOUT" "$SILERE_TEST_CHECKOUT" ;;
    *) exit 1 ;;
esac
EOF
    export SILERE_TEST_CHECKOUT="$client"
    local previous_rev status
    previous_rev="$(git -C "$client" rev-parse HEAD)"
    apply_release --expect-failure WAYLAND_DISPLAY=lab
    grep -qF 'could not be restarted' "$TMP/apply.out" \
        || fail "a rejected restart did not explain how to recover"
    status="$(HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" --transaction-status)"
    grep -qFx 'pending=1' <<<"$status" \
        || fail "a rejected restart discarded the update recovery journal"
    grep -qFx 'authenticated=1' <<<"$status" \
        || fail "a rejected restart lost the authenticated rollback target"
    HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" >/dev/null 2>&1 \
        || fail "an update check after a rejected restart failed"
    status="$(HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" --transaction-status)"
    grep -qFx 'pending=1' <<<"$status" \
        || fail "a later check mistook the old running shell for a successful restart and discarded rollback"
    printf '1\nrestart failed\n' > "$test_home/cache/silere-shell/update-error"
    printf '1\nstale release\n' > "$test_home/cache/silere-shell/update-pending"
    printf 'stale notes\n' > "$test_home/cache/silere-shell/release-notes"
    HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" --rollback >/dev/null 2>&1 \
        || fail "an update whose service restart failed could not be rolled back"
    assert_eq "$previous_rev" "$(git -C "$client" rev-parse HEAD)" \
        "rollback after a rejected service restart"
    [ ! -e "$test_home/cache/silere-shell/update-error" ] \
        || fail "a successful rollback left the failed update status behind"
    [ ! -e "$test_home/cache/silere-shell/update-checked" ] \
        || fail "a successful rollback kept a last-check time for the replaced revision"
    [ ! -e "$test_home/cache/silere-shell/update-pending" ] \
        && [ ! -e "$test_home/cache/silere-shell/release-notes" ] \
        || fail "a successful rollback kept stale release details"
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

    git -C "$seed" push -q origin :refs/tags/v1.0.1
    head_before="$(git -C "$client" rev-parse HEAD)"
    if out="$(HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
            bash "$client/scripts/update.sh" --apply 2>&1)"; then
        fail "apply installed a release withdrawn after confirmation"
    fi
    grep -q 'v1.0.1 was withdrawn upstream' <<<"$out" \
        || fail "withdrawn release refusal was unclear: $out"
    assert_eq "$head_before" "$(git -C "$client" rev-parse HEAD)" \
        "withdrawn release leaves the checkout untouched"
    [ -e "$test_home/cache/silere-shell/update-pending" ] \
        || fail "withdrawn release cleared the pending update flag"
    git -C "$seed" push -q origin refs/tags/v1.0.1

    pending_flag="$test_home/cache/silere-shell/update-pending"
    cp "$pending_flag" "$pending_flag.good"
    printf '%s\n' 1 'summary without a target' > "$pending_flag"
    head_before="$(git -C "$client" rev-parse HEAD)"
    if out="$(HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
            bash "$client/scripts/update.sh" --apply 2>&1)"; then
        fail "apply accepted a pending update with no confirmed target"
    fi
    grep -q 'confirmed release is missing or malformed' <<<"$out" \
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
    grep -q 'is not the release that was confirmed' <<<"$out" \
        || fail "apply binding: refusal did not name the confirmed release: $out"
    assert_eq "$head_before" "$(git -C "$client" rev-parse HEAD)" \
        "apply binding leaves the checkout untouched"

    # re-checking re-confirms the newest release, and then apply proceeds
    HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" >/dev/null
    # the menu can still be displaying the previous review while a background check rewrites the cache
    if out="$(HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
            bash "$client/scripts/update.sh" --apply v1.0.1 "$confirmed_rev" 2>&1)"; then
        fail "apply replaced the release reviewed in the menu with the background check's newer target"
    fi
    grep -qF 'release changed since it was reviewed' <<<"$out" \
        || fail "apply did not explain the stale menu confirmation: $out"
    assert_eq "$head_before" "$(git -C "$client" rev-parse HEAD)" \
        "a stale menu confirmation leaves the checkout untouched"
    if out="$(HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
            bash "$client/scripts/update.sh" --apply v1.0.2 "$confirmed_rev" 2>&1)"; then
        fail "apply accepted the right release tag with a different reviewed revision"
    fi
    grep -qF 'release changed since it was reviewed' <<<"$out" \
        || fail "apply did not explain the stale reviewed revision: $out"
    assert_eq "$head_before" "$(git -C "$client" rev-parse HEAD)" \
        "a changed reviewed revision leaves the checkout untouched"
    local current_target
    current_target="$(git -C "$client" rev-parse 'v1.0.2^{}')"
    HOME="$test_home" XDG_CACHE_HOME="$test_home/cache" PATH="$stub_dir:$PATH" \
        bash "$client/scripts/update.sh" --apply v1.0.2 "$current_target" >/dev/null 2>&1 \
        || fail "apply rejected a freshly reviewed release and revision"
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

    if HOME="$home" XDG_CONFIG_HOME="$home/.config" SILERE_HYPR_CONFIG="$conf" \
            SILERE_MENU_BIND_KEY=$'slash\nexec-once=unexpected' \
            bash "$ROOT/scripts/install.sh" --dry-run </dev/null >/dev/null 2>&1; then
        fail "installer accepted a newline in the menu keybind"
    fi
    if HOME="$home" XDG_CONFIG_HOME="$home/.config" SILERE_HYPR_CONFIG="$conf" \
            SILERE_MENU_BIND_MODS='SUPER, slash, exec, unexpected' \
            bash "$ROOT/scripts/install.sh" --dry-run </dev/null >/dev/null 2>&1; then
        fail "installer accepted compositor syntax in menu keybind modifiers"
    fi
    assert_eq "$before" "$(<"$conf")" "invalid keybinds left the config unchanged"

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
        *"append to $dir/hyprland.lua: "'hl.bind("SUPER + slash", hl.dsp.exec_cmd("qs ipc -p '*'call menu toggle"))'*) ;;
        *) fail "a stock Lua config was not offered the bind: $out" ;;
    esac
    case "$out" in
        *"append to $dir/hyprland.lua: hl.exec_cmd("*) ;;
        *) fail "a stock Lua config with no execs.lua was not offered autostart: $out" ;;
    esac
    assert_eq "$before" "$(<"$dir/hyprland.lua")" "a dry run leaves a Lua config unchanged"

    # data-driven binds in another file count, and a comment naming the key does not
    printf -- '-- SUPER + slash used to open the launcher\n' > "$dir/binds.lua"
    out="$(HOME="$home" XDG_CONFIG_HOME="$home/.config" SILERE_HYPR_CONFIG="$dir/hyprland.lua" \
        bash "$ROOT/scripts/install.sh" --dry-run </dev/null 2>&1)"
    case "$out" in
        *"looks taken"*) fail "a comment was read as a bind: $out" ;;
    esac
    printf 'return { { mods = "SUPER", key = "slash", run = "launcher" } }\n' > "$dir/binds.lua"
    out="$(HOME="$home" XDG_CONFIG_HOME="$home/.config" SILERE_HYPR_CONFIG="$dir/hyprland.lua" \
        bash "$ROOT/scripts/install.sh" --dry-run </dev/null 2>&1)"
    case "$out" in
        *"looks taken"*) ;;
        *) fail "a bind held as data in another file was not reported as taken: $out" ;;
    esac
    rm -f "$dir/binds.lua"

    # a config ending in a return cannot take a block after it, so nothing is planned for it
    printf 'return {}\n' > "$dir/hyprland.lua"
    out="$(HOME="$home" XDG_CONFIG_HOME="$home/.config" SILERE_HYPR_CONFIG="$dir/hyprland.lua" \
        bash "$ROOT/scripts/install.sh" --dry-run </dev/null 2>&1)"
    case "$out" in
        *"append to $dir/hyprland.lua"*) fail "a block was planned after a return: $out" ;;
    esac
    case "$out" in
        *"ends in a return"*'hl.exec_cmd('*) ;;
        *) fail "a config ending in a return was not told what to add: $out" ;;
    esac
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
        printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\n' "$1" > "$stubs/systemctl"
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
    for exec_start in 'QSG_TRANSIENT_IMAGES=1' 'QSG_TRANSIENT_IMAGES=0' \
            'QSG_TRANSIENT_IMAGES=' 'PATH=/usr/bin "QSG_TRANSIENT_IMAGES=1"'; do
        unit_says "$exec_start"
        PATH="$stubs:$PATH" _silere_unit_uses_transient_images \
            || fail "transient image setting '$exec_start' was not diagnosed"
    done
    for exec_start in '' 'PATH=/usr/bin' 'OTHER_QSG_TRANSIENT_IMAGES=1'; do
        unit_says "$exec_start"
        PATH="$stubs:$PATH" _silere_unit_uses_transient_images \
            && fail "environment '$exec_start' was diagnosed as transient images"
    done
    return 0
)

test_reset_workflow() (
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_CONFIG_NOSYSTEM=1
    local repo="$TMP/reset-repo" home="$TMP/reset-home" stubs="$TMP/reset-stubs" state="$TMP/reset-shell" out before
    local config="$home/config/silere-shell" saved="$home/state/silere-shell" cache="$home/cache/silere-shell"
    mkdir -p "$repo/scripts" "$stubs" "$config/hooks" "$saved" "$cache/art"
    cp -a "$ROOT/scripts/." "$repo/scripts/"
    cp "$ROOT/release.json" "$repo/release.json"
    printf 'shipped\n' > "$repo/shell.qml"
    git -C "$repo" init -q
    git -C "$repo" config user.name "Silere test"
    git -C "$repo" config user.email "test@example.invalid"
    git -C "$repo" add .
    git -C "$repo" commit -qm initial

    printf '%s\n' \
        '#!/bin/sh' \
        'case "$1" in' \
        '    list) [ -s "$SILERE_TEST_STATE" ] && printf "Instance t:\n  Process ID: %s\n" "$(cat "$SILERE_TEST_STATE")"; exit 0 ;;' \
        '    kill) : > "$SILERE_TEST_STATE"; echo kill >> "$SILERE_TEST_STATE.calls"; exit 0 ;;' \
        '    --no-detailed-logs|--version) exit 0 ;;' \
        '    *) echo launch >> "$SILERE_TEST_STATE.calls"; echo 777 > "$SILERE_TEST_STATE" ;;' \
        'esac' > "$stubs/qs"
    # never the real systemctl: it would restart the live shell of whoever runs the tests
    printf '#!/bin/sh\nexit 1\n' > "$stubs/systemctl"
    chmod +x "$stubs/qs" "$stubs/systemctl"
    run_reset() {
        env -u LC_ALL -u SILERE_TEST_ROOT PATH="$stubs:$PATH" HOME="$home" XDG_CONFIG_HOME="$home/config" XDG_STATE_HOME="$home/state" \
            XDG_CACHE_HOME="$home/cache" SILERE_TEST_STATE="$state" WAYLAND_DISPLAY=wayland-test bash "$repo/scripts/silere" reset "$@"
    }
    fill() {
        printf '{\n  "__version": 2,\n  "barHeight": 40,\n  "dnd": true\n}\n' > "$config/settings.json"
        printf '{"__version":1,"marks":[]}\n' > "$config/calendar-marks.json"
        printf '{"__version":1,"history":[]}\n' > "$config/notifications.json"
        printf '{"__version":1}\n' > "$config/settings.pre-v1.bak.json"
        printf '#!/bin/sh\n' > "$config/hooks/on-notify"
        mkdir -p "$cache/art"
        printf 'cover\n' > "$cache/art/one"
        printf 'stamp\n' > "$cache/update-checked"
        : > "$cache/update.lock"
        printf '{"history":[{"id":1}]}\n' > "$saved/notifications.json"
        printf 'edited\n' > "$repo/shell.qml"
        printf 'new\n' > "$repo/untracked.qml"
    }
    fill
    before="$(find "$home" "$repo/shell.qml" -type f | sort | xargs sha256sum)"

    out="$(run_reset)" || fail "the reset preview failed"
    case "$out" in
        *"2 back to defaults: barHeight, dnd"*) ;;
        *) fail "the preview did not list the changed settings: $out" ;;
    esac
    case "$out" in
        *"Files"*"Leftovers"*"Caches"*"Nothing was changed"*) ;;
        *) fail "the preview left out what it would change: $out" ;;
    esac
    assert_eq "$before" "$(find "$home" "$repo/shell.qml" -type f | sort | xargs sha256sum)" "a preview changes nothing"

    if run_reset --apply </dev/null >/dev/null 2>&1; then
        case "$(sed -n 's/.*"barHeight".*/kept/p' "$config/settings.json")" in
            kept) ;;
            *) fail "reset --apply went ahead with no terminal to confirm on" ;;
        esac
    fi
    assert_eq "$before" "$(find "$home" "$repo/shell.qml" -type f | sort | xargs sha256sum)" "no confirmation changes nothing"

    echo 4242 > "$state"; : > "$state.calls"
    run_reset --apply --yes >/dev/null || fail "reset --apply failed"
    assert_eq $'{\n  "__version": 2\n}' "$(cat "$config/settings.json")" "settings back to defaults"
    assert_eq "shipped" "$(cat "$repo/shell.qml")" "an edited file back to the installed revision"
    [ ! -e "$repo/untracked.qml" ] || fail "reset left a file the installed revision does not have"
    [ ! -e "$config/calendar-marks.json" ] && [ ! -e "$config/notifications.json" ] && [ ! -e "$config/settings.pre-v1.bak.json" ] \
        || fail "reset left files from older versions behind"
    [ ! -e "$cache/art" ] && [ ! -e "$cache/update-checked" ] || fail "reset left caches behind"
    [ -e "$cache/update.lock" ] || fail "reset removed a lock another update could hold"
    [ -e "$config/hooks/on-notify" ] || fail "reset removed the user's hooks"
    [ -e "$saved/notifications.json" ] || fail "reset cleared history without being asked"
    assert_eq $'kill\nlaunch' "$(cat "$state.calls")" "reset stops the shell first and starts it again"
    assert_eq "777" "$(cat "$state")" "the shell is running again"

    : > "$state.calls"
    run_reset --undo --yes >/dev/null || fail "reset --undo failed"
    assert_eq $'{\n  "__version": 2,\n  "barHeight": 40,\n  "dnd": true\n}' "$(cat "$config/settings.json")" "undo restores the settings"
    assert_eq "edited" "$(cat "$repo/shell.qml")" "undo restores the edited file"
    [ -e "$repo/untracked.qml" ] || fail "undo left out a new file"
    [ -e "$config/calendar-marks.json" ] || fail "undo left out a file set aside"
    assert_eq $'kill\nlaunch' "$(cat "$state.calls")" "undo restarts the shell too"
    if run_reset --undo --yes >/dev/null 2>&1; then fail "a second undo found something to restore"; fi

    # a file that will not parse is reported, replaced and still saved
    git -C "$repo" checkout -q -- shell.qml; rm -f "$repo/untracked.qml"
    printf '{ "barHeight": 40,' > "$config/settings.json"
    out="$(run_reset)"
    case "$out" in
        *"cannot be read"*) ;;
        *) fail "the preview did not report an unreadable settings file: $out" ;;
    esac
    run_reset --apply --yes >/dev/null || fail "reset could not replace an unreadable settings file"
    assert_eq '{ "barHeight": 40,' "$(cat "$saved/settings.pre-reset.json")" "the unreadable file is saved word for word"

    # a settings file in a dotfiles repo stays where it is, and history goes only when asked for
    printf '{\n  "barHeight": 40\n}\n' > "$home/dotfile.json"
    rm -f "$config/settings.json"; ln -s "$home/dotfile.json" "$config/settings.json"
    run_reset --apply --yes --history >/dev/null || fail "reset --history failed"
    [ -L "$config/settings.json" ] || fail "reset replaced a linked settings file with a plain one"
    assert_eq $'{\n  "__version": 2\n}' "$(cat "$home/dotfile.json")" "reset writes through the link"
    [ ! -e "$saved/notifications.json" ] || fail "--history left the history"

    # a settings file written by hand or another tool need not be laid out the way Silere writes it
    printf '{"__version":2,"barHeight":40,"dnd":true}' > "$config/settings.json"
    out="$(run_reset)"
    case "$out" in
        *"2 back to defaults: barHeight, dnd"*) ;;
        *) fail "the preview missed settings on one line: $out" ;;
    esac
    run_reset --apply --yes >/dev/null || fail "reset failed on a one-line settings file"

    # a reset with no settings file drops the copy an earlier one kept, or its undo would bring that back
    rm -f "$config/settings.json"; printf 'cover\n' > "$cache/art-stale"
    run_reset --apply --yes >/dev/null || fail "reset failed with no settings file"
    [ ! -e "$saved/settings.pre-reset.json" ] || fail "a reset kept an earlier reset's copy of the settings"

    # a clean install has nothing to do, and the shell stays as it is
    : > "$state.calls"
    out="$(run_reset --apply --yes)"
    case "$out" in
        *"Nothing to reset"*) ;;
        *) fail "a fresh install was reset anyway: $out" ;;
    esac
    assert_eq "" "$(cat "$state.calls")" "nothing to reset leaves the shell running"

    # from a text console the shell could not come back, so nothing is touched
    fill
    echo 4242 > "$state"; : > "$state.calls"
    before="$(sha256sum "$config/settings.json")"
    if env -u LC_ALL -u WAYLAND_DISPLAY PATH="$stubs:$PATH" HOME="$home" XDG_CONFIG_HOME="$home/config" XDG_STATE_HOME="$home/state" \
            XDG_CACHE_HOME="$home/cache" SILERE_TEST_STATE="$state" bash "$repo/scripts/silere" reset --apply --yes >/dev/null 2>&1; then
        fail "reset stopped a shell it could not bring back"
    fi
    assert_eq "$before" "$(sha256sum "$config/settings.json")" "a refused reset changes nothing"
    assert_eq "" "$(cat "$state.calls")" "a refused reset leaves the shell running"

    # a reset that fails after stopping the shell still brings it back
    fill
    rm -f "$config/settings.json"; ln -s "$home/missing/settings.json" "$config/settings.json"
    echo 4242 > "$state"; : > "$state.calls"
    if run_reset --apply --yes >/dev/null 2>&1; then fail "a reset that could not write the settings reported success"; fi
    assert_eq $'kill\nlaunch' "$(cat "$state.calls")" "a failed reset starts the shell it stopped"
    rm -f "$config/settings.json"

    # the shipped unit has an [Install] section, so a supervised shell stopped by the reset is neither active nor
    # enabled, and silere restart would bring it back outside its service: the reset has to start the service itself
    printf '%s\n' \
        '#!/bin/sh' \
        'case "$*" in' \
        "    *'-p ExecStart --value'*) echo '{ path=$repo/scripts/silere ; argv[]=$repo/scripts/silere run ; ignore_errors=no }' ;;" \
        '    *"is-active --quiet silere-shell.service"*) [ -s "$SILERE_TEST_STATE" ] ;;' \
        '    *" stop silere-shell.service"*) : > "$SILERE_TEST_STATE"; echo unit-stop >> "$SILERE_TEST_STATE.calls" ;;' \
        '    *" start silere-shell.service"*) echo 888 > "$SILERE_TEST_STATE"; echo unit-start >> "$SILERE_TEST_STATE.calls" ;;' \
        '    *) exit 1 ;;' \
        'esac' > "$stubs/systemctl"
    fill
    echo 4242 > "$state"; : > "$state.calls"
    run_reset --apply --yes >/dev/null || fail "reset failed with a supervised shell"
    assert_eq $'unit-stop\nunit-start' "$(cat "$state.calls")" "a reset brings a supervised shell back through its service"

    # the same unit stopped and disabled owns nothing: with no shell running, the reset starts none
    fill
    : > "$state"; : > "$state.calls"
    out="$(run_reset --apply --yes)" || fail "reset failed with a stopped, disabled unit"
    assert_eq "" "$(cat "$state.calls")" "a reset with a stopped unit and no shell running starts nothing"
    case "$out" in
        *"Silere is not running"*) ;;
        *) fail "a reset with no shell running did not say so: $out" ;;
    esac
)

# a checkout path with quotes, a backslash and spaces still gives the preview a menu shortcut that names it
test_try_config_quotes_paths() (
    command -v lua >/dev/null 2>&1 || return 0
    local fixture="$TMP/try it's \"odd\" \\here" stubs="$TMP/try-stubs" out="$TMP/try-out" cmd kdl
    mkdir -p "$fixture/scripts/lib" "$stubs" "$out"
    cp "$ROOT/scripts/try.sh" "$fixture/scripts/try.sh"
    cp "$ROOT/scripts/lib/ui.sh" "$fixture/scripts/lib/ui.sh"
    printf '#!/bin/sh\necho "Hyprland 0.57.1"\n' > "$stubs/Hyprland"
    printf '#!/bin/sh\nprintf "%%s" "$3"\n' > "$stubs/qs"
    chmod +x "$stubs/Hyprland" "$stubs/qs"
    PATH="$stubs:$PATH"
    SILERE_SCRIPT_LIB_ONLY=1 source "$fixture/scripts/try.sh"
    _write_hyprland_config "$out" kitty >/dev/null
    _write_niri_config "$out" kitty >/dev/null
    printf '%s\n' 'local cmds = {}' \
        'hl = { monitor = function() end, config = function() end, bind = function(k, a) cmds[k] = a end,' \
        '  dsp = { focus = function() return "" end, exec_cmd = function(c) return c end,' \
        '    window = { close = function() return "" end } } }' \
        'dofile(arg[1])' 'io.write(cmds["ALT + slash"])' > "$out/hl.lua"
    cmd="$(lua "$out/hl.lua" "$out/hyprland.lua")" || fail "the preview's Lua config does not load for a path with quotes"
    assert_eq "$fixture/shell.qml" "$(sh -c "$cmd")" "the preview's menu shortcut names a checkout path with quotes"
    kdl="$(sed -n 's/.*"-p" \(".*"\) "call".*/\1/p' "$out/niri.kdl")"
    assert_eq "$fixture/shell.qml" "$(lua - "$kdl" <<< 'io.write(load("return " .. arg[1])())')" \
        "niri's menu shortcut names a checkout path with quotes"
)

test_lua_block_is_checked() (
    local dir="$TMP/lua-block" stubs="$TMP/lua-block-stubs" before
    mkdir -p "$dir" "$stubs"
    # stands in for Hyprland --verify-config: anything marked BROKEN is rejected
    printf '#!/bin/sh\n! grep -q BROKEN "$3"\n' > "$stubs/Hyprland"
    chmod +x "$stubs/Hyprland"
    SILERE_SCRIPT_LIB_ONLY=1 source "$ROOT/scripts/install.sh"
    HYPR_CONFIG="$dir/hyprland.lua"
    export PATH="$stubs:$PATH"

    printf 'hl.config({})\n' > "$HYPR_CONFIG"
    _append_lua_block "$HYPR_CONFIG" '-- begin' '-- end' 'hl.bind()' || fail "a block a working config accepts was refused"
    assert_eq $'hl.config({})\n\n-- begin\nhl.bind()\n-- end' "$(<"$HYPR_CONFIG")" "the block goes at the end, between its markers"

    before="$(<"$HYPR_CONFIG")"
    if _append_lua_block "$HYPR_CONFIG" '-- begin2' '-- end2' 'BROKEN'; then
        fail "a block that breaks the config was reported as added"
    fi
    assert_eq "$before" "$(<"$HYPR_CONFIG")" "a block Hyprland rejects comes back out"

    # a dotfiles link stays a link, whichever way it goes
    mv "$HYPR_CONFIG" "$dir/real.lua"
    ln -s "$dir/real.lua" "$HYPR_CONFIG"
    _append_lua_block "$HYPR_CONFIG" '-- begin3' '-- end3' 'BROKEN' || true
    [ -L "$HYPR_CONFIG" ] || fail "putting a rejected block back replaced a linked config with a plain file"
    assert_eq "$before" "$(<"$dir/real.lua")" "the rejected block came out through the link"
    rm -f "$HYPR_CONFIG"; mv "$dir/real.lua" "$HYPR_CONFIG"

    # a config already failing says nothing about the block, so it is not blamed
    printf 'BROKEN\n' > "$HYPR_CONFIG"
    _append_lua_block "$HYPR_CONFIG" '-- begin' '-- end' 'hl.bind()' || fail "a config that was already failing refused the block"
    grep -qF 'hl.bind()' "$HYPR_CONFIG" || fail "a config that was already failing lost the block"

    # no Hyprland on PATH, as when installing before the compositor is set up
    local bare="$TMP/lua-block-bare" tool
    mkdir -p "$bare"
    for tool in cp mktemp cat rm; do ln -s "$(command -v "$tool")" "$bare/$tool"; done
    printf 'hl.config({})\n' > "$HYPR_CONFIG"
    PATH="$bare" _append_lua_block "$HYPR_CONFIG" '-- begin' '-- end' 'hl.bind()' \
        || fail "no Hyprland to ask refused the block"
)

test_other_bars_are_named() (
    local stubs="$TMP/bars-stubs" out
    mkdir -p "$stubs"
    printf '#!/bin/sh\n[ "$2" = waybar ]\n' > "$stubs/pgrep"
    printf '#!/bin/sh\n[ -f "$SILERE_TEST_QS_LIST" ] && cat "$SILERE_TEST_QS_LIST"\nexit 0\n' > "$stubs/qs"
    chmod +x "$stubs/pgrep" "$stubs/qs"
    source "$ROOT/scripts/lib/ui.sh"
    out="$(PATH="$stubs:$PATH" _silere_other_bars)"
    assert_eq "waybar" "$out" "a bar still running is named"
    printf '#!/bin/sh\n[ "$2" = hyprpanel-app ]\n' > "$stubs/pgrep"
    out="$(PATH="$stubs:$PATH" _silere_other_bars)"
    assert_eq "hyprpanel" "$out" "HyprPanel is found by the app it execs, and named as people know it"
    printf '#!/bin/sh\nexit 1\n' > "$stubs/pgrep"
    out="$(PATH="$stubs:$PATH" _silere_other_bars)"
    assert_eq "" "$out" "no other bar, nothing to say"

    # another Quickshell shell on this display is named; Silere checkouts, probes and nested sessions are not
    mkdir -p "$TMP/bars-silere/scripts" && : > "$TMP/bars-silere/scripts/silere"
    instance() { printf 'Instance x:\n  Process ID: 1\n  Config path: %s\n  Display connection: wayland/%s\n\n' "$1" "$2"; }
    {
        instance "$TMP/bars-silere/shell.qml" wayland-test
        instance "$HOME/.config/quickshell/noctalia-shell/shell.qml" wayland-test
        instance "$TMP/bars-silere/dev/probe-logic.qml" wayland-test
        instance "/usr/share/quickshell/dms/shell.qml" wayland-9
    } > "$TMP/bars-qs-list"
    out="$(PATH="$stubs:$PATH" WAYLAND_DISPLAY=wayland-test SILERE_TEST_QS_LIST="$TMP/bars-qs-list" _silere_other_bars)"
    assert_eq "noctalia-shell" "$out" "another Quickshell shell on this display is named by its folder"
)

test_launcher_uses_real_name() (
    local stubs="$TMP/name-stubs" calls="$TMP/name-calls"
    mkdir -p "$stubs"
    printf '#!/bin/sh\n[ "$1" != --no-duplicate ] || echo "$0" >> "$SILERE_TEST_CALLS"\nexit 0\n' > "$stubs/quickshell"
    chmod +x "$stubs/quickshell"
    ln -s quickshell "$stubs/qs"
    : > "$calls"
    env -u NIRI_SOCKET -u HYPRLAND_INSTANCE_SIGNATURE PATH="$stubs:$PATH" SILERE_TEST_CALLS="$calls" \
        bash "$ROOT/scripts/silere" run >/dev/null 2>&1 || fail "the launcher failed behind a qs link"
    assert_eq "$(readlink -f "$stubs")/quickshell" "$(cat "$calls")" \
        "the shell starts as quickshell, which ananicy rules for qs do not reach"
)

test_startup_failure_report() (
    local stubs="$TMP/startup-stubs" bare="$TMP/startup-bare" calls="$TMP/startup-calls" tool
    mkdir -p "$stubs" "$bare"
    printf '%s\n' \
        '#!/bin/sh' \
        'case "$1" in' \
        '    list) [ -z "${SILERE_TEST_SHELL_UP-}" ] || printf "Instance t:\n  Process ID: 777\n"; exit 0 ;;' \
        'esac' \
        'exit 1' > "$stubs/qs"
    # never the real hyprctl: it would draw on the desktop of whoever runs the tests
    printf '#!/bin/sh\necho "hyprctl $*" >> "$SILERE_TEST_CALLS"\n' > "$stubs/hyprctl"
    printf '#!/bin/sh\necho "notify-send $*" >> "$SILERE_TEST_CALLS"\n' > "$stubs/notify-send"
    chmod +x "$stubs/qs" "$stubs/hyprctl" "$stubs/notify-send"
    # a PATH with no qs, which the machine running the tests may well have
    for tool in bash dirname env grep readlink sed sleep timeout; do
        ln -s "$(command -v "$tool")" "$bare/$tool"
    done
    cp "$stubs/hyprctl" "$bare/hyprctl"

    # the report runs detached, so the launcher returning says nothing about it
    await_report() {
        for _ in $(seq 40); do [ -s "$calls" ] && return 0; sleep 0.1; done
        return 1
    }
    startup() {
        : > "$calls"
        env -u NIRI_SOCKET -u HYPRLAND_INSTANCE_SIGNATURE PATH="$stubs:$PATH" SILERE_STARTUP_GRACE=0 \
            SILERE_TEST_CALLS="$calls" "$@" >/dev/null 2>&1 || true
    }

    startup HYPRLAND_INSTANCE_SIGNATURE=test bash "$ROOT/scripts/silere" run --startup
    await_report || fail "a failed start on Hyprland reported nothing"
    case "$(cat "$calls")" in
        "hyprctl notify 3 60000 0 Silere did not start."*"doctor in a terminal to see why.") ;;
        *) fail "a failed start on Hyprland drew the wrong message: $(cat "$calls")" ;;
    esac

    startup bash "$ROOT/scripts/silere" run --startup
    await_report || fail "a failed start off Hyprland reported nothing"
    case "$(cat "$calls")" in
        "notify-send --urgency=critical --app-name=silere-shell Silere did not start"*) ;;
        *) fail "a failed start off Hyprland sent the wrong message: $(cat "$calls")" ;;
    esac

    startup SILERE_TEST_SHELL_UP=1 HYPRLAND_INSTANCE_SIGNATURE=test bash "$ROOT/scripts/silere" run --startup
    sleep 0.5
    assert_eq "" "$(cat "$calls")" "a shell that came up reports nothing"

    startup HYPRLAND_INSTANCE_SIGNATURE=test bash "$ROOT/scripts/silere" run
    sleep 0.5
    assert_eq "" "$(cat "$calls")" "only a login start reports, since a person is reading silere run"

    : > "$calls"
    env -u NIRI_SOCKET PATH="$bare" HYPRLAND_INSTANCE_SIGNATURE=test SILERE_STARTUP_GRACE=0 \
        SILERE_TEST_CALLS="$calls" "$(command -v bash)" "$ROOT/scripts/silere" run --startup >/dev/null 2>&1 \
        && fail "a start with no Quickshell claimed success"
    await_report || fail "a start with no Quickshell reported nothing"
    case "$(cat "$calls")" in
        *"Run $ROOT/scripts/silere doctor in a terminal"*) ;;
        *) fail "with silere off PATH, the report does not give the full path: $(cat "$calls")" ;;
    esac
)

test_cli_restart_and_log() (
    local stubs="$TMP/cli-stubs" state="$TMP/cli-state" out
    mkdir -p "$stubs"
    printf '%s\n' \
        '#!/bin/sh' \
        'state="$SILERE_TEST_STATE"' \
        'case "$1" in' \
        '    list) [ -s "$state" ] && printf "Instance t:\n  Process ID: %s\n" "$(cat "$state")"; exit 0 ;;' \
        '    kill) : > "$state"; echo kill >> "$state.calls"; exit 0 ;;' \
        '    log) echo "log $*" >> "$state.calls"; exit 0 ;;' \
        '    --no-detailed-logs) exit 0 ;;' \
        '    --version) [ -z "${SILERE_TEST_QS_BROKEN-}" ] || { echo "qs: symbol lookup error" >&2; exit 127; }; exit 0 ;;' \
        '    *) echo "launch $* locale=${LC_ALL-<unset>}" >> "$state.calls"; echo 777 > "$state" ;;' \
        'esac' > "$stubs/qs"
    # never the real systemctl: it would restart the live shell of whoever runs the tests
    printf '%s\n' \
        '#!/bin/sh' \
        'echo "systemctl $*" >> "$SILERE_TEST_STATE.calls"' \
        'case "$*" in' \
        '    *is-failed*) [ -n "${SILERE_TEST_UNIT_FAILED-}" ]; exit $? ;;' \
        '    *is-active*|*is-enabled*) [ -n "${SILERE_TEST_UNIT-}" ] && [ -z "${SILERE_TEST_UNIT_INACTIVE-}" ]; exit $? ;;' \
        '    *show*) [ -n "${SILERE_TEST_UNIT-}" ] || exit 1; printf "{ path=/usr/bin/qs ; argv[]=/usr/bin/qs -n -p %s/shell.qml ; }\n" "${SILERE_TEST_UNIT_ROOT:-$SILERE_TEST_ROOT}" ;;' \
        '    *" restart "*) echo 888 > "$SILERE_TEST_STATE" ;;' \
        '    *" stop "*) [ -z "${SILERE_TEST_STOP_FAIL-}" ] || exit 1; : > "$SILERE_TEST_STATE" ;;' \
        'esac' > "$stubs/systemctl"
    chmod +x "$stubs/qs" "$stubs/systemctl"
    cli() {
        env -u LC_ALL PATH="$stubs:$PATH" SILERE_TEST_STATE="$state" SILERE_TEST_ROOT="$ROOT" \
            bash "$ROOT/scripts/silere" "$@"
    }

    echo 4242 > "$state"; : > "$state.calls"
    out="$(WAYLAND_DISPLAY=wayland-test cli restart)" || fail "restart without a unit failed"
    assert_eq "Silere restarted (pid 777)" "$out" "restart without a unit"
    assert_eq $'kill\nlaunch --no-duplicate --no-detailed-logs -p '"$ROOT"$'/shell.qml --daemonize locale=<unset>' \
        "$(grep -v '^systemctl' "$state.calls")" "restart stops, then relaunches detached"

    echo 4242 > "$state"; : > "$state.calls"
    if env -u WAYLAND_DISPLAY PATH="$stubs:$PATH" SILERE_TEST_STATE="$state" \
            bash "$ROOT/scripts/silere" restart >/dev/null 2>&1; then
        fail "restart outside a Wayland session claimed success"
    fi
    assert_eq 4242 "$(cat "$state")" "restart outside a Wayland session left the shell running"

    echo 4242 > "$state"; : > "$state.calls"
    out="$(SILERE_TEST_UNIT=1 cli restart)" || fail "restart through the unit failed"
    assert_eq "Silere restarted (pid 888)" "$out" "restart through the unit"
    grep -qFx 'systemctl --user restart silere-shell.service' "$state.calls" \
        || fail "restart did not go through the user unit"
    ! grep -qx 'kill' "$state.calls" || fail "restart killed the unit's shell behind systemd"

    # a crash loop leaves a disabled unit failed: neither active nor enabled, and still the shell's owner
    : > "$state"; : > "$state.calls"
    out="$(SILERE_TEST_UNIT=1 SILERE_TEST_UNIT_INACTIVE=1 SILERE_TEST_UNIT_FAILED=1 cli restart)" \
        || fail "restart of a failed unit failed"
    assert_eq "Silere started (pid 888)" "$out" "restart of a failed unit"
    grep -qFx 'systemctl --user reset-failed silere-shell.service' "$state.calls" \
        && grep -qFx 'systemctl --user restart silere-shell.service' "$state.calls" \
        || fail "restart of a failed unit did not clear it and go through systemd"
    ! grep -q '^launch' "$state.calls" || fail "restart of a failed unit started a shell outside it"

    echo 4242 > "$state"; : > "$state.calls"
    if out="$(SILERE_TEST_UNIT=1 SILERE_TEST_QS_BROKEN=1 cli restart 2>&1)"; then
        fail "restart claimed success with a qs that cannot start"
    fi
    case "$out" in
        *"Quickshell cannot start, so the running shell was left alone: qs: symbol lookup error"*) ;;
        *) fail "restart with a qs that cannot start said: $out" ;;
    esac
    assert_eq 4242 "$(cat "$state")" "restart with a qs that cannot start left the shell running"
    assert_eq "" "$(cat "$state.calls")" "restart with a qs that cannot start touched nothing"

    echo 4242 > "$state"; : > "$state.calls"
    out="$(cli run)" || fail "run beside a running shell failed"
    assert_eq "Silere is already running (pid 4242); silere restart starts it again" "$out" \
        "run beside a running shell"
    ! grep -q '^launch' "$state.calls" || fail "run started a second shell"

    : > "$state"; : > "$state.calls"
    if cli log >/dev/null 2>&1; then fail "log claimed a stopped shell"; fi
    echo 4242 > "$state"
    cli log --follow > "$state.out" || fail "log of a running shell failed"
    assert_eq "log log --no-color -p $ROOT/shell.qml --follow" "$(grep '^log' "$state.calls")" \
        "log argv drops color when not writing to a terminal"

    echo 4242 > "$state"; : > "$state.calls"
    out="$(cli stop)" || fail "stop without a unit failed"
    assert_eq "Silere stopped" "$out" "stop without a unit"
    assert_eq "" "$(cat "$state")" "stop leaves no shell running"
    assert_eq kill "$(grep -v '^systemctl' "$state.calls")" "stop does not relaunch the shell"

    : > "$state.calls"
    out="$(cli stop)" || fail "stopping an already stopped shell failed"
    assert_eq "Silere is not running" "$out" "stop is idempotent"
    ! grep -qx kill "$state.calls" || fail "stop sent a kill with no shell running"

    echo 4242 > "$state"; : > "$state.calls"
    SILERE_TEST_UNIT=1 SILERE_TEST_UNIT_ROOT="$TMP/other-checkout" cli stop > /dev/null \
        || fail "stop failed beside another checkout's service"
    assert_eq "" "$(cat "$state")" "stop still stops this checkout's unsupervised shell"
    ! grep -qFx 'systemctl --user stop silere-shell.service' "$state.calls" \
        || fail "stop touched another checkout's service"

    echo 4242 > "$state"; : > "$state.calls"
    out="$(SILERE_TEST_UNIT=1 cli stop)" || fail "stop through the unit failed"
    assert_eq "Silere stopped" "$out" "stop through the unit"
    assert_eq "" "$(cat "$state")" "supervised stop leaves no shell running"
    grep -qFx 'systemctl --user stop silere-shell.service' "$state.calls" \
        || fail "stop did not go through the user unit"
    ! grep -qx kill "$state.calls" || fail "stop killed the unit's shell behind systemd"

    : > "$state.calls"
    SILERE_TEST_UNIT=1 SILERE_TEST_UNIT_INACTIVE=1 cli stop > /dev/null \
        || fail "stop could not cancel a service awaiting a restart"
    grep -qFx 'systemctl --user stop silere-shell.service' "$state.calls" \
        || fail "stop left an inactive service free to restart"

    echo 4242 > "$state"; : > "$state.calls"
    if SILERE_TEST_UNIT=1 SILERE_TEST_STOP_FAIL=1 cli stop >/dev/null 2>&1; then
        fail "stop claimed success after the service refused to stop"
    fi
    assert_eq 4242 "$(cat "$state")" "a failed service stop leaves its shell alone"
    ! grep -qx kill "$state.calls" || fail "a failed service stop killed the shell behind systemd"
    if cli stop unexpected >/dev/null 2>&1; then fail "stop accepted an unexpected argument"; fi
    assert_eq 4242 "$(cat "$state")" "invalid stop arguments leave the shell alone"
)

test_cli_ipc_resolution() (
    local stubs="$TMP/ipc-stubs" other="$TMP/ipc-other" out
    mkdir -p "$stubs" "$other/scripts"
    printf '#!/bin/sh\n' > "$other/scripts/silere"; chmod +x "$other/scripts/silere"
    printf '#!/bin/sh\nexit 1\n' > "$stubs/systemctl"
    # this checkout never answers; the other copy answers when SILERE_TEST_OTHER is set
    cat > "$stubs/qs" <<'STUB'
#!/bin/sh
case "$1" in
    list) if [ -n "${SILERE_TEST_OTHER-}" ]; then
              printf '[\n    {\n        "config_path": "%s/shell.qml",\n        "pid": 9\n    }\n]\n' "$SILERE_TEST_OTHER"
          else echo "[]"; fi ;;
    ipc)  [ "$3" = "${SILERE_TEST_OTHER-none}/shell.qml" ] || {
              echo "No running instances for \"$3\""; echo "Dead instances:"; echo " - abc"; exit 255; }
          case "$4" in
              show) printf 'target menu\n  function toggle(): string\ntarget calendar\n  function close(): void\n' ;;
              call) [ "$6" = toggle ] && echo opened || echo "Function not found." ;;
          esac ;;
    log)  echo "log $*" ;;
esac
STUB
    chmod +x "$stubs/qs" "$stubs/systemctl"
    cli() { env -u LC_ALL PATH="$stubs:$PATH" bash "$ROOT/scripts/silere" "$@"; }

    if out="$(cli ipc 2>&1)"; then fail "ipc claimed success with no shell running"; fi
    case "$out" in *"Silere is not running"*) ;; *) fail "ipc without a shell said: $out" ;; esac
    case "$out" in *"Dead instances"*) fail "ipc leaked Quickshell's dead instance list" ;; esac
    if cli ipc menu toggle >/dev/null 2>&1; then fail "an ipc call reached no shell yet succeeded"; fi

    out="$(SILERE_TEST_OTHER="$other" cli ipc 2>/dev/null)" || fail "ipc did not reach the copy that is running"
    case "$out" in "target menu"*) ;; *) fail "ipc listing from the running copy: $out" ;; esac
    assert_eq "opened" "$(SILERE_TEST_OTHER="$other" cli ipc menu toggle 2>/dev/null)" "ipc call through the running copy"
    assert_eq "  function close(): void" "$(SILERE_TEST_OTHER="$other" cli ipc calendar 2>/dev/null | tail -1)" \
        "a target alone lists its calls from the running copy"
    if SILERE_TEST_OTHER="$other" cli ipc menu frob >/dev/null 2>&1; then fail "a refused call exited 0"; fi
    out="$(SILERE_TEST_OTHER="$other" cli log 2>/dev/null)" || fail "log did not follow the copy that is running"
    case "$out" in *"-p $other/shell.qml"*) ;; *) fail "log read the wrong shell: $out" ;; esac
    if cli log >/dev/null 2>&1; then fail "log claimed a shell with none running"; fi

    if out="$(SILERE_TEST_OTHER="$other" cli stop 2>&1)"; then
        fail "stop claimed another checkout's shell"
    fi
    case "$out" in *"runs from $other"*) ;; *) fail "stop did not identify the other checkout: $out" ;; esac

    out="$(cli restrat 2>&1)" && fail "a mistyped command succeeded"
    case "$out" in *"Did you mean: silere restart"*) ;; *) fail "no suggestion for restrat: $out" ;; esac
    out="$(cli frobnicate 2>&1)" && fail "an unknown command succeeded"
    case "$out" in *"Did you mean"*) fail "a guess offered for frobnicate" ;; esac
    true
)

test_cli_use_switches_checkout() (
    local t="$TMP/use" out dropin
    mkdir -p "$t/stubs" "$t/other/scripts" "$t/home/.local/bin" "$t/config"
    : > "$t/other/shell.qml"
    printf '#!/bin/sh\necho "other $*" >> "%s/calls"\n' "$t" > "$t/other/scripts/silere"
    chmod +x "$t/other/scripts/silere"
    ln -s "$t/other/scripts/silere" "$t/home/.local/bin/silere"
    dropin="$t/config/systemd/user/silere-shell.service.d/silere-use.conf"
    # never the real systemctl: the unit follows the drop-in the way systemd would after daemon-reload
    cat > "$t/stubs/systemctl" <<STUB
#!/bin/sh
echo "systemctl \$*" >> "$t/calls"
unit_exec() {
    if [ -f "$dropin" ]; then sed -n 's/^ExecStart="\(.*\)" run\$/\1/p' "$dropin"
    else echo "$t/other/scripts/silere"; fi
}
case "\$*" in
    *"-p LoadState"*) echo loaded ;;
    *"-p ExecStart"*) p="\$(unit_exec)"; echo "{ path=\$p ; argv[]=\$p run ; ignore_errors=no ; }" ;;
    *is-active*|*is-enabled*) [ "\${SILERE_TEST_USE_UNIT_ACTIVE:-1}" = 1 ]; exit \$? ;;
    *" restart "*) p="\$(unit_exec)"; echo "\${p%/scripts/silere}/shell.qml" > "$t/running" ;;
esac
exit 0
STUB
    cat > "$t/stubs/qs" <<STUB
#!/bin/sh
case "\$1" in
    list) if [ "\$2" = --all ]; then
              printf '[\n    {\n        "config_path": "%s",\n        "pid": 9\n    }\n]\n' "\$(cat "$t/running")"
          elif [ "\$3" = "\$(cat "$t/running")" ]; then printf 'Instance t:\n  Process ID: 99\n'; fi ;;
    kill) echo "kill \$*" >> "$t/calls" ;;
    --version) [ "\${SILERE_TEST_USE_BROKEN_QS:-0}" != 1 ] || { echo 'qs: symbol lookup error' >&2; exit 127; }; exit 0 ;;
    --no-detailed-logs) exit 0 ;;
    *) echo "launch \$*" >> "$t/calls" ;;
esac
STUB
    chmod +x "$t/stubs/systemctl" "$t/stubs/qs"
    # the fake HOME hides any safe.directory that lets a container trust this checkout,
    # and without it git cannot read the repository and the checkout looks packaged
    cli() {
        env -u LC_ALL -u XDG_CONFIG_HOME HOME="$t/home" XDG_CONFIG_HOME="$t/config" PATH="$t/stubs:$PATH" \
            GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0="$ROOT" \
            WAYLAND_DISPLAY="${SILERE_TEST_USE_WAYLAND-wayland-test}" bash "$ROOT/scripts/silere" "$@"
    }

    echo "$t/other/shell.qml" > "$t/running"; : > "$t/calls"
    if out="$(cli restart 2>&1)"; then fail "restart beside another copy's shell claimed success"; fi
    case "$out" in *"runs from $t/other, not $ROOT"*) ;; *) fail "restart beside another copy said: $out" ;; esac
    if out="$(cli run 2>&1)"; then fail "run beside another copy's shell claimed success"; fi
    case "$out" in *"already running from $t/other"*) ;; *) fail "run beside another copy said: $out" ;; esac
    ! grep -q '^launch\|restart' "$t/calls" || fail "a second shell was started beside another copy: $(cat "$t/calls")"

    out="$(cli use --dry-run)" || fail "use --dry-run failed"
    case "$out" in *"would start $ROOT"*) ;; *) fail "use --dry-run said: $out" ;; esac
    [ ! -e "$dropin" ] || fail "use --dry-run wrote the drop-in"
    assert_eq "$t/other/scripts/silere" "$(readlink "$t/home/.local/bin/silere")" "use --dry-run left the link"

    : > "$t/calls"
    out="$(cli use)" || fail "use failed: $out"
    assert_eq "$ROOT/scripts/silere" "$(readlink "$t/home/.local/bin/silere")" "use links this checkout"
    grep -qFx "ExecStart=\"$ROOT/scripts/silere\" run" "$dropin" || fail "drop-in does not start this checkout"
    grep -qFx "ConditionPathExists=$ROOT/shell.qml" "$dropin" || fail "drop-in kept the old condition"
    grep -qFx 'systemctl --user daemon-reload' "$t/calls" || fail "use did not reload the units"
    grep -qFx 'systemctl --user restart silere-shell.service' "$t/calls" || fail "use did not restart the unit"
    ! grep -q '^kill' "$t/calls" || fail "use killed the unit's shell behind systemd"
    assert_eq "$ROOT/shell.qml" "$(cat "$t/running")" "the unit now runs this checkout"
    case "$out" in *"Silere started (pid 99)"*) ;; *) fail "use said: $out" ;; esac

    : > "$t/calls"
    cli use "$t/other" >/dev/null || fail "use back to the other copy failed"
    [ ! -e "$dropin" ] || fail "switching back to the unit's own checkout kept the drop-in"
    assert_eq "$t/other/scripts/silere" "$(readlink "$t/home/.local/bin/silere")" "use links the other copy back"
    grep -qFx 'other restart' "$t/calls" || fail "use did not hand the restart to the other copy"

    mkdir -p "${dropin%/*}"; printf '[Service]\nExecStart=\nExecStart=/x run\n' > "$dropin"
    if cli use >/dev/null 2>&1; then fail "use replaced a drop-in it did not write"; fi
    grep -qFx 'ExecStart=/x run' "$dropin" || fail "use changed a drop-in it did not write"
    assert_eq "$t/other/scripts/silere" "$(readlink "$t/home/.local/bin/silere")" \
        "use leaves the command link alone when an unmanaged drop-in blocks the switch"

    rm -- "$dropin"
    ln -s "$t/missing-dropin" "$dropin"
    if cli use >/dev/null 2>&1; then fail "use replaced a dangling service drop-in link"; fi
    assert_eq "$t/missing-dropin" "$(readlink "$dropin")" "use preserves an unmanaged drop-in link"
    assert_eq "$t/other/scripts/silere" "$(readlink "$t/home/.local/bin/silere")" \
        "a dangling drop-in does not redirect the command link"

    rm -- "$dropin"
    : > "$t/calls"
    if out="$(SILERE_TEST_USE_BROKEN_QS=1 cli use 2>&1)"; then fail "use accepted a broken runtime"; fi
    case "$out" in *"checkout switch was left unapplied"*) ;; *) fail "use did not explain the runtime failure: $out" ;; esac
    assert_eq "$t/other/scripts/silere" "$(readlink "$t/home/.local/bin/silere")" \
        "a failed runtime preflight leaves the command link alone"
    [ ! -e "$dropin" ] || fail "a failed runtime preflight wrote a drop-in"
    ! grep -q 'daemon-reload\|restart\|kill' "$t/calls" || fail "a failed runtime preflight changed the running shell"

    : > "$t/calls"
    if SILERE_TEST_USE_WAYLAND='' SILERE_TEST_USE_UNIT_ACTIVE=0 cli use >/dev/null 2>&1; then
        fail "use without a session or active service claimed success"
    fi
    assert_eq "$t/other/scripts/silere" "$(readlink "$t/home/.local/bin/silere")" \
        "a missing session leaves the command link alone"
    [ ! -e "$dropin" ] || fail "use outside a session wrote a drop-in"
    ! grep -q 'daemon-reload\|restart\|kill' "$t/calls" || fail "use outside a session changed the running shell"
    SILERE_TEST_USE_WAYLAND='' SILERE_TEST_USE_UNIT_ACTIVE=0 cli use --dry-run >/dev/null \
        || fail "use --dry-run requires a live session"

    if cli use "$ROOT" "$t/other" >/dev/null 2>&1; then fail "use accepted two checkout arguments"; fi
    assert_eq "$t/other/scripts/silere" "$(readlink "$t/home/.local/bin/silere")" \
        "an extra checkout argument cannot redirect the command link"
)

test_pooled_motion_scope() (
    command -v python3 >/dev/null 2>&1 || return 0
    local fixture="$TMP/pooled-motion" output
    mkdir -p "$fixture/modules"
    cat > "$fixture/modules/Picker.qml" <<'QML'
Item {
    MotionBehavior on opacity { NumberAnimation {} }
    ListView {
        reuseItems: true
        delegate: OptionRow {
            property string label: "a } brace and // comment in a label"
        }
    }
}
QML
    cat > "$fixture/modules/OptionRow.qml" <<'QML'
Item {
    ListView.onPooled: motionReady = false
    ListView.onReused: motionReady = true
    ColorFade on color { gate: motionReady }
}
QML
    python3 "$ROOT/dev/check-pooled-motion.py" "$fixture" \
        || fail "pooling lint mistook picker chrome for a recycled delegate"
    sed -i 's/gate: motionReady//' "$fixture/modules/OptionRow.qml"
    if output="$(python3 "$ROOT/dev/check-pooled-motion.py" "$fixture")"; then
        fail "pooling lint accepted an ungated external delegate"
    fi
    [[ "$output" == *'OptionRow.qml:4: recycled delegate animation needs a gate'* ]] \
        || fail "pooling lint did not identify the ungated delegate"
    sed -i 's/ColorFade on color { }/ColorFade on color { gate: motionReady }/; /onReused/d' \
        "$fixture/modules/OptionRow.qml"
    if python3 "$ROOT/dev/check-pooled-motion.py" "$fixture" >/dev/null; then
        fail "pooling lint accepted a delegate without a reuse handler"
    fi
)

test_benchmark_json() (
    [ -r "/proc/$BASHPID/stat" ] || return 0
    local stubs="$TMP/bench-stubs" out expected
    mkdir -p "$stubs"
    cat > "$stubs/qs" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = list ]; then
    printf '  Process ID: %s\n  Config path: %s/shell.qml\n' \
        "$SILERE_TEST_BENCH_PID" "$SILERE_TEST_BENCH_ROOT"
elif [ "${1:-}" = ipc ]; then
    printf '%s\n' "$*" >> "$SILERE_TEST_BENCH_CALLS"
    if [[ "$*" == *'call menu tab 0' ]]; then printf '%s\n' "${SILERE_TEST_BENCH_REPLY:-ok}"; fi
else
    printf 'Quickshell benchmark fixture\n'
fi
SH
    chmod +x "$stubs/qs"
    # Linux permits spaces and closing parentheses in comm. The benchmark must
    # still identify this short-lived process and read the correct CPU fields.
    printf 'bench ) fixture\n' > "/proc/$BASHPID/comm"
    export SILERE_TEST_BENCH_PID="$BASHPID" SILERE_TEST_BENCH_ROOT="$ROOT"
    out="$(PATH="$stubs:$PATH" XDG_CONFIG_HOME="$TMP/bench-config" \
        bash "$ROOT/scripts/bench.sh" 1 --json \
        --label $'release\nline\t"quote"\\slash\r\b\f\v\001\037 λ 🐚')" \
        || fail "benchmark fixture failed"
    expected='release\u000aline\u0009\"quote\"\\slash\u000d\u0008\u000c\u000b\u0001\u001f λ 🐚'
    [[ "$out" == *",\"label\":\"$expected\""* ]] \
        || fail "benchmark JSON did not preserve and escape its free-form label"
    [[ "$out" != *$'\n'* ]] || fail "benchmark JSON contains a raw newline"
    local uptime elapsed
    uptime="$(printf '%s\n' "$out" | sed -n 's/.*"process_uptime_seconds":\([0-9][0-9]*\).*/\1/p')"
    [[ "$uptime" =~ ^[0-9]+$ ]] && [ "$uptime" -lt 60 ] \
        || fail "benchmark read the wrong start time from a process name containing spaces and ')'"
    elapsed="$(printf '%s\n' "$out" | sed -n 's/.*"elapsed_seconds":\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')"
    awk -v elapsed="$elapsed" 'BEGIN { exit !(elapsed >= 1) }' \
        || fail "benchmark did not record its actual sampling duration"

    # Keep this fixture quick while exercising the actual warm-up IPC path.
    printf '#!/bin/sh\nexit 0\n' > "$stubs/sleep"
    chmod +x "$stubs/sleep"
    local seconds normalized
    for seconds in 08 010; do
        normalized="${seconds#0}"
        out="$(PATH="$stubs:$PATH" XDG_CONFIG_HOME="$TMP/bench-config" \
            bash "$ROOT/scripts/bench.sh" "$seconds" --json)" \
            || fail "benchmark rejected a zero-padded duration"
        [[ "$out" == *"\"sample_seconds\":$normalized,"* ]] \
            || fail "benchmark did not interpret $seconds as decimal seconds"
        [[ "$out" =~ \"rss_avg_mb\":[0-9]+, ]] \
            || fail "benchmark skipped sampling for $seconds seconds"
    done
    if PATH="$stubs:$PATH" bash "$ROOT/scripts/bench.sh" 000 --json >/dev/null 2>&1; then
        fail "benchmark accepted a zero-second duration"
    fi
    export SILERE_TEST_BENCH_CALLS="$TMP/bench-calls"
    out="$(PATH="$stubs:$PATH" XDG_CONFIG_HOME="$TMP/bench-config" \
        bash "$ROOT/scripts/bench.sh" 1 --warm --json)" || fail "warm benchmark fixture failed"
    assert_eq $'ipc -p '"$ROOT"$'/shell.qml call menu tab 0\nipc -p '"$ROOT"$'/shell.qml call menu close' \
        "$(<"$SILERE_TEST_BENCH_CALLS")" "benchmark warms Home even if a menu is already open"
    [[ "$out" == *'"state":"warm"'* ]] || fail "warm benchmark did not report its state"
    if out="$(PATH="$stubs:$PATH" SILERE_TEST_BENCH_REPLY='error: idle' \
            bash "$ROOT/scripts/bench.sh" 1 --warm --json 2>&1)"; then
        fail "benchmark accepted a refused warm-up"
    fi
    [[ "$out" == *'could not open Home: error: idle'* ]] \
        || fail "benchmark did not explain a refused warm-up"
)

test_doctor_json() (
    command -v python3 >/dev/null 2>&1 || return 0
    local fixture="$TMP/doctor-json" actual python_path
    python_path="$(command -v python3)"
    mkdir -p "$fixture/scripts" "$fixture/bin"
    cp "$ROOT/scripts/doctor.sh" "$ROOT/scripts/doctor-json.sh" "$fixture/scripts/"
    printf '{"version":"9.1.2"}\n' > "$fixture/release.json"
    cat > "$fixture/bin/qs" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then printf 'Quickshell 0.3.1\n'
else printf '%s\n' "${SILERE_JSON_REPLY:-unavailable}"; fi
EOF
    cat > "$fixture/bin/qtpaths6" <<'EOF'
#!/usr/bin/env bash
printf '6.10.2\n'
EOF
    cat > "$fixture/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
printf '{\n    "branch": "private-report-value",\n    "version": "0.57.2",\n    "dirty": false\n}\n'
EOF
    chmod +x "$fixture/bin/qs" "$fixture/bin/qtpaths6" "$fixture/bin/hyprctl"
    actual="$(PATH="$fixture/bin:$PATH" SILERE_TEST_SECRET=private-report-value \
        NIRI_SOCKET='' HYPRLAND_INSTANCE_SIGNATURE=fixture \
        SILERE_JSON_REPLY='{"schemaVersion":1,"compositor":"hyprland","bluetooth":{"enabled":true,"name":"private-report-value"},"audio":{"outputs":2,"name":"private-report-value"},"screens":[{"width":1920,"height":1080,"scale":1.25,"serial":"private-report-value"}],"private":"private-report-value"}' \
        bash "$fixture/scripts/doctor.sh" --json)" || fail "doctor --json failed"
    "$python_path" -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["schemaVersion"] == 1 and d["runtime"]["silere"] == "9.1.2"
assert d["runtime"]["quickshell"] == "0.3.1" and d["runtime"]["qt"] == "6.10.2"
assert d["runtime"]["compositor"] == "hyprland" and d["runtime"]["compositorVersion"] == "0.57.2"
assert d["runtime"]["distro"] and all(c.islower() or c.isdigit() or c in "._-" for c in d["runtime"]["distro"])
assert d["devices"]["audio"]["outputs"] == 2
assert d["devices"]["bluetooth"]["enabled"] is True
assert d["devices"]["screens"] == [{"width":1920,"height":1080,"scale":1.25}]
assert "private-report-value" not in sys.argv[1]
' "$actual" || fail "doctor report includes identifiers or loses required fields"
    for reply in unavailable '{"schemaVersion":1,broken}' '{"schemaVersion":2,"private":"hidden"}'; do
        actual="$(PATH="$fixture/bin:$PATH" SILERE_JSON_REPLY="$reply" bash "$fixture/scripts/doctor.sh" --json)"
        "$python_path" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["devices"] is None' "$actual" \
            || fail "doctor report did not handle a missing or malformed live reply"
    done
    printf '#!/bin/sh\nexit 127\n' > "$fixture/bin/python3"
    chmod +x "$fixture/bin/python3"
    actual="$(PATH="$fixture/bin:$PATH" bash "$fixture/scripts/doctor.sh" --json)"
    "$python_path" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["devices"] is None and d["availability"]["qs"]' "$actual" \
        || fail "doctor summary requires a working optional JSON parser"
)

test_keyboard_brightness_helper() (
    local fixture="$TMP/keyboard-helper" actual path=/org/freedesktop/UPower/KbdBacklight
    mkdir -p "$fixture/bin"
    cat > "$fixture/bin/busctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
    *' tree '*)
        printf '%s\n' /org/freedesktop/UPower/KbdBacklight \
            /org/freedesktop/UPower/KbdBacklight/led0 /org/freedesktop/UPower/KbdBacklight/led1 \
            /org/freedesktop/UPower/KbdBacklight/unsupported /org/freedesktop/UPower/KbdBacklight/invalid
        ;;
    *' get-property '*)
        case "$5" in
            */led1) printf 's "keyboard-1"\n' ;;
            *) printf 's "%s"\n' "${SILERE_KBD_IDENTITY:-keyboard-0}" ;;
        esac
        ;;
    *' call '*)
        case "$7" in
            GetMaxBrightness)
                case "$5" in */unsupported) printf 'i 0\n';; */invalid) printf 's "2"\n';; *) printf 'i 2\n';; esac
                ;;
            GetBrightness) printf 'i 1\n' ;;
            SetBrightness)
                [ "${SILERE_KBD_FAIL:-0}" = 0 ] || exit 1
                printf '%s:%s\n' "$5" "$9" >> "$SILERE_KBD_CALLS"
                ;;
            *) exit 1 ;;
        esac
        ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$fixture/bin/busctl"
    export PATH="$fixture/bin:$PATH" SILERE_KBD_CALLS="$fixture/calls" SILERE_SANDBOX=0
    actual="$(bash "$ROOT/scripts/keyboard-brightness.sh" list)"
    assert_eq "$path"$'\t1\t2\ts "keyboard-0"\n'"$path/led1"$'\t1\t2\ts "keyboard-1"' "$actual" \
        "keyboard discovery deduplicates UPower aliases and hides unsupported or malformed levels"
    bash "$ROOT/scripts/keyboard-brightness.sh" write "$path" 0 's "keyboard-0"'
    assert_eq "$path:0" "$(<"$fixture/calls")" "keyboard light supports zero as off"
    bash "$ROOT/scripts/keyboard-brightness.sh" write "$path/led1" 2 's "keyboard-1"'
    for level in -1 3 2147483648 invalid; do
        if bash "$ROOT/scripts/keyboard-brightness.sh" write "$path" "$level" 's "keyboard-0"'; then
            fail "keyboard writer accepted an unsupported hardware level"
        fi
    done
    if bash "$ROOT/scripts/keyboard-brightness.sh" write /org/other 1 unknown; then
        fail "keyboard writer accepted an unrelated object"
    fi
    if SILERE_KBD_IDENTITY=replacement bash "$ROOT/scripts/keyboard-brightness.sh" write "$path" 1 's "keyboard-0"'; then
        fail "keyboard writer changed a replacement device"
    fi
    if SILERE_KBD_FAIL=1 bash "$ROOT/scripts/keyboard-brightness.sh" write "$path" 1 's "keyboard-0"'; then
        fail "keyboard writer hid a UPower rejection"
    fi
    if SILERE_SANDBOX=1 bash "$ROOT/scripts/keyboard-brightness.sh" write "$path" 1 's "keyboard-0"'; then
        fail "keyboard writer changed lighting in a sandbox"
    fi
    assert_eq "$path:0"$'\n'"$path/led1:2" "$(<"$fixture/calls")" \
        "invalid, stale and sandbox keyboard requests never reach SetBrightness"
)

if [ "${SILERE_TEST_LIB_ONLY:-0}" = 1 ]; then
    return 0 2>/dev/null || exit 0
fi

test_xdg_paths_and_timer_default
test_doctor_json
test_keyboard_brightness_helper
test_fresh_install_permissions
test_existing_checkout_installer_update
test_lua_exec_return_guard
test_marker_removal
test_uninstall_targets_and_backups
test_uninstall_empty_optional_paths
test_qml_module_lookup
test_quickshell_version_after_qt_warning
test_quickshell_qt_drift
test_qml_type_floor
test_headless_qml_import_roots
test_font_archive_selection
test_assume_yes_prompts
test_piped_installer_bootstraps
test_install_path_safety
test_install_transaction_and_receipt
test_dry_run_writes_nothing
test_installer_options
test_autostart_line_runs
test_menu_keybind_plan
test_plain_copy_is_not_package_managed
test_unit_identity
test_hypr_discovery
test_niri_config_discovery
test_atomic_units
test_shared_launcher
test_reset_workflow
test_try_config_quotes_paths
test_lua_block_is_checked
test_other_bars_are_named
test_launcher_uses_real_name
test_startup_failure_report
test_cli_restart_and_log
test_cli_ipc_resolution
test_cli_use_switches_checkout
test_pooled_motion_scope
test_benchmark_json
test_hook_timeout_contains_tree
test_repair_workflow

printf 'portability regression tests passed\n'
