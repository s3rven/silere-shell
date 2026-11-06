#!/usr/bin/env bash
# Back to a fresh install, for when the menu will not open or a change cannot be found: settings, edited files, leftovers
# from older versions and caches. Everything but caches and a history the user chose to clear comes back with --undo.
# It stops at what Silere owns: hooks, the Matugen palette, autostart and the service are the user's and stay
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/xdg.sh"
source "$ROOT/scripts/lib/unit.sh"
source "$ROOT/scripts/lib/ui.sh"

_usage() {
    cat <<'EOF'
Usage:
  silere reset                   Show what a reset would change, and change nothing
  silere reset --apply           Reset settings, edited files, leftovers and caches, then restart the shell
  silere reset --apply --history Also clear notification history; this part cannot be undone
  silere reset --undo            Put back what the last reset replaced

Add --yes to skip the confirmation prompt.
EOF
}

_die() {
    printf '%ssilere:%s %s\n' "$ERED" "$ER" "$*" >&2
    exit 1
}

CONFIG_HOME="$(_silere_xdg_home "${XDG_CONFIG_HOME:-}" .config)" || _die "HOME must be absolute"
STATE_HOME="$(_silere_xdg_home "${XDG_STATE_HOME:-}" .local/state)" || _die "HOME must be absolute"
CACHE_HOME="$(_silere_xdg_home "${XDG_CACHE_HOME:-}" .cache)" || _die "HOME must be absolute"
CONFIG_DIR="$CONFIG_HOME/silere-shell"
STATE_DIR="$STATE_HOME/silere-shell"
CACHE_DIR="$CACHE_HOME/silere-shell"
SETTINGS="$CONFIG_DIR/settings.json"
HISTORY="$STATE_DIR/notifications.json"
SAVED_SETTINGS="$STATE_DIR/settings.pre-reset.json"
SAVED_DIR="$STATE_DIR/reset-saved"

ASSUME_YES=0
WITH_HISTORY=0

_confirm() {
    [ "$ASSUME_YES" = 1 ] && return 0
    # -r succeeds with no controlling terminal; only opening it proves one exists
    { : </dev/tty; } 2>/dev/null || _die "confirmation needs a terminal; add --yes to run non-interactively"
    printf '%s [y/N] ' "$1" >/dev/tty
    local reply
    read -r reply </dev/tty
    [[ "$reply" =~ ^[Yy]$ ]]
}

# settings.json stores only what differs from the defaults, so each key in it is one change
_changed_settings() {
    [ -f "$SETTINGS" ] || return 0
    grep -oE '"[A-Za-z_][A-Za-z0-9_]*"[[:space:]]*:' "$SETTINGS" 2>/dev/null | tr -d '": ' | grep -vx '__version' || true
}

_settings_readable() {
    [ -f "$SETTINGS" ] || return 0
    command -v python3 >/dev/null 2>&1 || return 0
    python3 -I -c 'import json, sys; json.load(open(sys.argv[1]))' "$SETTINGS" 2>/dev/null
}

# nothing reads these any more: removed features, and backups of migrations long finished
_leftovers() {
    local path
    for path in "$CONFIG_DIR"/calendar-marks.json "$CONFIG_DIR"/notifications.json \
            "$CONFIG_DIR"/settings.pre-reset-*.bak.json "$CONFIG_DIR"/settings.pre-v*.bak.json; do
        [ -e "$path" ] && printf '%s\n' "${path##*/}"
    done
    return 0
}

# the lock stays: another update run may hold it, and removing it would let two run at once
_caches() {
    [ -d "$CACHE_DIR" ] || return 0
    find "$CACHE_DIR" -mindepth 1 -maxdepth 1 ! -name update.lock -printf '%f\n' 2>/dev/null | sort
}

_is_checkout() {
    [ -f "$ROOT/scripts/repair.sh" ] || return 1
    command -v git >/dev/null 2>&1 || return 1
    local top
    top="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" || return 1
    [ "$(cd "$top" && pwd -P)" = "$(cd "$ROOT" && pwd -P)" ]
}

_edited_files() {
    _is_checkout || return 0
    git -C "$ROOT" status --short --untracked-files=normal
}

_count() {
    [ -n "$1" ] || { printf '0\n'; return; }
    printf '%s\n' "$1" | wc -l | tr -d ' '
}

_shell_is_up() {
    command -v qs >/dev/null 2>&1 || return 1
    local instances
    instances="$(env -u LC_ALL qs list -p "$ROOT/shell.qml" 2>/dev/null || true)"
    case "$instances" in *"Process ID: "[0-9]*) return 0 ;; *) return 1 ;; esac
}

_unit_owns_shell() {
    command -v systemctl >/dev/null 2>&1 && _silere_unit_runs_checkout "$ROOT"
}

# stopped first: a shell left running could write its old settings over the reset. Refused before anything changes
# if the shell could not be brought back afterwards, as from a text console
_stop_shell() {
    RESTART=0
    if _unit_owns_shell; then
        RESTART=1
    elif _shell_is_up; then
        [ -n "${WAYLAND_DISPLAY:-}" ] || _die "run this from inside your Wayland session, or the shell could not come back"
        RESTART=1
    fi
    [ "$RESTART" = 1 ] || return 0
    local out
    out="$(bash "$ROOT/scripts/silere" stop 2>&1)" || _die "${out:-could not stop the shell}"
}

_start_shell() {
    if [ "$RESTART" = 1 ]; then
        bash "$ROOT/scripts/silere" restart \
            || _die "the shell did not come back; silere doctor shows what is wrong"
    else
        printf 'Silere is not running; silere run starts it.\n'
    fi
}

# through a link when it is one: a settings file kept in a dotfiles repo has to stay there
_write_settings() {
    local schema
    schema="$(sed -n 's/^[[:space:]]*"settingsSchema"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$ROOT/release.json" 2>/dev/null)"
    (umask 077 && mkdir -p -- "$CONFIG_DIR")
    printf '{\n  "__version": %s\n}\n' "${schema:-2}" > "$SETTINGS"
    [ -L "$SETTINGS" ] || chmod 0600 -- "$SETTINGS"
}

_preview() {
    local keys edited old caches
    keys="$(_changed_settings)"
    edited="$(_edited_files)"
    old="$(_leftovers)"
    caches="$(_caches)"
    if [ -z "$keys$edited$old$caches" ] && _settings_readable; then
        printf 'Nothing to reset: Silere already matches a fresh install.\n'
        _undo_hint
        return 0
    fi
    printf 'A reset would change:\n\n'
    if ! _settings_readable; then
        printf '  %-11s%s\n' "Settings" "settings.json cannot be read; it is saved, then replaced with the defaults"
    elif [ -n "$keys" ]; then
        printf '  %-11s%s back to defaults: %s\n' "Settings" "$(_count "$keys")" "$(printf '%s\n' "$keys" | paste -sd ' ' | sed 's/ /, /g' | cut -c1-90)"
    fi
    [ -z "$edited" ] || printf '  %-11s%s edited in this checkout, saved in a Git stash and restored to the installed revision\n' "Files" "$(_count "$edited")"
    [ -z "$old" ] || printf '  %-11s%s from older versions, set aside: %s\n' "Leftovers" "$(_count "$old")" "$(printf '%s\n' "$old" | paste -sd ' ' | sed 's/ /, /g' | cut -c1-90)"
    [ -z "$caches" ] || printf '  %-11s%s cleared: %s\n' "Caches" "$(du -sh -- "$CACHE_DIR" 2>/dev/null | cut -f1)" "$(printf '%s\n' "$caches" | paste -sd ' ' | sed 's/ /, /g' | cut -c1-90)"
    printf '\nKept: notification history (--history clears it), hooks, the Matugen palette, autostart and the service.\n'
    printf 'Everything but caches comes back with silere reset --undo.\n\n'
    printf 'Nothing was changed. silere reset --apply does it.\n'
}

_undo_hint() {
    [ ! -e "$SAVED_SETTINGS" ] && [ ! -d "$SAVED_DIR" ] && return 0
    printf 'The last reset can be put back with silere reset --undo.\n'
}

_apply() {
    local keys edited old caches name
    keys="$(_changed_settings)"
    edited="$(_edited_files)"
    old="$(_leftovers)"
    caches="$(_caches)"
    local history_there=0
    [ "$WITH_HISTORY" = 1 ] && [ -e "$HISTORY" ] && history_there=1
    if [ -z "$keys$edited$old$caches" ] && [ "$history_there" = 0 ] && _settings_readable; then
        printf 'Nothing to reset: Silere already matches a fresh install.\n'
        return 0
    fi
    _preview | sed '/^Nothing was changed/d'
    [ "$history_there" = 0 ] || printf 'Notification history will be deleted. This part cannot be undone.\n\n'
    _confirm "Reset Silere?" || { printf 'Cancelled; nothing was changed.\n'; return 0; }

    _stop_shell
    (umask 077 && mkdir -p -- "$STATE_DIR")
    # only one reset is kept; a second has to replace the first or an undo would mix the two
    rm -rf -- "$SAVED_DIR" "$SAVED_SETTINGS"
    mkdir -m 0700 -- "$SAVED_DIR"

    if [ -f "$SETTINGS" ]; then
        cp -- "$SETTINGS" "$SAVED_SETTINGS" || _die "could not save a copy of the settings; nothing was reset"
        chmod 0600 -- "$SAVED_SETTINGS"
    fi
    _write_settings || _die "could not write the default settings"

    while IFS= read -r name; do
        [ -n "$name" ] || continue
        mv -- "$CONFIG_DIR/$name" "$SAVED_DIR/$name" || printf 'could not set aside %s\n' "$name" >&2
    done <<< "$old"

    while IFS= read -r name; do
        [ -n "$name" ] || continue
        rm -rf -- "${CACHE_DIR:?}/$name"
    done <<< "$caches"

    [ "$history_there" = 0 ] || rm -f -- "$HISTORY"

    if [ -n "$edited" ]; then
        # last before the restart: it can replace this very file, and the restart then runs the restored shell
        if bash "$ROOT/scripts/repair.sh" --apply --yes >/dev/null; then
            printf 'repaired=1\n' > "$SAVED_DIR/manifest"
        else
            printf 'Settings were reset, but the edited files could not be restored; silere repair shows them.\n' >&2
        fi
    fi
    printf 'Silere was reset. silere reset --undo puts it back.\n'
    _start_shell
}

_undo() {
    [ -e "$SAVED_SETTINGS" ] || [ -d "$SAVED_DIR" ] || _die "no reset to undo"
    printf 'This puts back what the last reset replaced'
    [ -e "$SAVED_SETTINGS" ] && printf ': settings'
    [ -f "$SAVED_DIR/manifest" ] && printf ', edited files'
    printf '.\n'
    _confirm "Undo the reset?" || { printf 'Cancelled; nothing was changed.\n'; return 0; }

    if [ -f "$SAVED_DIR/manifest" ] && [ -n "$(_edited_files)" ]; then
        _die "the checkout has new local changes; save or remove them before restoring older ones"
    fi
    _stop_shell
    if [ -e "$SAVED_SETTINGS" ]; then
        (umask 077 && mkdir -p -- "$CONFIG_DIR")
        # through a link when it is one, as the reset wrote it
        cat -- "$SAVED_SETTINGS" > "$SETTINGS" || _die "could not restore the settings"
        rm -f -- "$SAVED_SETTINGS"
    fi
    local item
    if [ -d "$SAVED_DIR" ]; then
        for item in "$SAVED_DIR"/*; do
            [ -e "$item" ] && [ "$(basename -- "$item")" != manifest ] || continue
            # a newer file of that name wins; the older one is not worth losing it for
            [ -e "$CONFIG_DIR/$(basename -- "$item")" ] || mv -- "$item" "$CONFIG_DIR/"
        done
    fi
    if [ -f "$SAVED_DIR/manifest" ]; then
        bash "$ROOT/scripts/repair.sh" --undo --yes >/dev/null \
            || printf 'The settings came back, but the edited files did not; silere repair --undo tries again.\n' >&2
    fi
    rm -rf -- "$SAVED_DIR"
    printf 'The last reset was undone.\n'
    _start_shell
}

# one function, parsed whole before it runs: the repair step can replace this file underneath a running bash
_main() {
    local action=preview arg
    for arg in "$@"; do
        case "$arg" in
            --apply) action=apply ;;
            --undo) action=undo ;;
            --yes) ASSUME_YES=1 ;;
            --history) WITH_HISTORY=1 ;;
            -h|--help) _usage; return 0 ;;
            *) _usage >&2; return 2 ;;
        esac
    done
    [ "$WITH_HISTORY" = 0 ] || [ "$action" = apply ] || { _usage >&2; return 2; }
    case "$action" in
        preview) _preview ;;
        apply) _apply ;;
        undo) _undo ;;
    esac
}

_main "$@"
exit
