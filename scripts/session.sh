#!/usr/bin/env bash
# Read session lock state, or wait for the compositor to confirm a secure lock.
set -euo pipefail

session_id="${XDG_SESSION_ID:-}"
if [ -z "$session_id" ]; then
    session_id="$(timeout 2 loginctl show-session self -p Id --value 2>/dev/null || true)"
fi
case "$session_id" in
    ''|*[!a-zA-Z0-9_.-]*) echo 'No local login session could be identified.' >&2; exit 1 ;;
esac

locked_state() {
    timeout 2 loginctl show-session "$session_id" -p LockedHint --value 2>/dev/null
}

case "${1:-status}" in
    status)
        locked="$(locked_state)" || exit 1
        case "$locked" in yes|no) ;; *) exit 1 ;; esac
        printf 'session=%s\nlocked=%s\n' "$session_id" "$locked"
        ;;
    wait-locked)
        for ((attempt=0; attempt<100; attempt++)); do
            [ "$(locked_state || true)" != yes ] || exit 0
            sleep 0.1
        done
        echo 'The session did not confirm a secure lock; sleep was cancelled.' >&2
        exit 1
        ;;
    *) echo 'Usage: session.sh status|wait-locked' >&2; exit 2 ;;
esac
