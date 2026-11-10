#!/usr/bin/env bash
# upower owns keyboard-light permissions and supports both legacy and per-device objects
set -euo pipefail
export LC_ALL=C

interface=org.freedesktop.UPower.KbdBacklight
valid_path() { [[ "$1" =~ ^/org/freedesktop/UPower/KbdBacklight(/[A-Za-z0-9_]+)?$ ]]; }
get_int() {
    local reply signature value extra
    reply="$(busctl --system --timeout=2 call org.freedesktop.UPower "$1" "$interface" "$2" 2>/dev/null)" || return 1
    read -r signature value extra <<< "$reply"
    [[ "$signature" = i && "$value" =~ ^[0-9]{1,10}$ && -z "$extra" ]] || return 1
    value=$((10#$value))
    [ "$value" -le 2147483647 ] || return 1
    printf '%s\n' "$value"
}
identity() {
    busctl --system --timeout=2 get-property org.freedesktop.UPower "$1" "$interface" NativePath 2>/dev/null \
        || printf 'unknown\n'
}

case "${1:-}" in
    list)
        mapfile -t paths < <(busctl --system --timeout=2 --list tree org.freedesktop.UPower 2>/dev/null || true)
        seen=()
        failed=0
        for path in "${paths[@]}"; do
            valid_path "$path" || continue
            maximum="$(get_int "$path" GetMaxBrightness)" || continue
            [ "$maximum" -gt 0 ] || continue
            # only an object that answered a positive maximum is known to be a light: a tree node without the
            # interface fails GetMaxBrightness too. Past that, a failed read is reported, after the rows that worked
            current="$(get_int "$path" GetBrightness)" || { failed=1; continue; }
            [ "$current" -le "$maximum" ] || { failed=1; continue; }
            native="$(identity "$path")"
            duplicate=0
            for previous in "${seen[@]}"; do
                if [ "$native" != unknown ] && [ "$native" = "$previous" ]; then duplicate=1; break; fi
            done
            [ "$duplicate" -eq 0 ] || continue
            seen+=("$native")
            printf '%s\t%s\t%s\t%s\n' "$path" "$current" "$maximum" "$native"
        done
        [ "$failed" -eq 0 ] || exit 1
        ;;
    write)
        [ "$#" -eq 4 ] || exit 2
        path="$2"; level="$3"; native="$4"
        valid_path "$path" && [[ "$level" =~ ^[0-9]{1,10}$ ]] || exit 2
        [ "${SILERE_SANDBOX:-0}" != 1 ] || exit 1
        level=$((10#$level))
        maximum="$(get_int "$path" GetMaxBrightness)" || exit 1
        [ "$maximum" -gt 0 ] && [ "$level" -le "$maximum" ] || exit 2
        [ "$native" = unknown ] || [ "$(identity "$path")" = "$native" ] || exit 3
        busctl --system --timeout=2 call org.freedesktop.UPower "$path" "$interface" SetBrightness i "$level" >/dev/null
        ;;
    *) printf 'Usage: keyboard-brightness.sh list|write object level identity\n' >&2; exit 2 ;;
esac
