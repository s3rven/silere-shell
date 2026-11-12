#!/usr/bin/env bash
# upower lets the active session set a battery's charge limit, but only the kernel knows whether one is on:
# a limit set in firmware or by another tool (Lenovo's conservation mode) leaves upower's own flag false
set -euo pipefail
export LC_ALL=C

service=org.freedesktop.UPower
interface=org.freedesktop.UPower.Device
power_root=/sys/class/power_supply
if [ "${SILERE_SANDBOX:-0}" = 1 ]; then
    [ -n "${SILERE_TEST_POWER_ROOT:-}" ] || exit 1
    power_root="$SILERE_TEST_POWER_ROOT"
fi

valid_path() { [[ "$1" =~ ^/org/freedesktop/UPower/devices/battery_[A-Za-z0-9_]+$ ]]; }
valid_native() { [[ "$1" =~ ^[A-Za-z0-9_.:-]{1,64}$ ]]; }
# a 0-100 threshold, read straight from sysfs
percent() {
    local value
    read -r value < "$1" 2>/dev/null && [[ "$value" =~ ^[0-9]{1,3}$ ]] || return 1
    value=$((10#$value))
    [ "$value" -le 100 ] || return 1
    printf '%s\n' "$value"
}

# on or off from the kernel, a tab, and the percentage it stops at (0 when it does not say); nothing when it cannot tell
kernel_state() { # $1 = power supply directory
    local dir="$1" types="" active="" start=0 stop=100
    if [ -r "$dir/charge_types" ]; then
        types="$(head -c 256 "$dir/charge_types" 2>/dev/null)" || types=""
        active="$(sed -n 's/.*\[\([A-Za-z_]*\)\].*/\1/p' <<< "$types")"
    fi
    # upower's own reading: thresholds where the driver has them, the charge type where it has only that
    if [ -e "$dir/charge_control_start_threshold" ] || [ -e "$dir/charge_control_end_threshold" ]; then
        if [ -e "$dir/charge_control_start_threshold" ]; then start="$(percent "$dir/charge_control_start_threshold")" || return 0; fi
        if [ -e "$dir/charge_control_end_threshold" ]; then stop="$(percent "$dir/charge_control_end_threshold")" || return 0; fi
        # a driver offering Custom applies its thresholds only there (Dell); upower picks Custom as it enables them
        if [ "$start" -eq 0 ] && [ "$stop" -eq 100 ]; then printf 'off\t0\n'
        elif [ -n "$active" ] && [ "$active" != Custom ] && [[ " $(tr -d '[]' <<< "$types") " = *" Custom "* ]]; then printf 'off\t0\n'
        elif [ "$stop" -lt 100 ]; then printf 'on\t%s\n' "$stop"
        else printf 'on\t0\n'
        fi
    elif [ -n "$active" ]; then
        # only Long_Life holds the charge short of full; the kernel does not say where
        [ "$active" = Long_Life ] && printf 'on\t0\n' || printf 'off\t0\n'
    fi
}

# one row: object, native path, on or off, and the percentage it stops at
row() { # $1 = object; 1 on a failed read, 2 for a device with no limit to set
    local reply type supply supported native enabled end state
    reply="$(busctl --system --timeout=2 get-property "$service" "$1" "$interface" \
        Type PowerSupply ChargeThresholdSupported NativePath ChargeThresholdEnabled ChargeEndThreshold 2>/dev/null)" || return 1
    { read -r _ type; read -r _ supply; read -r _ supported; read -r _ native; read -r _ enabled; read -r _ end; } <<< "$reply"
    native="${native#\"}"; native="${native%\"}"
    # laptop batteries only: a mouse or headset battery supplies no power and has nothing to limit
    [ "$type" = 2 ] && [ "$supply" = true ] && [ "$supported" = true ] && valid_native "$native" || return 2
    # the limit upower would set, for a battery whose kernel names none of its own
    [[ "$end" =~ ^[0-9]{1,3}$ ]] && [ "$((10#$end))" -lt 100 ] && end=$((10#$end)) || end=0
    state="$(kernel_state "$power_root/$native")"
    # the kernel did not say: upower's flag is the only word left
    [ -n "$state" ] || { [ "$enabled" = true ] && state="on"$'\t'0 || state="off"$'\t'0; }
    [ "${state#*$'\t'}" != 0 ] || state="${state%%$'\t'*}"$'\t'"$end"
    printf '%s\t%s\t%s\n' "$1" "$native" "$state"
}

case "${1:-}" in
    list)
        reply="$(busctl --system --timeout=2 call "$service" /org/freedesktop/UPower "$service" EnumerateDevices 2>/dev/null)" || exit 1
        read -r signature _ paths <<< "$reply"
        [ "$signature" = ao ] || exit 1
        failed=0
        for path in $paths; do
            path="${path#\"}"; path="${path%\"}"
            valid_path "$path" || continue
            code=0
            row "$path" || code=$?
            [ "$code" -ne 1 ] || failed=1
        done
        # the rows that answered still print; the status says a battery could not be read
        [ "$failed" -eq 0 ] || exit 1
        ;;
    write)
        [ "$#" -eq 4 ] || exit 2
        path="$2"; want="$3"; native="$4"
        valid_path "$path" && valid_native "$native" && { [ "$want" = on ] || [ "$want" = off ]; } || exit 2
        # the battery behind the object can change on a hot-swap; only the one the row named is written
        current="$(row "$path")" || exit 3
        [ "$(cut -f2 <<< "$current")" = "$native" ] || exit 3
        [ "$want" = on ] && value=true || value=false
        # polkit may ask for a password on another system, so the call gets time to be answered
        busctl --system --timeout=60 call "$service" "$path" "$interface" EnableChargeThreshold b "$value" >/dev/null 2>&1 || exit 1
        current="$(row "$path")" || exit 1
        printf '%s\n' "$current"
        # upower drops a failed charge_types write without an error, so the kernel's answer is the result
        [ "$(cut -f3 <<< "$current")" = "$want" ] || exit 4
        ;;
    *) printf 'Usage: battery-limit.sh list | write object on|off native-path\n' >&2; exit 2 ;;
esac
