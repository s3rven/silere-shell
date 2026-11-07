#!/usr/bin/env bash
# The whole shell in a window, for someone deciding whether to switch: a nested compositor on a private bus and private
# config, state, cache and runtime dirs, so the bar, notifications and settings already on this desktop are not touched.
# Closing the window removes all of it. Sound, network and Bluetooth stay real, so its controls show real things
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/ui.sh"

_die() {
    printf '%ssilere:%s %s\n' "$ERED" "$ER" "$*" >&2
    exit 1
}

_stop() { # $1 = pid
    [ -n "${1:-}" ] || return 0
    kill -0 "$1" 2>/dev/null || return 0
    kill "$1" 2>/dev/null || true
    local _
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$1" 2>/dev/null || return 0
        sleep 0.1
    done
    kill -KILL "$1" 2>/dev/null || true
}

_terminal() {
    local candidate
    for candidate in "${TERMINAL:-}" foot kitty alacritty ghostty wezterm konsole gnome-terminal xterm; do
        [ -n "$candidate" ] && command -v "$candidate" >/dev/null 2>&1 && { printf '%s\n' "$candidate"; return 0; }
    done
    printf 'true\n'
}

# a checkout path may hold quotes or backslashes: one shell word, and a double-quoted Lua or KDL string
_sh_word() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
_quoted_text() { local s="${1//\\/\\\\}"; printf '"%s"' "${s//\"/\\\"}"; }

# Lua configs arrived in 0.55 and 0.57 dropped hyprlang; a rejected config still starts, in emergency mode
_write_hyprland_config() { # $1 = scratch, $2 = terminal; prints the path
    local version major minor toggle n
    version="$(Hyprland --version 2>/dev/null | sed -n 's/^Hyprland \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p' | head -n 1)"
    read -r major minor <<< "${version:-0 0}"
    toggle="qs ipc -p $(_sh_word "$ROOT/shell.qml") call menu toggle"
    if [ "$major" -gt 0 ] || [ "$minor" -ge 55 ]; then
        {
            printf 'hl.monitor({ output = "", mode = "1600x1000@60", position = "auto", scale = 1 })\n'
            printf 'hl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true, disable_watchdog_warning = true } })\n'
            for n in 1 2 3 4 5; do
                printf 'hl.bind("ALT + %s", hl.dsp.focus({ workspace = %s }))\n' "$n" "$n"
            done
            printf 'hl.bind("ALT + Return", hl.dsp.exec_cmd(%s))\n' "$(_quoted_text "$2")"
            printf 'hl.bind("ALT + Q", hl.dsp.window.close())\n'
            printf 'hl.bind("ALT + slash", hl.dsp.exec_cmd(%s))\n' "$(_quoted_text "$toggle")"
        } > "$1/hyprland.lua"
        printf '%s/hyprland.lua\n' "$1"
    else
        {
            printf 'monitor = ,1600x1000@60,auto,1\n'
            printf 'misc {\n    disable_hyprland_logo = true\n    disable_splash_rendering = true\n}\n'
            for n in 1 2 3 4 5; do
                printf 'bind = ALT, %s, workspace, %s\n' "$n" "$n"
            done
            printf 'bind = ALT, Return, exec, %s\n' "$2"
            printf 'bind = ALT, Q, killactive\n'
            printf 'bind = ALT, slash, exec, %s\n' "$toggle"
        } > "$1/hyprland.conf"
        printf '%s/hyprland.conf\n' "$1"
    fi
}

_write_niri_config() { # $1 = scratch, $2 = terminal; prints the path
    local n
    {
        printf 'hotkey-overlay { skip-at-startup; }\n'
        printf 'prefer-no-csd\n'
        printf 'binds {\n'
        for n in 1 2 3 4 5; do
            printf '    Alt+%s { focus-workspace %s; }\n' "$n" "$n"
        done
        printf '    Alt+Return { spawn "%s"; }\n' "$2"
        printf '    Alt+Q { close-window; }\n'
        printf '    Alt+Slash { spawn "qs" "ipc" "-p" %s "call" "menu" "toggle"; }\n' "$(_quoted_text "$ROOT/shell.qml")"
        printf '}\n'
    } > "$1/niri.kdl"
    printf '%s/niri.kdl\n' "$1"
}

# closing a nested Hyprland's window leaves it running on a fallback output with nothing to show on
_window_closed() {
    [ "$COMPOSITOR" = Hyprland ] || return 1
    local monitors line
    monitors="$(hyprctl monitors 2>/dev/null || true)"
    while IFS= read -r line; do
        case "$line" in
            "Monitor FALLBACK"*) ;;
            "Monitor "*) return 1 ;;
        esac
    done <<< "$monitors"
    return 0
}

_inner() {
    local scratch="$1" terminal config child_pid="" shell_pid="" socket="" instance
    trap '_stop "$shell_pid"; _stop "$child_pid"' EXIT
    terminal="$(_terminal)"
    if [ "$COMPOSITOR" = Hyprland ]; then
        config="$(_write_hyprland_config "$scratch" "$terminal")"
        AQ_BACKEND=wayland Hyprland --config "$config" > "$scratch/compositor.log" 2>&1 &
    else
        config="$(_write_niri_config "$scratch" "$terminal")"
        niri --config "$config" > "$scratch/compositor.log" 2>&1 &
    fi
    child_pid=$!
    local _
    for _ in $(seq 1 200); do
        socket="$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-*' -print -quit)"
        [ -z "$socket" ] || break
        kill -0 "$child_pid" 2>/dev/null || break
        sleep 0.1
    done
    [ -n "$socket" ] || { tail -n 8 "$scratch/compositor.log" >&2; _die "$COMPOSITOR would not start in a window"; }
    export WAYLAND_DISPLAY="${socket##*/}" QT_QPA_PLATFORM=wayland
    if [ "$COMPOSITOR" = Hyprland ]; then
        for _ in $(seq 1 100); do
            for instance in "$XDG_RUNTIME_DIR"/hypr/*; do
                [ -S "$instance/.socket.sock" ] && export HYPRLAND_INSTANCE_SIGNATURE="${instance##*/}"
            done
            [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || break
            sleep 0.1
        done
    else
        for _ in $(seq 1 100); do
            NIRI_SOCKET="$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'niri.*.sock' -print -quit)"
            [ -z "$NIRI_SOCKET" ] || break
            sleep 0.1
        done
        export NIRI_SOCKET
    fi

    qs -p "$ROOT/shell.qml" --no-duplicate --no-color > "$scratch/shell.log" 2>&1 &
    shell_pid=$!
    local ready=0
    for _ in $(seq 1 200); do
        case "$(qs ipc -p "$ROOT/shell.qml" show 2>/dev/null || true)" in *"target menu"*) ready=1; break ;; esac
        kill -0 "$shell_pid" 2>/dev/null || break
        sleep 0.1
    done
    [ "$ready" = 1 ] || { tail -n 12 "$scratch/shell.log" >&2; _die "the shell would not start; silere doctor shows what is missing"; }

    if command -v notify-send >/dev/null 2>&1; then
        notify-send --app-name="Silere preview" --expire-time=45000 "Have a look around" \
            "Click the active workspace for the menu, or right-click it for quick actions. Click the clock for the calendar." || true
        notify-send --app-name="Silere preview" --expire-time=45000 "This is a private preview" \
            "Your own bar, notifications and settings are not touched. Close this window to end it." || true
    fi
    printf 'Silere is running in a window. Close it, or press Ctrl+C here, to end the preview.\n'
    printf 'Inside it: Alt+1 to Alt+5 change workspace, Alt+Return opens a terminal, Alt+/ opens the menu.\n'

    while kill -0 "$child_pid" 2>/dev/null; do
        _window_closed && break
        sleep 1
    done
}

if [ "${SILERE_SCRIPT_LIB_ONLY:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

if [ "${1:-}" = --inner ]; then
    COMPOSITOR="$2"
    _inner "$3"
    exit 0
fi

[ "$#" -eq 0 ] || { printf 'Usage: silere try\n' >&2; exit 2; }
command -v qs >/dev/null 2>&1 || _die "Quickshell is not installed. On Arch: sudo pacman -S quickshell"
for tool in dbus-run-session setsid; do
    command -v "$tool" >/dev/null 2>&1 || _die "the preview needs $tool"
done
[ -n "${WAYLAND_DISPLAY:-}" ] || _die "run this from inside a Wayland session; the preview opens as a window"
[ -n "${XDG_RUNTIME_DIR:-}" ] || _die "XDG_RUNTIME_DIR is not set"

# the session's own compositor first: it is the one the person would run Silere on
COMPOSITOR=""
if [ -n "${NIRI_SOCKET:-}" ] && command -v niri >/dev/null 2>&1; then COMPOSITOR=niri
elif command -v Hyprland >/dev/null 2>&1; then COMPOSITOR=Hyprland
elif command -v niri >/dev/null 2>&1; then COMPOSITOR=niri
else _die "the preview needs Hyprland or niri installed, the compositors Silere runs on"
fi

if command -v fc-list >/dev/null 2>&1; then
    fonts="$(fc-list : family 2>/dev/null || true)"
    case "${fonts,,}" in
        *nerd*) ;;
        *) printf '%snote:%s no Nerd Font found, so icons will show as boxes. On Arch: sudo pacman -S ttf-jetbrains-mono-nerd\n' "$YELLOW" "$R" ;;
    esac
fi

case "$WAYLAND_DISPLAY" in
    /*) parent="$WAYLAND_DISPLAY" ;;
    *) parent="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ;;
esac
real_runtime="$XDG_RUNTIME_DIR"

# short and under /tmp: Hyprland appends its long instance signature to this path to bind a socket
scratch="$(mktemp -d /tmp/silere-try.XXXXXX)"
inner_pid=""
cleanup() {
    if [ -n "$inner_pid" ]; then
        kill -TERM -- "-$inner_pid" 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 -- "-$inner_pid" 2>/dev/null || break
            sleep 0.1
        done
        kill -KILL -- "-$inner_pid" 2>/dev/null || true
    fi
    rm -rf -- "$scratch"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
mkdir -p "$scratch/config" "$scratch/state" "$scratch/cache" "$scratch/run"
chmod 0700 "$scratch" "$scratch/run"
# no servicedir: a notification daemon on this desktop must not be activated on this bus and take the shell's place
cat > "$scratch/bus.conf" <<'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
 <type>session</type><listen>unix:tmpdir=/tmp</listen><auth>EXTERNAL</auth>
 <policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
</busconfig>
EOF
printf 'Starting a private preview of Silere with %s.\n' "$COMPOSITOR"
printf 'Session files: %s\n' "$scratch"

# fonts and icons live in the real data dir, so that one stays; SILERE_SANDBOX keeps it from locking or suspending this desktop
env -u XDG_SESSION_ID -u HYPRLAND_INSTANCE_SIGNATURE -u NIRI_SOCKET -u DISPLAY -u PIPEWIRE_REMOTE \
    XDG_CONFIG_HOME="$scratch/config" XDG_STATE_HOME="$scratch/state" XDG_CACHE_HOME="$scratch/cache" \
    XDG_RUNTIME_DIR="$scratch/run" PIPEWIRE_RUNTIME_DIR="$real_runtime" WAYLAND_DISPLAY="$parent" \
    SILERE_SANDBOX=1 SILERE_WATCH_FILES=0 QS_PIPEWIRE_IMMEDIATE_RECONNECT=1 \
    setsid dbus-run-session --config-file="$scratch/bus.conf" -- bash "$ROOT/scripts/try.sh" --inner "$COMPOSITOR" "$scratch" &
inner_pid=$!
status=0
wait "$inner_pid" || status=$?
[ "$status" = 0 ] || exit "$status"
printf 'Preview ended and its files are gone. Nothing on your desktop changed.\n'
if [ ! -x "$(command -v silere 2>/dev/null || true)" ]; then
    printf 'To install it: bash %s/scripts/install.sh\n' "$ROOT"
fi
