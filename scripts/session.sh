#!/usr/bin/env bash
# Read session lock state, wait for the compositor to confirm a secure lock, or find and stop a tool of this session.
set -euo pipefail

# pgrep and pkill by name, limited to this session: a name alone also reaches the same tool in another one, such as the
# desktop a nested shell runs inside. Only a process naming another display or runtime dir is foreign, so a tool that
# names neither is still found, as a bare pkill would. Exits 0 for a match and 1 for none, like both of them
session_tools() {
    local action="$1" name="$2" pids pid entry display runtime found=1
    pids="$(pgrep -x -- "$name")" || return $?
    for pid in $pids; do
        display=
        runtime=
        { while IFS= read -r -d '' entry; do
            case "$entry" in
                WAYLAND_DISPLAY=*) display="${entry#*=}" ;;
                XDG_RUNTIME_DIR=*) runtime="${entry#*=}" ;;
            esac
        done < "/proc/$pid/environ"; } 2>/dev/null || continue
        [ -z "$display" ] || [ "$display" = "${WAYLAND_DISPLAY:-}" ] || continue
        [ -z "$runtime" ] || [ "$runtime" = "${XDG_RUNTIME_DIR:-}" ] || continue
        found=0
        [ "$action" = find ] || kill "$pid" 2>/dev/null || true
    done
    return "$found"
}

case "${1:-}" in
    tool-find) session_tools find "${2:?}"; exit $? ;;
    tool-stop) session_tools stop "${2:?}"; exit $? ;;
esac

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
    *) echo 'Usage: session.sh status|wait-locked|tool-find NAME|tool-stop NAME' >&2; exit 2 ;;
esac
