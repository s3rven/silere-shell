# shellcheck shell=bash
# Shared by scripts/test-{logic,mutate,surfaces,layout-fit}.sh: one Quickshell
# probe harness instead of four copies that drift apart.

# Qt reports these non-fatally — the object is still created and qs exits 0 — so a
# probe log has to be scanned as well as its sentinel checked. One copy because
# test-logic's had already lost "is not a type".
# shellcheck disable=SC2034
SILERE_PROBE_ERRORS='Unable to assign .*|Cannot assign .*|is not a type|ReferenceError: [^,]*|TypeError: [^,]*|Binding loop detected[^,]*'

# pgrep/pkill match the live night light by name; see NightLight._sandboxed
export SILERE_SANDBOX=1
# probes load fresh temp copies, whose compiled units would pile up in ~/.cache/quickshell/qmlcache forever
export QML_DISABLE_DISK_CACHE=1

_probe_require_qs() {
    if ! command -v qs >/dev/null 2>&1; then
        echo "SKIP: quickshell (qs) not installed" >&2
        exit 0
    fi
    # installed but unable to start must not skip: that would pass CI with no coverage
    local out
    if ! out="$(qs --version 2>&1)"; then
        echo "FAIL: quickshell (qs) will not start: ${out%%$'\n'*}" >&2
        exit 1
    fi
}

# quickshell makes the entry file's directory the project root, so a probe needs
# its own tree with the shell's import roots beside it.
_probe_project() { # $1 = repo root, $2 = probe source, $3 = destination dir
    cp "$2" "$3/${2##*/}"
    ln -s "$1/config" "$3/config"
    ln -s "$1/services" "$3/services"
    ln -s "$1/modules" "$3/modules"
}

# A root-level required property is the one thing a probe cannot supply, so it is
# the filter; a delegate declares its own indented well past this. A window root
# needs the Wayland backend these offscreen probes lack, and one built on
# FittedPopupWindow inherits its required screen, so window roots drop out by name.
_probe_standalone() { # $1 = directory
    find "$1" -maxdepth 1 -name '*.qml' \
        ! -exec grep -qE '^ {0,4}required property|^(PanelWindow|FittedPopupWindow) \{' {} \; -print
}

# Neither Qt.exit() nor Quickshell.exit() ends a Quickshell process, so a probe
# cannot quit itself: wait for its sentinel, then kill the pid it started on.
_probe_wait() { # $1 = log, $2 = pid, $3 = sentinel, $4 = ticks, $5 = seconds per tick
    local waited=0
    while [ "$waited" -lt "$4" ]; do
        grep -q "$3" "$1" 2>/dev/null && return 0
        kill -0 "$2" 2>/dev/null || return 1
        sleep "$5"
        waited=$((waited + 1))
    done
    return 1
}

# grep is line-oriented, so [^\n] here would mean "not backslash or n" and truncate
# "Cannot assign to non-existent..." at the first n. Use .* instead.
_probe_errors() { # $1 = log
    grep -oE "$SILERE_PROBE_ERRORS" "$1" | sort -u | head -10 || true
}

_probe_stop() { # $1 = pid
    [ -n "${1:-}" ] || return 0
    kill -0 "$1" 2>/dev/null || return 0
    kill "$1" 2>/dev/null || true
    # A broken probe must not wedge the test runner while ignoring TERM. Poll the
    # exact child briefly, then force it down before wait reaps its status.
    local i
    for ((i = 0; i < 20; i++)); do
        kill -0 "$1" 2>/dev/null || { wait "$1" 2>/dev/null || true; return 0; }
        sleep 0.05
    done
    kill -KILL "$1" 2>/dev/null || true
    wait "$1" 2>/dev/null || true
}
