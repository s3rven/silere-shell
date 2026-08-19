#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

on_interrupt() {
    exit 130
}
trap on_interrupt INT TERM

# A settings row can build cleanly and still lose its own label: the surface probe
# only proves the section instantiates. This builds each one at the width the
# detail pane actually ships at and fails if Qt marks any text truncated.
#
# 388 is derived, not chosen: the settings panel targets 632, the rail takes 44
# plus a nav column capped at 160, and the pane pads 20 a side — see
# MenuWindow's panelW/navW/contentPad. Narrower than this only happens on a
# screen under roughly 700px wide, where status text is expected to elide.
CONTENT_WIDTH="${FIT_W:-388}"
PROBE="scripts/probe-fit.qml"

if ! command -v qs >/dev/null 2>&1; then
    echo "SKIP: quickshell (qs) not installed" >&2
    exit 0
fi
[ -f "$PROBE" ] || { echo "FAIL: $PROBE missing" >&2; exit 1; }

# Every width here is a text measurement, so it is only meaningful against the font
# the shell actually ships with. Without it Settings.font falls back to whatever
# exists and a substitute's advance widths condemn labels that fit fine in practice —
# a bare CI container measured "Hidden until this is installed" at twice its real
# width. fc-match always answers, so the returned family has to be compared.
WANT_FONT="${FIT_FONT:-JetBrainsMono Nerd Font}"
if ! command -v fc-match >/dev/null 2>&1; then
    echo "SKIP: fontconfig missing, cannot confirm the shipped font" >&2
    exit 0
fi
have_font="$(fc-match -f '%{family[0]}' "$WANT_FONT" 2>/dev/null || true)"
if [ "$have_font" != "$WANT_FONT" ]; then
    echo "SKIP: $WANT_FONT not installed (got \"${have_font:-none}\"); text metrics would measure a substitute" >&2
    exit 0
fi

list="$(find modules/menu/settings -name 'Settings*Section.qml' | sort)"
[ -n "$list" ] || { echo "FAIL: no settings sections found" >&2; exit 1; }

scratch="$(mktemp -d)"
cleanup() { rm -rf "$scratch"; }
trap 'cleanup; exit 130' INT TERM
trap cleanup EXIT

status=0
# Both ends of the supported type range: labels are sized off font metrics, so the
# largest scale is where a row first runs out of room.
for scale in 1.0 1.15; do
    conf="$scratch/$scale"
    mkdir -p "$conf/silere-shell"
    printf '{ "__version": 1, "uiScale": %s }\n' "$scale" > "$conf/silere-shell/settings.json"

    out="$(FIT_ROOT="$ROOT" FIT_LIST="$list" FIT_W="$CONTENT_WIDTH" \
        XDG_CONFIG_HOME="$conf" QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
        timeout 120 qs -p "$PROBE" 2>&1)" && code=0 || code=$?

    if [ "$code" -eq 124 ]; then
        echo "FAIL: layout fit probe timed out at scale $scale" >&2
        status=1
        continue
    fi
    if printf '%s\n' "$out" | grep -qE "FIT-TRUNC|FIT-FAIL"; then
        printf '%s\n' "$out" | grep -E "FIT-TRUNC|FIT-FAIL" | sed 's/^/  /' >&2
        status=1
    fi
    if ! printf '%s\n' "$out" | grep -q "FIT-DONE"; then
        echo "FAIL: layout fit probe did not finish at scale $scale" >&2
        printf '%s\n' "$out" | tail -5 >&2
        status=1
    fi
done

if [ "$status" -eq 0 ]; then
    echo "settings labels fit at width $CONTENT_WIDTH across the type range"
fi
exit "$status"
