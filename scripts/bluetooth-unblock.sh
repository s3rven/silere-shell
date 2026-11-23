#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

adapter="${1:-}"
[[ "$adapter" =~ ^hci[0-9]+$ ]] || exit 2

rows="$(rfkill --noheadings --raw --output ID,DEVICE,HARD list bluetooth)"
count=0
target=""
platform=""
while read -r id device hard; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    count=$((count + 1))
    if [ "$device" = "$adapter" ]; then
        [ -z "$target" ] && [ "$hard" = unblocked ] || exit 1
        target="$id"
    elif [[ "$device" != hci[0-9]* && "$hard" = unblocked ]]; then
        platform="$id"
    fi
done <<< "$rows"

# Some laptops expose only a platform switch. Use it when there is one controller and one switch.
if [ -z "$target" ] && [ "${2:-0}" = 1 ] && [ "$count" = 1 ]; then
    target="$platform"
fi
[ -n "$target" ] || exit 1
exec rfkill unblock "$target"
