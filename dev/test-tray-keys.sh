#!/usr/bin/env bash
# Tray menus from the keyboard, against a real DBus menu: dev/fake-tray-menu.py's two apps on a private
# bus, in a virtual KWin, with real key events (dev/probe-tray-keys.qml). The menu's activations land in
# the fake app's log, so the last check reads that too.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/dev/probe-lib.sh"

if [ "${1:-}" = --inner ]; then
    scratch="$2"
    [[ "$XDG_CONFIG_HOME" = "$scratch/"* && -z "${XDG_SESSION_ID:-}" ]] || exit 1
    case "${DBUS_SESSION_BUS_ADDRESS:-}" in ''|*/run/user/*/bus*) exit 1 ;; esac
    kwin_pid=""; probe_pid=""; tray_pid=""
    trap '_probe_stop "$tray_pid"; _probe_stop "$probe_pid"; _probe_stop "$kwin_pid"' EXIT
    kwin_wayland --virtual --no-lockscreen --no-global-shortcuts --width 1280 --height 900 \
        --socket silere-tray-keys > "$scratch/kwin.log" 2>&1 &
    kwin_pid=$!
    for _ in $(seq 1 150); do [ -S "$XDG_RUNTIME_DIR/silere-tray-keys" ] && break; sleep 0.1; done
    [ -S "$XDG_RUNTIME_DIR/silere-tray-keys" ] || { cat "$scratch/kwin.log" >&2; exit 1; }
    export WAYLAND_DISPLAY=silere-tray-keys QT_QPA_PLATFORM=wayland SILERE_WATCH_FILES=0
    mkdir -p "$scratch/probe"
    _probe_project "$ROOT" "$ROOT/dev/probe-tray-keys.qml" "$scratch/probe"
    export SILERE_PROBE_SELF="$scratch/probe/probe-tray-keys.qml"
    ${SILERE_PROBE_WRAP:-} qs -p "$SILERE_PROBE_SELF" --no-color > "$scratch/probe.log" 2>&1 &
    probe_pid=$!
    python3 -I "$ROOT/dev/fake-tray-menu.py" "$scratch/events.log" > "$scratch/tray.log" 2>&1 &
    tray_pid=$!
    if ! _probe_wait "$scratch/probe.log" "$probe_pid" 'PROBE-TRAY-KEYS done' 900 0.1; then
        cat "$scratch/probe.log" "$scratch/tray.log" >&2
        echo "FAIL: the tray keyboard probe did not finish" >&2
        exit 1
    fi
    failed=0
    if grep -q 'PROBE-FAIL' "$scratch/probe.log"; then
        grep 'PROBE-FAIL' "$scratch/probe.log" | sed 's/^.*PROBE-FAIL tray keys :: /  /' >&2
        failed=1
    fi
    errors="$(_probe_errors "$scratch/probe.log")"
    [ -z "$errors" ] || { printf '%s\n' "$errors" | sed 's/^/  /' >&2; failed=1; }
    clicks="$(grep -c ' clicked$' "$scratch/events.log" 2>/dev/null || true)"
    if [ "$clicks" != 1 ] || ! grep -qx 'event 4 clicked' "$scratch/events.log"; then
        echo "  the menu activated $clicks entries, not Quit alone" >&2
        failed=1
    fi
    [ "$failed" = 0 ] || { echo "FAIL: a tray menu did not follow the keyboard" >&2; exit 1; }
    printf 'tray keyboard passed (%s)\n' "$(grep -oE '[0-9]+ checks' "$scratch/probe.log" | tail -1)"
    exit 0
fi

[ "$#" -eq 0 ] || { echo 'Usage: test-tray-keys.sh' >&2; exit 2; }
_probe_require_qs
for tool in kwin_wayland dbus-run-session python3; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'SKIP: the tray keyboard check needs %s\n' "$tool"; exit 0; }
done
python3 -I -c 'import dbus, gi' 2>/dev/null || { printf 'SKIP: the tray keyboard check needs python-dbus and PyGObject\n'; exit 0; }
# a Wayland socket path is capped at 108 bytes
scratch="$(mktemp -d /tmp/sk.XXXXXX)"
inner_pid=""
trap '_probe_stop "$inner_pid"; rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/config" "$scratch/state" "$scratch/data" "$scratch/cache" "$scratch/run"
chmod 0700 "$scratch/run"
XDG_CONFIG_HOME="$scratch/config" XDG_STATE_HOME="$scratch/state" XDG_DATA_HOME="$scratch/data" \
XDG_CACHE_HOME="$scratch/cache" XDG_RUNTIME_DIR="$scratch/run" LIBGL_ALWAYS_SOFTWARE=1 LC_ALL=C.UTF-8 \
    timeout 150 env -u XDG_SESSION_ID -u HYPRLAND_INSTANCE_SIGNATURE -u NIRI_SOCKET -u DISPLAY -u WAYLAND_DISPLAY \
    dbus-run-session --config-file="$ROOT/dev/probe-bus.conf" -- bash "$0" --inner "$scratch" &
inner_pid=$!
wait "$inner_pid"
