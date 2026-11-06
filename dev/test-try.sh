#!/usr/bin/env bash
# silere try has one promise: the whole shell runs, nothing outside it changes, and closing it leaves nothing behind.
# It runs here inside a virtual kwin, so no window reaches the desktop this test runs on
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/dev/probe-lib.sh"

for tool in qs kwin_wayland dbus-run-session setsid; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'SKIP: the preview test needs %s\n' "$tool"; exit 0; }
done
command -v Hyprland >/dev/null 2>&1 || command -v niri >/dev/null 2>&1 \
    || { printf 'SKIP: the preview test needs Hyprland or niri\n'; exit 0; }
compgen -G '/dev/dri/renderD*' >/dev/null || { printf 'SKIP: the preview test needs a GPU render node\n'; exit 0; }

if [ "${1:-}" = --inner ]; then
    scratch="$2"
    parent_pid=""; try_pid=""; session=""
    finish() {
        _probe_stop "$try_pid"
        _probe_stop "$parent_pid"
    }
    trap finish EXIT
    fail() {
        printf 'FAIL: %s\n' "$*" >&2
        tail -n 12 "$scratch/try.log" >&2 2>/dev/null || true
        [ -z "$session" ] || tail -n 12 "$session/shell.log" >&2 2>/dev/null || true
        exit 1
    }
    in_session() {
        local socket
        socket="$(find "$session/run" -maxdepth 1 -type s -name 'wayland-*' -print -quit)"
        env WAYLAND_DISPLAY="${socket##*/}" XDG_RUNTIME_DIR="$session/run" XDG_CONFIG_HOME="$session/config" \
            XDG_STATE_HOME="$session/state" XDG_CACHE_HOME="$session/cache" DBUS_SESSION_BUS_ADDRESS="" "$@"
    }
    fingerprint() { (cd "$scratch/home" && find . -type f -print0 | sort -z | xargs -0 sha256sum); }

    kwin_wayland --virtual --no-lockscreen --no-global-shortcuts --width 1700 --height 1100 --socket try-parent \
        > "$scratch/parent.log" 2>&1 &
    parent_pid=$!
    for _ in $(seq 1 150); do [ -S "$XDG_RUNTIME_DIR/try-parent" ] && break; sleep 0.1; done
    [ -S "$XDG_RUNTIME_DIR/try-parent" ] || fail "the virtual desktop did not start"

    # what this "desktop" already has, which the preview must leave alone
    mkdir -p "$scratch/home/config/silere-shell" "$scratch/home/state/silere-shell" "$scratch/home/cache/silere-shell"
    printf '{\n  "__version": 2,\n  "barHeight": 40\n}\n' > "$scratch/home/config/silere-shell/settings.json"
    printf '{"history":[]}\n' > "$scratch/home/state/silere-shell/notifications.json"
    before="$(fingerprint)"

    start_preview() {
        : > "$scratch/try.log"
        XDG_CONFIG_HOME="$scratch/home/config" XDG_STATE_HOME="$scratch/home/state" XDG_CACHE_HOME="$scratch/home/cache" \
            WAYLAND_DISPLAY=try-parent bash "$ROOT/scripts/silere" try > "$scratch/try.log" 2>&1 &
        try_pid=$!
        session=""
        for _ in $(seq 1 100); do
            session="$(sed -n 's/^Session files: //p' "$scratch/try.log")"
            [ -n "$session" ] && break
            kill -0 "$try_pid" 2>/dev/null || fail "the preview exited at once"
            sleep 0.1
        done
        [ -n "$session" ] || fail "the preview did not say where its session is"
        for _ in $(seq 1 300); do
            grep -q 'Silere is running in a window' "$scratch/try.log" && return 0
            kill -0 "$try_pid" 2>/dev/null || fail "the preview exited before the shell was up"
            sleep 0.1
        done
        fail "the shell did not come up in the preview"
    }
    instance_env() {
        local instance
        for instance in "$session"/run/hypr/*; do [ -S "$instance/.socket.sock" ] && printf '%s\n' "${instance##*/}"; done
    }
    assert_gone() { # $1 = what ended it
        for _ in $(seq 1 100); do kill -0 "$try_pid" 2>/dev/null || break; sleep 0.1; done
        kill -0 "$try_pid" 2>/dev/null && fail "the preview kept running after $1"
        wait "$try_pid" 2>/dev/null || true
        try_pid=""
        [ ! -e "$session" ] || fail "the preview left its session files behind after $1"
        # a group of its own, so anything of it still running names this session's path
        local leftovers
        leftovers="$(ps -eo pid,args | grep -F "$session" | grep -v grep || true)"
        [ -z "$leftovers" ] || fail "the preview left processes behind after $1: $leftovers"
        [ "$before" = "$(fingerprint)" ] || fail "the preview changed the desktop's own files"
    }

    start_preview
    answer="$(in_session qs ipc -p "$ROOT/shell.qml" call menu tab 0 2>&1 || true)"
    [ "$answer" = ok ] || fail "the shell in the preview did not answer: $answer"
    sig="$(instance_env)"
    if [ -n "$sig" ]; then
        layers="$(in_session HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl layers 2>/dev/null || true)"
        case "$layers" in
            *silere-bar*) ;;
            *) fail "the bar did not map in the preview" ;;
        esac
    fi
    [ -s "$session/config/silere-shell/settings.json" ] || [ -d "$session/config/silere-shell" ] \
        || fail "the preview did not use its own settings"
    in_session qs ipc -p "$ROOT/shell.qml" call settings set barHeight 34 >/dev/null 2>&1 || true
    sleep 0.5
    [ "$before" = "$(fingerprint)" ] || fail "changing a setting in the preview reached the desktop's own settings"
    kill -TERM "$try_pid"
    assert_gone "being stopped"

    if [ -n "$sig" ]; then
        # closing the window: the nested Hyprland stays up on a fallback output, and the preview has to notice
        start_preview
        sig="$(instance_env)"
        monitors="$(in_session HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl monitors 2>/dev/null || true)"
        output="$(sed -n 's/^Monitor \([^ ]*\) .*/\1/p' <<< "$monitors" | head -n 1)"
        in_session HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl eval "hl.monitor({ output = \"$output\", disabled = true })" > /dev/null 2>&1 \
            || fail "could not take the nested output away"
        assert_gone "its window went away"
    fi

    printf 'preview passed (the shell runs, stays private, and leaves nothing behind)\n'
    exit 0
fi

scratch="$(mktemp -d /tmp/st.XXXXXX)"
inner_pid=""
trap '_probe_stop "$inner_pid"; rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/run"
chmod 0700 "$scratch/run"
env -u XDG_SESSION_ID -u HYPRLAND_INSTANCE_SIGNATURE -u NIRI_SOCKET -u DISPLAY -u WAYLAND_DISPLAY \
    XDG_RUNTIME_DIR="$scratch/run" XDG_CONFIG_HOME="$scratch/parent-config" XDG_CACHE_HOME="$scratch/parent-cache" \
    XDG_STATE_HOME="$scratch/parent-state" LC_ALL=C.UTF-8 \
    timeout 180 dbus-run-session --config-file="$ROOT/dev/probe-bus.conf" -- bash "$0" --inner "$scratch" &
inner_pid=$!
wait "$inner_pid"
