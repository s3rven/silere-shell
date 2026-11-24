#!/usr/bin/env bash
# The gates a pass can run beside a live desktop without asking: one suite at a time, at low priority. dev/check.sh
# adds the nested compositor, screens, audio and stress probes, which load every core, and stays the final gate.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
logs="$(mktemp -d)"
trap 'rm -rf -- "$logs"' EXIT
status=0
# ci-lint runs the daily-driver probe through its helper fixtures, so it is not listed on its own
for suite in scripts/test-qml-headless.sh dev/test-logic.sh dev/test-layout-fit.sh dev/ci-lint.sh; do
    name="${suite##*/}"
    name="${name%.sh}"
    start=$SECONDS
    if nice -n 10 bash "$ROOT/$suite" > "$logs/$name.log" 2>&1; then
        printf 'ok   %-20s %4ss  %s\n' "$name" "$((SECONDS - start))" "$(grep -v '^[[:space:]]*$' "$logs/$name.log" | tail -n 1)"
    else
        status=1
        printf 'fail %-20s %4ss\n' "$name" "$((SECONDS - start))"
        tail -n 25 "$logs/$name.log" | sed 's/^/     /'
    fi
done
exit "$status"
