#!/usr/bin/env bash
# The shell against broken tools and hostile input, in a private nested session. Every external tool in turn hangs,
# fails or returns garbage, and then notifications, media players and tray items send what no well-behaved app would.
# The shell has to stay up and responsive, throw no script errors and leave no hung process behind.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/dev/probe-lib.sh"

if [ "${1:-}" = --inner ]; then
    scratch="$2"
    # refuses to run anywhere but its own private session, since it drives a whole shell
    [[ "$XDG_CONFIG_HOME" = "$scratch/"* && -z "${XDG_SESSION_ID:-}" ]] || exit 1
    case "${DBUS_SESSION_BUS_ADDRESS:-}" in ''|*/run/user/*/bus*) exit 1 ;; esac
    parent_pid=""; child_pid=""; shell_pid=""
    trap '_probe_stop "$shell_pid"; _probe_stop "$child_pid"; _probe_stop "$parent_pid"; pkill -f "^silere-fault-hang" 2>/dev/null || true' EXIT
    fail() {
        printf 'FAIL: %s\n' "$*" >&2
        [ ! -f "$scratch/shell.log" ] || tail -n 12 "$scratch/shell.log" >&2
        local report
        for report in "$XDG_CACHE_HOME"/quickshell/crashes/*/report.txt; do
            [ -f "$report" ] && grep -aE '^\s*#[0-9]+' "$report" | head -n 14 >&2
        done
        exit 1
    }

    kwin_wayland --virtual --no-lockscreen --no-global-shortcuts --width 1280 --height 900 \
        --socket silere-fault-parent > "$scratch/parent.log" 2>&1 &
    parent_pid=$!
    for _ in $(seq 1 150); do [ -S "$XDG_RUNTIME_DIR/silere-fault-parent" ] && break; sleep 0.1; done
    cat > "$scratch/hyprland.lua" <<'EOF'
hl.monitor({ output = "", mode = "1280x900@60", position = "auto", scale = 1 })
hl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true } })
EOF
    WAYLAND_DISPLAY=silere-fault-parent AQ_BACKEND=wayland Hyprland --config "$scratch/hyprland.lua" > "$scratch/child.log" 2>&1 &
    child_pid=$!
    socket=""
    for _ in $(seq 1 200); do
        socket="$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-*' -print -quit)"
        [ -z "$socket" ] || break
        sleep 0.1
    done
    [ -n "$socket" ] || fail "nested Hyprland did not start"
    export WAYLAND_DISPLAY="${socket##*/}" QT_QPA_PLATFORM=wayland SILERE_WATCH_FILES=0
    for _ in $(seq 1 100); do
        for instance in "$XDG_RUNTIME_DIR"/hypr/*; do
            [ -S "$instance/.socket.sock" ] && export HYPRLAND_INSTANCE_SIGNATURE="${instance##*/}"
        done
        [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && break
        sleep 0.1
    done
    [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || fail "nested Hyprland has no socket"
    crashes="$XDG_CACHE_HOME/quickshell/crashes"

    all_tools="brightnessctl inotifywait nmcli cava matugen hyprsunset wlsunset hyprlock swaylock gtklock systemctl loginctl busctl checkupdates paru yay apt dnf zypper xbps-install powerprofilesctl fc-list pwvucontrol pavucontrol blueman-manager nm-connection-editor nmtui xdg-terminal-exec ddcutil hyprctl pgrep pkill df curl wpctl playerctl notify-send xdg-open"
    # read-only tools stay real when they are not under test, so the tool scan works; anything that could touch hardware or the session never does
    read_only=" nmcli busctl hyprctl pgrep df curl fc-list checkupdates wpctl playerctl inotifywait "
    stub_tools() { # $1 = mode, $2... = the tools under test, none for every tool
        local mode="$1" dir="$scratch/stubs" tool use body; shift
        rm -rf "$dir"; mkdir -p "$dir"
        for tool in $all_tools; do
            if [ "$#" -eq 0 ] || [[ " $* " == *" $tool "* ]]; then use="$mode"
            elif [[ "$read_only" == *" $tool "* ]]; then continue
            else use=fail; fi
            case "$use" in
                hang) body='exec -a silere-fault-hang sleep 86400' ;;
                fail) body='echo "stub: failed" >&2; exit 3' ;;
                empty) body='exit 0' ;;
                garbage) body='head -c 600 /dev/urandom | tr -c "[:print:]\n" "?:,|"; printf "\n:::\n,,,\n-1 NaN null {\"a\":\n"; exit 0' ;;
            esac
            printf '#!/usr/bin/env bash\n%s\n' "$body" > "$dir/$tool"
            chmod +x "$dir/$tool"
        done
    }
    start_shell() {
        : > "$scratch/shell.log"
        PATH="$scratch/stubs:$PATH" qs -p "$ROOT/shell.qml" --no-duplicate --no-color > "$scratch/shell.log" 2>&1 &
        shell_pid=$!
        for _ in $(seq 1 300); do
            qs ipc -p "$ROOT/shell.qml" show 2>/dev/null | grep -q 'target menu' && return 0
            kill -0 "$shell_pid" 2>/dev/null || break
            sleep 0.1
        done
        fail "$1: the shell did not start"
    }
    answers() { # $1 = what is under test: alive, not restarted by the crash handler, and quick to answer
        [ -z "$(ls -A "$crashes" 2>/dev/null)" ] || fail "$1: the shell crashed"
        kill -0 "$shell_pid" 2>/dev/null || fail "$1: the shell exited"
        timeout 5 qs ipc -p "$ROOT/shell.qml" call settings get barHeight > /dev/null || fail "$1: the shell stopped answering"
    }
    drive() { # opens what a session opens, while the tools misbehave
        local call
        for call in "menu tab 0" "menu tab 1" "menu tab 2" "menu close" "calendar toggle" "calendar toggle" "quickActions toggle" "quickActions toggle"; do
            # shellcheck disable=SC2086
            timeout 5 qs ipc -p "$ROOT/shell.qml" call $call > /dev/null 2>&1 || true
            sleep 0.8
            answers "$label ($call)"
        done
    }
    finish_case() {
        answers "$label"
        errors="$(_probe_errors "$scratch/shell.log")"
        [ -z "$errors" ] || { printf '%s\n' "$errors" >&2; fail "$label: script errors"; }
        _probe_stop "$shell_pid"; shell_pid=""
    }
    scenarios=0
    tool_case() { # $1 = mode, $2... = tools. Bounded processes kill what hangs: none may outlive their deadlines
        label="tools $*"
        stub_tools "$@"
        start_shell "$label"
        sleep 2
        drive
        if [ "$1" = hang ]; then
            for _ in $(seq 1 50); do [ -z "$(pgrep -f '^silere-fault-hang' || true)" ] && break; sleep 0.5; done
            [ -z "$(pgrep -f '^silere-fault-hang' || true)" ] || fail "$label: a hung tool outlived its deadline: $(pgrep -af '^silere-fault-hang' | head -3)"
        fi
        finish_case
        scenarios=$((scenarios + 1))
    }
    group="nmcli pgrep df curl fc-list checkupdates wpctl playerctl brightnessctl ddcutil powerprofilesctl systemctl loginctl xdg-terminal-exec hyprsunset"
    # shellcheck disable=SC2086
    tool_case hang $group
    # shellcheck disable=SC2086
    tool_case fail $group
    # shellcheck disable=SC2086
    tool_case garbage $group
    # shellcheck disable=SC2086
    tool_case empty $group
    tool_case hang busctl
    tool_case hang hyprctl
    tool_case garbage hyprctl busctl

    if ! python3 -I -c 'import dbus, gi' 2>/dev/null; then
        printf 'tool faults passed (%s scenarios)\nSKIP: hostile input needs python-dbus and PyGObject\n' "$scenarios"
        exit 0
    fi
    # curl only records what it was given, so a hostile cover url reaches nothing
    label="hostile input"
    stub_tools fail
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/curl.log"\nexit 22\n' "$scratch" > "$scratch/stubs/curl"
    printf '#!/usr/bin/env bash\nexec -a silere-fault-hang sleep 86400\n' > "$scratch/stubs/cava"
    chmod +x "$scratch/stubs/curl" "$scratch/stubs/cava"
    start_shell "$label"
    sleep 2
    python3 -I "$ROOT/dev/fuzz-dbus.py" "$ROOT/shell.qml" "$shell_pid" "$crashes" "$scratch/marker" || fail "$label"
    [ ! -e "$scratch/marker" ] || fail "a hostile cover url ran a command"
    if [ -f "$scratch/curl.log" ] && grep -qv -- '--proto =https' "$scratch/curl.log"; then fail "curl ran without its https-only limit"; fi
    finish_case
    printf 'fault injection passed (%s tool scenarios, hostile notifications, media players and tray items)\n' "$scenarios"
    exit 0
fi

[ "$#" -eq 0 ] || { echo 'Usage: test-faults.sh' >&2; exit 2; }
for tool in qs kwin_wayland Hyprland dbus-run-session; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'SKIP: fault injection needs %s\n' "$tool"; exit 0; }
done
compgen -G '/dev/dri/renderD*' >/dev/null || { printf 'SKIP: fault injection needs a GPU render node\n'; exit 0; }
# Hyprland appends its long instance signature to this path before binding a Unix socket.
scratch="$(mktemp -d /tmp/sf.XXXXXX)"
inner_pid=""
trap '_probe_stop "$inner_pid"; rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/config" "$scratch/state" "$scratch/data" "$scratch/cache" "$scratch/run"
chmod 0700 "$scratch/run"
XDG_CONFIG_HOME="$scratch/config" XDG_STATE_HOME="$scratch/state" XDG_DATA_HOME="$scratch/data" \
XDG_CACHE_HOME="$scratch/cache" XDG_RUNTIME_DIR="$scratch/run" LC_ALL=C.UTF-8 \
    timeout 420 env -u XDG_SESSION_ID -u HYPRLAND_INSTANCE_SIGNATURE -u NIRI_SOCKET -u DISPLAY -u WAYLAND_DISPLAY \
    dbus-run-session --config-file="$ROOT/dev/probe-bus.conf" -- bash "$0" --inner "$scratch" &
inner_pid=$!
wait "$inner_pid"
