#!/usr/bin/env bash
# Structural lint — runs anywhere, no Qt/Quickshell or compositor needed.
# Deeper QML type-checking needs Quickshell installed (not feasible on stock
# CI runners), so this catches the common, cheap-to-detect breakages:
#   - merge conflict markers left in code
#   - broken shell scripts
#   - qmldir entries pointing at files that don't exist
#   - required Quickshell service imports and local module packaging
#   - non-portable Keys attached handlers rejected by the live QML engine
#   - ShellSettings properties and schema drifting apart
#   - settings navigation entries and detail components drifting apart
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
check_service_module Network Quickshell.Networking

section "shell script syntax"
for f in "${script_files[@]}"; do
  if err=$(bash -n "$f" 2>&1); then ok "$f"; else fail "syntax error in $f"; printf '%s\n' "$err"; fi
done

section "locale-stable parsers"
for f in scripts/check.sh scripts/install.sh scripts/update.sh scripts/uninstall.sh; do
  if grep -q '^export LC_ALL=C$' "$f"; then ok "$f"; else fail "$f must set LC_ALL=C"; fi
done
check_qml_locale_count() {
  local file="$1" expected="$2" actual
  actual="$(grep -c 'environment: ({ "LC_ALL": "C" })' "$file" || true)"
  if [ "$actual" -ge "$expected" ]; then
    ok "$file" "$actual parser process(es)"
  else
    fail "$file has $actual locale-stable parser process(es), expected at least $expected"
  fi
}
check_qml_locale_count services/Battery.qml 1
check_qml_locale_count services/Network.qml 1
check_qml_locale_count services/PowerProfiles.qml 1
check_qml_locale_count services/Updates.qml 1

section "credential handling"
if grep -qF 'cmd.push("password")' services/Network.qml; then
  fail "Wi-Fi credentials must not be passed in process argv"
elif grep -qF 'connectWithPsk(password)' services/Network.qml; then
  ok "Wi-Fi" "credentials use the native networking API"
elif ! grep -qF 'stdinEnabled: true' services/Network.qml \
    || ! grep -qF '"--ask"' services/Network.qml; then
  fail "Wi-Fi credentials must be sent to nmcli over stdin"
else
  ok "Wi-Fi" "credentials stay out of argv"
fi

section "public Quickshell imports"
if grep -R -n -F 'import Quickshell.Wayland._' --include='*.qml' .; then
  fail "QML files must not import private Quickshell Wayland modules"
else
  ok "Wayland" "public module only"
fi

section "portable QML key handlers"
# qmlcachegen accepts arbitrary Keys.onFooPressed names, but the live engine
# rejects handlers that are not signals on QtQuick.Keys. Keep this allowlist
# explicit so a typo cannot make the entire shell fail at startup again.
key_handlers="$(grep -RhoE 'Keys\.on[A-Za-z0-9_]+' --include='*.qml' shell.qml modules config services \
    | sed 's/^Keys\.//' | sort -u)"
unsupported_key_handlers="$(printf '%s\n' "$key_handlers" \
    | grep -vE '^(onPressed|onReleased|onUpPressed|onDownPressed|onLeftPressed|onRightPressed|onSpacePressed|onReturnPressed|onEnterPressed|onEscapePressed|onMenuPressed)$' \
    || true)"
if [ -n "$unsupported_key_handlers" ]; then
  fail "unsupported Keys attached handlers:"
  while IFS= read -r handler; do printf '  Keys.%s\n' "$handler"; done <<< "$unsupported_key_handlers"
else
  ok "Keys" "attached handlers are runtime-portable"
fi

section "installer environment defaults"
if grep -qF '${MALLOC_CONF-' scripts/install.sh \
    && grep -qF '${QSG_TRANSIENT_IMAGES-' scripts/install.sh; then
  ok "launcher" "inherited overrides are preserved"
else
  fail "installer launcher must preserve MALLOC_CONF and QSG_TRANSIENT_IMAGES overrides"
fi

section "responsive layout contracts"
if grep -qF '_availablePanelW' modules/menu/MenuWindow.qml \
    && grep -qF '_availablePanelH' modules/menu/MenuWindow.qml \
    && grep -qF 'targetScreen.width - 24' modules/notifications/NotificationPopups.qml; then
  ok "popups" "bounded to the target output"
else
  fail "menu and notification popups must stay bounded to the target output"
fi
if grep -qF 'SettingsSystemSection {}' modules/menu/SettingsPage.qml \
    && grep -qF 'SettingsSystemSection.qml' modules/menu/qmldir; then
  ok "settings" "large system subtree remains isolated"
else
  fail "system settings must remain split from the main settings page"
fi

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

section "settings navigation coverage"
settings_nav="services/MenuState.qml"
settings_page="modules/menu/SettingsPage.qml"
if [ -f "$settings_nav" ] && [ -f "$settings_page" ]; then
    nav_sections=$(grep -oE 'section: "[^"]+"' "$settings_nav" \
                   | sed -E 's/.*"([^"]+)"/\1/' | sort -u)
    mapped_sections=$(sed -n '/readonly property var _sectionComponents: ({/,/^[[:space:]]*})/p' "$settings_page" \
                      | grep -oE '[a-zA-Z][a-zA-Z0-9]*:' | tr -d ':' \
                      | grep -v '^sectionComponents$' | sort -u)
    missing=$(comm -23 <(printf '%s\n' "$nav_sections") <(printf '%s\n' "$mapped_sections"))
    extra=$(comm -13 <(printf '%s\n' "$nav_sections") <(printf '%s\n' "$mapped_sections"))
    if [ -n "$missing" ]; then
        fail "settings navigation entries without detail components:"
        while IFS= read -r m; do printf '  %s\n' "$m"; done <<< "$missing"
    fi
    if [ -n "$extra" ]; then
        fail "settings detail components missing from navigation:"
        while IFS= read -r m; do printf '  %s\n' "$m"; done <<< "$extra"
    fi
    if [ -z "$missing" ] && [ -z "$extra" ]; then
        ok "navigation" "entries match detail components"
    fi
else
    skip "navigation" "settings navigation files not found"
fi

section "theme palette coverage"
theme_tmpl="assets/matugen-theme.qml"
theme_default="config/MatugenTheme.default.qml"
if [ -f "$theme_tmpl" ] && [ -f "$theme_default" ]; then
    # roles the shell actually reads; the MatugenTheme.qml/.default.qml filename
    # mentions in comments collapse to a bare "qml", so drop it
    used=$(grep -rhoE 'MatugenTheme\.[a-zA-Z_][a-zA-Z0-9_]*' --include='*.qml' . \
           | sed 's/^MatugenTheme\.//' | grep -vx qml | sort -u)
    declared_roles() {
        grep -oE 'property +[a-zA-Z]+ +[a-zA-Z][a-zA-Z0-9]*' "$1" | awk '{print $NF}' | sort -u
    }
    theme_gap=0
    for f in "$theme_tmpl" "$theme_default"; do
        gap=$(comm -23 <(printf '%s\n' "$used") <(declared_roles "$f"))
        if [ -n "$gap" ]; then
            theme_gap=1
            fail "$f is missing palette roles the shell reads:"
            while IFS= read -r m; do printf '  %s\n' "$m"; done <<< "$gap"
        fi
    done
    if [ "$theme_gap" -eq 0 ]; then
        ok "theme" "matugen template and bundled default cover every role read"
    fi
else
    skip "theme" "matugen template or bundled default not found"
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
