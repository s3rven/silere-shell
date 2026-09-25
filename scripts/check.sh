#!/usr/bin/env bash
set -eu
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/xdg.sh"
cd "$ROOT" || exit 1

_stop_jobs=1
trap 'printf "\ninterrupted\n" >&2; exit 130' TERM
# ctrl-c reaches every probe itself, and a second signal would cut its own cleanup short
trap 'printf "\ninterrupted\n" >&2; _stop_jobs=0; exit 130' INT

status=0
warnings=0
seen_section=0

section() {
  [ "$seen_section" -eq 0 ] || printf '\n'
  seen_section=1
  printf '== %s ==\n' "$1"
}
ok() { printf 'ok   %-15s %s\n' "$1" "$2"; }
info() { printf '     %-15s %s\n' "$1" "$2"; }
warn() { printf 'warn %-15s %s\n' "$1" "$2"; warnings=$((warnings + 1)); }
fail() { printf 'fail %-15s %s\n' "$1" "$2" >&2; status=1; }

# a binary that cannot start still satisfies `command -v`; without this every probe below
# fails describing whatever it was testing instead of the runtime that never ran
qs_usable=0
qs_probe=""
if command -v qs >/dev/null 2>&1 && qs_probe="$(qs --version 2>&1)"; then
  qs_usable=1
fi

# each probe runs its own qs under private config and runtime dirs, so they all run at once
scratch="$(mktemp -d "${TMPDIR:-/tmp}/silere-check.XXXXXX")"
_jobs=""
_cleanup() {
  local j p
  for j in $_jobs; do
    p="_pid_$j"
    [ "$_stop_jobs" = 0 ] || kill "${!p}" 2>/dev/null || true
    wait "${!p}" 2>/dev/null || true
  done
  rm -rf "$scratch"
  return 0
}
trap _cleanup EXIT

_start() { # $1 = job, $2 = script
  if [ -f "$2" ]; then
    # a background job starts with Ctrl-C ignored, and the probes clean up on it
    ( trap - INT; exec bash "$2" ) >"$scratch/$1.out" 2>&1 &
    printf -v "_pid_$1" '%s' "$!"
    _jobs="$_jobs $1"
  else
    printf 'SKIP: %s missing\n' "$2" >"$scratch/$1.out"
  fi
}

_join() { # $1 = job; sets job_out and job_code
  local p="_pid_$1"
  job_code=0
  if [ -n "${!p:-}" ]; then
    wait "${!p}" || job_code=$?
    _jobs="${_jobs/ $1/}"
  fi
  job_out="$(cat "$scratch/$1.out")"
}

_report() { # $1 = job, $2 = label, $3 = failure, $4 = pattern for the ok line
  if [ "$qs_usable" != 1 ]; then
    warn "$2" "not run: Quickshell will not start"
    return 0
  fi
  _join "$1"
  if [ "$job_code" -ne 0 ]; then
    printf '%s\n' "$job_out" | sed 's/^/       /'
    fail "$2" "$3"
  elif printf '%s\n' "$job_out" | grep -q '^SKIP'; then
    warn "$2" "$(printf '%s\n' "$job_out" | sed -n 's/^SKIP: //p' | head -1)"
  else
    ok "$2" "$(printf '%s\n' "$job_out" | grep -oE "${4:-.+}" | tail -1)"
  fi
}

_start lint scripts/ci-lint.sh
if [ "$qs_usable" = 1 ]; then
  _start logic scripts/test-logic.sh
  _start surfaces scripts/test-surfaces.sh
  _start panels scripts/test-panels.sh
  _start mutate scripts/test-mutate.sh
  _start fit scripts/test-layout-fit.sh
fi

section "versions"
# reported, never judged: the dependency section below is what fails on a missing qs
_first_line() { head -n 1 2>/dev/null || true; }

if silere_ver="$(git describe --tags --always --dirty 2>/dev/null)" && [ -n "$silere_ver" ]; then
  info "silere" "$silere_ver"
else
  info "silere" "unknown (not a git checkout)"
fi

if command -v qs >/dev/null 2>&1; then
  info "quickshell" "$(qs --version 2>&1 | _first_line)"
else
  info "quickshell" "not in PATH"
fi

if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null 2>&1; then
  if compositor_ver="$(hyprctl version 2>/dev/null)"; then
    info "compositor" "$(printf '%s\n' "$compositor_ver" | _first_line)"
  else
    info "compositor" "Hyprland session unavailable"
  fi
elif [ -n "${NIRI_SOCKET:-}" ] && command -v niri >/dev/null 2>&1; then
  if compositor_ver="$(niri --version 2>&1)"; then
    info "compositor" "$(printf '%s\n' "$compositor_ver" | _first_line)"
  else
    info "compositor" "niri session unavailable"
  fi
else
  info "compositor" "no live Hyprland or niri session (${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}})"
fi

section "git diff --check"
# a packaged or tarball install is not a checkout; without this the whole run reports
# failure on a healthy shell and buries every check below it in git usage text
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
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
else
  info "git" "not a checkout, skipped"
fi

section "structural lint"
_join lint
if [ ! -f scripts/ci-lint.sh ]; then
  info "ci-lint" "developer tooling, not in this install"
elif [ "$job_code" -eq 0 ]; then
  ok "ci-lint" "structural checks passed"
else
  fail "ci-lint" "structural checks failed"
  printf '%s\n' "$job_out"
fi

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

if ! command -v qs >/dev/null 2>&1; then
  fail qs "Quickshell runtime is required but was not found in PATH"
elif [ "$qs_usable" = 1 ]; then
  ok qs "Quickshell runtime"
else
  fail qs "Quickshell is installed but will not start: ${qs_probe%%$'\n'*}"
fi
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
optional_tool inotifywait "screenshot feedback + Hyprland restart recovery"
optional_tool nmcli "VPN name fallback"
optional_tool cava "audio visualizer"
optional_tool matugen "wallpaper-matched colors"
optional_any_tool "updates" "update count widget" checkupdates apt dnf zypper xbps-install
optional_any_tool "AUR helper" "AUR update count" paru yay
optional_any_tool "night light" "night light toggle" hyprsunset wlsunset
optional_tool pgrep "night light external state check"
optional_tool pkill "night light external stop fallback"
optional_tool powerprofilesctl "power profile selector"
optional_any_tool "lock screen" "lock action" hyprlock swaylock gtklock
optional_any_tool "sound settings" "per-app routing hand-off" pwvucontrol pavucontrol
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
_data_home="$(_silere_xdg_home "${XDG_DATA_HOME:-}" .local/share)" || _data_home=""
_wayland_socket() {
  [ -n "${WAYLAND_DISPLAY:-}" ] || return 1
  case "$WAYLAND_DISPLAY" in
    /*) printf '%s\n' "$WAYLAND_DISPLAY" ;;
    *)  [ -n "${XDG_RUNTIME_DIR:-}" ] || return 1
        printf '%s\n' "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ;;
  esac
}

if [ "$qs_usable" = 1 ]; then
  if timeout 5 qs ipc -p "$ROOT/shell.qml" show >/dev/null 2>&1; then
    ok "qs IPC" "this checkout's shell answers"
  else
    warn "qs IPC" "this checkout's shell is not running or does not answer"
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

_autostart_hit=""
for _cdir in "$_cfg_home/hypr" "$_cfg_home/niri"; do
  [ -n "$_cfg_home" ] && [ -d "$_cdir" ] || continue
  # A theme rule or comment may mention Silere without launching it. Accept the
  # installer's marker or a real Hyprland/niri/Lua startup directive whose command
  # names the launcher (packaged install) or the shell.qml path (checkout install).
  _autostart_hit="$(grep -rliE \
    '^[[:space:]]*(#|//|--)[[:space:]]*silere-shell begin[[:space:]]*$|^[[:space:]]*(exec-once[[:space:]]*=|spawn-at-startup([[:space:]]|")|hl\.exec_cmd\().*(silere-shell|silere-shell/shell\.qml)' \
    "$_cdir" 2>/dev/null | head -n 1 || true)"
  [ -n "$_autostart_hit" ] && break
done
# A compositor directive is what install.sh writes, but a session can just as well
# start the shell from a systemd user unit. Without this the whole supported-but-
# unwritten path reports as "it will not start on login" on a working install.
_autostart_unit=""
if [ -z "$_autostart_hit" ] && command -v systemctl >/dev/null 2>&1; then
  _unit_dirs=(/etc/systemd/user /usr/lib/systemd/user)
  [ -z "$_data_home" ] || _unit_dirs=("$_data_home/systemd/user" "${_unit_dirs[@]}")
  [ -z "$_cfg_home" ] || _unit_dirs=("$_cfg_home/systemd/user" "${_unit_dirs[@]}")
  for _udir in "${_unit_dirs[@]}"; do
    [ -d "$_udir" ] || continue
    # the launcher binary or the checkout's shell.qml, never a path that merely lives
    # under silere-shell/ — the update timer's ExecStart does too, and sorts first
    _autostart_unit="$(grep -rlE \
      "^[[:space:]]*ExecStart=.*(shell\\.qml|silere-shell([[:space:]\"']|\$)|/silere[[:space:]]+run)" \
      "$_udir" 2>/dev/null | head -n 1 || true)"
    [ -n "$_autostart_unit" ] && break
  done
fi
unset _unit_dirs
_autostart_unit_live=false
if [ -n "$_autostart_unit" ]; then
  _unit_name="${_autostart_unit##*/}"
  case "$(systemctl --user is-enabled "$_unit_name" 2>/dev/null || true)" in
    enabled|enabled-runtime|indirect|generated) _autostart_unit_live=true ;;
  esac
  # a unit with no [Install] section is pulled in by a session target rather than
  # enabled, so being wanted or already running is the only signal it will start
  if ! $_autostart_unit_live \
     && systemctl --user is-active --quiet "$_unit_name" 2>/dev/null; then
    _autostart_unit_live=true
  fi
fi

if [ -n "$_autostart_hit" ]; then
  ok "autostart" "referenced in ${_autostart_hit#"${HOME:-}/"}"
elif $_autostart_unit_live; then
  ok "autostart" "started by ${_autostart_unit##*/}"
elif [ -n "$_autostart_unit" ]; then
  warn "autostart" "${_autostart_unit##*/} launches Silere but is neither enabled nor running"
elif [ -n "$_cfg_home" ] && { [ -d "$_cfg_home/hypr" ] || [ -d "$_cfg_home/niri" ]; }; then
  warn "autostart" "no Silere startup directive in the compositor config; it will not start on login"
fi

# These modules are imported unconditionally, so their packaging is required
# even when the corresponding service/agent is not active in this session.
# Shared with install.sh and CI so the module list and the import-root lookup
# only exist in one place.
source "$ROOT/scripts/lib/qml-modules.sh"

# the README and the AUR package both promise a floor; nothing checked it against the
# Quickshell actually installed, so an older one failed later as a missing property
if [ "$qs_usable" -eq 1 ]; then
  qs_version="$(_silere_quickshell_version || true)"
  if [ -z "$qs_version" ]; then
    warn "qs version" "cannot read a version from qs --version; Silere needs $SILERE_MIN_QUICKSHELL or newer"
  elif _silere_version_at_least "$qs_version" "$SILERE_MIN_QUICKSHELL"; then
    ok "qs version" "$qs_version (floor $SILERE_MIN_QUICKSHELL)"
  else
    fail "qs version" "$qs_version is older than the required $SILERE_MIN_QUICKSHELL"
  fi
fi

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
# teed rather than captured: the probe streams progress over several seconds, and a
# skip here still exits 0 while CI runs it under SILERE_REQUIRE_QML_TOOLS=1 and fails
qml_log="$scratch/qml.log"
bash scripts/test-qml-headless.sh 2>&1 | tee "$qml_log"
qml_code=${PIPESTATUS[0]}
if [ "$qml_code" -ne 0 ]; then
  status=1
elif grep -q '^SKIP' "$qml_log"; then
  warn "qml" "$(sed -n 's/^SKIP: //p' "$qml_log" | head -1)"
fi

section "behavioral logic"
_report logic logic "behavioral probe failed"

section "quickshell smoke"
if [ "$qs_usable" = 1 ]; then
  if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    warn "startup" "no Wayland display; runtime smoke test skipped"
  elif [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "$XDG_RUNTIME_DIR" ]; then
    warn "startup" "no usable XDG_RUNTIME_DIR; runtime smoke test skipped"
  elif ! _silere_timeout_kill_after_ok; then
    warn "startup" "timeout --kill-after unsupported; runtime smoke test skipped"
  else
    code=0
    smoke_log="$scratch/smoke.log"
    # The real settings decide whether this installation starts, so the dwell runs on a
    # copy of them: a whole shell sitting at the live config writes its state files back,
    # and a checkout under test would rewrite notification history the user is still using.
    smoke_home="$scratch/smoke-cfg"
    mkdir -p "$smoke_home/silere-shell"
    if [ -n "$_cfg_home" ] && [ -d "$_cfg_home/silere-shell" ]; then
      cp -a "$_cfg_home/silere-shell/." "$smoke_home/silere-shell/" 2>/dev/null || true
    fi

    # Every default-off setting gates a Loader, so the startup pass never loads those
    # paths and the type-check cannot see a runtime-only error inside one. Load once
    # more with them all on, in a scratch config so real settings stay untouched.
    # nightLightAuto and neutralAccentAuto drive a gamma tool and matugen hooks;
    # reduceMotion would zero the animations this is meant to instantiate.
    cov_keys="$(sed -n 's/.*property bool[[:space:]]\{1,\}\([A-Za-z_][A-Za-z0-9_]*\)[[:space:]]*:[[:space:]]*false.*/\1/p' \
      services/ShellSettings.qml \
      | grep -vxE '_loaded|nightLightAuto|neutralAccentAuto|reduceMotion' || true)"

    # Each case below is a whole shell that must sit at its config for the full dwell.
    # They share nothing but the checkout, so they dwell at the same time rather than
    # costing one 5s wait each.
    par_dir="$scratch/par"
    mkdir -p "$par_dir"
    smoke_pids=""
    _smoke_case() {
      mkdir -p "$par_dir/$1/silere-shell"
      printf '%s' "$2" > "$par_dir/$1/silere-shell/settings.json"
      _case_code=0
      XDG_CONFIG_HOME="$par_dir/$1" XDG_STATE_HOME="$par_dir/$1" timeout --kill-after=2s 5s qs -p shell.qml --no-color \
        >"$par_dir/$1.log" 2>&1 || _case_code=$?
      printf '%s' "$_case_code" > "$par_dir/$1.code"
    }

    # timeout above signals the whole group, which hides a helper that outlives the shell.
    # This one signals qs alone, as a crash or a manual restart does, then looks for
    # anything still carrying its tag.
    _exit_case() {
      mkdir -p "$par_dir/exit/silere-shell"
      # the screenshot glow starts the second long-running watcher
      printf '{"underlineGlow": true, "underlineScreenshotGlow": true}' \
        > "$par_dir/exit/silere-shell/settings.json"
      _tag="silere-exit-$$-$RANDOM$RANDOM"
      _tagged() {
        grep -lzxF "SILERE_EXIT_TAG=$_tag" /proc/[0-9]*/environ 2>/dev/null \
          | sed 's#^/proc/##; s#/environ$##' || true
      }
      SILERE_EXIT_TAG="$_tag" XDG_CONFIG_HOME="$par_dir/exit" XDG_STATE_HOME="$par_dir/exit" \
        qs -p shell.qml --no-color >"$par_dir/exit.log" 2>&1 &
      _qs=$!
      _i=0
      while [ "$_i" -lt 20 ] && ! grep -q 'Configuration Loaded' "$par_dir/exit.log" 2>/dev/null; do
        sleep 0.25; _i=$((_i + 1))
      done
      # the tool scan runs after load, and the watchers wait on it
      sleep 2
      _tagged | grep -vx "$_qs" | wc -l | tr -d ' ' > "$par_dir/exit.before"
      kill -TERM "$_qs" 2>/dev/null || true
      _i=0
      while [ "$_i" -lt 12 ] && kill -0 "$_qs" 2>/dev/null; do sleep 0.25; _i=$((_i + 1)); done
      kill -KILL "$_qs" 2>/dev/null || true
      wait "$_qs" 2>/dev/null || true
      sleep 0.5
      : > "$par_dir/exit.left"
      for _p in $(_tagged); do
        printf '%s(%s) ' "$(cat "/proc/$_p/comm" 2>/dev/null || echo gone)" "$_p" >> "$par_dir/exit.left"
        kill -KILL "$_p" 2>/dev/null || true
      done
    }
    exit_probe=0
    if printf 'a\0' | grep -qzx a 2>/dev/null && [ -r /proc/self/environ ]; then
      exit_probe=1
      _exit_case &
      smoke_pids="$smoke_pids $!"
    fi

    if [ -n "$cov_keys" ]; then
      _smoke_case cov "$({ printf '{\n'
        printf '%s\n' "$cov_keys" | sed '$!s/.*/  "&": true,/; $s/.*/  "&": true/'
        printf '}\n'; })" &
      smoke_pids="$smoke_pids $!"
    fi

    # settings.json is hand-editable and the README says so, so a truncated or
    # retyped file is a real user state, not a hypothetical. The loader must keep
    # the shell up and leave a file it could not read alone.
    bad_n=0
    for _case in '{"barHeight": 3' '[1,2,3]' 'null' '' \
      '{"barHeight":"tall","osdEnabled":42,"barPosition":"sideways"}' \
      '{"__version":999,"unknownFutureKey":"keep","barHeight":40}'
    do
      bad_n=$((bad_n + 1))
      printf '%s' "${_case:-<empty>}" > "$par_dir/bad$bad_n.desc"
      _smoke_case "bad$bad_n" "$_case" &
      smoke_pids="$smoke_pids $!"
    done

    # the startup dwell runs beside the cases below instead of ahead of them; they only
    # report once it has passed, so a shell that cannot start still fails just once
    ( _main_code=0
      XDG_CONFIG_HOME="$smoke_home" XDG_STATE_HOME="$smoke_home" timeout --kill-after=2s 5s qs -p shell.qml --no-color \
        >"$smoke_log" 2>&1 || _main_code=$?
      printf '%s' "$_main_code" > "$scratch/smoke.code" ) &
    smoke_pids="$smoke_pids $!"
    wait $smoke_pids || true
    code="$(cat "$scratch/smoke.code" 2>/dev/null || echo 1)"
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
      if [ -z "$cov_keys" ]; then
        warn "off-path load" "no default-off settings found; coverage pass skipped"
      else
        code="$(cat "$par_dir/cov.code" 2>/dev/null || echo 1)"
        if [ "$code" -ne 0 ] && [ "$code" -ne 124 ]; then
          cat "$par_dir/cov.log"
          fail "off-path load" "Quickshell exited with status $code with every option on"
        elif grep -qE 'Failed to load configuration|Type [^ ]+ unavailable|Cannot assign to non-existent property|is not a type|Binding loop detected' "$par_dir/cov.log"; then
          cat "$par_dir/cov.log"
          fail "off-path load" "a default-off code path failed to load"
        else
          # a script error does not fail the load, so this is the only pass that sees one.
          # warn rather than fail: absent hardware can make a path throw on machines this
          # one cannot stand in for
          cov_script="$(grep -oE 'ReferenceError: [^,]*|TypeError: [^,]*|Invalid write to global property "[^"]*"' \
            "$par_dir/cov.log" | sort -u | head -3 || true)"
          if [ -n "$cov_script" ]; then
            printf '%s\n' "$cov_script" | sed 's/^/       /'
            warn "off-path load" "a default-off path loaded but threw at runtime"
          else
            ok "off-path load" "$(printf '%s\n' "$cov_keys" | wc -l | tr -d ' ') default-off settings loaded without errors"
          fi
        fi
      fi

      bad_failures=""
      _i=0
      while [ "$_i" -lt "$bad_n" ]; do
        _i=$((_i + 1))
        code="$(cat "$par_dir/bad$_i.code" 2>/dev/null || echo 1)"
        _desc="$(cat "$par_dir/bad$_i.desc" 2>/dev/null || echo '?')"
        if [ "$code" -ne 0 ] && [ "$code" -ne 124 ]; then
          bad_failures="$bad_failures  exited $code on: $_desc"$'\n'
        elif grep -qE 'Failed to load configuration|Type [^ ]+ unavailable|Binding loop detected' "$par_dir/bad$_i.log"; then
          bad_failures="$bad_failures  failed to load on: $_desc"$'\n'
        fi
      done
      if [ -n "$bad_failures" ]; then
        printf '%s' "$bad_failures"
        fail "bad settings" "a malformed settings.json took the shell down"
      else
        ok "bad settings" "$bad_n malformed settings files each left the shell running"
      fi

      if [ "$exit_probe" = 0 ]; then
        warn "exit" "grep -z or /proc environ unavailable; leftover helper check skipped"
      else
        exit_left="$(cat "$par_dir/exit.left" 2>/dev/null || true)"
        exit_before="$(cat "$par_dir/exit.before" 2>/dev/null || echo 0)"
        if [ -n "$exit_left" ]; then
          if command -v setpriv >/dev/null 2>&1; then
            fail "exit" "helpers outlived a killed shell: $exit_left"
          else
            warn "exit" "helpers outlive a killed shell without setpriv (util-linux): $exit_left"
          fi
        else
          ok "exit" "a killed shell took its $exit_before helper process(es) with it"
        fi
      fi
    fi
  fi
else
  warn "startup" "not run: Quickshell will not start"
fi

section "surface build"
# The passes above launch the shell but never open the menu, so no settings
# section is ever built and a runtime-only error inside one stays invisible.
_report surfaces surfaces "a settings section failed to build standalone"

section "layer-shell build"
# The surface pass above cannot reach these: every layer-shell root requires a
# targetScreen, and a PanelWindow has no backend under the offscreen platform.
_report panels panels "a layer-shell surface failed to build"

section "live settings changes"
# Every pass above fixes the settings before the surface exists. A binding that
# only breaks when the value changes under a built surface survives all of them.
_report mutate mutate "a live settings change broke a surface" 'swept .*'

section "layout fit"
# Building a section says nothing about whether its labels survive the width they
# ship at; Qt elides them and reports success either way.
_report fit layout "settings text is truncated at the shipped panel width"

if [ "$status" -eq 0 ]; then
  printf '\nchecks passed (%d warning(s))\n' "$warnings"
else
  printf '\nchecks failed (%d warning(s))\n' "$warnings"
fi
exit "$status"
