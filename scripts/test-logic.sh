#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PROBE_SOURCE="scripts/probe-logic.qml"

if ! command -v qs >/dev/null 2>&1; then
    echo "SKIP: quickshell (qs) not installed" >&2
    exit 0
fi
# installed but unable to start must not skip: that would pass CI with no coverage
if ! qs_probe="$(qs --version 2>&1)"; then
    echo "FAIL: quickshell (qs) will not start: ${qs_probe%%$'\n'*}" >&2
    exit 1
fi

log="$(mktemp "${TMPDIR:-/tmp}/silere-logic.XXXXXX.log")"
cfg="$(mktemp -d "${TMPDIR:-/tmp}/silere-logic-cfg.XXXXXX")"
runtime="$(mktemp -d "${TMPDIR:-/tmp}/silere-logic-runtime.XXXXXX")"
probe_project="$(mktemp -d "${TMPDIR:-/tmp}/silere-logic-project.XXXXXX")"
chmod 0700 "$runtime"
# quickshell makes the entry file's directory the project root, so the probe needs its own
cp "$PROBE_SOURCE" "$probe_project/probe-logic.qml"
ln -s "$ROOT/config" "$probe_project/config"
ln -s "$ROOT/services" "$probe_project/services"
ln -s "$ROOT/modules" "$probe_project/modules"
probe_pid=""
cleanup() {
    if [ -n "$probe_pid" ] && kill -0 "$probe_pid" 2>/dev/null; then
        kill "$probe_pid" 2>/dev/null || true
        wait "$probe_pid" 2>/dev/null || true
    fi
    rm -f "$log"
    rm -rf "$cfg" "$runtime" "$probe_project"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$cfg/silere-shell"
printf '{"__version":1}\n' > "$cfg/silere-shell/settings.json"

XDG_CONFIG_HOME="$cfg" XDG_STATE_HOME="$cfg" XDG_RUNTIME_DIR="$runtime" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    qs -p "$probe_project/probe-logic.qml" --no-color >"$log" 2>&1 &
probe_pid=$!

waited=0
while [ "$waited" -lt 80 ]; do
    grep -q 'PROBE-LOGIC' "$log" 2>/dev/null && break
    kill -0 "$probe_pid" 2>/dev/null || break
    sleep 0.25
    waited=$((waited + 1))
done

if ! grep -q 'PROBE-LOGIC passed' "$log" 2>/dev/null; then
    cat "$log" >&2
    echo "FAIL: behavioral logic probe did not pass" >&2
    exit 1
fi
if grep -qE 'PROBE-FAIL|ReferenceError:|TypeError:|Unable to assign|Cannot assign|Binding loop detected' "$log"; then
    cat "$log" >&2
    echo "FAIL: behavioral logic probe logged a runtime error" >&2
    exit 1
fi

result="$(grep -oE 'PROBE-LOGIC passed [0-9]+ checks' "$log" | tail -1)"
printf '%s\n' "$result"
kill "$probe_pid" 2>/dev/null || true
wait "$probe_pid" 2>/dev/null || true
probe_pid=""
