#!/usr/bin/env bash
# Whole-shell measurements in a private nested session; docs/performance.md says what each one answers.
#   dev/bench-lab.sh startup  [--arm NAME=DIR ...] [--n 20]    bar and first menu open, memory cold and warm
#   dev/bench-lab.sh latency  [--arm NAME=DIR ...] [--n 12]    every panel's first and later opens
#   dev/bench-lab.sh cycles   [--arm NAME=DIR ...] [--cycles 50]  whether memory settles over repeated opens
#   dev/bench-lab.sh settings [--arm NAME=DIR]     [--n 10]    what each optional service setting saves and costs
#   dev/bench-lab.sh soak     [--arm NAME=DIR]     [--hours 6] [--idle]  memory over a long session
# Also: --settings FILE copies a settings.json in, --out FILE keeps the raw results. Run one at a time on a quiet machine
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for tool in quickshell qs kwin_wayland Hyprland pipewire wireplumber wpctl pw-cli dbus-run-session setsid python3; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'bench-lab needs %s\n' "$tool" >&2; exit 1; }
done
compgen -G '/dev/dri/renderD*' >/dev/null || { printf 'bench-lab needs a GPU render node\n' >&2; exit 1; }

# short and under /tmp: Hyprland appends its long instance signature to this path to bind a socket
scratch="$(mktemp -d /tmp/sb.XXXXXX)"
mkdir -p "$scratch/config" "$scratch/state" "$scratch/data" "$scratch/cache" "$scratch/run"
chmod 0700 "$scratch/run"
lab_pid=""
cleanup() {
    if [ -n "$lab_pid" ]; then
        kill -TERM -- "-$lab_pid" 2>/dev/null || true
        sleep 1
        kill -KILL -- "-$lab_pid" 2>/dev/null || true
    fi
    rm -rf -- "$scratch"
}
trap cleanup EXIT
trap 'exit 143' INT TERM

# a group of its own: signalling dbus-run-session alone would leave the lab and its bus running
env -u XDG_SESSION_ID -u HYPRLAND_INSTANCE_SIGNATURE -u NIRI_SOCKET -u DISPLAY -u WAYLAND_DISPLAY -u PIPEWIRE_REMOTE \
    XDG_CONFIG_HOME="$scratch/config" XDG_STATE_HOME="$scratch/state" XDG_DATA_HOME="$scratch/data" \
    XDG_CACHE_HOME="$scratch/cache" XDG_RUNTIME_DIR="$scratch/run" SILERE_BENCH_LAB="$scratch/run" \
    SILERE_SANDBOX=1 PYTHONDONTWRITEBYTECODE=1 \
    setsid dbus-run-session --config-file="$ROOT/dev/probe-bus.conf" -- python3 "$ROOT/dev/bench-lab.py" "$@" &
lab_pid=$!
wait "$lab_pid"
