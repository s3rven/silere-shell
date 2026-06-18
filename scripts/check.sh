#!/usr/bin/env bash
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

status=0

echo "== git diff --check =="
if ! git diff --check; then
  status=1
fi
if ! git diff --cached --check; then
  status=1
fi

echo
echo "== dependencies =="
check_tool() {
  local tool="$1" desc="$2"
  if command -v "$tool" >/dev/null 2>&1; then
    printf "ok   %-13s %s\n" "$tool" "$desc"
  else
    printf "miss %-13s %s\n" "$tool" "$desc"
  fi
}

check_any_tool() {
  local label="$1" desc="$2" tool found=""
  shift 2
  for tool in "$@"; do
    if command -v "$tool" >/dev/null 2>&1; then
      found="$tool"
      break
    fi
  done
  if [ -n "$found" ]; then
    printf "ok   %-13s %s (%s)\n" "$label" "$desc" "$found"
  else
    printf "miss %-13s %s (need one of: %s)\n" "$label" "$desc" "$*"
  fi
}

check_file() {
  local label="$1" path="$2" hint="$3"
  if [ -r "$path" ]; then
    printf "ok   %-13s %s\n" "$label" "$path"
  else
    printf "miss %-13s %s\n" "$label" "$hint"
  fi
}

check_tool qs "Quickshell runtime"
check_tool hyprctl "Hyprland dispatch/events"
check_tool pipewire "volume service"
check_tool wireplumber "PipeWire session manager"
check_tool upower "battery widget + warnings"
check_tool brightnessctl "brightness control + popup"
check_tool inotifywait "instant brightness/screenshot updates"
check_tool nmcli "Wi-Fi, VPN, network speed"
check_tool cava "audio visualizer"
check_tool matugen "wallpaper-matched colors"
check_any_tool "updates" "update count widget" checkupdates apt dnf zypper xbps-install
check_any_tool "AUR helper" "optional AUR update count" paru yay
check_tool hyprsunset "night light toggle"
check_tool pgrep "optional night light external state check"
check_tool pkill "optional night light external stop fallback"
check_tool hyprlock "lock screen"
check_tool systemctl "power menu actions"
check_tool notify-send "system alert notifications"
check_tool busctl "notification daemon conflict check"
check_tool fc-list "font detection"
check_tool fc-cache "font install refresh"
check_file "cava config" "$HOME/.config/cava/silere-shell.conf" "cp assets/cava.conf ~/.config/cava/silere-shell.conf"

if command -v qs >/dev/null 2>&1; then
  if qs list >/dev/null 2>&1; then
    printf "ok   %-13s %s\n" "qs IPC" "available"
  else
    printf "miss %-13s %s\n" "qs IPC" "qs list failed (shell may not be running)"
  fi
fi

if command -v busctl >/dev/null 2>&1; then
  if busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner s org.freedesktop.Notifications >/dev/null 2>&1; then
    printf "ok   %-13s %s\n" "notifications" "D-Bus owner present"
  else
    printf "miss %-13s %s\n" "notifications" "no D-Bus notification owner"
  fi
fi

if command -v upower >/dev/null 2>&1; then
  if upower -e 2>/dev/null | grep -q '/battery_'; then
    printf "ok   %-13s %s\n" "battery" "UPower battery detected"
  else
    printf "miss %-13s %s\n" "battery" "no UPower battery detected"
  fi
fi

if command -v fc-list >/dev/null 2>&1; then
  if fc-list : family 2>/dev/null | grep -qi "JetBrainsMono Nerd"; then
    printf "ok   %-13s %s\n" "font" "JetBrainsMono Nerd Font"
  else
    printf "miss %-13s %s\n" "font" "JetBrainsMono Nerd Font not found"
  fi
fi

if command -v pipewire >/dev/null 2>&1; then
  pipewire_state=""
  if command -v systemctl >/dev/null 2>&1; then
    pipewire_state="$(systemctl --user is-active pipewire.service 2>/dev/null || true)"
  fi
  if [ "$pipewire_state" = active ]; then
    printf "ok   %-13s %s\n" "audio service" "pipewire.service active"
  else
    printf "miss %-13s %s\n" "audio service" "pipewire.service not active or unavailable"
  fi
fi

if command -v wireplumber >/dev/null 2>&1; then
  wireplumber_state=""
  if command -v systemctl >/dev/null 2>&1; then
    wireplumber_state="$(systemctl --user is-active wireplumber.service 2>/dev/null || true)"
  fi
  if [ "$wireplumber_state" = active ]; then
    printf "ok   %-13s %s\n" "session mgr" "wireplumber.service active"
  else
    printf "miss %-13s %s\n" "session mgr" "wireplumber.service not active or unavailable"
  fi
fi

if command -v nmcli >/dev/null 2>&1; then
  nm_state="$(nmcli -t -f RUNNING general 2>/dev/null || true)"
  if [ "$nm_state" = running ]; then
    printf "ok   %-13s %s\n" "network mgr" "NetworkManager running"
  else
    printf "miss %-13s %s\n" "network mgr" "NetworkManager not running or unavailable"
  fi
fi

if command -v hyprctl >/dev/null 2>&1; then
  if hyprctl monitors >/dev/null 2>&1; then
    printf "ok   %-13s %s\n" "hyprland" "hyprctl can query compositor"
  else
    printf "miss %-13s %s\n" "hyprland" "hyprctl cannot query compositor"
  fi
fi

if command -v matugen >/dev/null 2>&1; then
  if [ -f config/MatugenTheme.qml ]; then
    printf "ok   %-13s %s\n" "theme" "config/MatugenTheme.qml"
  elif [ -f config/MatugenTheme.default.qml ]; then
    printf "miss %-13s %s\n" "theme" "generated theme absent; default will be seeded for smoke test"
  else
    printf "miss %-13s %s\n" "theme" "config/MatugenTheme.default.qml missing"
  fi
fi

if command -v cava >/dev/null 2>&1; then
  if pgrep -x cava >/dev/null 2>&1; then
    printf "ok   %-13s %s\n" "visualizer" "cava running"
  else
    printf "miss %-13s %s\n" "visualizer" "cava not running"
  fi
fi

echo
echo "== quickshell smoke =="
if command -v qs >/dev/null 2>&1; then
  if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "no Wayland display; skipping smoke launch"
  elif [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "$XDG_RUNTIME_DIR" ]; then
    echo "no usable XDG_RUNTIME_DIR; skipping smoke launch"
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
        echo "display unavailable; skipping smoke launch"
      else
        cat "$smoke_log"
        status=1
      fi
    fi
  fi
else
  echo "qs missing; skipping smoke launch"
  status=1
fi

exit "$status"
