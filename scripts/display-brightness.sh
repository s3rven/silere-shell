#!/usr/bin/env bash
# DDC work stays outside the UI process and checks the connector's EDID before writing.
set -euo pipefail
export LC_ALL=C

drm_root=/sys/class/drm
if [ "${SILERE_SANDBOX:-0}" = 1 ]; then
    [ -n "${SILERE_TEST_DRM_ROOT:-}" ] || exit 1
    drm_root="$SILERE_TEST_DRM_ROOT"
fi

identity() { sha256sum "$1/edid" | cut -d' ' -f1; }
direct_buses() {
    local device bus
    for device in "$1"/ddc/i2c-dev/i2c-*; do
        [ -d "$device" ] || continue
        bus="${device##*i2c-}"
        [[ "$bus" =~ ^[0-9]+$ ]] && printf '%s\n' "$bus"
    done
    return 0
}

# some drivers omit the connector's ddc symlink even when ddcutil can identify its bus
detect_buses() {
    timeout 4 ddcutil detect --brief 2>/dev/null | awk '
        function remember() {
            if (name != "" && bus != "") {
                by_name[name]++
                by_bus[bus]++
                pairs[name] = bus
            }
            name = bus = ""
        }
        /^[^[:space:]]/ || /^[[:space:]]*$/ { remember(); next }
        $1 == "I2C" && $2 == "bus:" && $3 ~ /^\/dev\/i2c-[0-9]+$/ {
            bus = substr($3, length("/dev/i2c-") + 1)
        }
        $1 == "DRM" && $2 == "connector:" && $3 ~ /^card[0-9]+-[A-Za-z0-9-]+$/ { name = $3 }
        END {
            remember()
            for (name in pairs)
                if (by_name[name] == 1 && by_bus[pairs[name]] == 1)
                    printf "%s\t%s\n", name, pairs[name]
        }'
}
levels() {
    timeout 4 ddcutil --bus "$1" getvcp 10 --brief 2>/dev/null \
        | awk '$1=="VCP" && $2=="10" && $3=="C" && $4 ~ /^[0-9]+$/ && $5 ~ /^[0-9]+$/ && $5>0 && $5<=65535 && $4<=$5 {print $4, $5; found=1; exit} END {if (!found) exit 1}'
}

case "${1:-}" in
    list)
        disabled=",${2:-},"
        failed=0
        detected=0
        declare -A detected_for=()
        for connector in "$drm_root"/card*-*; do
            [ -r "$connector/status" ] && [ "$(cat "$connector/status")" = connected ] || continue
            name="${connector##*/}"
            case "$name" in *-eDP-*|*-LVDS-*|*-DSI-*) continue ;; esac
            [ -r "$connector/edid" ] || continue
            fingerprint="$(identity "$connector")" || continue
            [ "$fingerprint" != e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ] || continue
            mapfile -t buses < <(direct_buses "$connector")
            if [ "${#buses[@]}" -eq 0 ]; then
                if [ "$detected" -eq 0 ]; then
                    detected=1
                    if mapping="$(detect_buses)"; then
                        while IFS=$'\t' read -r mapped_name mapped_bus; do
                            [ -z "$mapped_name" ] || detected_for[$mapped_name]="$mapped_bus"
                        done <<< "$mapping"
                    else
                        failed=1
                    fi
                fi
                bus="${detected_for[$name]-}"
                [ -z "$bus" ] || buses=("$bus")
            fi
            asked=""; answered=0
            for bus in "${buses[@]}"; do
                [ -n "$asked" ] || asked="$bus"
                current=-1; maximum=100
                case "$disabled" in
                    *",$name:$fingerprint,"*) ;;
                    *) read -r current maximum < <(levels "$bus") || continue ;;
                esac
                printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$bus" "$fingerprint" "$current" "$maximum"
                answered=1
                break
            done
            # a display with a DDC bus that answered on none is a failed read, not an absent display: it is
            # listed as unreadable (-2) so it can be switched off, and the exit status says the list is short
            if [ -n "$asked" ] && [ "$answered" -eq 0 ]; then
                printf '%s\t%s\t%s\t-2\t100\n' "$name" "$asked" "$fingerprint"
                failed=1
            fi
        done
        [ "$failed" -eq 0 ] || exit 1
        ;;
    write)
        # the maximum comes from the scan that read this same EDID: a monitor's range is fixed, and reading it again
        # cost every step a DDC read (and, on an unlinked connector, a second detection)
        [ "$#" -eq 6 ] || exit 2
        name="$2"; bus="$3"; fingerprint="$4"; percent="$5"; maximum="$6"
        [[ "$name" =~ ^card[0-9]+-[A-Za-z0-9-]+$ && "$bus" =~ ^[0-9]+$ && "$fingerprint" =~ ^[a-f0-9]{64}$ \
            && "$percent" =~ ^[0-9]{1,3}$ && "$maximum" =~ ^[0-9]{1,5}$ ]] || exit 2
        percent=$((10#$percent)); maximum=$((10#$maximum))
        [ "$percent" -ge 1 ] && [ "$percent" -le 100 ] && [ "$maximum" -ge 1 ] && [ "$maximum" -le 65535 ] || exit 2
        connector="$drm_root/$name"
        target_present() {
            [ -r "$connector/status" ] && [ "$(cat "$connector/status")" = connected ] \
                && [ "$(identity "$connector")" = "$fingerprint" ]
        }
        check_target() {
            local mapping
            target_present || return 1
            [ ! -d "$connector/ddc/i2c-dev/i2c-$bus" ] || return 0
            [ -z "$(direct_buses "$connector")" ] && mapping="$(detect_buses)" \
                && grep -Fxq -- "$name"$'\t'"$bus" <<< "$mapping" && target_present
        }
        value=$(((percent * maximum + 50) / 100))
        [ "$value" -gt 0 ] || value=1
        check_target || exit 3
        timeout 8 ddcutil --bus "$bus" setvcp 10 "$value" >/dev/null 2>&1
        ;;
    *) echo 'Usage: display-brightness.sh list [disabled]|write connector bus identity percent maximum' >&2; exit 2 ;;
esac
