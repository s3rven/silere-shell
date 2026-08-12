#!/usr/bin/env bash
set -eu
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/xdg.sh"
cd "$ROOT" || exit 1

trap 'printf "\ninterrupted\n" >&2; exit 130' INT TERM

status=0
warnings=0
seen_section=0

section() {
  [ "$seen_section" -eq 0 ] || printf '\n'
  seen_section=1
  printf '== %s ==\n' "$1"
}
ok() { printf 'ok   %-15s %s\n' "$1" "$2"; }
warn() { printf 'warn %-15s %s\n' "$1" "$2"; warnings=$((warnings + 1)); }
fail() { printf 'fail %-15s %s\n' "$1" "$2" >&2; status=1; }

section "git diff --check"
if git diff --check; then
  ok "worktree" "no whitespace errors"
else
  status=1
fi
if git diff --cached --check; then
  ok "index" "no staged whitespace errors"
else
  status=1
fi

section "structural lint"
lint_log="$(mktemp "${TMPDIR:-/tmp}/silere-ci-lint.XXXXXX.log")"
if bash scripts/ci-lint.sh >"$lint_log" 2>&1; then
  ok "ci-lint" "structural checks passed"
else
  status=1
  fail "ci-lint" "structural checks failed"
  cat "$lint_log"
fi
rm -f "$lint_log"

section "dependencies"
require_tool() {
  local tool="$1" desc="$2"
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool" "$desc"
  else
    fail "$tool" "$desc is required but was not found in PATH"
  fi
}

optional_tool() {
  local tool="$1" desc="$2"
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool" "$desc"
  else
    warn "$tool" "$desc unavailable (optional)"
  fi
}

optional_any_tool() {
  local label="$1" desc="$2" tool found=""
  shift 2
  for tool in "$@"; do
    if command -v "$tool" >/dev/null 2>&1; then
      found="$tool"
      break
    fi
  done
  if [ -n "$found" ]; then
    ok "$label" "$desc ($found)"
  else
    warn "$label" "$desc unavailable (optional; need one of: $*)"
  fi
}

check_file() {
  local label="$1" path="$2" hint="$3"
  if [ -r "$path" ]; then
    ok "$label" "$path"
  else
    warn "$label" "$hint (optional)"
  fi
}

require_tool qs "Quickshell runtime"
if [ -n "${NIRI_SOCKET:-}" ]; then
  require_tool niri "niri runtime and IPC client"
elif [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  require_tool hyprctl "Hyprland runtime and dispatch client"
else
  optional_any_tool compositor "niri or Hyprland client" niri hyprctl
fi
optional_tool pipewire "volume service"
optional_tool wireplumber "PipeWire session manager"
optional_tool upower "battery widget + warnings"
optional_tool brightnessctl "brightness control + popup"
optional_tool inotifywait "screenshot feedback"
optional_tool nmcli "VPN name fallback"
optional_tool cava "audio visualizer"
optional_tool matugen "wallpaper-matched colors"
optional_any_tool "updates" "update count widget" checkupdates apt dnf zypper xbps-install
optional_any_tool "AUR helper" "AUR update count" paru yay
optional_tool hyprsunset "night light toggle"
optional_tool pgrep "night light external state check"
optional_tool pkill "night light external stop fallback"
optional_tool powerprofilesctl "power profile selector"
optional_tool hyprlock "lock screen"
optional_any_tool "power actions" "power menu actions" systemctl loginctl
optional_tool notify-send "system alert notifications"
optional_tool busctl "notification daemon conflict check"
optional_tool timeout "bounded update checks and smoke launch"
optional_tool ssh-keygen "signed shell release verification"
optional_tool fc-list "font detection"
optional_tool fc-cache "font install refresh"

_backlights=()
for _backlight in /sys/class/backlight/*; do
  [ -d "$_backlight" ] && _backlights+=("${_backlight##*/}")
done
if [ "${#_backlights[@]}" -gt 1 ]; then
  ok "backlights" "${_backlights[*]} (choose the display in Settings > Interface)"
elif [ "${#_backlights[@]}" -eq 1 ]; then
  ok "backlight" "${_backlights[0]}"
elif command -v brightnessctl >/dev/null 2>&1; then
  warn "backlight" "no display backlight detected"
fi
_cfg_home="$(_silere_xdg_home "${XDG_CONFIG_HOME:-}" .config)" || {
  fail "XDG config" "HOME must be an absolute path"
  _cfg_home=""
}
_wayland_socket() {
  [ -n "${WAYLAND_DISPLAY:-}" ] || return 1
  case "$WAYLAND_DISPLAY" in
    /*) printf '%s\n' "$WAYLAND_DISPLAY" ;;
    *)  [ -n "${XDG_RUNTIME_DIR:-}" ] || return 1
        printf '%s\n' "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ;;
  esac
}

if command -v qs >/dev/null 2>&1; then
  # Include instances on other displays when this runs from a terminal or CI
  # environment without the active Wayland display variables.
  if qs list --all >/dev/null 2>&1; then
    ok "qs IPC" "available"
  else
    warn "qs IPC" "qs list failed (shell may not be running)"
  fi
fi

if command -v busctl >/dev/null 2>&1; then
  if busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner s org.freedesktop.Notifications >/dev/null 2>&1; then
    ok "notifications" "D-Bus owner present"
  else
    warn "notifications" "no D-Bus notification owner"
  fi
fi

if command -v upower >/dev/null 2>&1; then
  if upower -e 2>/dev/null | grep -q '/battery_'; then
    ok "battery" "UPower battery detected"
  else
    warn "battery" "no UPower battery detected"
  fi
fi

if command -v fc-list >/dev/null 2>&1; then
  if fc-list : family 2>/dev/null | grep -qi "JetBrainsMono Nerd"; then
    ok "font" "JetBrainsMono Nerd Font"
    if command -v fc-match >/dev/null 2>&1; then
      resolved="$(fc-match -f '%{family}' "JetBrainsMono Nerd Font" 2>/dev/null || true)"
      if printf '%s' "$resolved" | grep -qi "JetBrainsMono Nerd Font"; then
        ok "font match" "resolves to $resolved"
      else
        warn "font match" "fontconfig serves '$resolved' instead — icons will render wrong; run fc-cache -f (see README troubleshooting)"
      fi
    fi
  else
    warn "font" "JetBrainsMono Nerd Font not found"
  fi
fi

if command -v pipewire >/dev/null 2>&1; then
  pipewire_state=""
  if command -v systemctl >/dev/null 2>&1; then
    pipewire_state="$(systemctl --user is-active pipewire.service 2>/dev/null || true)"
  fi
  if [ "$pipewire_state" = active ]; then
    ok "audio service" "pipewire.service active"
  else
    warn "audio service" "pipewire.service not active or unavailable"
  fi
fi

# These modules are imported unconditionally, so their packaging is required
# even when the corresponding service/agent is not active in this session.
# Shared with install.sh and CI so the module list and the import-root lookup
# only exist in one place.
source "$ROOT/scripts/lib/qml-modules.sh"

require_qml_module() {
  local module="$1" rel found=""
  rel="${module//./\/}/qmldir"
  for _d in "${_silere_qml_import_roots[@]}"; do
    if [ -f "$_d/$rel" ]; then found="$_d/$rel"; break; fi
  done
  if [ -n "$found" ]; then
    ok "$module" "$found"
  else
    fail "$module" "required QML module not found in import paths"
  fi
}

for _module in "${SILERE_REQUIRED_QML_MODULES[@]}"; do
  require_qml_module "$_module"
done

if command -v wireplumber >/dev/null 2>&1; then
  wireplumber_state=""
  if command -v systemctl >/dev/null 2>&1; then
    wireplumber_state="$(systemctl --user is-active wireplumber.service 2>/dev/null || true)"
  fi
  if [ "$wireplumber_state" = active ]; then
    ok "session mgr" "wireplumber.service active"
  else
    warn "session mgr" "wireplumber.service not active or unavailable"
  fi
fi

if command -v nmcli >/dev/null 2>&1; then
  nm_state="$(nmcli -t -f RUNNING general 2>/dev/null || true)"
  if [ "$nm_state" = running ]; then
    ok "network mgr" "NetworkManager running"
  else
    warn "network mgr" "NetworkManager not running or unavailable"
  fi
fi

if [ -n "${NIRI_SOCKET:-}" ] && command -v niri >/dev/null 2>&1; then
  if niri msg version >/dev/null 2>&1; then
    ok "niri" "niri msg can query compositor"
  else
    warn "niri" "NIRI_SOCKET set but niri msg query failed"
  fi
elif command -v hyprctl >/dev/null 2>&1; then
  hyprctl_out="$(hyprctl monitors 2>&1)" && hyprctl_ok=true || hyprctl_ok=false
  wayland_sock="$(_wayland_socket || true)"
  if $hyprctl_ok; then
    ok "hyprland" "hyprctl can query compositor"
  elif [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || [ -z "${WAYLAND_DISPLAY:-}" ] \
    || [ -z "$wayland_sock" ] || [ ! -S "$wayland_sock" ]; then
    warn "hyprland" "not in a Hyprland session; compositor query skipped"
  elif printf '%s\n' "$hyprctl_out" | grep -q "Couldn't set socket timeout"; then
    warn "hyprland" "compositor socket inaccessible; hyprctl query skipped"
  else
    fail "hyprland" "hyprctl is installed but cannot query the compositor"
  fi
fi

if command -v matugen >/dev/null 2>&1; then
  [ -f config/MatugenPalette.qml ] \
    && ok "theme" "bundled fallback + live palette loader" \
    || fail "theme" "config/MatugenPalette.qml missing"
  _tmpl="$_cfg_home/matugen/templates/silere-shell/Theme.json"
  if [ -f "$_tmpl" ]; then
    ok "matugen tmpl" "$_tmpl"
    # An installed template predating a new palette role can regenerate incomplete JSON,
    # which surfaces as silently wrong colours rather than a load error
    _missing=""
    for _role in $(grep -rhoE 'MatugenTheme\.[a-zA-Z_][a-zA-Z0-9_]*' --include='*.qml' . \
      | sed 's/^MatugenTheme\.//' | grep -vE '^(_|qml$|usingFallback$|paletteStale$)' | sort -u); do
      grep -qE "\"$_role\"[[:space:]]*:" "$_tmpl" \
        || _missing="$_missing $_role"
    done
    if [ -n "$_missing" ]; then
      warn "matugen roles" "template lacks:$_missing — reinstall or: cp assets/matugen-theme.json $_tmpl"
    else
      ok "matugen roles" "template provides every palette role the shell reads"
    fi
  else
    warn "matugen tmpl" "template missing — run installer or: cp assets/matugen-theme.json $_tmpl"
  fi
  _matugen_cfg="$_cfg_home/matugen/config.toml"
  if [ -f "$_matugen_cfg" ] && grep -q '# silere-shell begin' "$_matugen_cfg"; then
    _managed_block="$(awk '
      $0 == "# silere-shell begin" { inside = 1 }
      inside { print }
      $0 == "# silere-shell end" { inside = 0 }
    ' "$_matugen_cfg")"
    if printf '%s\n' "$_managed_block" | grep -qF 'silere-shell.json'; then
      ok "matugen cfg" "writes the live per-user palette"
    else
      warn "matugen cfg" "Silere entry uses the legacy checkout output — rerun installer"
    fi
  else
    warn "matugen cfg" "silere-shell block missing from $_matugen_cfg — run installer"
  fi
  _palette="$_cfg_home/matugen/silere-shell.json"
  if [ -f "$_palette" ]; then
    _missing=""
    for _role in background surface text subtext accent error warning success; do
      grep -qE "\"$_role\"[[:space:]]*:[[:space:]]*\"#[0-9a-fA-F]{6}\"" "$_palette" \
        || _missing="$_missing $_role"
    done
    if [ -n "$_missing" ]; then
      warn "matugen output" "$_palette is malformed or lacks:$_missing"
    else
      ok "matugen output" "$_palette"
    fi
  else
    warn "matugen output" "palette not generated yet — run matugen once"
  fi
fi

if command -v cava >/dev/null 2>&1; then
  if grep -qE 'case "eco":[[:space:]]+return 0\.[0-9]+' services/Media.qml \
      && grep -qF '"method = raw\n"' services/Media.qml \
      && grep -qF '"data_format = ascii\n"' services/Media.qml; then
    ok "visualizer" "cava available; Silere supplies a bounded temporary raw profile"
  else
    fail "visualizer" "generated Cava profile is missing required bounded raw-output settings"
  fi
fi

section "headless QML probe"
ok "qml" "checking files; this can take a few seconds"
if ! bash scripts/test-qml-headless.sh; then
  status=1
fi

section "behavioral logic"
if [ -f scripts/test-logic.sh ]; then
  logic_out=""
  if logic_out="$(bash scripts/test-logic.sh 2>&1)"; then
    ok "logic" "$logic_out"
  else
    status=1
    fail "logic" "behavioral probe failed"
    printf '%s\n' "$logic_out"
  fi
else
  fail "logic" "scripts/test-logic.sh missing"
fi

section "quickshell smoke"
if command -v qs >/dev/null 2>&1; then
  if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    warn "startup" "no Wayland display; runtime smoke test skipped"
  elif [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "$XDG_RUNTIME_DIR" ]; then
    warn "startup" "no usable XDG_RUNTIME_DIR; runtime smoke test skipped"
  elif ! command -v timeout >/dev/null 2>&1; then
    warn "startup" "timeout command unavailable; runtime smoke test skipped"
  else
    smoke_log=""
    cov_log=""
    cov_cfg=""
    _smoke_cleanup() {
      if [ -n "$smoke_log" ]; then rm -f "$smoke_log"; fi
      if [ -n "$cov_log" ]; then rm -f "$cov_log"; fi
      if [ -n "$cov_cfg" ]; then rm -rf "$cov_cfg"; fi
      return 0
    }
    trap _smoke_cleanup EXIT

    code=0
    smoke_log="$(mktemp "${TMPDIR:-/tmp}/silere-qs-smoke.XXXXXX.log")"
    timeout 5s qs -p shell.qml --no-color >"$smoke_log" 2>&1 || code=$?
    if [ "$code" -ne 0 ] && [ "$code" -ne 124 ]; then
      if grep -qE 'Failed to create wl_display|could not connect to display|no Qt platform plugin could be initialized' "$smoke_log"; then
        warn "startup" "display inaccessible; runtime smoke test skipped"
      else
        cat "$smoke_log"
        fail "startup" "Quickshell exited with status $code"
      fi
    elif grep -qE 'Failed to load configuration|Type [^ ]+ unavailable|module ".*" is not installed|Binding loop detected' "$smoke_log"; then
      cat "$smoke_log"
      fail "startup" "Quickshell reported a QML compatibility error"
    else
      ok "startup" "Quickshell stayed alive for 5 seconds without load errors"

      # Every default-off setting gates a Loader, so the pass above never loads those
      # paths and the type-check cannot see a runtime-only error inside one. Load once
      # more with them all on, in a scratch config so real settings stay untouched.
      # nightLightAuto and neutralAccentAuto drive a gamma tool and matugen hooks;
      # reduceMotion would zero the animations this is meant to instantiate.
      cov_keys="$(sed -n 's/.*property bool[[:space:]]\{1,\}\([A-Za-z_][A-Za-z0-9_]*\)[[:space:]]*:[[:space:]]*false.*/\1/p' \
        services/ShellSettings.qml \
        | grep -vxE '_loaded|nightLightAuto|neutralAccentAuto|reduceMotion' || true)"
      if [ -z "$cov_keys" ]; then
        warn "off-path load" "no default-off settings found; coverage pass skipped"
      else
        cov_cfg="$(mktemp -d "${TMPDIR:-/tmp}/silere-qs-cov.XXXXXX")"
        mkdir -p "$cov_cfg/silere-shell"
        { printf '{\n'
          printf '%s\n' "$cov_keys" | sed '$!s/.*/  "&": true,/; $s/.*/  "&": true/'
          printf '}\n'
        } > "$cov_cfg/silere-shell/settings.json"
        cov_log="$(mktemp "${TMPDIR:-/tmp}/silere-qs-cov.XXXXXX.log")"
        code=0
        XDG_CONFIG_HOME="$cov_cfg" timeout 5s qs -p shell.qml --no-color \
          >"$cov_log" 2>&1 || code=$?
        if [ "$code" -ne 0 ] && [ "$code" -ne 124 ]; then
          cat "$cov_log"
          fail "off-path load" "Quickshell exited with status $code with every option on"
        elif grep -qE 'Failed to load configuration|Type [^ ]+ unavailable|Cannot assign to non-existent property|is not a type|Binding loop detected' "$cov_log"; then
          cat "$cov_log"
          fail "off-path load" "a default-off code path failed to load"
        else
          # a script error does not fail the load, so this is the only pass that sees one.
          # warn rather than fail: absent hardware can make a path throw on machines this
          # one cannot stand in for
          cov_script="$(grep -oE 'ReferenceError: [^,]*|TypeError: [^,]*|Invalid write to global property "[^"]*"' \
            "$cov_log" | sort -u | head -3 || true)"
          if [ -n "$cov_script" ]; then
            printf '%s\n' "$cov_script" | sed 's/^/       /'
            warn "off-path load" "a default-off path loaded but threw at runtime"
          else
            ok "off-path load" "$(printf '%s\n' "$cov_keys" | wc -l | tr -d ' ') default-off settings loaded without errors"
          fi
        fi
      fi
    fi
  fi
else
  fail "startup" "Quickshell missing; runtime smoke test could not run"
fi

section "surface build"
# The passes above launch the shell but never open the menu, so no settings
# section is ever built and a runtime-only error inside one stays invisible.
if [ -f scripts/test-surfaces.sh ]; then
  surf_code=0
  surf_out="$(bash scripts/test-surfaces.sh 2>&1)" || surf_code=$?
  if [ "$surf_code" -ne 0 ]; then
    printf '%s\n' "$surf_out" | sed 's/^/       /'
    fail "surfaces" "a settings section failed to build standalone"
  elif printf '%s' "$surf_out" | grep -q '^SKIP'; then
    warn "surfaces" "$(printf '%s' "$surf_out" | sed -n 's/^SKIP: //p' | head -1)"
  else
    ok "surfaces" "$(printf '%s' "$surf_out" | tail -1)"
  fi
else
  warn "surfaces" "scripts/test-surfaces.sh missing; section build check skipped"
fi

section "layout fit"
# Building a section says nothing about whether its labels survive the width they
# ship at; Qt elides them and reports success either way.
if [ -f scripts/test-layout-fit.sh ]; then
  fit_code=0
  fit_out="$(bash scripts/test-layout-fit.sh 2>&1)" || fit_code=$?
  if [ "$fit_code" -ne 0 ]; then
    printf '%s\n' "$fit_out" | sed 's/^/       /'
    fail "layout" "settings text is truncated at the shipped panel width"
  elif printf '%s' "$fit_out" | grep -q '^SKIP'; then
    warn "layout" "$(printf '%s' "$fit_out" | sed -n 's/^SKIP: //p' | head -1)"
  else
    ok "layout" "$(printf '%s' "$fit_out" | tail -1)"
  fi
else
  warn "layout" "scripts/test-layout-fit.sh missing; label fit check skipped"
fi

if [ "$status" -eq 0 ]; then
  printf '\nchecks passed (%d warning(s))\n' "$warnings"
else
  printf '\nchecks failed (%d warning(s))\n' "$warnings"
fi
exit "$status"
