#!/usr/bin/env bash
set -eu

secs="${1:-10}"
case "$secs" in
    ''|*[!0-9]*) echo "usage: $0 [seconds>=1]" >&2; exit 2 ;;
esac
[ "$secs" -ge 1 ] || { echo "usage: $0 [seconds>=1]" >&2; exit 2; }

repo="$(cd "$(dirname "$0")/.." && pwd)"
pid="$(
    qs list --all 2>/dev/null | awk -v path="$repo/shell.qml" '
        /^  Process ID:/ { p = $3 }
        /^  Config path:/ {
            sub(/^  Config path: /, "")
            if ($0 == path && p) { print p; exit }
        }
    '
)" || true
[ -n "${pid:-}" ] || pid="$(pgrep -x qs | head -1)" || true
[ -n "${pid:-}" ] || { echo "qs not running"; exit 1; }
clk="$(getconf CLK_TCK)"

# CPU baseline before the sample window
read -r u1 s1 < <(awk '{print $14, $15}' "/proc/$pid/stat")

# Sample RSS every second throughout the window
rss_sum=0; rss_peak=0; n=0
for ((i = 0; i < secs; i++)); do
    rss_kb="$(awk '/^VmRSS:/{print $2; exit}' "/proc/$pid/status" 2>/dev/null || echo 0)"
    rss_mb=$(( rss_kb / 1024 ))
    rss_sum=$(( rss_sum + rss_mb ))
    (( rss_mb > rss_peak )) && rss_peak=$rss_mb
    n=$(( n + 1 ))
    sleep 1
done
rss_avg=$(( rss_sum / n ))

# PSS (proportional set size) — shared Qt libs counted only once, far more accurate than RSS
pss="-"
if [ -r "/proc/$pid/smaps_rollup" ]; then
    pss="$(awk '/^Pss:[[:space:]]/{printf "%.0f", $2/1024; exit}' "/proc/$pid/smaps_rollup")"
fi

# VmHWM — RSS high water mark (peak resident RAM over process lifetime)
vmpeak="$(awk '/^VmHWM:/{printf "%.0f", $2/1024; exit}' "/proc/$pid/status")"

# CPU% over the window
read -r u2 s2 < <(awk '{print $14, $15}' "/proc/$pid/stat")
cpu="$(awk -v a="$u1" -v b="$s1" -v c="$u2" -v d="$s2" -v k="$clk" -v s="$secs" \
       'BEGIN{printf "%.1f", ((c+d)-(a+b))/k/s*100}')"

threads="$(awk '/^Threads:/{print $2; exit}' "/proc/$pid/status")"
cava="$(pgrep -x cava >/dev/null 2>&1 && echo "playing" || echo "stopped")"

printf 'qs %s | rss %d avg / %d peak MB | pss %s MB | hwm %s MB | cpu %s%% over %ss | threads %s | visualizer %s\n' \
  "$pid" "$rss_avg" "$rss_peak" "$pss" "$vmpeak" "$cpu" "$secs" "$threads" "$cava"
