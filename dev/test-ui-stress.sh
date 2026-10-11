#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/dev/probe-lib.sh"
PROBE_SOURCE="dev/probe-ui-stress.qml"

if ! [[ "${SILERE_UI_STRESS_CYCLES:-120}" =~ ^[1-9][0-9]*$ ]]; then
    echo "FAIL: SILERE_UI_STRESS_CYCLES must be a positive whole number" >&2
    exit 2
fi

_probe_require_qs

log="$(mktemp "${TMPDIR:-/tmp}/silere-ui-stress.XXXXXX.log")"
cfg="$(mktemp -d "${TMPDIR:-/tmp}/silere-ui-stress-cfg.XXXXXX")"
runtime="$(mktemp -d "${TMPDIR:-/tmp}/silere-ui-stress-runtime.XXXXXX")"
probe_project="$(mktemp -d "${TMPDIR:-/tmp}/silere-ui-stress-project.XXXXXX")"
chmod 0700 "$runtime"
_probe_project "$ROOT" "$PROBE_SOURCE" "$probe_project"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    rm -f "$log"
    rm -rf "$cfg" "$runtime" "$probe_project"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$cfg/silere-shell"
printf '{"__version":1}\n' > "$cfg/silere-shell/settings.json"

XDG_CONFIG_HOME="$cfg" XDG_STATE_HOME="$cfg" XDG_CACHE_HOME="$cfg/cache" XDG_RUNTIME_DIR="$runtime" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    qs -p "$probe_project/probe-ui-stress.qml" --no-color >"$log" 2>&1 &
probe_pid=$!

# Sustained pointer input and reflow take longer than the ordinary logic probe.
_probe_wait "$log" "$probe_pid" 'PROBE-UI-STRESS' 480 0.25 || true

if ! grep -q 'PROBE-UI-STRESS passed' "$log" 2>/dev/null; then
    cat "$log" >&2
    echo "FAIL: extended UI stress probe did not pass" >&2
    exit 1
fi

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
    echo "FAIL: extended UI stress probe logged a runtime error" >&2
    exit 1
fi

grep -oE 'PROBE-UI-STRESS passed [0-9]+ checks over [0-9]+ cycles' "$log" | tail -1
_probe_stop "$probe_pid"
probe_pid=""
