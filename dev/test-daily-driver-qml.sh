#!/usr/bin/env bash
# Exercise the real asynchronous services against private tools and state.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/dev/probe-lib.sh"
_probe_require_qs
scratch="$(mktemp -d "${TMPDIR:-/tmp}/silere-daily-qml.XXXXXX")"
probe_pid=""
trap '_probe_stop "$probe_pid"; rm -rf -- "$scratch"' EXIT
trap 'exit 130' INT TERM
mkdir -p "$scratch/fixtures" "$scratch/services" "$scratch/config" "$scratch/bin" "$scratch/scripts" "$scratch/run"
chmod 0700 "$scratch/run"
cp "$ROOT/dev/probe-daily-driver.qml" "$scratch/probe.qml"
cp "$ROOT/services/Vpn.qml" "$ROOT/services/DisplayBrightness.qml" "$ROOT/services/FontScan.qml" \
    "$ROOT/services/Session.qml" "$ROOT/services/BoundedProcess.qml" "$scratch/services/"
cat > "$scratch/services/qmldir" <<'EOF'
singleton Vpn 1.0 Vpn.qml
singleton DisplayBrightness 1.0 DisplayBrightness.qml
singleton SystemTools 1.0 SystemTools.qml
singleton Network 1.0 Network.qml
singleton Idle 1.0 Idle.qml
singleton MenuState 1.0 MenuState.qml
singleton ShellSettings 1.0 ShellSettings.qml
singleton SafeText 1.0 SafeText.qml
singleton FontScan 1.0 FontScan.qml
singleton Session 1.0 Session.qml
singleton Compositor 1.0 Compositor.qml
singleton SystemAlerts 1.0 SystemAlerts.qml
BoundedProcess 1.0 BoundedProcess.qml
EOF
cat > "$scratch/services/SystemAlerts.qml" <<'EOF'
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    property var sent: []
    function send(summary: string, body: string, urgency: string): bool {
        sent = sent.concat([{ summary: summary, body: body, urgency: urgency }])
        return true
    }
}
EOF
cat > "$scratch/services/SystemTools.qml" <<'EOF'
pragma Singleton
import Quickshell
Singleton {
    property bool ready: true
    property bool checking: false
    property int scanRevision: 0
    property bool hasFcList: true
    property bool hasLoginctl: false
    property bool hasNmcli: true
    property bool hasDdcutil: true
    property bool hasTimeout: true
    property var commands: []
    function runOrNotify(command, title) { commands = commands.concat([command]) }
}
EOF
cat > "$scratch/services/Compositor.qml" <<'EOF'
pragma Singleton
import Quickshell
Singleton {
    property var commands: []
    function launch(command) { commands = commands.concat([command]) }
}
EOF
cat > "$scratch/config/qmldir" <<'EOF'
singleton Settings 1.0 Settings.qml
EOF
cat > "$scratch/config/Settings.qml" <<'EOF'
pragma Singleton
import Quickshell
Singleton {
    property var lockCommand: ["fixture-lock"]
    property var suspendCommand: ["fixture-suspend"]
}
EOF
cat > "$scratch/services/Network.qml" <<'EOF'
pragma Singleton
import Quickshell
Singleton {
    property bool toolAvailable: true
    property bool hasVpn: false
    property string vpnName: ""
    property int refreshes: 0
    function _queueVpnRefresh() { refreshes++ }
    function _splitNmcliLine(raw) { return raw.split(":") }
}
EOF
cat > "$scratch/services/Idle.qml" <<'EOF'
pragma Singleton
import Quickshell
Singleton { property bool isIdle: false }
EOF
cat > "$scratch/services/MenuState.qml" <<'EOF'
pragma Singleton
import Quickshell
Singleton {
    property bool open: false
    property bool homeActive: true
    property bool settingsActive: false
    property string settingsSection: "interface"
}
EOF
cat > "$scratch/services/ShellSettings.qml" <<'EOF'
pragma Singleton
import Quickshell
Singleton {
    property bool ddcBrightnessEnabled: false
    property string ddcDisabledDisplays: ""
}
EOF
cat > "$scratch/services/SafeText.qml" <<'EOF'
pragma Singleton
import Quickshell
Singleton { function singleLineText(raw, limit) { return String(raw).slice(0, limit) } }
EOF
cat > "$scratch/bin/nmcli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
fixtures="$SILERE_DAILY_FIXTURES"
if [[ " $* " = *' --wait '* ]]; then
    printf 'action\n' >> "$fixtures/vpn-calls"
    cp "$fixtures/vpn-after-action" "$fixtures/vpn-profiles"
    exit 0
fi
printf 'list\n' >> "$fixtures/vpn-calls"
snapshot="$(cat "$fixtures/vpn-profiles")"
sleep 0.2
[ ! -s "$fixtures/vpn-fail" ] || exit 1
printf '%s\n' "$snapshot"
EOF
cat > "$scratch/scripts/display-brightness.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
fixtures="$SILERE_DAILY_FIXTURES"
if [ "$1" = list ]; then
    printf 'scan\n' >> "$fixtures/ddc-calls"
    snapshot="$(cat "$fixtures/ddc-displays")"
    sleep 0.2
    printf '%s\n' "$snapshot"
else
    printf 'write %s\n' "$5" >> "$fixtures/ddc-calls"
    sleep 0.2
    [ ! -s "$fixtures/ddc-fail" ] || exit 1
    awk -F '\t' -v level="$5" 'BEGIN { OFS="\t" } { $4=level; print }' \
        "$fixtures/ddc-displays" > "$fixtures/ddc-next"
    mv "$fixtures/ddc-next" "$fixtures/ddc-displays"
fi
EOF
chmod +x "$scratch/bin/nmcli"
cat > "$scratch/bin/fc-list" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
fixtures="$SILERE_DAILY_FIXTURES"
snapshot="$(cat "$fixtures/font-families")"
printf 'scan\n' >> "$fixtures/font-calls"
while [ -s "$fixtures/font-hold" ]; do sleep 0.02; done
sleep 0.1
[ ! -s "$fixtures/font-fail" ] || exit 1
printf '%s\n' "$snapshot"
EOF
chmod +x "$scratch/bin/fc-list"
cat > "$scratch/scripts/session.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
fixtures="$SILERE_DAILY_FIXTURES"
if [ "$1" = status ]; then
    snapshot="$(cat "$fixtures/session-state")"
    printf 'status\n' >> "$fixtures/session-calls"
    while [ -s "$fixtures/session-status-hold" ]; do sleep 0.02; done
    sleep 0.1
    printf 'session=fixture\nlocked=%s\n' "$snapshot"
else
    printf 'wait\n' >> "$fixtures/session-calls"
    while [ -s "$fixtures/session-wait-hold" ]; do sleep 0.02; done
    sleep 0.1
    [ ! -s "$fixtures/session-wait-fail" ]
fi
EOF

# This project loads only the copied services and their mocks. Every action
# resolves to a private helper; lock and suspend requests are recorded without execution.
SILERE_SANDBOX=0 SILERE_DAILY_FIXTURES="$scratch/fixtures" PATH="$scratch/bin:$PATH" \
    XDG_CONFIG_HOME="$scratch/config" XDG_STATE_HOME="$scratch/state" \
    XDG_CACHE_HOME="$scratch/cache" XDG_RUNTIME_DIR="$scratch/run" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    qs -p "$scratch/probe.qml" --no-color > "$scratch/probe.log" 2>&1 &
probe_pid=$!
_probe_wait "$scratch/probe.log" "$probe_pid" 'PROBE-DAILY' 160 0.25 || true
if ! grep -q 'PROBE-DAILY passed' "$scratch/probe.log" || grep -q 'PROBE-FAIL' "$scratch/probe.log" \
    || [ -n "$(_probe_errors "$scratch/probe.log")" ]; then
    cat "$scratch/probe.log" >&2
    exit 1
fi
grep -oE 'PROBE-DAILY passed [0-9]+ checks' "$scratch/probe.log" | tail -1
