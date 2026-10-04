#!/usr/bin/env bash
set -eu

usage() {
    cat >&2 <<'USAGE'
usage: bench.sh [seconds] [--warm] [--json] [--label TEXT]

  seconds       sample window in whole seconds, default 10
  --warm        cycle the menu once before sampling, so the reading describes a
                session that has been used rather than one that has only ever
                drawn the bar
  --json        emit one JSON object instead of the readable report
  --label TEXT  free-form tag carried into the output, such as a version
USAGE
    exit 2
}

secs=""
want_json=false
want_warm=false
label=""

while [ $# -gt 0 ]; do
    case "$1" in
        --warm) want_warm=true ;;
        --json) want_json=true ;;
        --label) [ $# -ge 2 ] || usage; label="$2"; shift ;;
        --label=*) label="${1#--label=}" ;;
        -h|--help) usage ;;
        -*) echo "bench: unknown option $1" >&2; usage ;;
        *) [ -z "$secs" ] || usage; secs="$1" ;;
    esac
    shift
done

secs="${secs:-10}"
case "$secs" in
    ''|*[!0-9]*) usage ;;
esac
[ "$secs" -ge 1 ] || usage

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

# Load Home deterministically; toggling an already open menu would only close it.
warm_menu() {
    command -v qs >/dev/null 2>&1 || {
        echo "bench: --warm needs qs on PATH" >&2
        exit 1
    }
    local result
    result="$(qs ipc -p "$repo/shell.qml" call menu tab 0 2>/dev/null)" || {
        echo "bench: --warm could not reach the menu over IPC" >&2
        exit 1
    }
    if [ "$result" != ok ]; then
        printf 'bench: --warm could not open Home: %s\n' "$result" >&2
        exit 1
    fi
    sleep 2
    qs ipc -p "$repo/shell.qml" call menu close >/dev/null 2>&1 || true
    # let the allocator's dirty decay hand back what the cycle freed before sampling
    sleep 5
}

# without --warm the process is however the session left it, so do not call it idle
state="as-found"
if $want_warm; then
    warm_menu
    state="warm"
fi

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

# include reaped-child ticks so an exiting helper cannot make the tree total go backwards
accounted_cpu_ticks() {
    local target="$1"
    awk '{print ($14 + $15 + $16 + $17)}' "/proc/$target/stat" 2>/dev/null \
        || printf '0\n'
}

# A shell that leaks descriptors climbs here while everything else looks flat.
fd_count() {
    local target="$1" value
    value="$(ls -1 "/proc/$target/fd" 2>/dev/null | wc -l)" || true
    printf '%s\n' "${value:-0}"
}

tree_cpu_ticks() {
    local total member
    total="$(accounted_cpu_ticks "$pid")"
    while IFS= read -r member; do
        [ -n "$member" ] || continue
        total=$((total + $(accounted_cpu_ticks "$member")))
    done < <(descendants "$pid")
    printf '%s\n' "$total"
}

# Main-process CPU baseline before the sample window.
read -r u1 s1 < <(awk '{print $14, $15}' "/proc/$pid/stat")
tree_ticks1="$(tree_cpu_ticks)"
fds1="$(fd_count "$pid")"

# Sample both the Quickshell process and its helper-process tree. Helpers can
# appear or disappear during the window, so discover them on every sample.
rss_sum_kb=0
rss_peak_kb=0
tree_sum_kb=0
tree_peak_kb=0
n=0
cpu_ticks_prev="$(awk '{print $14 + $15}' "/proc/$pid/stat")"
cpu_samples=()
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

    cpu_ticks_now="$(awk '{print $14 + $15}' "/proc/$pid/stat" 2>/dev/null || echo "$cpu_ticks_prev")"
    cpu_samples+=("$((cpu_ticks_now - cpu_ticks_prev))")
    cpu_ticks_prev="$cpu_ticks_now"
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

fds2="$(fd_count "$pid")"
fd_delta=$((fds2 - fds1))
if [ "$fd_delta" -gt 0 ]; then
    fd_trend="+$fd_delta over ${secs}s"
elif [ "$fd_delta" -lt 0 ]; then
    fd_trend="$fd_delta over ${secs}s"
else
    fd_trend="flat over ${secs}s"
fi

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

# an average over a busy session reads like a calm one, which is how a wrong idle figure
# survives review; report the spread so a contaminated sample is visible
cpu_p50="-"
cpu_max="-"
steadiness="unknown"
if [ "${#cpu_samples[@]}" -gt 0 ]; then
    mapfile -t _sorted < <(printf '%s\n' "${cpu_samples[@]}" | sort -n)
    _mid=$(( ${#_sorted[@]} / 2 ))
    _p50_ticks="${_sorted[$_mid]}"
    _max_ticks="${_sorted[-1]}"
    cpu_p50="$(awk -v t="$_p50_ticks" -v k="$clk" 'BEGIN{printf "%.1f", t / k * 100}')"
    cpu_max="$(awk -v t="$_max_ticks" -v k="$clk" 'BEGIN{printf "%.1f", t / k * 100}')"
    # a quiet session's worst second stays near its median; input makes it jump
    if [ "$_max_ticks" -gt $(( _p50_ticks * 3 + 3 )) ]; then
        steadiness="noisy"
    else
        steadiness="steady"
    fi
fi

# archived rows only compare within one machine, so record which one produced them
first_line() { head -n 1 2>/dev/null || true; }
uptime_secs="$(awk -v k="$clk" '{printf "%d", $22 / k}' "/proc/$pid/stat" 2>/dev/null || true)"
boot_secs="$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null || true)"
[ -n "${uptime_secs:-}" ] && [ -n "${boot_secs:-}" ] \
    && uptime_secs=$((boot_secs - uptime_secs)) || uptime_secs="-"

cpu_model="$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"
kernel="$(uname -r 2>/dev/null || true)"
qs_version="$(qs --version 2>/dev/null | first_line || true)"
qs_version="${qs_version# }"
version="$(git -C "$repo" describe --tags --always --dirty 2>/dev/null || true)"
settings_file="${XDG_CONFIG_HOME:-$HOME/.config}/silere-shell/settings.json"
font_family="$(sed -n 's/.*"fontFamily"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$settings_file" 2>/dev/null | first_line || true)"
[ -n "${font_family:-}" ] || font_family="default"

# memory tracks what is drawing, and most widget keys never appear in settings.json
# because they are defaults; without the effective set two runs are not comparable
widget_set() {
    local catalog="$repo/services/ShellSettings.qml" name key def val out=""
    [ -r "$catalog" ] || { printf 'unknown\n'; return; }
    while IFS='=' read -r name key; do
        [ -n "$name" ] || continue
        if [ -z "$key" ]; then
            out="$out${out:+,}$name"
            continue
        fi
        def="$(sed -n "s/.*property bool[[:space:]]\{1,\}$key:[[:space:]]*\(true\|false\).*/\1/p" \
            "$catalog" 2>/dev/null | first_line)"
        val="$(sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p" \
            "$settings_file" 2>/dev/null | first_line)"
        [ -n "${val:-}" ] || val="${def:-false}"
        [ "$val" = true ] && out="$out${out:+,}$name"
    done < <(sed -n 's/^[[:space:]]*\([a-zA-Z][a-zA-Z0-9]*\):[[:space:]]*{.*setting:[[:space:]]*"\([^"]*\)".*/\1=\2/p' \
        "$catalog" 2>/dev/null)
    printf '%s\n' "${out:-none}"
}
widgets="$(widget_set)"

# a second instance maps the same Qt and driver pages, which moves them out of this
# process's private total: measured 7.0 MB PSS and 6.6 MB USS per extra instance, so
# neither figure is comparable across runs without knowing this count
instances=0
for _other in $(pgrep -x quickshell 2>/dev/null || true) $(pgrep -x qs 2>/dev/null || true); do
    [ "$_other" = "$pid" ] || instances=$((instances + 1))
done

if $want_json; then
    # Free-form labels and host metadata can include control characters. Escape
    # bytes under C locale so UTF-8 passes through while JSON stays on one line.
    esc() {
        local LC_ALL=C value="${1-}" ch code i
        for ((i = 0; i < ${#value}; i++)); do
            ch="${value:i:1}"
            case "$ch" in
                '"') printf '\\"' ;;
                '\') printf '\\\\' ;;
                *)
                    printf -v code '%d' "'$ch"
                    if [ "$code" -lt 32 ]; then printf '\\u%04x' "$code"
                    else printf '%s' "$ch"
                    fi
                    ;;
            esac
        done
    }
    num() { case "${1-}" in ''|*[!0-9]*) printf 'null' ;; *) printf '%s' "$1" ;; esac; }
    printf '{'
    printf '"schema":1'
    printf ',"label":"%s"' "$(esc "$label")"
    printf ',"version":"%s"' "$(esc "$version")"
    printf ',"state":"%s"' "$(esc "$state")"
    printf ',"sample_seconds":%s' "$(num "$secs")"
    printf ',"process_uptime_seconds":%s' "$(num "$uptime_secs")"
    printf ',"rss_avg_mb":%s' "$(num "$rss_avg")"
    printf ',"rss_peak_mb":%s' "$(num "$rss_peak")"
    printf ',"pss_mb":%s' "$(num "$pss")"
    printf ',"uss_mb":%s' "$(num "$uss")"
    printf ',"hwm_mb":%s' "$(num "$vmpeak")"
    printf ',"tree_pss_mb":%s' "$(num "$tree_pss")"
    printf ',"cpu_percent":%s' "${cpu:-null}"
    printf ',"tree_cpu_percent":%s' "${tree_cpu:-null}"
    printf ',"cpu_p50_percent":%s' "${cpu_p50/-/null}"
    printf ',"cpu_max_percent":%s' "${cpu_max/-/null}"
    printf ',"steadiness":"%s"' "$(esc "$steadiness")"
    printf ',"threads":%s' "$(num "$threads")"
    printf ',"helpers":%s' "$(num "$helpers")"
    printf ',"fds":%s' "$(num "$fds2")"
    printf ',"fd_delta":%s' "$fd_delta"
    printf ',"visualizer":"%s"' "$(esc "$visualizer")"
    printf ',"allocator":"%s"' "$(esc "$allocator")"
    printf ',"font_family":"%s"' "$(esc "$font_family")"
    printf ',"widgets":"%s"' "$(esc "$widgets")"
    printf ',"other_instances":%s' "$(num "$instances")"
    printf ',"cpu_model":"%s"' "$(esc "$cpu_model")"
    printf ',"kernel":"%s"' "$(esc "$kernel")"
    printf ',"quickshell":"%s"' "$(esc "$qs_version")"
    printf '}\n'
    exit 0
fi

printf '== silere bench ==\n'
printf 'qs pid:     %s (%ss sample)\n' "$pid" "$secs"
printf 'state:      %s, up %ss\n' "$state" "$uptime_secs"
[ -n "$label" ] && printf 'label:      %s\n' "$label"
[ -n "$version" ] && printf 'version:    %s\n' "$version"
printf 'main rss:   %d MB avg / %d MB peak\n' "$rss_avg" "$rss_peak"
printf 'main mem:   PSS %s MB, USS %s MB, HWM %s MB\n' "$pss" "$uss" "$vmpeak"
printf 'tree rss:   %d MB avg / %d MB peak, PSS %s MB\n' "$tree_avg" "$tree_peak" "$tree_pss"
printf 'cpu:        %s%% main / %s%% tree\n' "$cpu" "$tree_cpu"
printf 'per-second: median %s%%, worst %s%% (%s)\n' "$cpu_p50" "$cpu_max" "$steadiness"
printf 'processes:  %s threads + %s helpers\n' "$threads" "$helpers"
printf 'fds:        %s open (%s)\n' "$fds2" "$fd_trend"
printf 'widgets:    %s\n' "$widgets"
[ "$instances" -gt 0 ] && printf 'note:       %s other Quickshell instance(s) running; memory reads low (~7 MB per instance)\n' "$instances"
printf 'visualizer: %s\n' "$visualizer"
printf 'allocator:  %s\n' "$allocator"
printf 'font:       %s\n' "$font_family"
printf 'machine:    %s, kernel %s\n' "${cpu_model:-unknown}" "${kernel:-unknown}"
printf 'runtime:    %s\n' "${qs_version:-unknown}"
