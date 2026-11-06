#!/usr/bin/env bash
# What a new user does, end to end: Hyprland's own example config, the real installer, then a login. The bar has to come up
# with nobody starting it and the installed shortcut has to open the menu. A virtual kwin hosts it, on a throwaway home
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/dev/probe-lib.sh"

for tool in qs Hyprland hyprctl kwin_wayland dbus-run-session setsid; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'SKIP: the first login test needs %s\n' "$tool"; exit 0; }
done
compgen -G '/dev/dri/renderD*' >/dev/null || { printf 'SKIP: the first login test needs a GPU render node\n'; exit 0; }
example=/usr/share/hypr/hyprland.lua
[ -f "$example" ] || { printf 'SKIP: this Hyprland ships no example Lua config\n'; exit 0; }

if [ "${1:-}" = --inner ]; then
    scratch="$2"
    parent_pid=""; hypr_pid=""; home_env=(); installed=""
    finish() {
        # the compositor starts the shell in a session of its own, so stopping the test's group does not reach it
        [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || "${home_env[@]}" WAYLAND_DISPLAY="${nested:-}" \
            qs kill -p "$installed/shell.qml" >/dev/null 2>&1 || true
        _probe_stop "$hypr_pid"
        _probe_stop "$parent_pid"
    }
    trap finish EXIT
    fail() {
        printf 'FAIL: %s\n' "$*" >&2
        for log in install.log hypr.log; do
            [ ! -s "$scratch/$log" ] || { printf -- '--- %s\n' "$log" >&2; tail -n 25 "$scratch/$log" | cut -c1-200 >&2; }
        done
        exit 1
    }
    home="$scratch/home"
    stubs="$scratch/stubs"
    mkdir -p "$home/.config/hypr" "$stubs"
    # the installer offers fonts and packages; none of that may reach this machine
    for tool in systemctl sudo pacman yay paru; do
        printf '#!/bin/sh\nexit 1\n' > "$stubs/$tool"
        chmod +x "$stubs/$tool"
    done
    cp "$example" "$home/.config/hypr/hyprland.lua"
    # a nested output, and no terminal to wait for; the rest of the file is exactly what Hyprland ships
    printf '\nhl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true, disable_watchdog_warning = true } })\n' \
        >> "$home/.config/hypr/hyprland.lua"
    # already checked out where the installer would clone it, so this tree is what gets tested and nothing is downloaded.
    # The release step needs the network and has suites of its own, so this copy's updater answers that all is current
    installed="$home/.config/silere-shell"
    mkdir -p "$installed"
    (cd "$ROOT" && tar --exclude=.git --exclude=TODO.md -cf - .) | tar -x -C "$installed"
    printf '#!/bin/sh\nexit 0\n' > "$installed/scripts/update.sh"
    git -C "$installed" init -q
    git -C "$installed" add -A
    git -C "$installed" -c user.name=lab -c user.email=lab@example.invalid -c commit.gpgsign=false commit -qm checkout

    # an array, not a function: a function backgrounded with & is a subshell, and stopping that leaves its child running
    home_env=(env HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" XDG_CACHE_HOME="$home/.cache"
        XDG_DATA_HOME="$home/.local/share" PATH="$stubs:$home/.local/bin:$PATH")
    "${home_env[@]}" bash "$installed/scripts/install.sh" --yes --no-start </dev/null > "$scratch/install.log" 2>&1 \
        || fail "the installer failed"
    grep -qF -- '-- silere-shell begin' "$home/.config/hypr/hyprland.lua" \
        || fail "the installer set up no autostart on a stock config"
    grep -qF -- '-- silere-shell keybind begin' "$home/.config/hypr/hyprland.lua" \
        || fail "the installer set up no menu shortcut on a stock config"
    env -u LC_ALL Hyprland --verify-config --config "$home/.config/hypr/hyprland.lua" >/dev/null 2>&1 \
        || fail "the installer left a config Hyprland rejects"
    cp "$home/.config/hypr/hyprland.lua" "$scratch/after-install.lua"
    "${home_env[@]}" bash "$installed/scripts/install.sh" --yes --no-start </dev/null >> "$scratch/install.log" 2>&1 \
        || fail "running the installer again failed"
    cmp -s "$home/.config/hypr/hyprland.lua" "$scratch/after-install.lua" \
        || fail "running the installer again changed the config"

    kwin_wayland --virtual --no-lockscreen --no-global-shortcuts --width 1280 --height 900 --socket login-parent \
        > "$scratch/parent.log" 2>&1 &
    parent_pid=$!
    for _ in $(seq 1 150); do [ -S "$XDG_RUNTIME_DIR/login-parent" ] && break; sleep 0.1; done
    [ -S "$XDG_RUNTIME_DIR/login-parent" ] || fail "the virtual desktop did not start"

    "${home_env[@]}" WAYLAND_DISPLAY=login-parent AQ_BACKEND=wayland SILERE_WATCH_FILES=0 SILERE_STARTUP_GRACE=1 \
        Hyprland --config "$home/.config/hypr/hyprland.lua" > "$scratch/hypr.log" 2>&1 &
    hypr_pid=$!
    export HYPRLAND_INSTANCE_SIGNATURE=""
    for _ in $(seq 1 100); do
        for instance in "$XDG_RUNTIME_DIR"/hypr/*; do
            [ -S "$instance/.socket.sock" ] && HYPRLAND_INSTANCE_SIGNATURE="${instance##*/}"
        done
        [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ] || break
        kill -0 "$hypr_pid" 2>/dev/null || fail "Hyprland exited"
        sleep 0.1
    done
    [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] || fail "Hyprland did not start"

    # nothing here starts the shell: this is the login
    has_layer() {
        case "$(hyprctl layers 2>/dev/null || true)" in *"namespace: $1"*) return 0 ;; *) return 1 ;; esac
    }
    up=0
    for _ in $(seq 1 200); do
        has_layer silere-bar && { up=1; break; }
        sleep 0.1
    done
    [ "$up" = 1 ] || fail "the bar did not come up at login"

    # a login has no window to send a key to, so the bind is checked as registered and its command is run as written
    nested=""
    for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
        [ -S "$socket" ] && nested="${socket##*/}"
    done
    binds="$(hyprctl binds 2>/dev/null || true)"
    case "$binds" in
        *"key: slash"*) ;;
        *) printf '%s\n' "$binds" | head -n 12 >&2; fail "the installed menu shortcut is not bound" ;;
    esac
    bind_cmd="$(sed -n 's/.*hl\.dsp\.exec_cmd("\(qs ipc .*call menu toggle\)").*/\1/p' "$home/.config/hypr/hyprland.lua" | head -n 1)"
    [ -n "$bind_cmd" ] || fail "could not read the installed shortcut's command"
    "${home_env[@]}" WAYLAND_DISPLAY="$nested" sh -c "$bind_cmd" > /dev/null 2>&1 || true
    opened=0
    for _ in $(seq 1 50); do
        has_layer silere-menu && { opened=1; break; }
        sleep 0.1
    done
    [ "$opened" = 1 ] || fail "the installed menu shortcut's command did not open the menu"

    # and it all comes back out
    "${home_env[@]}" SILERE_ASSUME_YES=1 bash "$installed/scripts/uninstall.sh" </dev/null >> "$scratch/install.log" 2>&1 \
        || fail "uninstall failed"
    if grep -qF 'silere-shell' "$home/.config/hypr/hyprland.lua"; then
        fail "uninstall left Silere in the Hyprland config"
    fi
    printf 'first login passed (stock Hyprland config: autostart, shortcut, a clean second run and a clean uninstall)\n'
    exit 0
fi

scratch="$(mktemp -d /tmp/sf.XXXXXX)"
inner_pid=""
trap '_probe_stop "$inner_pid"; rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/run"
chmod 0700 "$scratch/run"
env -u XDG_SESSION_ID -u HYPRLAND_INSTANCE_SIGNATURE -u NIRI_SOCKET -u DISPLAY -u WAYLAND_DISPLAY \
    XDG_RUNTIME_DIR="$scratch/run" XDG_CONFIG_HOME="$scratch/parent-config" XDG_CACHE_HOME="$scratch/parent-cache" \
    XDG_STATE_HOME="$scratch/parent-state" LC_ALL=C.UTF-8 SILERE_SANDBOX=1 \
    timeout 150 dbus-run-session --config-file="$ROOT/dev/probe-bus.conf" -- bash "$0" --inner "$scratch" &
inner_pid=$!
wait "$inner_pid"
