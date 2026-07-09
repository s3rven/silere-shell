#!/usr/bin/env bash
set -eu

secs="${1:-10}"
case "$secs" in
    ''|*[!0-9]*) echo "usage: $0 [seconds>=1]" >&2; exit 2 ;;
esac
[ "$secs" -ge 1 ] || { echo "usage: $0 [seconds>=1]" >&2; exit 2; }

repo="$(cd "$(dirname "$0")/.." && pwd)"

find_pid() {
    qs list --all 2>/dev/null | awk -v path="$repo/shell.qml" '
        /^  Process ID:/ { p = $3 }
        /^  Config path:/ {
            sub(/^  Config path: /, "")
            if ($0 == path && p) { print p; exit }
        }
    '
}

pid="$(find_pid)" || true
[ -n "${pid:-}" ] || { echo "qs not running for $repo/shell.qml" >&2; exit 1; }
[ -r "/proc/$pid/stat" ] || {
    echo "cannot read host metrics for qs $pid (/proc is unavailable in this namespace)" >&2
    exit 1
}

clk="$(getconf CLK_TCK)"
start_time="$(awk '{print $22}' "/proc/$pid/stat")"

process_alive() {
    [ -r "/proc/$pid/stat" ] \
        && [ "$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null)" = "$start_time" ]
}

descendants() {
    local parent="$1" child children
    [ -r "/proc/$parent/task/$parent/children" ] || return 0
    children="$(<"/proc/$parent/task/$parent/children")" 2>/dev/null || return 0
    for child in $children; do
        [ -d "/proc/$child" ] || continue
        printf '%s\n' "$child"
        descendants "$child"
    done
}

rss_kb() {
    local value
    value="$(awk '/^VmRSS:/{print $2; found=1; exit} END{if (!found) print 0}' "/proc/$1/status" 2>/dev/null)" || true
    printf '%s\n' "${value:-0}"
}

rollup_kb() {
    local target="$1" field="$2" value
    value="$(awk -v field="$field" '$1 == field":" {sum += $2} END {print sum + 0}' \
        "/proc/$target/smaps_rollup" 2>/dev/null)" || true
    printf '%s\n' "${value:-0}"
}

cpu_ticks() {
    local target="$1"
    awk '{print ($14 + $15)}' "/proc/$target/stat" 2>/dev/null || printf '0\n'
}

tree_cpu_ticks() {
    local total member
    total="$(cpu_ticks "$pid")"
    while IFS= read -r member; do
        [ -n "$member" ] || continue
        total=$((total + $(cpu_ticks "$member")))
    done < <(descendants "$pid")
    printf '%s\n' "$total"
}

# Main-process CPU baseline before the sample window.
read -r u1 s1 < <(awk '{print $14, $15}' "/proc/$pid/stat")
tree_ticks1="$(tree_cpu_ticks)"

# Sample both the Quickshell process and its helper-process tree. Helpers can
# appear or disappear during the window, so discover them on every sample.
rss_sum_kb=0
rss_peak_kb=0
tree_sum_kb=0
tree_peak_kb=0
n=0
for ((i = 0; i < secs; i++)); do
    process_alive || {
        echo "qs $pid exited or restarted after ${i}s; discard this sample and retry" >&2
        exit 1
    }

    main_kb="$(rss_kb "$pid")"
    tree_kb="$main_kb"
    while IFS= read -r child; do
        [ -n "$child" ] && tree_kb=$((tree_kb + $(rss_kb "$child")))
    done < <(descendants "$pid")

    rss_sum_kb=$((rss_sum_kb + main_kb))
    tree_sum_kb=$((tree_sum_kb + tree_kb))
    (( main_kb > rss_peak_kb )) && rss_peak_kb=$main_kb
    (( tree_kb > tree_peak_kb )) && tree_peak_kb=$tree_kb
    n=$((n + 1))
    sleep 1
done

process_alive || {
    echo "qs $pid exited or restarted at the end of the sample; discard it and retry" >&2
    exit 1
}

rss_avg=$((rss_sum_kb / n / 1024))
rss_peak=$((rss_peak_kb / 1024))
tree_avg=$((tree_sum_kb / n / 1024))
tree_peak=$((tree_peak_kb / 1024))

# PSS apportions shared Qt/driver mappings; USS is memory private to Silere.
pss="-"
uss="-"
if [ -r "/proc/$pid/smaps_rollup" ]; then
    pss="$(( $(rollup_kb "$pid" Pss) / 1024 ))"
    uss_kb=$(( $(rollup_kb "$pid" Private_Clean) + $(rollup_kb "$pid" Private_Dirty) ))
    uss="$((uss_kb / 1024))"
fi

tree_pss_kb=0
tree_pss_known=true
for member in "$pid" $(descendants "$pid"); do
    if [ -r "/proc/$member/smaps_rollup" ]; then
        tree_pss_kb=$((tree_pss_kb + $(rollup_kb "$member" Pss)))
    else
        tree_pss_known=false
    fi
done
tree_pss="-"
$tree_pss_known && tree_pss="$((tree_pss_kb / 1024))"

vmpeak="$(awk '/^VmHWM:/{printf "%.0f", $2/1024; found=1; exit} END{if (!found) print "-"}' "/proc/$pid/status")"

read -r u2 s2 < <(awk '{print $14, $15}' "/proc/$pid/stat")
cpu="$(awk -v a="$u1" -v b="$s1" -v c="$u2" -v d="$s2" -v k="$clk" -v s="$secs" \
    'BEGIN{printf "%.1f", ((c+d)-(a+b))/k/s*100}')"
tree_ticks2="$(tree_cpu_ticks)"
tree_cpu="$(awk -v a="$tree_ticks1" -v b="$tree_ticks2" -v k="$clk" -v s="$secs" \
    'BEGIN{printf "%.1f", (b-a)/k/s*100}')"

threads="$(awk '/^Threads:/{print $2; exit}' "/proc/$pid/status")"
visualizer="stopped"
helpers=0
while IFS= read -r child; do
    [ -n "$child" ] || continue
    helpers=$((helpers + 1))
    [ "$(cat "/proc/$child/comm" 2>/dev/null || true)" = "cava" ] && visualizer="playing"
done < <(descendants "$pid")

allocator="unknown"
if [ -r "/proc/$pid/environ" ]; then
    if tr '\0' '\n' < "/proc/$pid/environ" | grep -q '^MALLOC_CONF='; then
        allocator="tuned"
    else
        allocator="default"
    fi
fi

printf '== silere bench ==\n'
printf 'qs pid:     %s (%ss sample)\n' "$pid" "$secs"
printf 'main rss:   %d MB avg / %d MB peak\n' "$rss_avg" "$rss_peak"
printf 'main mem:   PSS %s MB, USS %s MB, HWM %s MB\n' "$pss" "$uss" "$vmpeak"
printf 'tree rss:   %d MB avg / %d MB peak, PSS %s MB\n' "$tree_avg" "$tree_peak" "$tree_pss"
printf 'cpu:        %s%% main / %s%% tree\n' "$cpu" "$tree_cpu"
printf 'processes:  %s threads + %s helpers\n' "$threads" "$helpers"
printf 'visualizer: %s\n' "$visualizer"
printf 'allocator:  %s\n' "$allocator"
