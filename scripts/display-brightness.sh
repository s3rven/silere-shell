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
levels() {
    timeout 4 ddcutil --bus "$1" getvcp 10 --brief 2>/dev/null \
        | awk '$1=="VCP" && $2=="10" && $3=="C" && $4 ~ /^[0-9]+$/ && $5 ~ /^[0-9]+$/ && $5>0 && $5<=65535 && $4<=$5 {print $4, $5; found=1; exit} END {if (!found) exit 1}'
}

case "${1:-}" in
    list)
        disabled=",${2:-},"
        for connector in "$drm_root"/card*-*; do
            [ -r "$connector/status" ] && [ "$(cat "$connector/status")" = connected ] || continue
            name="${connector##*/}"
            case "$name" in *-eDP-*|*-LVDS-*|*-DSI-*) continue ;; esac
            [ -r "$connector/edid" ] || continue
            fingerprint="$(identity "$connector")" || continue
            [ "$fingerprint" != e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ] || continue
            for device in "$connector"/ddc/i2c-dev/i2c-*; do
                [ -d "$device" ] || continue
                bus="${device##*i2c-}"
                case "$bus" in ''|*[!0-9]*) continue ;; esac
                current=-1; maximum=100
                case "$disabled" in
                    *",$name:$fingerprint,"*) ;;
                    *) read -r current maximum < <(levels "$bus") || continue ;;
                esac
                printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$bus" "$fingerprint" "$current" "$maximum"
                break
            done
        done
        ;;
    write)
        [ "$#" -eq 5 ] || exit 2
        name="$2"; bus="$3"; fingerprint="$4"; percent="$5"
        [[ "$name" =~ ^card[0-9]+-[A-Za-z0-9-]+$ && "$bus" =~ ^[0-9]+$ \
            && "$fingerprint" =~ ^[a-f0-9]{64}$ && "$percent" =~ ^[0-9]{1,3}$ ]] || exit 2
        percent=$((10#$percent))
        [ "$percent" -ge 1 ] && [ "$percent" -le 100 ] || exit 2
        connector="$drm_root/$name"
        check_target() {
            [ -r "$connector/status" ] && [ "$(cat "$connector/status")" = connected ] \
                && [ -d "$connector/ddc/i2c-dev/i2c-$bus" ] \
                && [ "$(identity "$connector")" = "$fingerprint" ]
        }
        check_target || exit 3
        read -r _current maximum < <(levels "$bus") || exit 1
        value=$(((percent * maximum + 50) / 100))
        [ "$value" -gt 0 ] || value=1
        # an unplug while reading must not turn a queued write into a different display's value
        check_target || exit 3
        timeout 8 ddcutil --bus "$bus" setvcp 10 "$value" >/dev/null 2>&1
        ;;
    *) echo 'Usage: display-brightness.sh list [disabled]|write connector bus identity percent' >&2; exit 2 ;;
esac
