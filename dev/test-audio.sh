#!/usr/bin/env bash
# Audio against a real PipeWire and WirePlumber, private and with no hardware: null sinks only, with its own
# runtime dir, state and bus, so the user's audio is never touched. Volume and mute reach the OSD, a default
# device replaced under its own name stays usable, a lost device claims no mute, and the daemons can restart.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/dev/probe-lib.sh"
_probe_private_bus "$@"
for tool in pipewire wireplumber wpctl pw-cli; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'SKIP: the audio test needs %s\n' "$tool"; exit 0; }
done
_probe_require_qs

scratch="$(mktemp -d "${TMPDIR:-/tmp}/silere-audio.XXXXXX")"
pw_pid=""; wp_pid=""; probe_pid=""
stop_daemons() {
    _probe_stop "$wp_pid"; wp_pid=""
    _probe_stop "$pw_pid"; pw_pid=""
    rm -f "$scratch"/run/pipewire-0*
}
cleanup() {
    _probe_stop "$probe_pid"
    stop_daemons
    rm -rf "$scratch"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$scratch"/run "$scratch"/state "$scratch"/data "$scratch"/cache \
    "$scratch"/config/wireplumber/wireplumber.conf.d "$scratch"/config/silere-shell "$scratch"/project
chmod 0700 "$scratch/run"
printf '{"__version":1}\n' > "$scratch/config/silere-shell/settings.json"
cat > "$scratch/pipewire.conf" <<'EOF'
context.properties = { core.daemon = true, core.name = pipewire-0, default.clock.rate = 48000, support.dbus = false }
context.spa-libs = { audio.convert.* = audioconvert/libspa-audioconvert, support.* = support/libspa-support }
context.modules = [
  { name = libpipewire-module-protocol-native }
  { name = libpipewire-module-metadata }
  { name = libpipewire-module-spa-node-factory }
  { name = libpipewire-module-client-node }
  { name = libpipewire-module-client-device }
  { name = libpipewire-module-adapter }
  { name = libpipewire-module-link-factory }
  { name = libpipewire-module-access, args = { } }
]
context.objects = [
  { factory = spa-node-factory, args = { factory.name = support.node.driver, node.name = Dummy-Driver, node.group = pipewire.dummy, priority.driver = 20000 } }
]
EOF
cat > "$scratch/config/wireplumber/wireplumber.conf.d/90-no-hardware.conf" <<'EOF'
wireplumber.profiles = { main = {
  monitor.alsa = disabled, monitor.alsa-midi = disabled, monitor.bluez = disabled, monitor.bluez-midi = disabled,
  monitor.libcamera = disabled, monitor.v4l2 = disabled, support.reserve-device = disabled,
  support.portal-permissionstore = disabled, support.logind = disabled
} }
EOF
export XDG_RUNTIME_DIR="$scratch/run" PIPEWIRE_RUNTIME_DIR="$scratch/run" XDG_CONFIG_HOME="$scratch/config" \
    XDG_STATE_HOME="$scratch/state" XDG_DATA_HOME="$scratch/data" XDG_CACHE_HOME="$scratch/cache" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QS_PIPEWIRE_IMMEDIATE_RECONNECT=1
unset PIPEWIRE_REMOTE WAYLAND_DISPLAY

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    [ ! -f "$scratch/probe.log" ] || tail -n 12 "$scratch/probe.log" >&2
    exit 1
}
start_daemons() {
    pipewire -c "$scratch/pipewire.conf" > "$scratch/pipewire.log" 2>&1 &
    pw_pid=$!
    wireplumber > "$scratch/wireplumber.log" 2>&1 &
    wp_pid=$!
    # a client of a daemon still starting waits for ever, hence the deadline on each
    for _ in $(seq 1 50); do
        timeout 2 wpctl status > /dev/null 2>&1 && return 0
        sleep 0.2
    done
    fail "the private PipeWire did not start"
}
add_node() { # $1 = name, $2 = media class
    timeout 4 pw-cli create-node adapter "{ factory.name=support.null-audio-sink node.name=$1 node.description=$1 media.class=$2 object.linger=true audio.position=[FL,FR] monitor.channel-volumes=true }" > /dev/null
}
node_ids() { # $1 = name
    timeout 4 pw-cli ls Node 2>/dev/null | awk -v want="node.name = \"$1\"" '/^[[:space:]]*id /{ id = $2 + 0 } index($0, want) { print id }'
}
wait_node() { # $1 = name; ids are the session manager's to see before wpctl can use them
    for _ in $(seq 1 30); do
        id="$(node_ids "$1" | tail -n 1)"
        [ -n "$id" ] && timeout 2 wpctl inspect "$id" > /dev/null 2>&1 && return 0
        sleep 0.1
    done
    fail "node $1 did not appear"
}
# quickshell#1301, as a Bluetooth transport reconnecting does it: the new node is seen while the old one still exists
replace_node() { # $1 = name, $2 = media class
    local old
    old="$(node_ids "$1" | tail -n 1)"
    add_node "$1" "$2"
    timeout 4 pw-cli destroy "$old" > /dev/null 2>&1
    for _ in $(seq 1 30); do
        [ "$(node_ids "$1" | wc -l)" = 1 ] && return 0
        sleep 0.1
    done
    fail "the old $1 did not go away"
}
set_default() { # $1 = name
    # WirePlumber can still refuse a node it has only just started to track, more often under load
    local _
    for _ in $(seq 1 20); do
        wait_node "$1"
        timeout 4 wpctl set-default "$id" 2>/dev/null && return 0
        sleep 0.2
    done
    fail "$1 could not be made the default"
}
set_volume() { # $1 = name, $2 = linear volume
    wait_node "$1"
    timeout 4 wpctl set-volume "$id" "$2"
}
start_probe() {
    : > "$scratch/probe.log"
    qs -p "$scratch/project/probe-audio.qml" --no-color > "$scratch/probe.log" 2>&1 &
    probe_pid=$!
    for _ in $(seq 1 100); do
        timeout 2 qs ipc -p "$scratch/project/probe-audio.qml" show 2>/dev/null | grep -q 'target probe' && return 0
        kill -0 "$probe_pid" 2>/dev/null || fail "the shell's services did not start"
        sleep 0.1
    done
    fail "the shell's services did not answer"
}
state() { timeout 5 qs ipc -p "$scratch/project/probe-audio.qml" call probe state 2>/dev/null; }
checks=0
expect() { # $1 = what the step proves, $2 = extended regex the state has to reach
    local seen=""
    for _ in $(seq 1 60); do
        seen="$(state || true)"
        [[ "$seen" =~ $2 ]] && { checks=$((checks + 1)); return 0; }
        sleep 0.1
    done
    fail "$1: wanted '$2', state is '$seen'"
}

# for what must never show, not even briefly: the OSD would time out and pass an expect
stays() { # $1 = what the step proves, $2 = extended regex every reading has to match
    local seen=""
    for _ in $(seq 1 15); do
        seen="$(state || true)"
        [[ "$seen" =~ $2 ]] || fail "$1: wanted '$2', state is '$seen'"
        sleep 0.1
    done
    checks=$((checks + 1))
}

_probe_project "$ROOT" "$ROOT/dev/probe-audio.qml" "$scratch/project"
start_daemons
add_node lab-a Audio/Sink; add_node lab-b Audio/Sink; add_node lab-mic Audio/Source
set_default lab-a; set_default lab-mic; set_volume lab-a 0.5
start_probe
expect "the default devices are found" 'ready=1 sink=lab-a source=lab-mic vol=50 muted=0'
# the OSD arms itself shortly after start, and a change before that shows nothing
sleep 1

set_volume lab-a 0.33
expect "a volume change reaches the OSD" 'vol=33 muted=0 osd=33%'
wait_node lab-a; timeout 4 wpctl set-mute "$id" 1
expect "a mute reaches the OSD" 'vol=0 muted=1 osd=Muted'
timeout 4 wpctl set-mute "$id" 0
expect "an unmute reaches the OSD" 'vol=33 muted=0 osd=33%'
set_default lab-b
expect "a new default shows its name" 'sink=lab-b .*osd=lab-b'
set_default lab-a
expect "the old default comes back" 'sink=lab-a .*vol=33 '

replace_node lab-a Audio/Sink
expect "a default output replaced under its name stays the output" 'sink=lab-a '
set_volume lab-a 0.61
expect "the replacement is the live node" 'vol=61 muted=0 osd=.*61%'
replace_node lab-mic Audio/Source
expect "a default input replaced under its name stays the input" 'source=lab-mic '

expect "the OSD times out" 'osd=none'
# the spare goes first: losing the default with a spare around is a device change, and rightly named on the OSD
while read -r gone; do timeout 4 pw-cli destroy "$gone" > /dev/null 2>&1; sleep 0.2; done < <(node_ids lab-b; node_ids lab-a)
stays "a lost output claims no mute" 'muted=0 osd=none'
expect "a lost output is gone" 'sink=none source=lab-mic vol=none'
add_node lab-a Audio/Sink
set_default lab-a
expect "an output that returns is picked up" 'sink=lab-a '

_probe_stop "$wp_pid"; wp_pid=""
sleep 0.5
expect "the output stays usable while the session manager is away" 'sink=lab-a .*vol=[0-9]+ '
wireplumber > "$scratch/wireplumber.log" 2>&1 &
wp_pid=$!
expect "the session manager comes back" 'ready=1 sink=lab-a '

expect "the OSD times out" 'osd=none'
stop_daemons
stays "losing PipeWire claims no mute" 'muted=0 osd=none'
expect "PipeWire is gone" 'ready=0 sink=none source=none vol=none'
start_daemons
add_node lab-a Audio/Sink
set_default lab-a
expect "PipeWire comes back" 'ready=1 sink=lab-a '
set_volume lab-a 0.72
expect "volume works after PipeWire comes back" 'vol=72 muted=0 osd=.*72%'

_probe_stop "$probe_pid"; probe_pid=""
stop_daemons
start_probe
expect "no PipeWire at start is not an error" 'ready=0 sink=none'
start_daemons
add_node lab-a Audio/Sink
set_default lab-a
expect "PipeWire arriving after the shell is picked up" 'ready=1 sink=lab-a '

[ -z "$(ls -A "$XDG_CACHE_HOME/quickshell/crashes" 2>/dev/null)" ] || fail "the shell crashed"
errors="$(_probe_errors "$scratch/probe.log")"
[ -z "$errors" ] || { printf '%s\n' "$errors" >&2; fail "script errors"; }
printf 'audio passed (%s checks)\n' "$checks"
