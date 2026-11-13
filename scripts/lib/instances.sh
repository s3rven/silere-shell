# shellcheck shell=bash
# Which Quickshell instances run, and from which config, read in one place so a change in `qs list` is fixed
# once. `qs list -p` sees only shells on this display; `--all` sees every one. The other-bars check in ui.sh
# reads the text form instead, since only that names each instance's display

# Qt logs a locale warning straight to the journal under LC_ALL=C, and nothing parsed here is translated
_silere_qs() {
    local bin
    bin="$(command -v qs || command -v quickshell)" || return 127
    env -u LC_ALL "$bin" "$@"
}

# the pid of the shell running $1 (a shell.qml path) on this display; fails when there is none
_silere_shell_pid() {
    local out pid
    out="$(_silere_qs list -p "$1" 2>/dev/null)" || true
    pid="$(sed -n '/^  Process ID: [0-9][0-9]*$/{s/^  Process ID: //p;q;}' <<<"$out")"
    [ -n "$pid" ] || return 1
    printf '%s\n' "$pid"
}

_silere_shell_running() { _silere_shell_pid "$1" >/dev/null; }

# every running instance's config path, on any display, one per line
_silere_running_configs() {
    local out
    out="$(_silere_qs list --all --json 2>/dev/null)" || true
    sed -n 's/^ *"config_path": "\(.*\)",\{0,1\}$/\1/p' <<<"$out"
}
