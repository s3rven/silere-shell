#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"

trap 'exit 130' INT TERM

# test-surfaces.sh builds every section under a handful of fixed settings files;
# check.sh loads default-off options once at startup. Neither ever changes a
# setting while a surface is alive, so a binding that only breaks on the change
# itself — a cleared model, a stale cached index, a divide by a now-zero size —
# passes both. This drives the whole schema against surfaces that already exist.
PROBE_SOURCE="$ROOT/scripts/probe-mutate.qml"

_probe_require_qs

list="$(
    find modules/menu/settings -name 'Settings*Section.qml'
    _probe_standalone modules/menu
    _probe_standalone modules/menu/controls
)"
list="$(printf '%s\n' "$list" | sort -u)"
count="$(printf '%s\n' "$list" | grep -c . || true)"
if [ "$count" -eq 0 ]; then
    echo "FAIL: no surfaces to sweep" >&2
    exit 1
fi

# 180 states at two 40ms ticks each is a 15s wait, and each state is restored before the
# next, so shards split the sweep with the same settle per state
shards="${SILERE_MUTATE_SHARDS:-4}"
case "$shards" in ''|*[!0-9]*|0) shards=1 ;; esac
work="$(mktemp -d "${TMPDIR:-/tmp}/silere-mutate.XXXXXX")"
pids=()
cleanup() {
    local p
    for p in "${pids[@]}"; do _probe_stop "$p"; done
    rm -rf "$work"
}
trap cleanup EXIT

printf 'sweeping the settings schema against %s live surfaces in %s shards\n' "$count" "$shards"
for ((i = 0; i < shards; i++)); do
    d="$work/$i"
    # each shard saves settings.json as it sweeps, so a shared file would leak one into another
    mkdir -p "$d/cfg/silere-shell" "$d/runtime" "$d/project"
    chmod 0700 "$d/runtime"
    printf '{"__version":1}\n' > "$d/cfg/silere-shell/settings.json"
    _probe_project "$ROOT" "$PROBE_SOURCE" "$d/project"
    XDG_CONFIG_HOME="$d/cfg" XDG_STATE_HOME="$d/cfg" XDG_RUNTIME_DIR="$d/runtime" \
        SILERE_PROBE_ROOT="$ROOT" SILERE_PROBE_LIST="$list" SILERE_PROBE_SHARD="$i/$shards" \
        QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
        qs -p "$d/project/probe-mutate.qml" --no-color >"$d/log" 2>&1 &
    pids+=("$!")
done

for ((i = 0; i < shards; i++)); do
    _probe_wait "$work/$i/log" "${pids[$i]}" 'PROBE-MUTATE' 2000 0.1 || true
    if ! grep -q 'PROBE-MUTATE' "$work/$i/log" 2>/dev/null; then
        cat "$work/$i/log" >&2
        echo "FAIL: mutation sweep shard $i did not finish" >&2
        exit 1
    fi
done

log="$work/all.log"
cat "$work"/[0-9]*/log > "$log"

failed=0
if grep -q 'PROBE-FAIL' "$log"; then
    grep 'PROBE-FAIL' "$log" | sed 's/^.*PROBE-FAIL/  /' | sort -u | head -20 >&2
    failed=1
fi
errs="$(_probe_errors "$log")"
if [ -n "$errs" ]; then
    printf '%s\n' "$errs" | sed 's/^/  /' >&2
    failed=1
fi
if [ "$failed" -ne 0 ]; then
    echo "FAIL: a live settings change broke a surface" >&2
    exit 1
fi

states="$(grep -oE 'PROBE-MUTATE swept [0-9]+' "$log" | awk '{ n += $3 } END { print n + 0 }')"
surfaces="$(grep -oE 'over [0-9]+ surfaces' "$log" | head -1 | grep -oE '[0-9]+')"
printf '  PROBE-MUTATE swept %s states over %s surfaces\n' "$states" "${surfaces:-0}"
echo "mutation sweep passed"
