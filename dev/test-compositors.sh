#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/dev/probe-lib.sh"

if [ "${1:-}" = --inner ]; then
    scratch="$2"; backend="$3"; benchmark="${4:-}"
    [[ "$XDG_CONFIG_HOME" = "$scratch/"* && -z "${XDG_SESSION_ID:-}" ]] || exit 1
    case "${DBUS_SESSION_BUS_ADDRESS:-}" in ''|*/run/user/*/bus*) exit 1 ;; esac
    parent_pid=""; child_pid=""; shell_pid=""; monitors_pid=""
    trap '_probe_stop "$monitors_pid"; _probe_stop "$shell_pid"; _probe_stop "$child_pid"; _probe_stop "$parent_pid"' EXIT
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
hl.workspace_rule({ workspace = "2", default_name = "two" })
EOF
        else
            hypr_config="$scratch/hyprland.conf"
            cat > "$hypr_config" <<'EOF'
monitor = ,1280x900@60,auto,1
workspace = 2, defaultName:two
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
    # without a render node a nested niri stops answering layer surfaces, so the shell never
    # finishes starting; the surfaces above still built and their behavior still ran
    if [ "$backend" = niri ] && ! compgen -G '/dev/dri/renderD*' >/dev/null; then
        printf 'compositor integration passed (niri; panels, popup interactions)\n'
        printf 'SKIP: full niri startup needs a GPU render node\n'
        exit 0
    fi
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
    # Read-only and rejected calls verify the audio target without touching host audio.
    audio_status="$(qs ipc -p "$ROOT/shell.qml" call audio status)"
    case "$audio_status" in
        *'"output":{'*'"input":{'*) ;;
        *) printf 'FAIL: audio IPC returned no device state: %s\n' "$audio_status" >&2; exit 1 ;;
    esac
    test "$(qs ipc -p "$ROOT/shell.qml" call audio setVolume 101)" = 'error: volume must be between 0 and 100'
    test "$(qs ipc -p "$ROOT/shell.qml" call audio setMicVolume 101)" = 'error: volume must be between 0 and 100'
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
    checked="panels, popup interactions, startup, menu/audio IPC"
    if [ "$backend" = hyprland ]; then
        # a special workspace shown before the shell starts is still marked, and a second output showing a
        # named numbered workspace keeps it active as focus moves there and back (dev/probe-hypr-monitors.qml);
        # the shell above also puts a bar on the new output
        first_output="$(hyprctl monitors | sed -n 's/^Monitor \([^ ]*\) .*/\1/p' | head -n 1)"
        focus() { # $1 = monitor, $2 = optional workspace id
            if [[ "$hypr_config" = *.lua ]]; then
                hyprctl dispatch "hl.dsp.focus({ monitor = \"$1\" })" > /dev/null
                [ -z "${2:-}" ] || hyprctl dispatch "hl.dsp.focus({ workspace = $2 })" > /dev/null
            else
                hyprctl dispatch focusmonitor "$1" > /dev/null
                [ -z "${2:-}" ] || hyprctl dispatch workspace "$2" > /dev/null
            fi
        }
        step() { # $1 = phase name; the refresh behind focusedmon needs a moment to land
            sleep 0.6
            printf '%s\n' "$1" > "$scratch/phase"
            for _ in $(seq 1 50); do grep -q "PROBE-MONITORS $1 " "$scratch/monitors.log" && return 0; sleep 0.1; done
            return 1
        }
        toggle_special() {
            if [[ "$hypr_config" = *.lua ]]; then hyprctl dispatch 'hl.dsp.workspace.toggle_special("magic")' > /dev/null
            else hyprctl dispatch togglespecialworkspace magic > /dev/null
            fi
        }
        toggle_special
        mkdir -p "$scratch/monitors"
        _probe_project "$ROOT" "$ROOT/dev/probe-hypr-monitors.qml" "$scratch/monitors"
        printf 'start\n' > "$scratch/phase"
        SILERE_PROBE_PHASE="$scratch/phase" qs -p "$scratch/monitors/probe-hypr-monitors.qml" --no-color \
            > "$scratch/monitors.log" 2>&1 &
        monitors_pid=$!
        for _ in $(seq 1 100); do grep -q 'PROBE-MONITORS start' "$scratch/monitors.log" && break; sleep 0.1; done
        step special-before-start
        if ! grep -q "PROBE-MONITORS special-before-start .*special=$first_output\$" "$scratch/monitors.log"; then
            printf 'FAIL: a special workspace shown before the shell started is not marked\n' >&2
            grep 'PROBE-MONITORS' "$scratch/monitors.log" >&2 || cat "$scratch/monitors.log" >&2
            exit 1
        fi
        toggle_special
        step special-closed
        grep -q "PROBE-MONITORS special-closed .*special=\$" "$scratch/monitors.log" \
            || { printf 'FAIL: closing the special workspace left it marked\n' >&2; exit 1; }
        hyprctl output create headless SILERE-2 > /dev/null
        focus SILERE-2 2; step second
        focus "$first_output"; step first
        focus SILERE-2; step second-again
        for phase in second first second-again; do
            grep -q "PROBE-MONITORS $phase .*SILERE-2=two" "$scratch/monitors.log" && continue
            printf 'FAIL: the second monitor lost its named workspace at "%s"\n' "$phase" >&2
            grep 'PROBE-MONITORS' "$scratch/monitors.log" >&2 || cat "$scratch/monitors.log" >&2
            exit 1
        done
        errors="$(_probe_errors "$scratch/monitors.log")"
        [ -z "$errors" ] || { printf '%s\n' "$errors" >&2; exit 1; }
        checked="$checked, a special workspace open at start, a second monitor's named workspace"
    fi
    errors="$(_probe_errors "$scratch/shell.log")"
    [ -z "$errors" ] || { printf '%s\n' "$errors" >&2; exit 1; }
    printf 'compositor integration passed (%s; %s)\n' "$backend" "$checked"
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
case "$backend" in hyprland) need=Hyprland ;; niri) need=niri ;; *) need="" ;; esac
[ -z "$need" ] || command -v "$need" >/dev/null 2>&1 || { echo "FAIL: integration requires $need" >&2; exit 1; }
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
