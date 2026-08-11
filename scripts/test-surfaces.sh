#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

on_interrupt() {
    exit 130
}
trap on_interrupt INT TERM

# Settings sections are reached through one Loader and are never built by the
# startup smoke test, so a runtime-only error inside one stays invisible until a
# user opens that page. Every section is a bare Column by construction, so each
# can be built standalone — this asserts that they all still can.
#
# scripts/test-qml-headless.sh notes that an older probe importing components
# statically from scripts/ broke on import resolution. This one hands
# Qt.createComponent an absolute file:// URL instead, so each component resolves
# its own imports from its real path and the entry file's location is irrelevant.
#
# Qt reports a bad property type as a non-fatal "Unable to assign X to Y"
# warning: the object is still created and the exit code stays 0, so the log has
# to be scanned as well as the build count.
PROBE="scripts/probe-surfaces.qml"

if ! command -v qs >/dev/null 2>&1; then
    echo "SKIP: quickshell (qs) not installed" >&2
    exit 0
fi
# No display check on purpose: the offscreen QPA plugin needs neither Wayland
# nor X, which is what lets this run in a CI container.
# Seeded and then left in place: the file is gitignored, and a live shell reloads from
# this checkout, so removing it on exit takes that shell down until matugen runs again.
if [ ! -f config/MatugenTheme.qml ]; then
    if [ -f config/MatugenTheme.default.qml ]; then
        cp config/MatugenTheme.default.qml config/MatugenTheme.qml
    else
        echo "SKIP: no config/MatugenTheme.qml and no bundled default to seed from" >&2
        exit 0
    fi
fi

if [ "$#" -gt 0 ]; then
    list="$(printf '%s\n' "$@")"
else
    # Every settings section, plus every bar, menu and shared surface that builds
    # standalone. A root-level required property is the one thing the probe cannot
    # guess, so it is the filter; a delegate declares its own indented well past it,
    # and PanelWindow roots drop out the same way since they all require a screen.
    probeable() {
        find "$1" -maxdepth 1 -name '*.qml' \
            ! -exec grep -qE '^ {0,4}required property' {} \; -print
    }
    list="$(
        find modules/menu/settings -name 'Settings*Section.qml'
        probeable modules/menu
        probeable modules/menu/controls
        probeable modules/bar
        probeable modules/bar/widgets
        probeable modules/common
        printf '%s\n' modules/menu/settings/SettingsPage.qml \
                      modules/menu/settings/DraggableWidgetList.qml
    )"
    list="$(printf '%s\n' "$list" | sort -u)"
fi
count="$(printf '%s\n' "$list" | grep -c . || true)"
if [ "$count" -eq 0 ]; then
    echo "FAIL: no surfaces to probe" >&2
    exit 1
fi

log="$(mktemp "${TMPDIR:-/tmp}/silere-surfaces.XXXXXX.log")"
default_cfg="$(mktemp -d "${TMPDIR:-/tmp}/silere-surfaces-cfg.XXXXXX")"
a11y_cfg="$(mktemp -d "${TMPDIR:-/tmp}/silere-surfaces-cfg.XXXXXX")"
allon_cfg="$(mktemp -d "${TMPDIR:-/tmp}/silere-surfaces-cfg.XXXXXX")"
scale_cfg="$(mktemp -d "${TMPDIR:-/tmp}/silere-surfaces-cfg.XXXXXX")"
probe_runtime="$(mktemp -d "${TMPDIR:-/tmp}/silere-surfaces-runtime.XXXXXX")"
chmod 0700 "$probe_runtime"
probe_pid=""
cleanup() {
    if [ -n "${probe_pid:-}" ] && kill -0 "$probe_pid" 2>/dev/null; then
        kill "$probe_pid" 2>/dev/null || true
        wait "$probe_pid" 2>/dev/null || true
    fi
    rm -f "$log"
    rm -rf "$default_cfg" "$a11y_cfg" "$allon_cfg" "$scale_cfg" "$probe_runtime"
}
trap cleanup EXIT

# An empty config dir is the real default state: no settings.json at all. Pointing
# this pass at the live one instead made the result depend on whose machine it ran
# on — a section only reachable from a default value went untested for anyone who
# had changed that value. check.sh's smoke pass still launches on the real config.
mkdir -p "$default_cfg/silere-shell"

# Reduce motion zeroes every Motion token and high contrast swaps the whole line
# palette, so both change what the sections actually build. check.sh's off-path
# pass deliberately excludes reduceMotion, which leaves that mode untested.
mkdir -p "$a11y_cfg/silere-shell"
printf '{"__version":1,"reduceMotion":true,"highContrast":true}\n' \
    > "$a11y_cfg/silere-shell/settings.json"

# check.sh loads every default-off option once, but never opens a settings section
# under them, and the a11y pass above builds the sections with those options off.
# A row that only exists when some default-off toggle is on is unbuilt by both.
# Same key derivation as check.sh's off-path pass, minus the ones that are not
# plain feature flags.
allon_keys="$(sed -n 's/.*property bool[[:space:]]\{1,\}\([A-Za-z_][A-Za-z0-9_]*\)[[:space:]]*:[[:space:]]*false.*/\1/p' \
    services/ShellSettings.qml \
    | grep -vxE '_loaded|nightLightAuto|neutralAccentAuto|reduceMotion' || true)"
mkdir -p "$allon_cfg/silere-shell"
if [ -n "$allon_keys" ]; then
    { printf '{\n'
      printf '%s\n' "$allon_keys" | sed '$!s/.*/  "&": true,/; $s/.*/  "&": true/'
      printf '}\n'
    } > "$allon_cfg/silere-shell/settings.json"
else
    printf '{"__version":1}\n' > "$allon_cfg/silere-shell/settings.json"
fi

# Every pass above leaves uiScale at 1.0, because the all-on keys are derived from
# bool properties only. Row heights, icon cells and every wrapping label are computed
# from font metrics, so the largest type is a distinct layout with its own failures.
mkdir -p "$scale_cfg/silere-shell"
ui_max="$(sed -n 's/.*k: "uiScale".*max: \([0-9.]*\).*/\1/p' services/ShellSettings.qml | head -1)"
[ -n "$ui_max" ] || { echo "test-surfaces: cannot read the uiScale max from the schema" >&2; exit 1; }
printf '{"__version":1,"uiScale":%s}\n' "$ui_max" > "$scale_cfg/silere-shell/settings.json"

# Neither Qt.exit() nor Quickshell.exit() ends a Quickshell process, so the probe
# cannot quit itself: run it in the background, wait for its sentinel line, then
# kill that PID. Never pkill — a name match would take down the user's shell.
run_probe() {  # $1 = label, $2 = XDG_CONFIG_HOME, $3 = Qt scale
    local qt_scale="${3:-1}"
    : > "$log"
    XDG_CONFIG_HOME="$2" XDG_RUNTIME_DIR="$probe_runtime" \
        SILERE_PROBE_ROOT="$ROOT" SILERE_PROBE_LIST="$list" \
        QT_SCALE_FACTOR="$qt_scale" \
        QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
        qs -p "$PROBE" --no-color >"$log" 2>&1 &
    probe_pid=$!
    local waited=0
    while [ "$waited" -lt 120 ]; do
        grep -q 'PROBE-SURFACES built' "$log" 2>/dev/null && break
        kill -0 "$probe_pid" 2>/dev/null || break
        sleep 0.5
        waited=$((waited + 1))
    done
    if ! grep -q 'PROBE-SURFACES built' "$log" 2>/dev/null; then
        cat "$log" >&2
        echo "FAIL: surface probe did not finish ($1)" >&2
        exit 1
    fi

    local failed=0
    if grep -q 'PROBE-FAIL' "$log"; then
        grep 'PROBE-FAIL' "$log" | sed "s/^.*PROBE-FAIL/  [$1] /" >&2
        failed=1
    fi
    # "Unable to assign" is the one that caught a QtObject bound to a property
    # typed Item — invisible to qmlcachegen and to a plain startup launch.
    local errs
    # grep is line-oriented, so [^\n] here means "not backslash or n" and would
    # truncate "Cannot assign to non-existent..." at the first n. Use .* instead.
    errs="$(grep -oE 'Unable to assign .*|Cannot assign .*|is not a type|ReferenceError: [^,]*|TypeError: [^,]*|Binding loop detected[^,]*' "$log" \
        | sort -u | head -10 || true)"
    if [ -n "$errs" ]; then
        printf '%s\n' "$errs" | sed "s/^/  [$1] /" >&2
        failed=1
    fi
    if [ "$failed" -ne 0 ]; then
        echo "FAIL: a surface failed to build cleanly ($1)" >&2
        exit 1
    fi
    printf '  %-12s %s\n' "$1" "$(grep -oE 'PROBE-SURFACES built [0-9]+/[0-9]+' "$log" | tail -1 | sed 's/PROBE-SURFACES built //')"
    kill "$probe_pid" 2>/dev/null || true
    wait "$probe_pid" 2>/dev/null || true
    probe_pid=""
}

printf 'building %s surfaces standalone\n' "$count"
run_probe "default" "$default_cfg"
run_probe "a11y" "$a11y_cfg"
run_probe "all-on" "$allon_cfg"
run_probe "max-scale" "$scale_cfg"
run_probe "fractional" "$default_cfg" "1.25"
echo "surface probe passed (default + reduce-motion/high-contrast + every option on + largest type + fractional scale)"
