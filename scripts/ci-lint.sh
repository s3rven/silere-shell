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

section "local singleton imports"
missing_singleton_import=0
singleton_consumer_count=0
while IFS= read -r f; do
  singleton_consumer_count=$((singleton_consumer_count + 1))
  if ! grep -qE '^import[[:space:]]+"([^"]*/)?services"[[:space:]]*$' "$f"; then
    fail "$f uses a local singleton without importing the services module"
    missing_singleton_import=1
  fi
done < <(
  while IFS= read -r singleton; do
    grep -RIl --include='*.qml' -E "(^|[^A-Za-z0-9_])${singleton}\." shell.qml modules config || true
  done < <(awk '$1 == "singleton" { print $2 }' services/qmldir) | sort -u
)
if [ "$missing_singleton_import" -eq 0 ]; then
  ok "singletons" "$singleton_consumer_count consumers import services"
else
  status=1
fi

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
check_qml_locale_count services/CpuTemp.qml 1
check_qml_locale_count services/Network.qml 1
check_qml_locale_count services/PowerProfiles.qml 1
check_qml_locale_count services/Updates.qml 1

section "credential handling"
if grep -qF 'cmd.push("password")' services/Network.qml; then
  fail "Wi-Fi credentials must not be passed in process argv"
else
  ok "Wi-Fi" "credentials stay out of argv"
fi

section "public Quickshell imports"
if grep -R -n -F 'import Quickshell.Wayland._' --include='*.qml' .; then
  fail "QML files must not import private Quickshell Wayland modules"
else
  ok "Wayland" "public module only"
fi

section "loader lifetime bindings"
# Loader.item only exists while Loader.active is true. Feeding item visibility
# or status back into active creates a runtime binding loop that qmlcachegen
# does not diagnose, so keep lifetime state outside the Loader instead.
loader_item_cycles="$(grep -RInE --include='*.qml' \
  '^[[:space:]]*(active:|\|\||&&).*(^|[^A-Za-z0-9_.])item(\?)?\.(opacity|visible|status)([^A-Za-z0-9_]|$)' \
  shell.qml modules config services || true)"
if [ -n "$loader_item_cycles" ]; then
  fail "Loader.active must not depend on its own item:"
  printf '%s\n' "$loader_item_cycles"
else
  ok "Loaders" "lifetime does not depend on Loader.item"
fi

section "coordinate mapping in bindings"
# mapToItem()/mapFromItem() read ancestor geometry in C++, so a binding that
# calls them captures no dependency and keeps its first, pre-layout answer
# forever. Call them from a function when the position is needed instead.
mapped_bindings="$(grep -RInE --include='*.qml' \
  '^[[:space:]]*(readonly[[:space:]]+)?(property[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+)?[A-Za-z_][A-Za-z0-9_.]*:.*map(To|From)Item\(' \
  shell.qml modules config services | grep -vE ':[[:space:]]*on[A-Z][A-Za-z0-9_]*:' || true)"
if [ -n "$mapped_bindings" ]; then
  fail "mapToItem()/mapFromItem() must not be used in a property binding:"
  printf '%s\n' "$mapped_bindings"
else
  ok "mapping" "coordinate mapping stays out of bindings"
fi

section "reduce-motion gating"
# MotionBehavior carries the reduce-motion gate. A bare Behavior silently
# animates for users who asked for no motion, so route every one through it
# and put any extra condition on `gate:` instead of `enabled:`.
bare_behaviors="$(grep -RInE --include='*.qml' '^[[:space:]]*Behavior[[:space:]]+on[[:space:]]' \
  shell.qml modules config services || true)"
if [ -n "$bare_behaviors" ]; then
  fail "use MotionBehavior instead of a bare Behavior:"
  printf '%s\n' "$bare_behaviors"
else
  ok "motion" "every Behavior carries the reduce-motion gate"
fi
# PulseLoop derives running from `active` so the gate cannot be bypassed. Setting
# running: directly reintroduces an infinite loop that spins at zero duration.
pulse_running="$(awk '
  {
    line = $0
    sub(/\/\/.*/, "", line)
    if (!inpulse && line ~ /PulseLoop[[:space:]]*\{/) { inpulse = 1; depth = 0 }
    if (inpulse) {
      if (line ~ /running:/) print FILENAME ":" FNR ":" $0
      depth += gsub(/\{/, "{", line) - gsub(/\}/, "}", line)
      if (depth <= 0) inpulse = 0
    }
  }
' $(find modules config services -name '*.qml') || true)"
if [ -n "$pulse_running" ]; then
  fail "set active: on PulseLoop, not running::"
  printf '%s\n' "$pulse_running"
else
  ok "motion" "PulseLoop gating stays on active"
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

# A held activation key produces auto-repeat release events on Qt. Triggering
# from those releases activates early (and can repeat) instead of waiting for
# the user's real key-up event.
release_without_repeat=""
while IFS=: read -r file line _; do
  [ -n "$file" ] || continue
  end=$((line + 14))
  if ! sed -n "${line},${end}p" "$file" | grep -q 'isAutoRepeat'; then
    release_without_repeat="${release_without_repeat}${file}:${line}"$'\n'
  fi
done < <(grep -RInE --include='*.qml' 'Keys\.onReleased' shell.qml modules config services || true)
release_without_repeat="${release_without_repeat%$'\n'}"
if [ -n "$release_without_repeat" ]; then
  fail "release-based key activation must ignore auto-repeat releases:"
  printf '%s\n' "$release_without_repeat"
else
  ok "Keys" "release-based activation waits for the real key-up event"
fi

section "reduce-motion durations"
# The Behavior check above cannot see a NumberAnimation sitting inside a
# Sequential/Parallel block or a states transition. Motion.* collapses to 0 under
# reduce motion; a literal duration keeps animating for users who asked for none.
# the exclusion must match only the declaration form: animation one-liners carry
# `property: "_op"` on the same line and a bare `grep -v property` hides every real hit
raw_durations="$(grep -RInE 'duration:[[:space:]]*[0-9]' --include='*.qml' \
  shell.qml modules config services \
  | grep -vE 'property[[:space:]]+(int|real|var)[[:space:]]+duration' || true)"
if [ -n "$raw_durations" ]; then
  fail "animation durations must route through Motion.* so reduce motion can zero them:"
  printf '%s\n' "$raw_durations"
else
  ok "motion" "every animation duration routes through Motion"
fi

section "underscore property handlers"
# Qt strips leading underscores before capitalising a handler name, so property
# `_foo` is served by on_FooChanged. on_fooChanged type-checks, loads, and never
# fires — there is no runtime warning for it either.
lower_underscore_handlers="$(grep -RInE --include='*.qml' '^[[:space:]]*on_[a-z][A-Za-z0-9_]*[[:space:]]*:' \
  shell.qml modules config services || true)"
if [ -n "$lower_underscore_handlers" ]; then
  fail "underscore handlers must capitalise the property name (on_FooChanged):"
  printf '%s\n' "$lower_underscore_handlers"
else
  ok "handlers" "underscore property handlers are spelled so they fire"
fi

section "installer environment defaults"
if grep -qF '${MALLOC_CONF-' scripts/install.sh \
    && grep -qF '${QSG_TRANSIENT_IMAGES-' scripts/install.sh; then
  ok "launcher" "inherited overrides are preserved"
else
  fail "installer launcher must preserve MALLOC_CONF and QSG_TRANSIENT_IMAGES overrides"
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

section "menu module boundaries"
menu_root_public="$(awk 'NF && $1 !~ /^#/ && $1 != "internal" {print $1}' modules/menu/qmldir)"
settings_public="$(awk 'NF && $1 !~ /^#/ && $1 != "internal" {print $1}' modules/menu/settings/qmldir)"
stray_settings="$(find modules/menu -maxdepth 1 -type f \
  \( -name 'Settings*Section.qml' -o -name 'SettingsPage.qml' \
     -o -name 'DraggableWidgetList.qml' \) -print)"
back_imports="$(grep -RInE --include='*.qml' \
  '^import[[:space:]]+"\.\."[[:space:]]*$|^import[[:space:]]+"\.\./settings"' \
  modules/menu/controls modules/menu/settings || true)"
if [ "$menu_root_public" != "MenuWindow" ]; then
  fail "modules/menu must expose only MenuWindow; found: $menu_root_public"
elif [ "$settings_public" != "SettingsPage" ]; then
  fail "modules/menu/settings must expose only SettingsPage; found: $settings_public"
elif [ -n "$stray_settings" ]; then
  fail "settings implementation files belong in modules/menu/settings:"
  printf '%s\n' "$stray_settings"
elif [ -n "$back_imports" ]; then
  fail "controls/settings must not import app-level menu code:"
  printf '%s\n' "$back_imports"
else
  ok "menu modules" "root → settings → controls dependency stays one-way"
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

section "bar widget layout API"
# The three persisted order strings form one logical layout. Let ShellSettings
# validate and update them together so arranger/bar callers cannot drift.
direct_layout_writes="$(grep -RInE --include='*.qml' \
  'ShellSettings\.barWidgetOrder(Left|Center|Right)[[:space:]]*=' \
  shell.qml modules config || true)"
if [ -n "$direct_layout_writes" ]; then
    fail "bar widget order must be changed through ShellSettings layout methods:"
    printf '%s\n' "$direct_layout_writes"
else
    ok "bar layout" "writes stay behind the settings API"
fi

section "config storage boundary"
private_config_access="$(grep -RInE --include='*.qml' \
  'ShellSettings\._(configDir|configDirReady|ensureConfigDir)' \
  shell.qml modules services config || true)"
if [ -n "$private_config_access" ]; then
    fail "config consumers must use ConfigStore instead of ShellSettings internals:"
    printf '%s\n' "$private_config_access"
else
    ok "config store" "paths and directory readiness have one owner"
fi

section "solid structural surfaces"
# Structural lines, progress fills, and readability scrims are intentionally
# uniform. Gradients remain available to data visualisations and opt-in glows.
solid_surface_files=(
  modules/bar/Bar.qml
  modules/common/BarDivider.qml
  modules/menu/controls/RowDividers.qml
  modules/common/ListEdgeLines.qml
  modules/bar/widgets/MediaWidget.qml
  modules/bar/widgets/OsdBarWidget.qml
  modules/osd/OsdWindow.qml
  modules/notifications/NotificationCard.qml
  modules/menu/HomePage.qml
)
surface_gradients="$(grep -nHE 'Gradient|GradientStop|create(Linear|Radial)Gradient' \
  "${solid_surface_files[@]}" || true)"
if [ -n "$surface_gradients" ]; then
    fail "structural surfaces must use uniform fills:"
    printf '%s\n' "$surface_gradients"
else
    ok "solid fills" "structural surfaces contain no gradients"
fi

section "settings navigation coverage"
settings_nav="services/MenuState.qml"
settings_page="modules/menu/settings/SettingsPage.qml"
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

# The accent picker marks a swatch active by string-matching neutralAccent against
# its own preset list, so a default with no matching swatch opens with nothing
# selected on a fresh config.
section "accent preset coverage"
accent_section="modules/menu/settings/SettingsThemeSection.qml"
accent_default="$(sed -n 's/^[[:space:]]*property string neutralAccent:[[:space:]]*"\(#[0-9a-fA-F]\{3,8\}\)".*/\1/p' services/ShellSettings.qml)"
if [ -z "$accent_default" ]; then
  fail "could not read the neutralAccent default from services/ShellSettings.qml"
elif grep -qiF "\"$accent_default\"" "$accent_section"; then
  ok "accent" "default $accent_default has a preset swatch"
else
  fail "neutralAccent default $accent_default has no swatch in $accent_section"
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
