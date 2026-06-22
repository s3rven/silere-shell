#!/usr/bin/env bash
# Append one benchmark row to LOG.md.
# Usage: record.sh "note about this run"   (silere must be running)
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="${SILERE_REPO:-$(cd "$HERE/.." && pwd)}"
LOG="$HERE/LOG.md"
note="${*:-}"

bench="$REPO/scripts/bench.sh"
[ -x "$bench" ] || { echo "bench.sh not found at $bench — set SILERE_REPO to your checkout"; exit 1; }

if ! line="$(bash "$bench" 10)"; then
    echo "$line"
    exit 1
fi

rss_avg="$(printf '%s' "$line"  | sed -n 's/.*rss \([0-9]*\) avg.*/\1/p')"
rss_peak="$(printf '%s' "$line" | sed -n 's/.*rss [0-9]* avg \/ \([0-9]*\) peak.*/\1/p')"
pss="$(printf '%s' "$line"      | sed -n 's/.*pss \([0-9-]*\) MB.*/\1/p')"
uss="$(printf '%s' "$line"      | sed -n 's/.*uss \([0-9-]*\) MB.*/\1/p')"
tree_rss="$(printf '%s' "$line" | sed -n 's/.*tree \([0-9]*\) avg.*/\1/p')"
tree_pss="$(printf '%s' "$line" | sed -n 's/.*peak RSS, \([0-9-]*\) PSS.*/\1/p')"
cpu="$(printf '%s' "$line"      | sed -n 's/.*cpu \([0-9.]*\)%.*/\1/p')"
thr="$(printf '%s' "$line"      | sed -n 's/.*threads \([0-9]*\) +.*/\1/p')"
viz="$(printf '%s' "$line"      | sed -n 's/.*visualizer \([a-z]*\).*/\1/p')"
commit="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '-')"
dirty=""; [ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ] && dirty="*"
when="$(date '+%Y-%m-%d %H:%M')"

if [ ! -s "$LOG" ]; then
    cat > "$LOG" <<'EOF'
# Silere benchmarks

RSS includes shared mappings; PSS apportions them; USS is memory private to Silere. Tree columns include long-lived helper processes.

| Time | Commit | RSS avg | RSS peak | PSS | USS | Tree RSS | Tree PSS | CPU | Threads | Visualizer | Note |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
EOF
fi

printf '| %s | %s%s | %s | %s | %s | %s | %s | %s | %s%% | %s | %s | %s |\n' \
    "$when" "$commit" "$dirty" "$rss_avg" "$rss_peak" "$pss" "$uss" "$tree_rss" "$tree_pss" \
    "$cpu" "$thr" "$viz" "$note" >> "$LOG"

echo "logged -> $LOG"
echo "$line"
