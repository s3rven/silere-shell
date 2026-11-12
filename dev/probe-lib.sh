# shellcheck shell=bash
# Shared by scripts/test-{logic,mutate,surfaces,layout-fit}.sh: one Quickshell
# probe harness instead of four copies that drift apart.

# Qt reports these non-fatally — the object is still created and qs exits 0 — so a
# probe log has to be scanned as well as its sentinel checked. One copy because
# test-logic's had already lost "is not a type".
# shellcheck disable=SC2034
SILERE_PROBE_ERRORS='Unable to assign .*|Cannot assign .*|is not a type|ReferenceError: [^,]*|TypeError: [^,]*|Binding loop detected[^,]*'

# a test shell must not lock, suspend or adopt anything of the desktop it runs on
export SILERE_SANDBOX=1
# probes load fresh temp copies, whose compiled units would pile up in ~/.cache/quickshell/qmlcache forever
export QML_DISABLE_DISK_CACHE=1
# A failed headless probe must exit instead of leaving Quickshell's crash
# reporter/relaunch process behind after the harness has reaped its child.
# Scope this to probes; keep normal desktop crash reporting available.
export QS_DISABLE_CRASH_HANDLER=1

# A probe on the desktop's own session bus takes org.freedesktop.Notifications from a live shell that
# restarts during the run, and the desktop's players and tray items leak into what it checks. Each probe
# script reruns itself on a private bus that activates nothing and exits with the rerun's status; without
# dbus-run-session it stays put. Call it before the script makes anything it has to clean up
_probe_private_bus() { # "$@" = the calling script's own arguments
    [ "${SILERE_PROBE_BUS:-}" = private ] && return 0
    command -v dbus-run-session >/dev/null 2>&1 && command -v setsid >/dev/null 2>&1 || return 0
    local pid status
    # a group of its own: a stop sent here reaches the rerun script, which cleans up, and the bus beside it,
    # where signalling dbus-run-session alone would leave both running. Ctrl-C goes on as TERM, since a
    # background job starts with INT ignored and the probes clean up the same on either
    SILERE_PROBE_BUS=private setsid dbus-run-session --config-file="$ROOT/dev/probe-bus.conf" \
        -- bash "$ROOT/dev/${BASH_SOURCE[1]##*/}" "$@" &
    pid=$!
    trap 'kill -TERM -- "-$pid" 2>/dev/null || true' INT TERM
    # a trapped signal ends wait early, so wait again until the group is really gone
    while :; do
        status=0
        wait "$pid" || status=$?
        kill -0 "$pid" 2>/dev/null || break
    done
    exit "$status"
}

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
    ln -s "$1/scripts" "$3/scripts"
}

# A root-level required property is the one thing a probe cannot supply, so it is
# the filter; a delegate declares its own indented well past this. A window root
# needs the Wayland backend these offscreen probes lack, and one built on
# FittedPopupWindow inherits its required screen, so window roots drop out by name.
_probe_standalone() { # $1 = directory
    find "$1" -maxdepth 1 -name '*.qml' \
        ! -exec grep -qE '^ {0,4}required property|^(PanelWindow|FittedPopupWindow) \{' {} \; -print
}

# Keep the QML engine alive until its result and runtime errors are collected.
# Qt.exit() can tear down bindings before the harness reads the log; terminate
# only the process started by this harness after validating its sentinel.
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
    # Keep the QML filename and line number: stripping the matched phrase hid
    # the source of CI-only warnings such as assigning undefined to a bool.
    grep -E "$SILERE_PROBE_ERRORS" "$1" | sort -u | head -10 || true
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
