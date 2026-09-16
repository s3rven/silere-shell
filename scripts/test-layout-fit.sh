#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"

trap 'exit 130' INT TERM

# A settings row can build cleanly and still lose its own label: the surface probe
# only proves the section instantiates. This builds each one at the width the
# detail pane actually ships at and fails if Qt marks any text truncated.
#
# 388 is derived, not chosen: the settings panel targets 632, the rail takes 44
# plus a nav column capped at 160, and the pane pads 20 a side — see
# MenuWindow's panelW/navW/contentPad. Narrower than this only happens on a
# screen under roughly 700px wide, where status text is expected to elide.
# The panel and the nav cap take the same growth above 100% type, so this pane
# width holds across the range; the rail below is probed at its base 160, which
# measures a narrower column than the shell draws there.
CONTENT_WIDTH="${FIT_W:-388}"
PROBE="scripts/probe-fit.qml"

_probe_require_qs
[ -f "$PROBE" ] || { echo "FAIL: $PROBE missing" >&2; exit 1; }

# Every width here is a text measurement, so it is only meaningful against the font
# the shell actually ships with. Without it Settings.font falls back to whatever
# exists and a substitute's advance widths condemn labels that fit fine in practice —
# a bare CI container measured "Hidden until this is installed" at twice its real
# width. fc-match always answers, so the returned family has to be compared.
WANT_FONT="${FIT_FONT:-JetBrainsMono Nerd Font}"
font_problem=""
if ! command -v fc-match >/dev/null 2>&1; then
    font_problem="fontconfig missing"
else
    have_font="$(fc-match -f '%{family[0]}' "$WANT_FONT" 2>/dev/null || true)"
    [ "$have_font" = "$WANT_FONT" ] \
        || font_problem="$WANT_FONT not installed (got \"${have_font:-none}\")"
fi
if [ -n "$font_problem" ]; then
    # CI installs the shipped font on purpose; skipping there would drop the only
    # check that catches elided labels while still reporting success
    if [ "${FIT_REQUIRE_FONT:-0}" = 1 ]; then
        echo "FAIL: $font_problem; text metrics would measure a substitute" >&2
        exit 1
    fi
    echo "SKIP: $font_problem; text metrics would measure a substitute" >&2
    exit 0
fi

list="$(find modules/menu/settings -name 'Settings*Section.qml' | sort)"
[ -n "$list" ] || { echo "FAIL: no settings sections found" >&2; exit 1; }

# The other tabs are narrower: 400 panel less the 44 rail and 12 of pad a side. The nav
# column ships at its 160 cap. HomePage stays out on purpose — its status lines carry
# network and device names from outside the shell, which are meant to elide.
list="$list
modules/menu/RecentPage.qml|332
modules/menu/PowerRailContent.qml|332
modules/menu/VitalsStrip.qml|332
modules/menu/SettingsNav.qml|160"

scratch="$(mktemp -d)"
probe_pid=""
declare -A scale_pid=()
cleanup() {
    _probe_stop "${probe_pid:-}"
    # both scales run at once, so an interrupt has two children to answer for
    local pid
    for pid in "${scale_pid[@]}"; do _probe_stop "$pid"; done
    rm -rf "$scratch"
}
trap 'cleanup; exit 130' INT TERM
trap cleanup EXIT

status=0
# Both ends of the supported type range: labels are sized off font metrics, so the
# largest scale is where a row first runs out of room. The two share nothing but the
# read-only tree, so they measure at once rather than one after the other.
scales=(1.0 1.15)
for scale in "${scales[@]}"; do
    conf="$scratch/$scale"
    runtime="$conf/runtime"
    mkdir -p "$conf/silere-shell" "$conf/cache" "$conf/state" "$runtime"
    chmod 0700 "$runtime"
    printf '{ "__version": 1, "uiScale": %s }\n' "$scale" > "$conf/silere-shell/settings.json"

    # Capture to a regular file, not command substitution. A component may launch
    # a detached helper which inherits stdout; that helper can keep a capture pipe
    # open forever even after the probe itself has reached FIT-DONE.
    FIT_ROOT="$ROOT" FIT_LIST="$list" FIT_W="$CONTENT_WIDTH" \
        XDG_CONFIG_HOME="$conf" XDG_CACHE_HOME="$conf/cache" \
        XDG_STATE_HOME="$conf/state" XDG_RUNTIME_DIR="$runtime" \
        QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
        qs -p "$PROBE" --no-color >"$conf/layout.log" 2>&1 &
    scale_pid["$scale"]=$!
done

for scale in "${scales[@]}"; do
    conf="$scratch/$scale"
    log="$conf/layout.log"
    code=0
    probe_pid="${scale_pid[$scale]}"
    if ! _probe_wait "$log" "$probe_pid" 'FIT-DONE' 240 0.5; then
        if kill -0 "$probe_pid" 2>/dev/null; then
            code=124
        else
            wait "$probe_pid" 2>/dev/null || code=$?
        fi
    fi
    _probe_stop "$probe_pid"
    unset 'scale_pid[$scale]'
    probe_pid=""
    out="$(<"$log")"

    if [ "$code" -eq 124 ]; then
        echo "FAIL: layout fit probe timed out at scale $scale" >&2
        status=1
        continue
    fi
    # grep -q would SIGPIPE the producer on an early match, and pipefail turns that
    # into a false pass; collect the matches instead of testing for them
    fit_failures="$(printf '%s\n' "$out" | grep -E "FIT-TRUNC|FIT-CLIP|FIT-WIDE|FIT-SHRINK|FIT-FAIL" || true)"
    if [ -n "$fit_failures" ]; then
        printf '%s\n' "$fit_failures" | sed 's/^/  /' >&2
        status=1
    fi
    done_line="$(printf '%s\n' "$out" | grep -o 'FIT-DONE.*' | tail -1)"
    if [ -z "$done_line" ]; then
        echo "FAIL: layout fit probe did not finish at scale $scale" >&2
        printf '%s\n' "$out" | tail -5 >&2
        status=1
    # a scan that reaches no text reports zero findings for the wrong reason
    elif [ "$(printf '%s' "$done_line" | sed -n 's/.*texts \([0-9]*\).*/\1/p')" -lt 200 ]; then
        echo "FAIL: layout fit probe scanned too little text at scale $scale: $done_line" >&2
        status=1
    # likewise for the clip check: no item measured against a clipping ancestor
    # means the overflow scan reported clean because it never ran
    elif [ "$(printf '%s' "$done_line" | sed -n 's/.*clipped \([0-9]*\).*/\1/p')" -lt 500 ]; then
        echo "FAIL: layout fit probe measured too few clipped items at scale $scale: $done_line" >&2
        status=1
    fi
done

# The health and update cards only list tools that are MISSING, so on a machine with them
# installed those rows never render and never get measured. A PATH holding nothing but bash
# lets the real scan find none of them, which is the bare install the rows are written for.
bare_conf="$scratch/bare"
bare_bin="$bare_conf/bin"
mkdir -p "$bare_conf/silere-shell" "$bare_conf/cache" "$bare_conf/state" \
    "$bare_conf/runtime" "$bare_bin"
chmod 0700 "$bare_conf/runtime"
# the tighter end of the type range only: this pass measures rows, not the range
printf '{ "__version": 1, "uiScale": 1.15 }\n' > "$bare_conf/silere-shell/settings.json"
qs_bin="$(command -v qs)"
ln -s "$(command -v bash)" "$bare_bin/bash"
bare_list="modules/menu/settings/SettingsMaintenanceSection.qml
modules/menu/settings/SettingsUpdatesSection.qml"

FIT_ROOT="$ROOT" FIT_LIST="$bare_list" FIT_W="$CONTENT_WIDTH" \
    PATH="$bare_bin" \
    XDG_CONFIG_HOME="$bare_conf" XDG_CACHE_HOME="$bare_conf/cache" \
    XDG_STATE_HOME="$bare_conf/state" XDG_RUNTIME_DIR="$bare_conf/runtime" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    "$qs_bin" -p "$PROBE" --no-color >"$bare_conf/layout.log" 2>&1 &
probe_pid=$!
code=0
if ! _probe_wait "$bare_conf/layout.log" "$probe_pid" 'FIT-DONE' 240 0.5; then
    if kill -0 "$probe_pid" 2>/dev/null; then code=124; else wait "$probe_pid" 2>/dev/null || code=$?; fi
fi
_probe_stop "$probe_pid"
probe_pid=""
out="$(<"$bare_conf/layout.log")"

if [ "$code" -eq 124 ]; then
    echo "FAIL: bare-install fit probe timed out" >&2
    status=1
else
    fit_failures="$(printf '%s\n' "$out" | grep -E "FIT-TRUNC|FIT-CLIP|FIT-WIDE|FIT-SHRINK|FIT-FAIL" || true)"
    if [ -n "$fit_failures" ]; then
        printf '%s\n' "$fit_failures" | sed 's/^/  /' >&2
        status=1
    fi
    done_line="$(printf '%s\n' "$out" | grep -o 'FIT-DONE.*' | tail -1)"
    bare_texts="$(printf '%s' "$done_line" | sed -n 's/.*texts \([0-9]*\).*/\1/p')"
    # a failed scan hides the whole card, and the pass would then report clean without
    # ever reaching the rows it exists for
    if [ -z "$bare_texts" ] || [ "$bare_texts" -lt "${FIT_BARE_FLOOR:-60}" ]; then
        echo "FAIL: bare-install fit probe never reached the missing-tool rows: ${done_line:-no FIT-DONE}" >&2
        status=1
    fi
fi

if [ "$status" -eq 0 ]; then
    echo "menu labels fit at the widths they ship at across the type range"
fi
exit "$status"
