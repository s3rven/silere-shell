#!/usr/bin/env bash
# Structural lint — runs anywhere, no Qt/Quickshell or compositor needed.
# Deeper QML type-checking needs Quickshell installed (not feasible on stock
# CI runners), so this catches the common, cheap-to-detect breakages:
#   - merge conflict markers left in code
#   - broken shell scripts
#   - qmldir entries pointing at files that don't exist
#   - ShellSettings properties and schema drifting apart
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
status=0
fail() { printf 'FAIL: %s\n' "$*"; status=1; }

echo "== merge conflict markers =="
if git grep -n -I -E '^(<<<<<<< |=======$|>>>>>>> )' -- . ; then
  fail "conflict markers found"
else
  echo "ok"
fi

echo
echo "== shell script syntax =="
for f in scripts/*.sh; do
  if err=$(bash -n "$f" 2>&1); then printf 'ok   %s\n' "$f"; else fail "syntax error in $f"; printf '%s\n' "$err"; fi
done

echo
echo "== shellcheck =="
if command -v shellcheck >/dev/null 2>&1; then
  # error severity only — real bugs gate the build, style nits don't
  if shellcheck --severity=error scripts/*.sh; then echo "ok"; else fail "shellcheck reported errors"; fi
else
  echo "skipped (shellcheck not installed)"
fi

echo
echo "== qmldir integrity =="
missing=""
while IFS= read -r qd; do
  dir="$(dirname "$qd")"
  while read -r f; do
    [ -f "$dir/$f" ] && continue
    # generated files (e.g. matugen's MatugenTheme.qml) are gitignored and only
    # exist after install — absent on a fresh checkout, which is expected.
    git check-ignore -q "$dir/$f" 2>/dev/null && continue
    missing="$missing $dir/$f"
  done < <(awk 'NF>=2 && $NF ~ /\.qml$/ {print $NF}' "$qd")
done < <(find . \( -path './.git' -o -path './.claude' -o -path './.agents' \) -prune -o -name qmldir -print)
if [ -n "$missing" ]; then
  fail "qmldir references missing files:"
  for m in $missing; do printf '  %s\n' "$m"; done
else
  echo "ok"
fi

echo
echo "== settings schema coverage =="
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
        echo "ok"
    else
        :
    fi
else
    echo "skipped (ShellSettings.qml not found)"
fi

echo
[ "$status" -eq 0 ] && echo "lint passed" || echo "lint failed"
exit "$status"
