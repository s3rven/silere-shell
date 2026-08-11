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
source "$ROOT/scripts/lib/qml-modules.sh"
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
# grep, not git grep: this lint is also meant to work from a release archive or
# any other plain source tree without repository metadata.
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

section "external QML module inventory"
imported_modules="$(
  # MatugenTheme.qml is a local generated file; inventory the shipped template
  # instead so personal output cannot change validation results.
  grep -RhE --include='*.qml' --exclude='MatugenTheme.qml' \
    '^[[:space:]]*import[[:space:]]+[A-Za-z][A-Za-z0-9_.]*([[:space:]]|$)' \
    shell.qml modules config services assets/matugen-theme.qml \
    | awk '$1 == "import" { print $2 }' | sort -u
)"
required_modules="$(printf '%s\n' "${SILERE_REQUIRED_QML_MODULES[@]}" | sort -u)"
unlisted_modules="$(comm -23 <(printf '%s\n' "$imported_modules") \
  <(printf '%s\n' "$required_modules"))"
unused_modules="$(comm -13 <(printf '%s\n' "$imported_modules") \
  <(printf '%s\n' "$required_modules"))"
if [ -n "$unlisted_modules" ] || [ -n "$unused_modules" ]; then
  [ -z "$unlisted_modules" ] || fail "unlisted unconditional QML modules: $unlisted_modules"
  [ -z "$unused_modules" ] || fail "required QML modules no longer imported: $unused_modules"
else
  ok "modules" "inventory covers every unconditional external import"
fi

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

section "signed shell updates"
if awk 'NF == 0 || /^#/ { next } \
        NF == 4 && $1 == "silere-release" && $2 == "namespaces=\"git\"" \
        && $3 == "ssh-ed25519" && $4 ~ /^AAA[A-Za-z0-9+\/=]+$/ { valid++; next } \
        { bad=1 } END { exit bad || valid < 1 }' security/update-signers \
        && grep -qF 'verify-tag "$release_tag"' scripts/update.sh \
        && grep -qF 'tag --merged origin/main' scripts/update.sh \
        && grep -qF 'verify-tag "$GITHUB_REF_NAME"' .github/workflows/release.yml \
        && ! grep -qF 'ShellUpdate.apply()' modules/bar/widgets/ShellUpdateWidget.qml; then
  ok "shell updater" "trust key, signed release gates, and review-only bar action"
else
  fail "shell updater must verify stable release tags before the UI can apply them"
fi

section "optional tool detection"
# The status of the final command in a shell `for` loop becomes the loop's
# status. Since fc-list is optional and currently last, an explicit success is
# required or its absence makes SystemTools discard every earlier match.
if grep -qF '"done; exit 0"]' services/SystemTools.qml; then
  ok "SystemTools" "optional final lookup cannot fail the completed probe"
else
  fail "SystemTools tool probe must exit successfully after scanning optional tools"
fi

section "credential handling"
if grep -qF 'cmd.push("password")' services/Network.qml; then
  fail "Wi-Fi credentials must not be passed in process argv"
else
  ok "Wi-Fi" "credentials stay out of argv"
fi

section "Bluetooth battery normalization"
if ! grep -qF 'function batteryPercent(device)' services/Bluetooth.qml; then
  fail "Bluetooth battery conversion must have one validated service helper"
elif grep -qF 'Math.round(modelData.battery' modules/menu/BluetoothList.qml; then
  fail "Bluetooth menu must use the shared battery conversion"
else
  ok "Bluetooth" "battery labels use a validated shared conversion"
fi

section "live backend collection fallbacks"
if grep -qF 'const all = Pipewire.nodes.values' services/Audio.qml; then
  fail "PipeWire node model must tolerate a reconnecting backend"
elif grep -qF '? adapter.devices.values : []' services/Bluetooth.qml; then
  fail "Bluetooth device model must tolerate backend re-enumeration"
else
  ok "collections" "live backend models have empty-state fallbacks"
fi

section "public Quickshell imports"
if grep -R -n -F 'import Quickshell.Wayland._' --include='*.qml' .; then
  fail "QML files must not import private Quickshell Wayland modules"
else
  ok "Wayland" "public module only"
fi

section "niri event stream lifecycle"
# Quickshell Socket buffers writes until flush(), so the Niri event-stream
# subscription otherwise never reaches the compositor. A dropped compositor
# socket also changes connected to false and needs an explicit retry.
if ! awk '
    /write\("\\"EventStream\\"\\n"\)/ { line = NR }
    line && NR <= line + 2 && /flush\(\)/ { flushed = 1 }
    END { exit !flushed }
' services/Compositor.qml; then
  fail "Niri EventStream request must flush the socket write"
elif ! grep -qF 'id: _niriReconnect' services/Compositor.qml \
    || ! grep -qF 'running: root.isNiri && !_niriSocket.connected' services/Compositor.qml; then
  fail "Niri socket must retry after a dropped connection"
else
  ok "niri socket" "event stream flushes and reconnects"
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
# -print0/xargs: an unquoted $(find) word-splits on a path containing a space,
# which would feed awk bogus filenames and let `|| true` swallow the failure —
# the check would then pass by reporting nothing.
pulse_running="$(find modules config services -name '*.qml' -print0 \
  | xargs -0 -r awk '
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
' || true)"
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
# the user's real key-up event. KeyActivation owns that rule; a handler that
# delegates to it inherits the guard, anything else must spell it out again.
# The delegating form must be matched on the handler's OWN line: scanning the
# 15-line window for it lets a neighbouring delegated handler excuse a
# hand-rolled one that never checks isAutoRepeat.
release_without_repeat=""
while IFS=: read -r file line text; do
  [ -n "$file" ] || continue
  printf '%s' "$text" | grep -qE '\.release\(' && continue
  end=$((line + 14))
  sed -n "${line},${end}p" "$file" | grep -q 'isAutoRepeat' && continue
  release_without_repeat="${release_without_repeat}${file}:${line}"$'\n'
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
# fires — there is no runtime warning for it either. Connections spells the same
# handler as a function, where the mistake is just as quiet.
lower_underscore_handlers="$(grep -RInE --include='*.qml' \
  -e '^[[:space:]]*on_[a-z][A-Za-z0-9_]*[[:space:]]*:' \
  -e 'function[[:space:]]+on_[a-z][A-Za-z0-9_]*[[:space:]]*\(' \
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

section "terminal detection"
# `[ -r /dev/tty ]` only stats the device node — it succeeds in a session with no
# controlling terminal, where the following read fails with ENXIO and leaves the
# reply unset, so `set -u` aborts with a cryptic error instead of the intended
# "needs a terminal" message. Open the device to test it.
tty_readability_tests="$(grep -nE '^[^#]*\[[[:space:]]+-r[[:space:]]+/dev/tty[[:space:]]+\]' "${script_files[@]}" || true)"
if [ -n "$tty_readability_tests" ]; then
  fail "test /dev/tty by opening it ({ : </dev/tty; } 2>/dev/null), not with -r:"
  printf '%s\n' "$tty_readability_tests"
else
  ok "tty" "terminal checks open /dev/tty instead of stat-ing it"
fi

section "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  # Warnings include mode/word-splitting mistakes that are real portability or
  # permission bugs. Intentional sourced-library false positives are suppressed
  # at their declaration so a new warning cannot disappear in the noise.
  # one invocation, not per-file: shellcheck resolves assignments and uses across the whole set,
  # so sharding it invents SC2154/SC2034 false positives
  if shellcheck --severity=warning "${script_files[@]}"; then ok "shellcheck"; else fail "shellcheck reported warnings"; fi
else
  skip "shellcheck" "not installed"
fi

section "aur metadata"
aur_dir="packaging/aur"
if [ ! -f "$aur_dir/PKGBUILD" ] || [ ! -f "$aur_dir/.SRCINFO" ]; then
  fail "AUR packaging must include PKGBUILD and .SRCINFO"
elif ! grep -qF "depends=('quickshell>=0.3')" "$aur_dir/PKGBUILD" \
    || ! grep -qF $'\tdepends = quickshell>=0.3' "$aur_dir/.SRCINFO"; then
  fail "AUR package must enforce the documented Quickshell 0.3 minimum"
elif ! awk '/^#!\/bin\/sh$/ { wrapper=1; next } wrapper && /^umask 077$/ { private=1 } END { exit !private }' \
    "$aur_dir/PKGBUILD"; then
  fail "AUR launcher must use a private umask for Quickshell state"
elif command -v makepkg >/dev/null 2>&1; then
  aur_srcinfo="$(mktemp "${TMPDIR:-/tmp}/silere-srcinfo.XXXXXX")"
  # makepkg refuses to run as root, which is exactly how a container CI runs it;
  # that is "could not check", not "stale", and the two must not report the same
  if ! (cd "$aur_dir" && makepkg --printsrcinfo -p PKGBUILD) >"$aur_srcinfo" 2>/dev/null \
      || [ ! -s "$aur_srcinfo" ]; then
    skip "AUR" "makepkg cannot run here; dependency floor still checked"
  elif [ "$(cat "$aur_srcinfo")" = "$(cat "$aur_dir/.SRCINFO")" ]; then
    ok "AUR" ".SRCINFO matches PKGBUILD"
  else
    fail "packaging/aur/.SRCINFO is stale; regenerate it with makepkg --printsrcinfo"
  fi
  rm -f "$aur_srcinfo"
else
  skip "AUR" "makepkg unavailable; dependency floor still checked"
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

section "slider range coverage"
# A slider narrower than its schema entry hides part of the range from the UI;
# a wider one lets the row show values the setting clamps straight back off.
mapfile -t slider_files < <(find modules -name '*.qml' | sort)
slider_drift=$(awk '
function braces(s, c,   n, i) {
    n = 0
    for (i = 1; i <= length(s); i++) if (substr(s, i, 1) == c) n++
    return n
}
FILENAME ~ /ShellSettings\.qml$/ {
    if (!match($0, /k: "[A-Za-z0-9_]+"/)) next
    key = substr($0, RSTART + 4, RLENGTH - 5)
    if (!match($0, /min: *[-0-9.]+/)) next
    lo = substr($0, RSTART + 4, RLENGTH - 4) + 0
    if (!match($0, /max: *[-0-9.]+/)) next
    smin[key] = lo
    smax[key] = substr($0, RSTART + 4, RLENGTH - 4) + 0
    next
}
!inrow && /SliderRow[ \t]*\{/ {
    inrow = 1; depth = 1; key = ""; rmin = ""; rmax = ""
    next
}
inrow {
    depth += braces($0, "{") - braces($0, "}")
    if (key == "" && $0 ~ /value:/ && match($0, /ShellSettings\.[A-Za-z0-9_]+/))
        key = substr($0, RSTART + 14, RLENGTH - 14)
    if (match($0, /min: *[-0-9.]+/)) rmin = substr($0, RSTART + 4, RLENGTH - 4) + 0
    if (match($0, /max: *[-0-9.]+/)) rmax = substr($0, RSTART + 4, RLENGTH - 4) + 0
    if (depth > 0) next
    inrow = 0
    if (key == "" || rmin == "" || rmax == "" || !(key in smin)) next
    if (smin[key] != rmin || smax[key] != rmax)
        printf "  %s: row %s..%s, schema %s..%s (%s)\n",
            key, rmin, rmax, smin[key], smax[key], FILENAME
}
' services/ShellSettings.qml "${slider_files[@]}")
if [ -n "$slider_drift" ]; then
    fail "slider ranges do not match their settings schema:"
    printf '%s\n' "$slider_drift"
else
    ok "settings" "slider ranges match the schema"
fi

section "bar widget layout API"
# The settings key list, settings metadata, and runtime component registry are
# three views of one widget catalog. A widget is incomplete if any view drifts.
widget_keys="$(awk '/barWidgetKeys:[[:space:]]*\[/{take=1} take{print; if ($0 ~ /\]/) exit}' \
  services/ShellSettings.qml | grep -oE '"[A-Za-z][A-Za-z0-9]*"' | tr -d '"' | sort)"
widget_meta="$(awk '/barWidgetMeta:[[:space:]]*\(\{/{take=1; next} \
  take && /^[[:space:]]*\}\)/{exit} take{print}' services/ShellSettings.qml \
  | sed -nE 's/^[[:space:]]*([A-Za-z][A-Za-z0-9]*):.*/\1/p' | sort)"
widget_components="$(awk '/_widgetComponents:[[:space:]]*\(\{/{take=1; next} \
  take && /^[[:space:]]*\}\)/{exit} take{print}' modules/bar/BarContent.qml \
  | grep -oE '[A-Za-z][A-Za-z0-9]*[[:space:]]*:' | tr -d ': ' | sort)"
if [ -z "$widget_keys" ] || [ "$widget_keys" != "$widget_meta" ] \
        || [ "$widget_keys" != "$widget_components" ]; then
    fail "barWidgetKeys, barWidgetMeta, and _widgetComponents must be nonempty and identical"
    printf 'keys:\n%s\nmeta:\n%s\ncomponents:\n%s\n' \
      "$widget_keys" "$widget_meta" "$widget_components"
else
    ok "bar widgets" "keys, metadata, and components agree"
fi

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

section "settings section attribution"
shell_settings="services/ShellSettings.qml"
if [ -f "$shell_settings" ] && [ -f "$settings_nav" ]; then
    # the nav dot lies if a schema key is unattributed or points at a page that does not exist
    attr_nav=$(grep -oE 'section: "[^"]+"' "$settings_nav" \
               | sed -E 's/.*"([^"]+)"/\1/' | sort -u)
    schema_block=$(sed -n '/readonly property var _schema: \[/,/^[[:space:]]*\]/p' "$shell_settings")
    schema_keys=$(printf '%s\n' "$schema_block" | grep -cE '\{ k: "')
    schema_secs=$(printf '%s\n' "$schema_block" | grep -cE 'sec: "')
    if [ "$schema_keys" -ne "$schema_secs" ]; then
        fail "settings schema entries missing a sec: attribution ($schema_secs of $schema_keys):"
        printf '%s\n' "$schema_block" | grep -E '\{ k: "' | grep -v 'sec: "' \
            | sed -E 's/^[[:space:]]*/  /'
    else
        used_secs=$(printf '%s\n' "$schema_block" | grep -oE 'sec: "[^"]*"' \
                    | sed -E 's/.*"([^"]*)"/\1/' | tr ',' '\n' \
                    | grep -vx '-' | grep -v '^$' | sort -u)
        unknown=$(comm -23 <(printf '%s\n' "$used_secs") <(printf '%s\n' "$attr_nav"))
        if [ -n "$unknown" ]; then
            fail "settings schema attributed to unknown pages:"
            while IFS= read -r m; do printf '  %s\n' "$m"; done <<< "$unknown"
        else
            ok "attribution" "$schema_keys schema keys map to known settings pages"
        fi
    fi
else
    skip "attribution" "settings schema files not found"
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

section "release note archive"
release_count=0
release_archive_failed=0
indexed_release_paths="$(sed -nE \
  's#^- \[([0-9]+\.[0-9]+\.[0-9]+)\]\((docs/releases/[^)]+)\).*#\2#p' \
  CHANGELOG.md | sort -u)"
while IFS='|' read -r version archive; do
  [ -n "$version" ] || continue
  release_count=$((release_count + 1))
  if [ ! -f "$archive" ]; then
    fail "CHANGELOG.md links missing release notes: $archive"
    release_archive_failed=1
  elif [ "$(sed -n '1p' "$archive")" != "# Silere Shell $version" ]; then
    fail "$archive has the wrong release heading"
    release_archive_failed=1
  elif ! notes="$(bash scripts/release-notes.sh "$version")" || [ -z "$notes" ]; then
    fail "$archive cannot produce publishable release notes"
    release_archive_failed=1
  fi
done < <(sed -nE \
  's#^- \[([0-9]+\.[0-9]+\.[0-9]+)\]\((docs/releases/[^)]+)\).*#\1|\2#p' \
  CHANGELOG.md)

archive_paths="$(find docs/releases -maxdepth 1 -type f -name '*.md' | sort)"
orphaned_release_paths="$(comm -13 \
  <(printf '%s\n' "$indexed_release_paths") \
  <(printf '%s\n' "$archive_paths"))"
if [ "$release_count" -eq 0 ]; then
  fail "CHANGELOG.md has no archived releases"
  release_archive_failed=1
elif [ -n "$orphaned_release_paths" ]; then
  fail "release notes missing from CHANGELOG.md: $orphaned_release_paths"
  release_archive_failed=1
fi
if bash scripts/release-notes.sh Unreleased >/dev/null 2>&1 \
    || bash scripts/release-notes.sh 999.999.999 >/dev/null 2>&1; then
  fail "release notes must reject Unreleased and unknown versions"
  release_archive_failed=1
fi
[ "$release_archive_failed" -ne 0 ] \
  || ok "release notes" "$release_count indexed archives are publishable"

section "high-contrast alpha coverage"
# every other Theme token re-bases onto white text under high contrast. An alpha that
# ignores _hc silently keeps its normal-mode weight there, which is how the focus ring
# ended up as the one affordance high contrast did not touch.
flat_alphas="$(grep -nE '^[[:space:]]*readonly property real [a-zA-Z]*Alpha:' config/Theme.qml \
  | grep -v '_hc' || true)"
if [ -n "$flat_alphas" ]; then
  fail "Theme alpha tokens must branch on _hc:"
  printf '%s\n' "$flat_alphas"
else
  ok "contrast" "every Theme alpha token participates in high contrast"
fi

section "capability reporting coverage"
# a capability gating a *send* path leaves its settings page visible and settable, so the
# health card is the only surface that can report the feature is inert without it
missing_caps=""
for cap in $(grep -oE 'SystemTools\.has[A-Za-z]+' services/SystemAlerts.qml | sort -u); do
  flag="${cap#SystemTools.}"
  grep -qF "$flag" modules/menu/settings/SettingsMaintenanceSection.qml \
    || missing_caps="$missing_caps $flag"
done
if [ -n "$missing_caps" ]; then
  fail "health card must report capabilities that gate alert delivery:$missing_caps"
else
  ok "health" "alert-delivery capabilities are reported when missing"
fi

section "shared spacing derivation"
# two independent formulas over one setting drift apart: the tray gap grew wider than the
# widget gap it sits inside, at both ends of the range, while each formula was fine alone
if grep -qE 'spacing:.*ShellSettings\.barSpacing' modules/bar/widgets/TrayWidget.qml; then
  fail "tray spacing must derive from Metrics.widgetGapFor, not re-derive from barSpacing"
elif ! grep -qF 'Metrics.widgetGapFor' modules/bar/widgets/TrayWidget.qml; then
  fail "tray spacing must derive from Metrics.widgetGapFor"
else
  ok "spacing" "tray gap derives from the shared widget gap"
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
