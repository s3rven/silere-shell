#!/usr/bin/env bash
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

status=0
warnings=0

ok() { printf "ok   %-15s %s\n" "$1" "$2"; }
warn() { printf "WARN %-15s %s\n" "$1" "$2"; warnings=$((warnings + 1)); }
fail() { printf "FAIL %-15s %s\n" "$1" "$2" >&2; status=1; }

echo "== git diff --check =="
if ! git diff --check; then
  status=1
fi
if ! git diff --cached --check; then
  status=1
fi

echo
echo "== structural lint =="
if ! bash scripts/ci-lint.sh; then
  status=1
fi

echo
echo "== dependencies =="
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
require_tool hyprctl "Hyprland runtime and dispatch client"
optional_tool pipewire "volume service"
optional_tool wireplumber "PipeWire session manager"
optional_tool upower "battery widget + warnings"
optional_tool brightnessctl "brightness control + popup"
optional_tool inotifywait "instant brightness/screenshot updates"
optional_tool nmcli "Wi-Fi, VPN, network speed"
optional_tool cava "audio visualizer"
optional_tool matugen "wallpaper-matched colors"
optional_any_tool "updates" "update count widget" checkupdates apt dnf zypper xbps-install
optional_any_tool "AUR helper" "AUR update count" paru yay
optional_tool hyprsunset "night light toggle"
optional_tool pgrep "night light external state check"
optional_tool pkill "night light external stop fallback"
optional_tool powerprofilesctl "power profile selector"
optional_tool hyprlock "lock screen"
optional_tool systemctl "power menu actions"
optional_tool notify-send "system alert notifications"
optional_tool busctl "notification daemon conflict check"
optional_tool timeout "bounded update checks and smoke launch"
optional_tool fc-list "font detection"
optional_tool fc-cache "font install refresh"
_cfg_home="${XDG_CONFIG_HOME:-$HOME/.config}"
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
    fail "$module" "required Quickshell QML module not found in import paths"
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

if command -v hyprctl >/dev/null 2>&1; then
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
  if [ -f config/MatugenTheme.qml ]; then
    ok "theme" "config/MatugenTheme.qml"
  elif [ -f config/MatugenTheme.default.qml ]; then
    warn "theme" "generated theme absent; default will be seeded for smoke test"
  else
    fail "theme" "config/MatugenTheme.default.qml missing"
  fi
  _tmpl="$_cfg_home/matugen/templates/silere-shell/Theme.qml"
  if [ -f "$_tmpl" ]; then
    ok "matugen tmpl" "$_tmpl"
  else
    warn "matugen tmpl" "template missing — run installer or: cp assets/matugen-theme.qml $_tmpl"
  fi
  _matugen_cfg="$_cfg_home/matugen/config.toml"
  if [ -f "$_matugen_cfg" ] && grep -q '# silere-shell begin' "$_matugen_cfg"; then
    ok "matugen cfg" "silere-shell entry present in config.toml"
  else
    warn "matugen cfg" "silere-shell block missing from $_matugen_cfg — run installer"
  fi
fi

if command -v cava >/dev/null 2>&1; then
  ok "visualizer" "cava available; starts while media visualizer is visible"
fi

echo
echo "== headless QML probe =="
if ! bash scripts/test-qml-headless.sh; then
  status=1
fi

echo
echo "== quickshell smoke =="
if command -v qs >/dev/null 2>&1; then
  if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    warn "startup" "no Wayland display; runtime smoke test skipped"
  elif [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "$XDG_RUNTIME_DIR" ]; then
    warn "startup" "no usable XDG_RUNTIME_DIR; runtime smoke test skipped"
  elif ! command -v timeout >/dev/null 2>&1; then
    warn "startup" "timeout command unavailable; runtime smoke test skipped"
  else
    # The shell needs config/MatugenTheme.qml to exist. If it's missing (bare clone),
    # seed it from the default for the smoke test. One cleanup removes both the
    # seeded theme and the temp log, on interrupt as well as normal exit.
    _seeded_theme=false
    smoke_log=""
    _smoke_cleanup() {
      if [ "$_seeded_theme" = true ]; then rm -f config/MatugenTheme.qml; fi
      if [ -n "$smoke_log" ]; then rm -f "$smoke_log"; fi
      return 0
    }
    trap _smoke_cleanup INT TERM EXIT

    if [ ! -f config/MatugenTheme.qml ] && [ -f config/MatugenTheme.default.qml ]; then
      cp config/MatugenTheme.default.qml config/MatugenTheme.qml
      _seeded_theme=true
    fi
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
    elif grep -qE 'Failed to load configuration|Type [^ ]+ unavailable|module ".*" is not installed' "$smoke_log"; then
      cat "$smoke_log"
      fail "startup" "Quickshell reported a QML compatibility error"
    else
      ok "startup" "Quickshell stayed alive for 5 seconds without load errors"
    fi
  fi
else
  fail "startup" "Quickshell missing; runtime smoke test could not run"
fi

echo
if [ "$status" -eq 0 ]; then
  printf 'checks passed (%d warning(s))\n' "$warnings"
else
  printf 'checks failed (%d warning(s))\n' "$warnings"
fi
exit "$status"
