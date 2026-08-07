#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/xdg.sh"
cd "$ROOT"

CACHE_HOME="$(_silere_xdg_home "${XDG_CACHE_HOME:-}" .cache)" || {
    printf 'silere-update: HOME must be an absolute path\n' >&2
    exit 1
}
CONFIG_HOME="$(_silere_xdg_home "${XDG_CONFIG_HOME:-}" .config)" || {
    printf 'silere-update: HOME must be an absolute path\n' >&2
    exit 1
}
CACHE_DIR="$CACHE_HOME/silere-shell"
FLAG="$CACHE_DIR/update-pending"
NOTIFIED="$CACHE_DIR/update-notified"
TIMER_UNIT="silere-update.timer"
SERVICE_UNIT="silere-update.service"
SYSTEMD_USER_DIR="$CONFIG_HOME/systemd/user"

_notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    # Notifications are advisory. A missing/stale session bus must never turn a
    # successful update check or apply into a failed systemd unit.
    notify-send -a "Silere Shell" "$@" >/dev/null 2>&1 || true
}

# The periodic pass runs unattended and its failures are routine (a laptop
# offline, a branch left diverged), so it exits quietly and lets the shell
# surface the reason. Only user-initiated work is worth a critical popup.
_quiet_fail() {
    echo "silere-update: $1" >&2
    exit 1
}

_fail() {
    _notify -u critical "Silere update failed" "$1"
    _quiet_fail "$1"
}

_clear_flag() {
    rm -f "$FLAG" "$NOTIFIED"
}

_write_cache_file() {
    local target="$1" tmp
    shift
    mkdir -m 0700 -p "$CACHE_DIR" || return 1
    tmp="$(mktemp "$CACHE_DIR/.${target##*/}.XXXXXX")" || return 1
    if ! printf '%s\n' "$@" > "$tmp" || ! mv -- "$tmp" "$target"; then
        rm -f -- "$tmp"
        return 1
    fi
}

_has_local_changes() {
    [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=normal)" ]
}

_systemd_execstart() {
    local escaped="$ROOT/scripts/update.sh"
    escaped="${escaped//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    escaped="${escaped//%/%%}"
    escaped="${escaped//&/\\&}"
    escaped="${escaped//|/\\|}"
    printf '/bin/sh -c '\''exec "$1"'\'' silere-update "%s"\n' "$escaped"
}

_timer_status() {
    if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
        echo supported=1
        systemctl --user is-enabled --quiet "$TIMER_UNIT" 2>/dev/null && echo enabled=1 || echo enabled=0
    else
        echo supported=0
        echo enabled=0
    fi
}

_write_update_units() {
    local service_tmp timer_tmp
    service_tmp="$(mktemp "$SYSTEMD_USER_DIR/.silere-update.service.XXXXXX")" || return 1
    timer_tmp="$(mktemp "$SYSTEMD_USER_DIR/.silere-update.timer.XXXXXX")" || {
        rm -f "$service_tmp"
        return 1
    }

    if ! sed "s|^ExecStart=__ROOT__/scripts/update.sh$|ExecStart=$(_systemd_execstart)|" \
        "$ROOT/scripts/$SERVICE_UNIT" > "$service_tmp" \
        || ! cp "$ROOT/scripts/$TIMER_UNIT" "$timer_tmp"; then
        rm -f "$service_tmp" "$timer_tmp"
        return 1
    fi
    chmod --reference="$ROOT/scripts/$SERVICE_UNIT" "$service_tmp" 2>/dev/null || true
    chmod --reference="$ROOT/scripts/$TIMER_UNIT" "$timer_tmp" 2>/dev/null || true

    if ! mv -- "$service_tmp" "$SYSTEMD_USER_DIR/$SERVICE_UNIT"; then
        rm -f "$service_tmp" "$timer_tmp"
        return 1
    fi
    service_tmp=""
    if ! mv -- "$timer_tmp" "$SYSTEMD_USER_DIR/$TIMER_UNIT"; then
        rm -f "$timer_tmp"
        return 1
    fi
}

_set_timer() {
    local want="$1"
    command -v systemctl >/dev/null 2>&1 || _fail "systemctl not found"
    if [ "$want" = "1" ]; then
        mkdir -p "$SYSTEMD_USER_DIR"
        _write_update_units || _fail "failed to install systemd user units"
        systemctl --user daemon-reload
        systemctl --user enable --now "$TIMER_UNIT" >/dev/null
    else
        systemctl --user disable --now "$TIMER_UNIT" >/dev/null 2>&1 || true
        systemctl --user daemon-reload
    fi
}

# Exits 0 (clearing the pending-update flag) when local is already at or ahead
# of remote. Exits 1 when the branches have diverged; the periodic pass also
# clears the flag there so a non-actionable badge doesn't linger, while an
# --apply retry keeps showing pending until the divergence is resolved.
_exit_if_not_behind() {
    local local_rev="$1" remote_rev="$2" periodic="$3"
    if git merge-base --is-ancestor "$remote_rev" "$local_rev"; then
        _clear_flag
        exit 0
    fi
    if ! git merge-base --is-ancestor "$local_rev" "$remote_rev"; then
        if [ "$periodic" = "1" ]; then
            _clear_flag
            _quiet_fail "local branch has diverged from origin/main — update manually"
        fi
        _fail "local branch has diverged from origin/main — update manually"
    fi
}

if [ "${SILERE_SCRIPT_LIB_ONLY:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || _fail "not a git repo: $ROOT"

case "${1:-}" in
    --version)
        # "<short-sha> <YYYY-MM-DD>"; the date is what makes a rolling hash mean anything
        git -C "$ROOT" log -1 --format='%h %cs'
        exit 0
        ;;
    --timer-status)
        _timer_status
        exit 0
        ;;
    --timer-enable)
        _set_timer 1
        exit 0
        ;;
    --timer-disable)
        _set_timer 0
        exit 0
        ;;
esac

# --apply: fast-forward to the already-fetched origin/main and restart the shell.
# The flag carries the pending commit summary written by the check pass.
if [ "${1:-}" = "--apply" ]; then
    local_rev="$(git rev-parse HEAD)"
    remote_rev="$(git rev-parse origin/main 2>/dev/null)" \
        || _fail "origin/main is unavailable — check for updates again"
    _exit_if_not_behind "$local_rev" "$remote_rev" 0
    if _has_local_changes; then
        _fail "local changes detected — commit or stash them before applying the update"
    fi
    if ! git -C "$ROOT" merge --ff-only --quiet "$remote_rev"; then
        _fail "fast-forward merge failed — local branch diverged"
    fi
    _clear_flag
    new_rev="$(git rev-parse HEAD)"
    count="$(git rev-list --count "${local_rev}..${new_rev}")"
    plural="change"; [ "$count" -ne 1 ] && plural="changes"
    # systemd unit only exists on dev installs; exec-once users restart by hand
    if systemctl --user is-active --quiet silere-shell.service 2>/dev/null; then
        systemctl --user restart silere-shell.service
    else
        _notify "Silere Shell updated" "$count new $plural — restart the shell to use it"
    fi
    exit 0
fi

# Default (check): fetch and flag a pending update; never restarts on its own, so
# the shell can surface an indicator instead of vanishing mid-session.

GIT_TERMINAL_PROMPT=0 git fetch --quiet origin main \
    || _quiet_fail "git fetch failed (check network / connectivity)"

local_rev="$(git rev-parse HEAD)"
remote_rev="$(git rev-parse origin/main)"
_exit_if_not_behind "$local_rev" "$remote_rev" 1

count="$(git rev-list --count "${local_rev}..${remote_rev}")"
summary="$(git log -5 --oneline --no-decorate "${local_rev}..${remote_rev}")"

_write_cache_file "$FLAG" "$count" "$summary" \
    || _quiet_fail "failed to write update status"

# The badge is the persistent reminder. Notify once per pending revision, or a
# daily timer re-announces the same commits until they are installed.
if [ "$(cat "$NOTIFIED" 2>/dev/null || true)" != "$remote_rev" ]; then
    plural="change"; [ "$count" -ne 1 ] && plural="changes"
    _notify "Silere Shell update ready" "$count new $plural ready — install from the bar$([ -n "$summary" ] && printf '\n%s' "$summary")"
    # If this bookkeeping write fails, keep the successful update check and
    # simply allow the next periodic pass to retry the advisory notification.
    _write_cache_file "$NOTIFIED" "$remote_rev" \
        || echo "silere-update: could not record update notification" >&2
fi
