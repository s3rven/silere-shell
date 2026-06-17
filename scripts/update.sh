#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/silere-shell"
FLAG="$CACHE_DIR/update-pending"

_notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a "Silere Shell" "$@"
}

_fail() {
    _notify -u critical "Silere update failed" "$1"
    echo "silere-update: $1" >&2
    exit 1
}

_clean_tree() {
    if ! git -C "$ROOT" diff --quiet || ! git -C "$ROOT" diff --cached --quiet; then
        _fail "working tree has local changes — resolve them first"
    fi
}

[ -d "$ROOT/.git" ] || _fail "not a git repo: $ROOT"

# --apply: fast-forward to the already-fetched origin/main and restart the shell.
# The flag carries the pending commit summary written by the check pass.
if [ "${1:-}" = "--apply" ]; then
    _clean_tree
    local_rev="$(git rev-parse HEAD)"
    remote_rev="$(git rev-parse origin/main 2>/dev/null || echo "$local_rev")"
    if [ "$local_rev" = "$remote_rev" ]; then
        rm -f "$FLAG"
        exit 0
    fi
    if ! GIT_TERMINAL_PROMPT=0 git pull --ff-only --quiet origin main; then
        _fail "fast-forward pull failed — local branch diverged"
    fi
    rm -f "$FLAG"
    count="$(git rev-list --count "${local_rev}..${remote_rev}")"
    plural="commit"; [ "$count" -ne 1 ] && plural="commits"
    # systemd unit only exists on dev installs; exec-once users restart by hand
    if systemctl --user is-active --quiet silere-shell.service 2>/dev/null; then
        systemctl --user restart silere-shell.service
    else
        _notify "Silere Shell updated" "$count new $plural — restart the shell to apply"
    fi
    exit 0
fi

# Default (check): fetch and flag a pending update; never restarts on its own, so
# the shell can surface an indicator instead of vanishing mid-session.
_clean_tree

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

plural="commit"; [ "$count" -ne 1 ] && plural="commits"
_notify "Silere Shell update ready" "$count new $plural pending — apply from the bar$([ -n "$summary" ] && printf '\n%s' "$summary")"
