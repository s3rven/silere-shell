#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/silere-shell"
FLAG="$CACHE_DIR/update-pending"
TIMER_UNIT="silere-update.timer"
SERVICE_UNIT="silere-update.service"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

_notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a "Silere Shell" "$@"
}

_fail() {
    _notify -u critical "Silere update failed" "$1"
    echo "silere-update: $1" >&2
    exit 1
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
    command -v systemctl >/dev/null 2>&1 && echo supported=1 || echo supported=0
    systemctl --user is-enabled --quiet "$TIMER_UNIT" 2>/dev/null && echo enabled=1 || echo enabled=0
}

_set_timer() {
    local want="$1"
    command -v systemctl >/dev/null 2>&1 || _fail "systemctl not found"
    if [ "$want" = "1" ]; then
        mkdir -p "$SYSTEMD_USER_DIR"
        sed "s|^ExecStart=__ROOT__/scripts/update.sh$|ExecStart=$(_systemd_execstart)|" \
            "$ROOT/scripts/$SERVICE_UNIT" > "$SYSTEMD_USER_DIR/$SERVICE_UNIT"
        cp "$ROOT/scripts/$TIMER_UNIT" "$SYSTEMD_USER_DIR/$TIMER_UNIT"
        systemctl --user daemon-reload
        systemctl --user enable --now "$TIMER_UNIT" >/dev/null
    else
        systemctl --user disable --now "$TIMER_UNIT" >/dev/null 2>&1 || true
        systemctl --user daemon-reload
    fi
}

[ -d "$ROOT/.git" ] || _fail "not a git repo: $ROOT"

case "${1:-}" in
    --version)
        git -C "$ROOT" rev-parse --short HEAD
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
    remote_rev="$(git rev-parse origin/main 2>/dev/null || echo "$local_rev")"
    if [ "$local_rev" = "$remote_rev" ]; then
        rm -f "$FLAG"
        exit 0
    fi
    stashed=0
    if _has_local_changes; then
        if ! git -C "$ROOT" stash push --include-untracked -m "silere-update pre-apply" >/dev/null; then
            _fail "failed to stash local changes before applying update"
        fi
        stashed=1
    fi
    if ! GIT_TERMINAL_PROMPT=0 git pull --ff-only --quiet origin main; then
        [ "$stashed" -eq 1 ] && git -C "$ROOT" stash pop >/dev/null 2>&1 || true
        _fail "fast-forward pull failed — local branch diverged"
    fi
    # update succeeded; pop may conflict but the restart should still proceed
    stash_conflict=0
    if [ "$stashed" -eq 1 ] && ! git -C "$ROOT" stash pop >/dev/null 2>&1; then
        stash_conflict=1
    fi
    rm -f "$FLAG"
    if [ "$stash_conflict" -eq 1 ]; then
        _notify -u critical "Silere update applied with conflicts" "Your local changes conflicted and were kept in the stash — run 'git stash list' to find it, 'git stash pop' to retry"
    fi
    count="$(git rev-list --count "${local_rev}..${remote_rev}")"
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

GIT_TERMINAL_PROMPT=0 git fetch --quiet origin main || _fail "git fetch failed (check network / connectivity)"

local_rev="$(git rev-parse HEAD)"
remote_rev="$(git rev-parse origin/main)"
if [ "$local_rev" = "$remote_rev" ]; then
    rm -f "$FLAG"
    exit 0
fi

count="$(git rev-list --count "${local_rev}..${remote_rev}")"
summary="$(git log --oneline --no-decorate "${local_rev}..${remote_rev}" | head -5)"

mkdir -p "$CACHE_DIR"
{
    printf '%s\n' "$count"
    printf '%s\n' "$summary"
} > "$FLAG"

plural="change"; [ "$count" -ne 1 ] && plural="changes"
_notify "Silere Shell update ready" "$count new $plural ready — install from the bar$([ -n "$summary" ] && printf '\n%s' "$summary")"
