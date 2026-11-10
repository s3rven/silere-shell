#!/usr/bin/env bash
# Exercise the real asynchronous services against private tools and state.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/dev/probe-lib.sh"
_probe_private_bus "$@"
_probe_require_qs
scratch="$(mktemp -d "${TMPDIR:-/tmp}/silere-daily-qml.XXXXXX")"
probe_pid=""
trap '_probe_stop "$probe_pid"; rm -rf -- "$scratch"' EXIT
trap 'exit 130' INT TERM
mkdir -p "$scratch/fixtures" "$scratch/services" "$scratch/config" "$scratch/bin" "$scratch/scripts" "$scratch/run"
chmod 0700 "$scratch/run"
cp "$ROOT/dev/probe-daily-driver.qml" "$scratch/probe.qml"
cp "$ROOT/services/Vpn.qml" "$ROOT/services/DisplayBrightness.qml" "$ROOT/services/FontScan.qml" \
    "$ROOT/services/Session.qml" "$ROOT/services/BoundedProcess.qml" "$ROOT/services/RequestSet.qml" \
    "$ROOT/services/PowerProfiles.qml" "$ROOT/services/KeyboardBrightness.qml" \
    "$ROOT/services/SafeText.qml" "$ROOT/services/Grapheme.js" "$ROOT/services/SystemAlerts.qml" \
    "$scratch/services/"
# Exercise the Bluetooth service with injectable adapters, keeping every radio
# action on fixture objects rather than the machine's real Bluetooth backend.
sed -e '/^pragma Singleton$/d' \
    -e 's/readonly property var _adapters: .*$/property var _adapters: []/' \
    -e 's/readonly property var _defaultAdapter: .*$/property var _defaultAdapter: null/' \
    "$ROOT/services/Bluetooth.qml" > "$scratch/services/BluetoothProbe.qml"
grep -qF 'property var _defaultAdapter: null' "$scratch/services/BluetoothProbe.qml"
sed '/^pragma Singleton$/d' "$ROOT/services/AudioMode.qml" > "$scratch/services/AudioModeProbe.qml"
cat > "$scratch/services/qmldir" <<'EOF'
singleton Vpn 1.0 Vpn.qml
singleton DisplayBrightness 1.0 DisplayBrightness.qml
singleton SystemTools 1.0 SystemTools.qml
singleton Network 1.0 Network.qml
singleton Idle 1.0 Idle.qml
singleton MenuState 1.0 MenuState.qml
singleton QuickActionsState 1.0 QuickActionsState.qml
singleton ControlSurfaces 1.0 ControlSurfaces.qml
singleton ShellSettings 1.0 ShellSettings.qml
singleton SafeText 1.0 SafeText.qml
singleton FontScan 1.0 FontScan.qml
singleton Session 1.0 Session.qml
singleton Compositor 1.0 Compositor.qml
singleton SystemAlerts 1.0 SystemAlerts.qml
BoundedProcess 1.0 BoundedProcess.qml
RequestSet 1.0 RequestSet.qml
singleton PowerProfiles 1.0 PowerProfiles.qml
singleton Battery 1.0 Battery.qml
singleton Bluetooth 1.0 Bluetooth.qml
BluetoothProbe 1.0 BluetoothProbe.qml
AudioModeProbe 1.0 AudioModeProbe.qml
singleton Audio 1.0 Audio.qml
singleton KeyboardBrightness 1.0 KeyboardBrightness.qml
singleton CpuTemp 1.0 CpuTemp.qml
singleton Notifications 1.0 Notifications.qml
EOF
cat > "$scratch/services/Audio.qml" <<'EOF'
pragma Singleton
import Quickshell
Singleton {
    property var sink: null
    property bool backendReady: true
    property bool profileSwitching: false
    property int switches: 0
    property int restored: 0
    function beginProfileSwitch() { profileSwitching = true; switches++ }
    function endProfileSwitch() { profileSwitching = false; restored++ }
}
EOF
cat > "$scratch/services/Bluetooth.qml" <<'EOF'
pragma Singleton
import Quickshell
Singleton {
    property var _devices: []
    function batteryPercent(device) { return device.percent }
    function deviceLabel(device) { return device.name }
}
EOF
cat > "$scratch/services/CpuTemp.qml" <<'EOF'
pragma Singleton
import Quickshell
Singleton {
    property bool critical: false
    property real temp: 40
}
EOF
cat > "$scratch/services/Notifications.qml" <<'EOF'
pragma Singleton
import Quickshell
Singleton {
    property bool screenShareSilenced: false
    property bool silencingActive: false
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
    property bool hasPowerProfilesCtl: true
    property bool hasPowerProfilesService: false
    property bool hasBusctl: false
    property bool hasWpctl: true
    property bool hasPwDump: true
    property bool hasNotifySend: false
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
cat > "$scratch/services/QuickActionsState.qml" <<'EOF'
pragma Singleton
import Quickshell
Singleton { property bool open: false }
EOF
cat > "$scratch/services/ControlSurfaces.qml" <<'EOF'
pragma Singleton
import Quickshell
Singleton { readonly property bool anyOpen: MenuState.open || QuickActionsState.open }
EOF
cat > "$scratch/services/ShellSettings.qml" <<'EOF'
pragma Singleton
import Quickshell
Singleton {
    property bool ddcBrightnessEnabled: false
    property string ddcDisabledDisplays: ""
    property bool powerProfileRemember: true
    property string powerProfileAc: "balanced"
    property string powerProfileBattery: "power-saver"
    property bool osdBatteryWarn: true
    property bool osdTempWarn: true
    property bool notifPopupEnabled: true
    property bool notifCriticalBypass: true
    property int sysAlertTimeout: 5000
    property real batteryLowThreshold: 20
    property bool firstRun: false
    function markFirstRunSeen() { firstRun = false }
}
EOF
cat > "$scratch/services/Battery.qml" <<'EOF'
pragma Singleton
import Quickshell
Singleton {
    property bool available: true
    property bool onBattery: false
    property bool critical: false
    property string alertWarning: ""
    property real pct: 100
    property real _critPct: 10
}
EOF
cat > "$scratch/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SILERE_DAILY_FIXTURES/alert-calls"
EOF
chmod +x "$scratch/bin/notify-send"
cat > "$scratch/bin/powerprofilesctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
fixtures="$SILERE_DAILY_FIXTURES"
printf '%s\n' "$*" >> "$fixtures/power-calls"
while [ -s "$fixtures/power-hold" ]; do sleep 0.02; done
if [ -s "$fixtures/power-fail" ]; then
    printf 'Permission denied\n' >&2
    exit 1
fi
EOF
chmod +x "$scratch/bin/powerprofilesctl"
cat > "$scratch/bin/rfkill" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$SILERE_DAILY_FIXTURES/rfkill-actions"
[ ! -s "$SILERE_DAILY_FIXTURES/rfkill-fail" ]
EOF
chmod +x "$scratch/bin/rfkill"
cat > "$scratch/bin/pw-dump" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
fixtures="$SILERE_DAILY_FIXTURES"
snapshot="$(cat "$fixtures/audio-profiles")"
printf 'list %s\n' "$*" >> "$fixtures/audio-calls"
while [ -s "$fixtures/audio-list-hold" ]; do sleep 0.02; done
sleep 0.1
[ ! -s "$fixtures/audio-list-fail" ] || exit 1
printf '%s\n' "$snapshot"
EOF
cat > "$scratch/bin/wpctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
fixtures="$SILERE_DAILY_FIXTURES"
printf '%s\n' "$*" >> "$fixtures/audio-calls"
while [ -s "$fixtures/audio-set-hold" ]; do sleep 0.02; done
[ ! -s "$fixtures/audio-set-fail" ] || exit 1
EOF
chmod +x "$scratch/bin/pw-dump" "$scratch/bin/wpctl"
cat > "$scratch/scripts/keyboard-brightness.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
fixtures="$SILERE_DAILY_FIXTURES"
if [ "$1" = list ]; then
    snapshot="$(cat "$fixtures/keyboard-devices")"
    printf 'list\n' >> "$fixtures/keyboard-calls"
    while [ -s "$fixtures/keyboard-list-hold" ]; do sleep 0.02; done
    sleep 0.1
    printf '%s\n' "$snapshot"
    [ ! -s "$fixtures/keyboard-list-fail" ] || exit 1
else
    printf 'write %s %s\n' "$2" "$3" >> "$fixtures/keyboard-calls"
    while [ -s "$fixtures/keyboard-set-hold" ]; do sleep 0.02; done
    sleep 0.1
    [ ! -s "$fixtures/keyboard-set-fail" ] || exit 1
    awk -F '\t' -v path="$2" -v level="$3" -v identity="$4" 'BEGIN { OFS="\t" }
        $1 == path && $4 == identity { $2=level } { print }' "$fixtures/keyboard-devices" > "$fixtures/keyboard-next"
    mv "$fixtures/keyboard-next" "$fixtures/keyboard-devices"
fi
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
    [ ! -s "$fixtures/ddc-scan-fail" ] || exit 1
else
    printf 'write %s\n' "$5" >> "$fixtures/ddc-calls"
    sleep 0.2
    [ ! -s "$fixtures/ddc-fail" ] || exit 1
    if [ -s "$fixtures/ddc-fail-connector" ] && [ "$(cat "$fixtures/ddc-fail-connector")" = "$2" ]; then exit 1; fi
    awk -F '\t' -v level="$5" -v connector="$2" 'BEGIN { OFS="\t" } $1 == connector { $4=level } { print }' \
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
# PowerProfiles reads the live daemon through UPower, which answers the first read with
# its default; the probe waits for this value before picking a mode to request.
# Read here, outside the stub PATH, so the real tool answers
timeout 2 powerprofilesctl get > "$scratch/fixtures/power-live" 2>/dev/null \
    || : > "$scratch/fixtures/power-live"

# This project loads only the copied services and their mocks. Every action
# resolves to a private helper; lock and suspend requests are recorded without execution.
SILERE_SANDBOX=0 SILERE_DAILY_FIXTURES="$scratch/fixtures" PATH="$scratch/bin:$PATH" \
    XDG_CONFIG_HOME="$scratch/config" XDG_STATE_HOME="$scratch/state" \
    XDG_CACHE_HOME="$scratch/cache" XDG_RUNTIME_DIR="$scratch/run" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    qs -p "$scratch/probe.qml" --no-color > "$scratch/probe.log" 2>&1 &
probe_pid=$!
_probe_wait "$scratch/probe.log" "$probe_pid" 'PROBE-DAILY' 180 0.25 || true
if ! grep -q 'PROBE-DAILY passed' "$scratch/probe.log" || grep -q 'PROBE-FAIL' "$scratch/probe.log" \
    || [ -n "$(_probe_errors "$scratch/probe.log")" ]; then
    cat "$scratch/probe.log" >&2
    exit 1
fi
grep -oE 'PROBE-DAILY passed [0-9]+ checks' "$scratch/probe.log" | tail -1
