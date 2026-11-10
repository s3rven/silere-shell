#!/usr/bin/env bash
# a bounded, allowlisted summary shared by the CLI and the diagnostic copy action
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "$#" -eq 0 ] || exit 2
source "$ROOT/scripts/lib/qml-modules.sh"

json_string() {
    local value="$1" ch escaped i
    printf '"'
    for ((i = 0; i < ${#value}; i++)); do
        ch="${value:i:1}"
        case "$ch" in
            '"') printf '\\"' ;;
            \\) printf '\\\\' ;;
            [[:cntrl:]]) printf -v escaped '\\u%04x' "'$ch"; printf '%s' "$escaped" ;;
            *) printf '%s' "$ch" ;;
        esac
    done
    printf '"'
}

# BusyBox and toybox take the plain form only; with --kill-after sent to them every probe failed and read "unknown"
if _silere_timeout_kill_after_ok; then bound=(timeout --kill-after=1 3)
elif command -v timeout >/dev/null 2>&1; then bound=(timeout 3)
else bound=()
fi
bounded() {
    # without timeout, binary presence is still reportable; optional probes are skipped
    [ "${#bound[@]}" -gt 0 ] || return 1
    "${bound[@]}" "$@" 2>/dev/null
}

silere_version=""
if [ -e "$ROOT/.git" ] && command -v git >/dev/null 2>&1; then
    silere_version="$(bounded git -C "$ROOT" describe --tags --always --dirty || true)"
fi
# also where git is present and cannot describe the checkout: a shallow copy, or one git refuses to trust
if [ -z "$silere_version" ] && [ -r "$ROOT/release.json" ]; then
    silere_version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/release.json" | head -n 1)"
fi
[[ "$silere_version" =~ ^[A-Za-z0-9][A-Za-z0-9.+_-]{0,127}$ ]] || silere_version=unknown

qs_version=""
live=null
if command -v qs >/dev/null 2>&1; then
    qs_version="$(bounded env -u LC_ALL qs --version | sed -n 's/.*Quickshell \([0-9][0-9.]*\).*/\1/p' | head -n 1 || true)"
    # the shell's own copy action supplies the device snapshot itself (SILERE_DOCTOR_LIVE=0)
    if [ "${SILERE_DOCTOR_LIVE:-1}" != 0 ] && command -v python3 >/dev/null 2>&1; then
        # an optional parser validates the live reply and drops every identifier-bearing field
        live="$(bounded env -u LC_ALL qs ipc -p "$ROOT/shell.qml" call diagnostics status \
            | head -c 65536 | sed -n '/^{"schemaVersion":1,/p' | head -n 1 || true)"
        live="$(printf '%s' "$live" | bounded python3 -I -c '
import json, math, sys
try:
    source = json.load(sys.stdin)
    if not isinstance(source, dict) or type(source.get("schemaVersion")) is not int or source["schemaVersion"] != 1:
        raise ValueError("unsupported report")
    fields = {
        "audio": "ready outputReady inputReady outputs inputs recordingApps",
        "brightness": "toolAvailable ready devices writeFailed",
        "externalBrightness": "enabled available displays scanning failed",
        "keyboardBrightness": "toolAvailable ready devices failed",
        "bluetooth": "available controllers enabled hardBlocked connected",
        "network": "available connected wifiAvailable wifiEnabled hardBlocked vpn",
        "battery": "present available devices",
    }
    result = {"schemaVersion": 1}
    for section, keys in fields.items():
        values = source.get(section, {})
        if not isinstance(values, dict):
            continue
        result[section] = {key: values[key] for key in keys.split()
            if key in values and type(values[key]) in (bool, int, float) and math.isfinite(values[key])}
    if source.get("compositor") in ("none", "hyprland", "niri"):
        result["compositor"] = source["compositor"]
    screens = source.get("screens", [])
    if isinstance(screens, list):
        result["screens"] = [{key: screen[key] for key in ("width", "height", "scale")
            if key in screen and type(screen[key]) in (int, float) and math.isfinite(screen[key])}
            for screen in screens[:32] if isinstance(screen, dict)]
    network = source.get("network", {})
    if isinstance(network, dict) and network.get("connectivity") in ("", "portal", "limited"):
        result.setdefault("network", {})["connectivity"] = network["connectivity"]
    print(json.dumps(result, separators=(",", ":"), allow_nan=False))
except (ValueError, TypeError, KeyError, OverflowError):
    print("null")
' || true)"
        [ -n "$live" ] || live=null
    fi
fi
qt_version=""
for qt_tool in qtpaths6 qtpaths /usr/lib/qt6/bin/qtpaths6 /usr/lib64/qt6/bin/qtpaths6 /usr/lib/qt6/bin/qtpaths; do
    command -v "$qt_tool" >/dev/null 2>&1 || continue
    qt_version="$(bounded "$qt_tool" --qt-version | sed -n '/^6\.[0-9][0-9.]*$/p' | head -n 1 || true)"
    [ -z "$qt_version" ] || break
done

compositor=none
compositor_version=""
if [ -n "${NIRI_SOCKET:-}" ]; then
    compositor=niri
    compositor_version="$(bounded niri --version | sed -n 's/^niri \([0-9][0-9.]*\).*/\1/p' | head -n 1 || true)"
elif [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    compositor=hyprland
    compositor_version="$(bounded hyprctl version -j \
        | sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([0-9.]*\)".*/\1/p' | head -n 1 || true)"
fi
distro="$(sed -n 's/^ID=//p' /etc/os-release 2>/dev/null | tr -d "\"'" | head -n 1 || true)"
[[ "$distro" =~ ^[a-z0-9._-]{1,64}$ ]] || distro=unknown

printf '{"schemaVersion":1,"runtime":{"silere":'
json_string "${silere_version:-unknown}"
printf ',"quickshell":'; json_string "${qs_version:-unknown}"
printf ',"qt":'; json_string "${qt_version:-unknown}"
printf ',"compositor":'; json_string "$compositor"
printf ',"compositorVersion":'; json_string "${compositor_version:-unknown}"
printf ',"distro":'; json_string "$distro"
printf '},"availability":{'
separator=""
for tool in qs git pipewire wireplumber upower brightnessctl ddcutil nmcli busctl wpctl pw-dump timeout python3; do
    printf '%s' "$separator"
    json_string "$tool"
    if command -v "$tool" >/dev/null 2>&1; then printf ':true'; else printf ':false'; fi
    separator=,
done
printf '},"devices":%s}\n' "$live"
