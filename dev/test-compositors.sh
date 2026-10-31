#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/dev/probe-lib.sh"

if [ "${1:-}" = --inner ]; then
    scratch="$2"; backend="$3"; benchmark="${4:-}"
    [[ "$XDG_CONFIG_HOME" = "$scratch/"* && -z "${XDG_SESSION_ID:-}" ]] || exit 1
    case "${DBUS_SESSION_BUS_ADDRESS:-}" in ''|*/run/user/*/bus*) exit 1 ;; esac
    parent_pid=""; child_pid=""; shell_pid=""
    trap '_probe_stop "$shell_pid"; _probe_stop "$child_pid"; _probe_stop "$parent_pid"' EXIT
    kwin_wayland --virtual --no-lockscreen --no-global-shortcuts --width 1280 --height 900 \
        --socket silere-test-parent > "$scratch/parent.log" 2>&1 &
    parent_pid=$!
    for _ in $(seq 1 150); do [ -S "$XDG_RUNTIME_DIR/silere-test-parent" ] && break; sleep 0.1; done
    [ -S "$XDG_RUNTIME_DIR/silere-test-parent" ] || { cat "$scratch/parent.log" >&2; exit 1; }
    export WAYLAND_DISPLAY=silere-test-parent QT_QPA_PLATFORM=wayland SILERE_WATCH_FILES=0
    if [ "$backend" = niri ]; then
        printf 'hotkey-overlay { skip-at-startup; }\n' > "$scratch/niri.kdl"
        niri --config "$scratch/niri.kdl" > "$scratch/child.log" 2>&1 &
        child_pid=$!
    elif [ "$backend" = hyprland ]; then
        # Lua configs arrived in 0.55 and 0.57 dropped hyprlang; a rejected config
        # still starts, but in emergency mode with none of the settings below
        hypr_version="$(Hyprland --version 2>/dev/null | sed -n 's/^Hyprland \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p' | head -n 1)"
        read -r hypr_major hypr_minor <<< "${hypr_version:-0 0}"
        if [ "$hypr_major" -gt 0 ] || [ "$hypr_minor" -ge 55 ]; then
            hypr_config="$scratch/hyprland.lua"
            cat > "$hypr_config" <<'EOF'
hl.monitor({ output = "", mode = "1280x900@60", position = "auto", scale = 1 })
hl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true } })
EOF
        else
            hypr_config="$scratch/hyprland.conf"
            cat > "$hypr_config" <<'EOF'
monitor = ,1280x900@60,auto,1
misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
}
EOF
        fi
        AQ_BACKEND=wayland Hyprland --config "$hypr_config" > "$scratch/child.log" 2>&1 &
        child_pid=$!
    fi
    if [ -n "$child_pid" ]; then
        child_socket=""
        for _ in $(seq 1 200); do
            child_socket="$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-*' -print -quit)"
            [ -z "$child_socket" ] || break
            kill -0 "$child_pid" 2>/dev/null || break
            sleep 0.1
        done
        [ -n "$child_socket" ] || { cat "$scratch/child.log" >&2; exit 1; }
        export WAYLAND_DISPLAY="${child_socket##*/}"
    fi
    if [ "$backend" = niri ]; then
        NIRI_SOCKET=""
        for _ in $(seq 1 100); do
            NIRI_SOCKET="$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'niri.*.sock' -print -quit)"
            [ -z "$NIRI_SOCKET" ] || break
            sleep 0.1
        done
        export NIRI_SOCKET
        [ -n "$NIRI_SOCKET" ] || { cat "$scratch/child.log" >&2; exit 1; }
    elif [ "$backend" = hyprland ]; then
        for _ in $(seq 1 100); do
            for instance in "$XDG_RUNTIME_DIR"/hypr/*; do
                [ -S "$instance/.socket.sock" ] || continue
                export HYPRLAND_INSTANCE_SIGNATURE="${instance##*/}"
                break
            done
            [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || break
            sleep 0.1
        done
        [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || { cat "$scratch/child.log" >&2; exit 1; }
    fi

    bash "$ROOT/dev/test-panels.sh" > "$scratch/panels.log" 2>&1 \
        || { cat "$scratch/panels.log" >&2; exit 1; }
    if grep -q '^SKIP' "$scratch/panels.log"; then cat "$scratch/panels.log" >&2; exit 1; fi
    ${SILERE_PROBE_WRAP:-} qs -p "$ROOT/shell.qml" --no-duplicate --no-color > "$scratch/shell.log" 2>&1 &
    shell_pid=$!
    ready=0
    for _ in $(seq 1 300); do
        if qs ipc -p "$ROOT/shell.qml" show 2>/dev/null | grep -q 'target menu'; then ready=1; break; fi
        kill -0 "$shell_pid" 2>/dev/null || break
        sleep 0.1
    done
    if [ "$ready" != 1 ]; then
        cat "$scratch/shell.log" >&2
        [ ! -s "$scratch/child.log" ] || tail -n 30 "$scratch/child.log" >&2
        exit 1
    fi
    if [ -n "$benchmark" ]; then
        mkdir -p "$benchmark"
        bash "$ROOT/scripts/bench.sh" 10 --json --label "$backend-development-cold" > "$benchmark/$backend-cold.json"
    fi
    test "$(qs ipc -p "$ROOT/shell.qml" call menu tab 0)" = ok
    sleep 0.5
    qs ipc -p "$ROOT/shell.qml" call menu close > /dev/null
    if [ -n "$benchmark" ]; then
        bash "$ROOT/scripts/bench.sh" 10 --warm --json --label "$backend-development-warm" > "$benchmark/$backend-warm.json"
        for _ in $(seq 1 30); do
            qs ipc -p "$ROOT/shell.qml" call menu tab 0 >/dev/null
            sleep 0.1
            qs ipc -p "$ROOT/shell.qml" call menu close >/dev/null
            sleep 0.1
        done
        sleep 2
        bash "$ROOT/scripts/bench.sh" 10 --json --label "$backend-after-30-menu-cycles" > "$benchmark/$backend-cycles.json"
    fi
    errors="$(_probe_errors "$scratch/shell.log")"
    [ -z "$errors" ] || { printf '%s\n' "$errors" >&2; exit 1; }
    printf 'compositor integration passed (%s; panels, popup interactions, startup, menu IPC)\n' "$backend"
    exit 0
fi

backend="${1:-kwin}"
case "$backend" in kwin|hyprland|niri) ;; *) echo 'Usage: test-compositors.sh kwin|hyprland|niri [--bench OUTPUT_DIR]' >&2; exit 2 ;; esac
benchmark=""
if [ "${2:-}" = --bench ] && [ "$#" -eq 3 ]; then
    mkdir -p -- "$3"
    benchmark="$(cd "$3" && pwd)"
elif [ "$#" -gt 1 ]; then exit 2; fi
for tool in qs kwin_wayland dbus-run-session; do
    command -v "$tool" >/dev/null 2>&1 || { echo "FAIL: integration requires $tool" >&2; exit 1; }
done
case "$backend" in hyprland) command -v Hyprland >/dev/null ;; niri) command -v niri >/dev/null ;; esac
# Hyprland cannot start without a render node, even nested; a hosted runner has none
if [ "$backend" = hyprland ] && ! compgen -G '/dev/dri/renderD*' >/dev/null; then
    printf 'SKIP: Hyprland integration needs a GPU render node\n'
    exit 0
fi
# Hyprland appends its long instance signature to this path before binding a Unix socket.
scratch="$(mktemp -d /tmp/sc.XXXXXX)"
inner_pid=""
trap '_probe_stop "$inner_pid"; rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/config" "$scratch/state" "$scratch/data" "$scratch/cache" "$scratch/run"
chmod 0700 "$scratch/run"
cat > "$scratch/bus.conf" <<'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
 <type>session</type><listen>unix:tmpdir=/tmp</listen><auth>EXTERNAL</auth>
 <policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
</busconfig>
EOF
XDG_CONFIG_HOME="$scratch/config" XDG_STATE_HOME="$scratch/state" XDG_DATA_HOME="$scratch/data" \
XDG_CACHE_HOME="$scratch/cache" XDG_RUNTIME_DIR="$scratch/run" LIBGL_ALWAYS_SOFTWARE=1 LC_ALL=C.UTF-8 \
    timeout 150 env -u XDG_SESSION_ID -u HYPRLAND_INSTANCE_SIGNATURE -u NIRI_SOCKET -u DISPLAY -u WAYLAND_DISPLAY \
    dbus-run-session --config-file="$scratch/bus.conf" -- bash "$0" --inner "$scratch" "$backend" "$benchmark" &
inner_pid=$!
wait "$inner_pid"
