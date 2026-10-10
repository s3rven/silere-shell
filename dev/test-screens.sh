#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/dev/probe-lib.sh"

# only a real compositor removes an output: a nested KWin with two virtual outputs switches one off under open surfaces

if [ "${1:-}" = --inner ]; then
    TMP="$2"
    # kwin follows the real logind session and writes into XDG_CONFIG_HOME; both once leaked into a live session
    case "${DBUS_SESSION_BUS_ADDRESS:-}" in
        ""|*/run/user/*/bus*) echo "FAIL: refusing to run on the real session bus" >&2; exit 1 ;;
    esac
    case "${XDG_CONFIG_HOME:-}" in
        "$TMP"/*) ;;
        *) echo "FAIL: refusing to run with a shared XDG_CONFIG_HOME" >&2; exit 1 ;;
    esac
    [ -z "${XDG_SESSION_ID:-}" ] || { echo "FAIL: refusing to run inside a login session" >&2; exit 1; }

    log="$TMP/qs.log"
    kwin_wayland --virtual --no-lockscreen --no-global-shortcuts --output-count 2 \
        --width 1280 --height 800 --socket silere-screens >"$TMP/kwin.log" 2>&1 &
    kwin=$!
    qs_pid=""
    trap '_probe_stop "$qs_pid"; _probe_stop "$kwin"' EXIT
    for _ in $(seq 1 100); do [ -S "$XDG_RUNTIME_DIR/silere-screens" ] && break; sleep 0.1; done
    if [ ! -S "$XDG_RUNTIME_DIR/silere-screens" ]; then
        echo "SKIP: nested KWin did not start: $(tail -n 1 "$TMP/kwin.log")" >&2
        exit 0
    fi
    # under check.sh's LC_ALL=C qs prints a locale warning into every ipc reply
    export LC_ALL=C.UTF-8 WAYLAND_DISPLAY=silere-screens QT_QPA_PLATFORM=wayland KSCREEN_BACKEND_INPROCESS=1 SILERE_WATCH_FILES=0

    qs -p "$TMP/copy/shell.qml" --no-duplicate >"$log" 2>&1 &
    qs_pid=$!
    state() { qs ipc -p "$TMP/copy/shell.qml" call screenprobe state 2>/dev/null || true; }
    for _ in $(seq 1 80); do
        qs ipc -p "$TMP/copy/shell.qml" show 2>/dev/null | grep -q 'target screenprobe' && break
        kill -0 "$qs_pid" 2>/dev/null || break
        sleep 0.1
    done
    first="$(state)"
    case "$first" in
        "screens=2 "*) ;;
        *) cat "$log" >&2; echo "FAIL: the shell did not start with two screens (got '$first')" >&2; exit 1 ;;
    esac
    names="$(qs ipc -p "$TMP/copy/shell.qml" call screenprobe names)"
    one="${names%,*}"
    two="${names#*,}"

    checks=0
    failed=0
    expect() { # $1 = label, $2 = state
        local got=""
        for _ in $(seq 1 40); do
            got="$(state)"
            [ "$got" = "$2" ] && { checks=$((checks + 1)); return 0; }
            sleep 0.1
        done
        echo "PROBE-FAIL $1: expected '$2', got '$got'"
        failed=1
    }

    notify-send -t 0 "Screen probe" "stays until dismissed"
    qs ipc -p "$TMP/copy/shell.qml" call quickActions keepAwake >/dev/null
    qs ipc -p "$TMP/copy/shell.qml" call menu toggle >/dev/null
    expect "surfaces open on the first screen" "screens=2 notif=$one menu=$one keepawake=$one"

    kscreen-doctor "output.$one.disable" >/dev/null 2>&1
    expect "surfaces move when their screen goes away" "screens=1 notif=$two menu=$two keepawake=$two"

    kscreen-doctor "output.$one.enable" >/dev/null 2>&1
    sleep 1
    expect "a returning screen does not pull surfaces back" "screens=2 notif=$two menu=$two keepawake=$two"

    qs ipc -p "$TMP/copy/shell.qml" call quickActions keepAwake >/dev/null
    expect "keep awake releases its surface" "screens=2 notif=$two menu=$two keepawake="

    errs="$(_probe_errors "$log")"
    if [ -n "$errs" ]; then
        printf '%s\n' "$errs" | sed 's/^/  /' >&2
        failed=1
    fi
    if [ "$failed" -ne 0 ]; then
        echo "FAIL: a surface was lost when its screen went away" >&2
        exit 1
    fi
    echo "screen probe passed ($checks checks)"
    exit 0
fi

trap 'exit 130' INT TERM
_probe_require_qs
for tool in kwin_wayland kscreen-doctor dbus-run-session notify-send; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "SKIP: $tool not installed; screen removal needs a nested KWin" >&2
        exit 0
    fi
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/silere-screens.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/copy" "$TMP/config" "$TMP/data" "$TMP/state" "$TMP/cache" "$TMP/run"
chmod 700 "$TMP/run"

for entry in "$ROOT"/*; do
    [ "${entry##*/}" = shell.qml ] || ln -s "$entry" "$TMP/copy/${entry##*/}"
done
cat >"$TMP/probe.qml" <<'EOF'
    IpcHandler {
        target: "screenprobe"
        function names(): string { return Quickshell.screens.map(s => s.name).join(",") }
        function state(): string {
            const n = s => s ? s.name : "none"
            return "screens=" + Quickshell.screens.length
                + " notif=" + n(_notificationPopup.latchedScreen)
                + " menu=" + n(_menuPopup.latchedScreen)
                + " keepawake=" + _keepAwakeSurfaces.instances
                    .map(w => n(w.screen) + (w.visible ? "" : ":hidden")).join(",")
        }
    }
EOF
awk -v probe="$TMP/probe.qml" '
    { print }
    /^import Quickshell$/ && !io { print "import Quickshell.Io"; io = 1 }
    /^    id: root$/ && !hooked { while ((getline line < probe) > 0) print line; hooked = 1 }
' "$ROOT/shell.qml" >"$TMP/copy/shell.qml" </dev/null
if [ "$(grep -c 'target: "screenprobe"\|^import Quickshell.Io$' "$TMP/copy/shell.qml")" -lt 2 ]; then
    echo "FAIL: the screen probe could not be hooked into shell.qml" >&2
    exit 1
fi

# no servicedir: nothing is activated on the private bus, so no portal or locker joins it
cat >"$TMP/bus.conf" <<'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOF

XDG_CONFIG_HOME="$TMP/config" XDG_DATA_HOME="$TMP/data" XDG_STATE_HOME="$TMP/state" \
XDG_CACHE_HOME="$TMP/cache" XDG_RUNTIME_DIR="$TMP/run" \
    timeout 90 env -u XDG_SESSION_ID -u HYPRLAND_INSTANCE_SIGNATURE -u NIRI_SOCKET -u DISPLAY -u WAYLAND_DISPLAY \
    dbus-run-session --config-file="$TMP/bus.conf" -- bash "$0" --inner "$TMP" &
inner=$!
# timeout signals its whole process group, so stopping it takes kwin and the shell down too
trap '_probe_stop "$inner"; rm -rf "$TMP"' EXIT
wait "$inner"
