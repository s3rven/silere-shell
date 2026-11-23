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
source "$ROOT/scripts/lib/instances.sh"

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
LEGACY_HISTORY="$CONFIG_DIR/notifications.json"
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
    python3 -I -c 'import json, sys; sys.exit(not isinstance(json.load(open(sys.argv[1])), dict))' "$SETTINGS" 2>/dev/null
}

# nothing reads these any more: removed features, and backups of migrations long finished
_leftovers() {
    local path
    for path in "$CONFIG_DIR"/calendar-marks.json \
            "$CONFIG_DIR"/settings.pre-reset-*.bak.json "$CONFIG_DIR"/settings.pre-v*.bak.json; do
        [ -e "$path" ] && printf '%s\n' "${path##*/}"
    done
    # leave a sole legacy copy for startup to migrate, and keep the live file when both XDG paths name it
    if [ "$WITH_HISTORY" = 0 ] && [ -f "$HISTORY" ] && [ -f "$LEGACY_HISTORY" ] \
            && ! [[ "$LEGACY_HISTORY" -ef "$HISTORY" ]]; then
        printf '%s\n' "${LEGACY_HISTORY##*/}"
    fi
    return 0
}

_has_history_to_clear() {
    [ "$WITH_HISTORY" = 1 ] || return 1
    local path
    for path in "$HISTORY" "$LEGACY_HISTORY" "$SAVED_DIR/notifications.json"; do
        if [ -f "$path" ] || [ -L "$path" ]; then return 0; fi
    done
    return 1
}

# the lock stays: another update run may hold it, and removing it would let two run at once. qs-flags is the
# launcher's note about the Quickshell binary, rewritten at every start, so counting it made a reset never find
# nothing to do; it follows the binary on its own
_caches() {
    [ -d "$CACHE_DIR" ] || return 0
    find "$CACHE_DIR" -mindepth 1 -maxdepth 1 ! -name update.lock ! -name qs-flags -printf '%f\n' 2>/dev/null | sort
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
    _silere_shell_running "$ROOT/shell.qml"
}

_lock_reset() {
    (umask 077 && mkdir -p -- "$STATE_DIR") || _die "could not create the reset backup directory"
    command -v flock >/dev/null 2>&1 || return 0
    exec 8>>"$STATE_DIR/reset.lock"
    flock -n 8 || _die "another reset or undo is in progress"
}

# stopped first: a shell left running could write its old settings over the reset. Refused before anything changes
# if the shell could not be brought back afterwards, as from a text console
_stop_shell() {
    RESTART=0
    SUPERVISED=0
    if _silere_unit_owns_shell "$ROOT"; then
        RESTART=1
        # silere restart only goes through systemd for a unit that is active or enabled, and a stopped unit
        # started by silere run --supervised is neither: it would come back with nothing to restart it after a crash
        if systemctl --user is-active --quiet silere-shell.service 2>/dev/null; then SUPERVISED=1; fi
    elif _shell_is_up; then
        [ -n "${WAYLAND_DISPLAY:-}" ] || _die "run this from inside your Wayland session, or the shell could not come back"
        RESTART=1
    fi
    [ "$RESTART" = 1 ] || return 0
    local out
    out="$(bash "$ROOT/scripts/silere" stop 2>&1)" || _die "${out:-could not stop the shell}"
    # a failure from here on must not leave the desktop without its shell
    trap '[ $? = 0 ] || _start_shell' EXIT
}

_start_shell() {
    trap - EXIT
    if [ "$SUPERVISED" = 1 ]; then
        systemctl --user start silere-shell.service 8>&- \
            || _die "systemd could not start silere-shell.service again; silere doctor shows what is wrong"
    elif [ "$RESTART" = 1 ]; then
        bash "$ROOT/scripts/silere" restart 8>&- \
            || _die "the shell did not come back; silere doctor shows what is wrong"
    else
        printf 'Silere is not running; silere run starts it.\n'
    fi
}

# through a link when it is one: a settings file kept in a dotfiles repo has to stay there
_write_settings() {
    local schema
    schema="$(sed -n 's/^[[:space:]]*"settingsSchema"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$ROOT/release.json" 2>/dev/null)"
    # called under ||, which turns set -e off in here: every step has to report its own failure
    (umask 077 && mkdir -p -- "$CONFIG_DIR") || return 1
    printf '{\n  "__version": %s\n}\n' "${schema:-2}" > "$SETTINGS" || return 1
    [ -L "$SETTINGS" ] || chmod 0600 -- "$SETTINGS"
}

# one name per line in, "a, b, c and 4 more" out: a cut mid-name reads as a real key
_names() {
    awk 'NF { n++; name[n] = $0 }
        END {
            for (i = 1; i <= n; i++) {
                add = (i == 1 ? "" : ", ") name[i]
                if (i > 1 && length(out add) > (i < n ? 76 : 90)) { printf "%s and %d more", out, n - i + 1; exit }
                out = out add
            }
            printf "%s", out
        }'
}

_preview() {
    local keys edited old caches
    keys="$(_changed_settings)"
    edited="$(_edited_files)"
    old="$(_leftovers)"
    caches="$(_caches)"
    if [ -z "$keys$edited$old$caches" ] && _settings_readable && ! _has_history_to_clear; then
        printf 'Nothing to reset: Silere already matches a fresh install.\n'
        _undo_hint
        return 0
    fi
    printf 'A reset would change:\n\n'
    if ! _settings_readable; then
        printf '  %-11s%s\n' "Settings" "settings.json cannot be read; it is saved, then replaced with the defaults"
    elif [ -n "$keys" ]; then
        printf '  %-11s%s back to defaults: %s\n' "Settings" "$(_count "$keys")" "$(_names <<<"$keys")"
    fi
    [ -z "$edited" ] || printf '  %-11s%s edited in this checkout, saved in a Git stash and restored to the installed revision\n' "Files" "$(_count "$edited")"
    [ -z "$old" ] || printf '  %-11s%s from older versions, set aside: %s\n' "Leftovers" "$(_count "$old")" "$(_names <<<"$old")"
    [ -z "$caches" ] || printf '  %-11s%s cleared: %s\n' "Caches" "$(du -sh -- "$CACHE_DIR" 2>/dev/null | cut -f1)" "$(_names <<<"$caches")"
    if [ "$WITH_HISTORY" = 1 ]; then
        printf '\nNotification history will be deleted. This part cannot be undone.\n'
        printf 'Kept: hooks, the Matugen palette, autostart and the service.\n'
        printf 'Settings and edited files come back with silere reset --undo.\n\n'
    else
        printf '\nKept: notification history (--history clears it), hooks, the Matugen palette, autostart and the service.\n'
        printf 'Everything but caches comes back with silere reset --undo.\n\n'
    fi
    printf 'Nothing was changed. silere reset --apply does it.\n'
}

_undo_hint() {
    [ ! -e "$SAVED_SETTINGS" ] && [ ! -d "$SAVED_DIR" ] && return 0
    printf 'The last reset can be put back with silere reset --undo.\n'
}

_stash_for_reset() {
    local label="$1"
    git -C "$ROOT" stash push --include-untracked -m "$label" >/dev/null || return 1
    # the stash position can change while other Git commands run; match this reset's unique label
    git -C "$ROOT" stash list --format='%H%x09%gs' | awk -F '\t' -v suffix=": $label" '
        !found && substr($2, length($2) - length(suffix) + 1) == suffix { print $1; found = 1 }
        END { if (!found) exit 1 }'
}

_apply() {
    local keys edited old caches name pending stash label
    keys="$(_changed_settings)"
    edited="$(_edited_files)"
    old="$(_leftovers)"
    caches="$(_caches)"
    if [ -z "$keys$edited$old$caches" ] && _settings_readable && ! _has_history_to_clear; then
        printf 'Nothing to reset: Silere already matches a fresh install.\n'
        return 0
    fi
    _preview | sed '/^Nothing was changed/d'
    _confirm "Reset Silere?" || { printf 'Cancelled; nothing was changed.\n'; return 0; }

    _lock_reset
    _stop_shell
    old="$(_leftovers)"
    pending="$(mktemp -d "$STATE_DIR/.reset-saved.XXXXXX")" || _die "could not prepare the reset backup"
    # keep the CLI settings and stash together; the GUI keeps its own settings-only backup
    if ! (umask 077; printf 'stash=\n' > "$pending/manifest" && {
        [ ! -f "$SETTINGS" ] || cp -- "$SETTINGS" "$pending/settings.json"
    }); then
        rm -rf -- "$pending"
        _die "could not save a copy of the settings; nothing was reset"
    fi
    rm -rf -- "$SAVED_DIR"
    mv -T -- "$pending" "$SAVED_DIR"
    _write_settings || _die "could not write the default settings"

    while IFS= read -r name; do
        [ -n "$name" ] || continue
        mv -- "$CONFIG_DIR/$name" "$SAVED_DIR/$name" || printf 'could not set aside %s\n' "$name" >&2
    done <<< "$old"

    while IFS= read -r name; do
        [ -n "$name" ] || continue
        rm -rf -- "${CACHE_DIR:?}/$name"
    done <<< "$caches"

    if [ "$WITH_HISTORY" = 1 ]; then
        for name in "$HISTORY" "$LEGACY_HISTORY"; do
            [ -f "$name" ] || [ -L "$name" ] || continue
            rm -f -- "$name"
        done
    fi

    if [ -n "$edited" ]; then
        # last before the restart: it can replace this very file, and the restart then runs the restored shell
        label="silere-reset ${pending##*.}"
        if stash="$(_stash_for_reset "$label" 8>&-)"; then
            printf 'stash=%s\n' "$stash" > "$SAVED_DIR/stash.new" \
                && mv -Tf -- "$SAVED_DIR/stash.new" "$SAVED_DIR/manifest" \
                || _die "settings were reset and edits saved in stash $stash; could not link them in the reset backup"
        else
            printf 'Settings were reset. Could not record the edited files; check the worktree and Git stash list for %s.\n' "$label" >&2
        fi
    fi
    printf 'Silere was reset. silere reset --undo puts it back.\n'
    _start_shell
}

_undo() {
    [ -e "$SAVED_SETTINGS" ] || [ -d "$SAVED_DIR" ] || _die "no reset to undo"
    # what comes back, read the way the undo below reads the backup
    local preview="" recorded=""
    [ ! -f "$SAVED_DIR/manifest" ] || recorded="$(cat -- "$SAVED_DIR/manifest" 2>/dev/null || true)"
    case "$recorded" in
        stash=*)
            [ ! -e "$SAVED_DIR/settings.json" ] || preview="settings"
            [ "$recorded" = stash= ] || preview="${preview:+$preview, }edited files"
            ;;
        *) [ ! -e "$SAVED_SETTINGS" ] || preview="settings" ;;
    esac
    [ -z "$preview" ] || printf 'This puts back what the last reset replaced: %s.\n' "$preview"
    _confirm "Undo the reset?" || { printf 'Cancelled; nothing was changed.\n'; return 0; }
    _lock_reset
    [ -e "$SAVED_SETTINGS" ] || [ -d "$SAVED_DIR" ] || _die "no reset to undo"

    local saved_settings="$SAVED_SETTINGS" manifest="" stash="" item
    if [ -f "$SAVED_DIR/manifest" ]; then
        manifest="$(cat -- "$SAVED_DIR/manifest")"
    fi
    case "$manifest" in
        stash=*) saved_settings="$SAVED_DIR/settings.json"; stash="${manifest#stash=}" ;;
        repaired=1|'') ;;
        *) _die "could not read the reset manifest in $SAVED_DIR" ;;
    esac

    if [ -n "$stash" ]; then
        if ! [[ "$stash" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] || ! _is_checkout \
            || ! git -C "$ROOT" cat-file -e "$stash^{commit}" 2>/dev/null \
            || ! git -C "$ROOT" stash show --stat "$stash" >/dev/null 2>&1; then
            _die "could not find the reset's saved edits in this checkout; the reset backup was kept"
        fi
        [ -z "$(_edited_files)" ] \
            || _die "the checkout has new local changes; save or remove them before restoring older ones"
    fi
    _stop_shell
    if [ -e "$saved_settings" ]; then
        (umask 077 && mkdir -p -- "$CONFIG_DIR")
        # through a link when it is one, as the reset wrote it
        cat -- "$saved_settings" > "$SETTINGS" || _die "could not restore the settings"
    fi
    if [ -d "$SAVED_DIR" ]; then
        for item in "$SAVED_DIR"/*; do
            [ -e "$item" ] || continue
            case "${item##*/}" in manifest|settings.json|stash.new) continue ;; esac
            # a newer file of that name wins; the older one is not worth losing it for
            [ -e "$CONFIG_DIR/${item##*/}" ] || mv -- "$item" "$CONFIG_DIR/"
        done
    fi
    if [ -n "$stash" ]; then
        git -C "$ROOT" stash apply --quiet "$stash" 8>&- \
            || _die "could not restore edits from stash $stash; the reset backup and stash were kept"
    elif [ "$manifest" = repaired=1 ]; then
        printf 'This older reset did not record a stash ID. Find its edited files in git stash list.\n' >&2
    fi
    rm -f -- "$saved_settings"
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
