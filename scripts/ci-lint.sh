#!/usr/bin/env bash
# Structural lint — runs anywhere, no Qt/Quickshell or compositor needed.
# Deeper QML type-checking needs Quickshell installed (not feasible on stock
# CI runners), so this catches the common, cheap-to-detect breakages:
#   - merge conflict markers left in code
#   - broken shell scripts
#   - qmldir entries pointing at files that don't exist
#   - required Quickshell service imports and local module packaging
#   - ShellSettings properties and schema drifting apart
#   - installer/updater portability regressions
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
status=0
seen_section=0
section() {
  [ "$seen_section" -eq 0 ] || printf '\n'
  seen_section=1
  printf '== %s ==\n' "$1"
}
ok() {
  if [ "$#" -gt 1 ] && [ -n "$2" ]; then printf 'ok   %-15s %s\n' "$1" "$2"
  else printf 'ok   %s\n' "$1"
  fi
}
skip() {
  if [ "$#" -gt 1 ] && [ -n "$2" ]; then printf 'skip %-15s %s\n' "$1" "$2"
  else printf 'skip %s\n' "$1"
  fi
}
fail() { printf 'fail %s\n' "$*" >&2; status=1; }
script_files=(scripts/*.sh scripts/lib/*.sh)

section "merge conflict markers"
# grep, not git grep: in CI the container may have no git at checkout time, so
# the tree is checked out without a .git. This lint is meant to run on a plain tree.
if grep -rn -I -E '^(<<<<<<< |=======$|>>>>>>> )' --exclude-dir=.git . ; then
  fail "conflict markers found"
else
  ok "markers" "none"
fi

section "required service modules"
check_service_module() {
  local service="$1" module="$2"
  if [ ! -f "services/$service.qml" ]; then
    fail "services/$service.qml is missing"
  elif ! grep -qE "^import[[:space:]]+$module([[:space:]]|$)" "services/$service.qml"; then
    fail "services/$service.qml must import $module"
  elif ! awk -v name="$service" '$1 == "singleton" && $2 == name && $NF == name ".qml" { found=1 } END { exit !found }' services/qmldir; then
    fail "services/qmldir must package singleton $service"
  else
    ok "$service" "$module"
  fi
}
check_service_module Audio Quickshell.Services.Pipewire
check_service_module Battery Quickshell.Services.UPower
check_service_module Media Quickshell.Services.Mpris
check_service_module Notifications Quickshell.Services.Notifications
check_service_module Bluetooth Quickshell.Bluetooth

section "shell script syntax"
for f in "${script_files[@]}"; do
  if err=$(bash -n "$f" 2>&1); then ok "$f"; else fail "syntax error in $f"; printf '%s\n' "$err"; fi
done

section "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  # error severity only — real bugs gate the build, style nits don't
  if shellcheck --severity=error "${script_files[@]}"; then ok "shellcheck"; else fail "shellcheck reported errors"; fi
else
  skip "shellcheck" "not installed"
fi

section "qmldir integrity"
missing=""
while IFS= read -r qd; do
  dir="$(dirname "$qd")"
  while read -r f; do
    [ -f "$dir/$f" ] && continue
    # generated files (e.g. matugen's MatugenTheme.qml) ship as a tracked
    # *.default.qml and are copied into place on install — absent on a fresh
    # checkout, which is expected. (No git here: CI may have no .git.)
    [ -f "$dir/${f%.qml}.default.qml" ] && continue
    missing="$missing $dir/$f"
  done < <(awk 'NF>=2 && $NF ~ /\.qml$/ {print $NF}' "$qd")
done < <(find . -path './.git' -prune -o -name qmldir -print)
if [ -n "$missing" ]; then
  fail "qmldir references missing files:"
  for m in $missing; do printf '  %s\n' "$m"; done
else
  ok "qmldir" "all referenced files exist"
fi

section "settings schema coverage"
settings="services/ShellSettings.qml"
if [ -f "$settings" ]; then
    # public (non-underscore) mutable properties — these must all be in _schema
    declared=$(grep -v 'readonly' "$settings" \
               | grep -oE 'property (bool|int|real|string) +[a-zA-Z][a-zA-Z0-9]*' \
               | awk '{print $NF}' | sort)
    schema=$(grep -oE '\{ k: "[^"]*"' "$settings" | grep -oE '"[^"]*"$' | tr -d '"' | sort)
    missing=$(comm -23 <(echo "$declared") <(echo "$schema"))
    extra=$(comm -13 <(echo "$declared") <(echo "$schema"))
    if [ -n "$missing" ]; then
        fail "ShellSettings properties missing from _schema:"
        echo "$missing" | while read -r m; do printf '  %s\n' "$m"; done
    fi
    if [ -n "$extra" ]; then
        fail "ShellSettings _schema keys without properties:"
        echo "$extra" | while read -r m; do printf '  %s\n' "$m"; done
    fi
    if [ -z "$missing" ] && [ -z "$extra" ]; then
        ok "settings" "properties match _schema"
    else
        :
    fi
else
    skip "settings" "ShellSettings.qml not found"
fi

section "portability regressions"
if bash scripts/test-portability.sh; then
  ok "portability"
else
  fail "portability regression tests failed"
fi

if [ "$status" -eq 0 ]; then
  printf '\nlint passed\n'
else
  printf '\nlint failed\n'
fi
exit "$status"
