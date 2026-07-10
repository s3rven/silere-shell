#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

REPO_URL="https://github.com/s3rven/silere-shell.git"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DEFAULT_DIR="$CONFIG_HOME/silere-shell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── colors ──────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    R='\033[0m' BOLD='\033[1m'
    GREEN='\033[0;32m' CYAN='\033[0;36m' YELLOW='\033[1;33m' DIM='\033[2m' RED='\033[0;31m'
else
    R='' BOLD='' GREEN='' CYAN='' YELLOW='' DIM='' RED=''
fi

_ok()   { printf "    ${GREEN}ok${R}      %s\n" "$*"; }
_skip() { printf "    ${DIM}skip${R}    %s\n" "$*"; }
_warn() { printf "    ${YELLOW}warn${R}    %s\n" "$*"; }
_err()  { printf "    ${RED}error${R}   %s\n" "$*" >&2; }
_die()  { _err "$*"; exit 1; }

_section() { printf "\n${BOLD}==> %s${R}\n" "$1"; }

_need_tty() {
    [ -r /dev/tty ] || _die "interactive install requires a TTY — clone the repo and run scripts/install.sh from a terminal"
}

_reject_unsafe_path() {
    if printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        _die "install path may not contain control characters or newlines: $1"
    fi
}

_shell_quote() {
    local s="$1"
    s="${s//\'/\'\\\'\'}"
    printf "'%s'" "$s"
}

_shell_printf_bytes() {
    local LC_ALL=C s="$1" out="" ch oct i
    for ((i = 0; i < ${#s}; i++)); do
        ch="${s:i:1}"
        printf -v oct '%03o' "'$ch"
        out+="\\$oct"
    done
    printf '%s' "$out"
}

_lua_string() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '"%s"' "$s"
}

_toml_basic_string() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '"%s"' "$s"
}

source "$SCRIPT_DIR/lib/qml-modules.sh"

# Resolve the Hyprland process that owns this shell session. Prefer an ancestor
# (Quickshell and terminals are normally descendants of their compositor), then
# accept a same-user process only when it is the sole candidate. Never guess
# between multiple sessions.
_HYPR_PROC_ROOT="${SILERE_PROC_ROOT:-/proc}"

_proc_ppid() {
    local pid="$1" stat rest
    stat="$(cat "$_HYPR_PROC_ROOT/$pid/stat" 2>/dev/null)" || return 1
    rest="${stat##*) }"
    [ "$rest" != "$stat" ] || return 1
    rest="${rest#* }"
    printf '%s\n' "${rest%% *}"
}

_same_user_process() {
    [ "$(stat -c '%u' "$_HYPR_PROC_ROOT/$1" 2>/dev/null)" = "$(id -u)" ]
}

_find_hyprland_pid() {
    local pid="${SILERE_PARENT_PID:-$PPID}" parent comm candidate="" count=0

    while [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" -gt 1 ]; do
        if _same_user_process "$pid"; then
            comm="$(cat "$_HYPR_PROC_ROOT/$pid/comm" 2>/dev/null || true)"
            if [ "$comm" = "Hyprland" ]; then
                printf '%s\n' "$pid"
                return 0
            fi
        fi
        parent="$(_proc_ppid "$pid" 2>/dev/null || true)"
        [[ "$parent" =~ ^[0-9]+$ ]] && [ "$parent" != "$pid" ] || break
        pid="$parent"
    done

    for comm in "$_HYPR_PROC_ROOT"/[0-9]*/comm; do
        [ -r "$comm" ] || continue
        [ "$(cat "$comm" 2>/dev/null)" = "Hyprland" ] || continue
        pid="${comm%/comm}"
        pid="${pid##*/}"
        _same_user_process "$pid" || continue
        candidate="$pid"
        count=$((count + 1))
    done
    [ "$count" -eq 1 ] || return 1
    printf '%s\n' "$candidate"
}

_normalize_hypr_path() {
    local path="$1" base="$2"
    path="${path/#\~/$HOME}"
    case "$path" in
        /*) ;;
        *) path="$base/$path" ;;
    esac
    readlink -m -- "$path" 2>/dev/null || printf '%s\n' "$path"
}

_hypr_config_for_pid() {
    local pid="$1" cwd raw="" i
    local -a args=()
    mapfile -d '' -t args 2>/dev/null < "$_HYPR_PROC_ROOT/$pid/cmdline" || return 1
    for ((i = 0; i < ${#args[@]}; i++)); do
        if [ "${args[i]}" = "--config" ] || [ "${args[i]}" = "-c" ]; then
            ((i + 1 < ${#args[@]})) || return 1
            raw="${args[i + 1]}"
            break
        fi
    done
    [ -n "$raw" ] || return 1
    cwd="$(readlink -f -- "$_HYPR_PROC_ROOT/$pid/cwd" 2>/dev/null)" || return 1
    _normalize_hypr_path "$raw" "$cwd"
}

_hypr_config_path() {
    local config pid
    if [ -n "${SILERE_HYPR_CONFIG:-}" ]; then
        _normalize_hypr_path "$SILERE_HYPR_CONFIG" "$PWD"
        return
    fi
    pid="$(_find_hyprland_pid 2>/dev/null || true)"
    if [ -n "$pid" ]; then
        config="$(_hypr_config_for_pid "$pid" 2>/dev/null || true)"
        if [ -n "$config" ]; then
            printf '%s\n' "$config"
            return
        fi
    fi
    if [ -f "$CONFIG_HOME/hypr/hyprland.lua" ]; then
        printf '%s\n' "$CONFIG_HOME/hypr/hyprland.lua"
    elif [ -f "$CONFIG_HOME/hypr/hyprland.conf" ]; then
        printf '%s\n' "$CONFIG_HOME/hypr/hyprland.conf"
    fi
}

# Side-effect-free helpers used by the runtime detector and focused tests.
case "${1:-}" in
    --hypr-config-path)
        _hypr_config_path
        exit 0
        ;;
    --hypr-config-kind)
        _hypr_kind="$(_hypr_config_path)"
        [[ "$_hypr_kind" == *.lua ]] && exit 0
        exit 1
        ;;
esac
if [ "${SILERE_SCRIPT_LIB_ONLY:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

# Always read from /dev/tty so curl | bash works
_ask() {
    local reply
    _need_tty
    printf "  ${CYAN}::${R}  %s ${DIM}[Y/n]${R} " "$1"
    read -r reply </dev/tty
    [[ ! "$reply" =~ ^[Nn] ]]
}

_ask_path() {
    local reply
    _need_tty
    printf "  ${CYAN}::${R}  Use a different install path? ${DIM}[y/N]${R} " >&2
    read -r reply </dev/tty
    if [[ "$reply" =~ ^[Yy] ]]; then
        printf "  ${CYAN}::${R}  Install to: " >&2
        read -r reply </dev/tty
        reply="${reply/#\~/$HOME}"
        [[ "$reply" =~ ^[[:space:]]*$ ]] && reply=""
        printf '%s' "${reply:-$DEFAULT_DIR}"
    else
        printf '%s' "$DEFAULT_DIR"
    fi
}

_backup() {
    local file="$1"
    if [ -f "$file" ] && [ ! -f "${file}.bak" ]; then
        cp -p "$file" "${file}.bak"
        _skip "backed up existing → ${file##*/}.bak"
    fi
}

# Copy src→dst after asking; backs up an existing file first.
# Returns 0 only when it actually writes, so callers can record the step.
_install_file() {
    local label="$1" src="$2" dst="$3"
    if [ -r "$dst" ]; then
        _skip "already at $dst"
        _ask "Overwrite?" || return 1
        _backup "$dst"
        cp "$src" "$dst" || _die "could not write $dst"
        _ok "updated"
    else
        _ask "Install $label?" || { _skip "skipped"; return 1; }
        mkdir -p "${dst%/*}" || _die "could not create ${dst%/*}"
        cp "$src" "$dst" || _die "could not write $dst"
        _ok "installed"
    fi
}

# ── spinner ──────────────────────────────────────────────────────────────────────
_spin_pid=""
font_tmp=""

spin_start() {
    local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' msg="$1"
    if [ ! -t 1 ]; then
        printf "  %s\n" "$msg"
        return
    fi
    ( local i=0
      while true; do
          printf "\r  ${CYAN}%s${R}  %s " "${chars:$((i % ${#chars})):1}" "$msg"
          sleep 0.08
          ((i++)) || true
      done
    ) &
    _spin_pid=$!
}

spin_stop() {
    [ -z "$_spin_pid" ] && return
    kill "$_spin_pid" 2>/dev/null || true
    wait "$_spin_pid" 2>/dev/null || true
    printf "\r\033[K"
    _spin_pid=""
}

_cleanup() {
    spin_stop
    [ -n "$font_tmp" ] && rm -f "$font_tmp"
    return 0
}
trap '_cleanup' EXIT
trap '_cleanup; exit 130' INT TERM

# ── header ───────────────────────────────────────────────────────────────────────
printf "\n${BOLD}:: silere-shell installer${R}\n"

# ── dependencies ─────────────────────────────────────────────────────────────────
_section "checking dependencies"

command -v git >/dev/null 2>&1 || _die "git is required — install it and re-run"
_ok "git"

has_qs=true
if command -v qs >/dev/null 2>&1; then
    _ok "quickshell"
else
    _warn "quickshell not found — install it before launching silere"
    has_qs=false
fi

qs_modules_ok=true
if $has_qs; then
    for module in "${SILERE_REQUIRED_QML_MODULES[@]}"; do
        if ! _qml_module_available "$module"; then
            _warn "required Quickshell module missing: $module"
            qs_modules_ok=false
        fi
    done
    $qs_modules_ok || _warn "this Quickshell build cannot load Silere; install the full current package"
fi

has_matugen=true
if command -v matugen >/dev/null 2>&1; then
    _ok "matugen"
else
    _warn "matugen not found — wallpaper theming skipped, neutral theme is used"
    has_matugen=false
fi

# ── optional tools ─────────────────────────────────────────────────────────────────
# Each one lights up a single feature; a missing tool just hides it.
_section "optional tools"

_optdep() {
    if command -v "$1" >/dev/null 2>&1; then
        printf "    ${GREEN}ok${R}      %-13s ${DIM}%s${R}\n" "$1" "$2"
    else
        printf "    ${DIM}–       %-13s %s${R}\n" "$1" "$2"
    fi
}

_optdep_any() {
    local label="$1" desc="$2" tool found=""
    shift 2
    for tool in "$@"; do
        if command -v "$tool" >/dev/null 2>&1; then
            found="$tool"
            break
        fi
    done
    if [ -n "$found" ]; then
        printf "    ${GREEN}ok${R}      %-13s ${DIM}%s${R}\n" "$label ($found)" "$desc"
    else
        printf "    ${DIM}–       %-13s %s${R}\n" "$label" "$desc"
    fi
}

if _qml_module_available Quickshell.Services.Pipewire; then
    printf "    ${GREEN}ok${R}      %-13s ${DIM}%s${R}\n" "pipewire" "volume + sound popup"
else
    printf "    ${DIM}–       %-13s %s${R}\n" "pipewire" "volume + sound popup"
fi
_optdep brightnessctl "brightness control + popup"
_optdep inotifywait   "screenshot flash, wallpaper-picker feedback"
_optdep nmcli         "Wi-Fi name, signal, VPN"
_optdep cava          "audio visualizer"
_optdep_any updates   "update count" checkupdates apt dnf zypper xbps-install
_optdep_any "AUR helper" "AUR update count" paru yay
_optdep busctl        "notification daemon check"
_optdep upower        "battery percentage + warnings"
_optdep hyprsunset    "night light toggle"
_optdep pgrep         "optional night light external state check"
_optdep pkill         "optional night light external stop fallback"
_optdep powerprofilesctl "power profile selector"
_optdep hyprlock      "lock screen"
_optdep_any "power actions" "suspend / reboot / shutdown" systemctl loginctl
_optdep notify-send   "low-battery + hot-CPU alerts"
_optdep timeout       "bounded update checks"

# ── font ─────────────────────────────────────────────────────────────────────────
_section "JetBrainsMono Nerd Font"

_font_installed() {
    command -v fc-list >/dev/null 2>&1 && fc-list : family 2>/dev/null | grep -qi "JetBrainsMono Nerd"
}

_font_download_tools_ready() {
    local -a missing=()
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v tar  >/dev/null 2>&1 || missing+=("tar")
    if [ "${#missing[@]}" -eq 0 ]; then
        return 0
    fi
    _warn "font auto-install needs: ${missing[*]}"
    _warn "install those tools or install JetBrainsMono Nerd Font manually"
    return 1
}

did_font=false

if _font_installed; then
    _ok "already installed"
else
    _warn "JetBrainsMono Nerd Font not found"
    if _font_download_tools_ready && _ask "Download and install it now?"; then
        FONT_DIR="$HOME/.local/share/fonts/JetBrainsMono"
        mkdir -p "$FONT_DIR"
        font_tmp="$(mktemp "${TMPDIR:-/tmp}/silere-font.XXXXXX.tar.xz")"
        spin_start "downloading..."
        if curl -fsSL -o "$font_tmp" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz" \
            && tar -xJ -f "$font_tmp" -C "$FONT_DIR" --wildcards "*.ttf" 2>/dev/null; then
            spin_stop
            rm -f "$font_tmp"
            fc-cache -f "$FONT_DIR" 2>/dev/null || true
            _ok "installed to $FONT_DIR"
            did_font=true
        else
            spin_stop
            rm -f "$font_tmp"
            _warn "download failed — install JetBrainsMono Nerd Font manually"
        fi
    else
        _skip "skipped — install a Nerd Font manually before launching silere"
    fi
fi

# ── clone ────────────────────────────────────────────────────────────────────────
_section "silere-shell"

printf "  ${CYAN}::${R}  Install to: ${CYAN}%s${R}\n" "$DEFAULT_DIR"
INSTALL_DIR="$(_ask_path)"

_reject_unsafe_path "$INSTALL_DIR"

if [ -d "$INSTALL_DIR/.git" ]; then
    _ok "already cloned at $INSTALL_DIR"
    if _ask "Pull latest changes?"; then
        spin_start "pulling..."
        if ! GIT_TERMINAL_PROMPT=0 git -C "$INSTALL_DIR" pull --ff-only --quiet; then
            spin_stop; _die "git pull failed — local changes conflict, pull manually"
        fi
        spin_stop; _ok "up to date"
    else
        _skip "using existing clone"
    fi
elif [ -e "$INSTALL_DIR" ]; then
    if _ask "Directory exists but is not a git repo. Remove it and clone fresh?"; then
        rm -rf "$INSTALL_DIR"
        spin_start "cloning..."
        if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 --single-branch --quiet "$REPO_URL" "$INSTALL_DIR"; then
            spin_stop; _die "git clone failed — check your connection"
        fi
        spin_stop; _ok "cloned to $INSTALL_DIR"
    else
        _die "$INSTALL_DIR exists but is not a git repo — pick a different path or clean it up manually"
    fi
else
    spin_start "cloning..."
    if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 --single-branch --quiet "$REPO_URL" "$INSTALL_DIR"; then
        spin_stop; _die "git clone failed — check your connection"
    fi
    spin_stop; _ok "cloned to $INSTALL_DIR"
fi

ROOT="$INSTALL_DIR"
did_tmpl=false did_toml=false did_autostart=false did_update=false
ROOT_PRINTF_BYTES="$(_shell_quote "$(_shell_printf_bytes "$ROOT")")"
MATUGEN_OUTPUT_TOML="$(_toml_basic_string "$ROOT/config/MatugenTheme.qml")"
MATUGEN_INPUT_TOML="$(_toml_basic_string "$CONFIG_HOME/matugen/templates/silere-shell/Theme.qml")"

# Seed the generated theme from the bundled default so the shell themes
# correctly before matugen has run. matugen later overwrites this file.
if [ ! -f "$ROOT/config/MatugenTheme.qml" ] && [ -f "$ROOT/config/MatugenTheme.default.qml" ]; then
    cp "$ROOT/config/MatugenTheme.default.qml" "$ROOT/config/MatugenTheme.qml"
fi

# ── matugen template ─────────────────────────────────────────────────────────────
_section "matugen template"
TMPL_SRC="$ROOT/assets/matugen-theme.qml"
TMPL_DST="$CONFIG_HOME/matugen/templates/silere-shell/Theme.qml"
if ! $has_matugen; then
    _skip "matugen not installed"
elif _install_file "matugen template" "$TMPL_SRC" "$TMPL_DST"; then
    did_tmpl=true
fi

# ── matugen config.toml ──────────────────────────────────────────────────────────
_section "matugen config.toml"
MATUGEN_CFG="$CONFIG_HOME/matugen/config.toml"

if ! $has_matugen; then
    _skip "matugen not installed"
elif [ -f "$MATUGEN_CFG" ] && grep -q '# silere-shell begin' "$MATUGEN_CFG"; then
    _ok "entry already present"
else
    if _ask "Add entry to $MATUGEN_CFG?"; then
        cfg_existed=false
        [ -f "$MATUGEN_CFG" ] && cfg_existed=true
        mkdir -p "${MATUGEN_CFG%/*}"
        [ ! -f "$MATUGEN_CFG" ] && printf '[config]\nversion_check = false\n' > "$MATUGEN_CFG"
        $cfg_existed && _backup "$MATUGEN_CFG"
        cat >> "$MATUGEN_CFG" <<EOF

# silere-shell begin
[templates.silere-shell]
input_path  = $MATUGEN_INPUT_TOML
output_path = $MATUGEN_OUTPUT_TOML
# silere-shell end
EOF
        _ok "entry added"; did_toml=true
    else
        _skip "skipped"
    fi
fi

# ── Hyprland autostart ───────────────────────────────────────────────────────────
_section "Hyprland autostart"
HYPR_CONF="$CONFIG_HOME/hypr/hyprland.conf"
HYPR_LUA="$CONFIG_HOME/hypr/hyprland.lua"

# A compositor launched with `Hyprland --config /custom/path` does not expose
# that choice through XDG_CONFIG_HOME. Prefer an explicit installer override,
# then inspect the current same-user Hyprland session, and only then use the
# standard roots. Relative process arguments are resolved via /proc/PID/cwd.
HYPR_CONFIG="$(_hypr_config_path)"
if [ -n "$HYPR_CONFIG" ]; then
    _reject_unsafe_path "$HYPR_CONFIG"
    [ -f "$HYPR_CONFIG" ] || _die "Hyprland config not found: $HYPR_CONFIG"
    case "$HYPR_CONFIG" in
        *.lua|*.conf) ;;
        *) _die "Hyprland config must end in .lua or .conf: $HYPR_CONFIG" ;;
    esac
fi
# Quickshell links jemalloc, which defaults to 4×nCPU arenas and no purge thread,
# so memory freed after a spike (menu close, wifi scan, notification burst) is
# retained rather than returned to the OS — RSS only ever climbs. Fewer arenas
# plus a background decay thread hand it back. ~50 MB reclaimed per spike here;
# drop the env to revert. Override by exporting MALLOC_CONF before launch.
MALLOC_TUNE="narenas:2,background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:0"

# Qt Quick keeps a CPU-side copy of every image it uploads to the GPU (album art,
# notification images, app icons). Transient mode frees the copy after upload;
# worst case is a re-decode if the texture is ever lost, which never happens on
# a long-lived desktop session.
QSG_TUNE="QSG_TRANSIENT_IMAGES=1 "

# On hybrid GPUs that render on the iGPU, libglvnd still loads the nvidia EGL
# vendor into every GL process (~33 MB unused). Pin to mesa to skip it — but only
# when the active renderer isn't nvidia, or we'd force llvmpipe and break GPU
# rendering. No glxinfo / NVIDIA-only / iGPU-only: leave it unset.
EGL_PIN=""
_mesa_egl="/usr/share/glvnd/egl_vendor.d/50_mesa.json"
_nv_egl="/usr/share/glvnd/egl_vendor.d/10_nvidia.json"
if [ -f "$_mesa_egl" ] && [ -f "$_nv_egl" ] && command -v glxinfo >/dev/null 2>&1; then
    _renderer="$(glxinfo -B 2>/dev/null | grep -i 'OpenGL renderer' || true)"
    if [ -n "$_renderer" ] && ! printf '%s\n' "$_renderer" | grep -qi nvidia; then
        EGL_PIN="__EGL_VENDOR_LIBRARY_FILENAMES=$_mesa_egl "
        _ok "EGL pinned to mesa (skips unused nvidia driver, ~33 MB)"
    fi
fi
# sleep 1: at Hyprland start the Wayland socket may not be ready yet; without the
# delay Qt's platform plugin aborts with SIGABRT in createEventDispatcher. Braces
# group delay+launch so || short-circuits correctly in exec_unless_running.
MALLOC_TUNE_SHELL="$(_shell_quote "$MALLOC_TUNE")"
EGL_ENV_ARG=""
[ -n "$EGL_PIN" ] && EGL_ENV_ARG="__EGL_VENDOR_LIBRARY_FILENAMES=$(_shell_quote "$_mesa_egl") "
LAUNCH_CMD="{ sleep 1; env MALLOC_CONF=$MALLOC_TUNE_SHELL ${QSG_TUNE}${EGL_ENV_ARG}qs -p \"\$(printf '%b' $ROOT_PRINTF_BYTES)/shell.qml\"; }"
LAUNCH_CMD_LUA="$(_lua_string "$LAUNCH_CMD")"

_already_present() { grep -qF 'silere-shell begin' "$1" 2>/dev/null; }

HYPR_DIR="$(dirname -- "${HYPR_CONFIG:-$CONFIG_HOME/hypr/hyprland.conf}")"

if [ "$HYPR_CONFIG" = "$HYPR_LUA" ] && [ -f "$HYPR_CONF" ]; then
    _warn "both hyprland.lua and hyprland.conf found; Lua takes priority"
fi

if [[ "$HYPR_CONFIG" == *.lua ]]; then
    LUA_EXEC_FILE=""
    for candidate in \
        "$HYPR_DIR/custom/execs.lua" \
        "$HYPR_DIR/hyprland/execs.lua" \
        "$HYPR_DIR/execs.lua"
    do
        [ -f "$candidate" ] && { LUA_EXEC_FILE="$candidate"; break; }
    done

    # the snippet uses a framework-specific API; only emit it where that framework exists
    if [ -n "$LUA_EXEC_FILE" ] && ! grep -qE 'hyprland\.lib|hl\.on' "$LUA_EXEC_FILE" "$HYPR_CONFIG" 2>/dev/null; then
        _warn "Lua config found but no hyprland.lib/hl.on framework detected"
        _warn "add manually: local h = require(\"hyprland.lib\"); h.exec($LAUNCH_CMD_LUA)"
    elif [ -n "$LUA_EXEC_FILE" ] && _already_present "$LUA_EXEC_FILE"; then
        _ok "already present in $LUA_EXEC_FILE"
    elif [ -n "$LUA_EXEC_FILE" ]; then
        if _ask "Add autostart to ${LUA_EXEC_FILE##*/}?"; then
            _backup "$LUA_EXEC_FILE"
            cat >> "$LUA_EXEC_FILE" <<EOF

-- silere-shell begin
local _silere_lib = require("hyprland.lib")
hl.on("hyprland.start", function()
    _silere_lib.exec($LAUNCH_CMD_LUA)
end)
-- silere-shell end
EOF
            _ok "added to $LUA_EXEC_FILE"; did_autostart=true
        else
            _skip "skipped — add manually: _silere_lib.exec($LAUNCH_CMD_LUA)"
        fi
    else
        _warn "Lua config detected but no execs.lua found"
        _warn "add manually: local h = require(\"hyprland.lib\"); h.exec($LAUNCH_CMD_LUA)"
    fi

elif [[ "$HYPR_CONFIG" == *.conf ]]; then
    if _already_present "$HYPR_CONFIG"; then
        _ok "already present in $HYPR_CONFIG"
    else
        if _ask "Add exec-once to $HYPR_CONFIG?"; then
            _backup "$HYPR_CONFIG"
            cat >> "$HYPR_CONFIG" <<EOF

# silere-shell begin
exec-once = $LAUNCH_CMD
# silere-shell end
EOF
            _ok "added"; did_autostart=true
        else
            _skip "skipped — add manually: exec-once = $LAUNCH_CMD"
        fi
    fi
else
    _warn "no Hyprland config found"
    _warn "add manually: exec-once = $LAUNCH_CMD"
fi

# ── update-check timer ──────────────────────────────────────────────────────────────
_section "update-check timer"

if ! command -v systemctl >/dev/null 2>&1; then
    _skip "systemctl not found"
elif _ask "Install daily update-check timer (flags pending updates in the bar)?"; then
    if "$ROOT/scripts/update.sh" --timer-enable 2>/dev/null; then
        _ok "enabled — checks for Silere updates and shows a bar badge when one is ready"
        did_update=true
    else
        _warn "units installed but enable failed — run: systemctl --user enable --now silere-update.timer"
    fi
else
    _skip "skipped — enable later with: $ROOT/scripts/update.sh --timer-enable"
fi

# ── summary ──────────────────────────────────────────────────────────────────────
printf "\n${BOLD}==> done${R}\n"
printf "    ${GREEN}ok${R}      installed at %s\n" "$ROOT"
$did_font      && printf "    ${GREEN}ok${R}      JetBrainsMono Nerd Font\n" || printf "    ${DIM}skip${R}    JetBrainsMono Nerd Font\n"
$did_tmpl      && printf "    ${GREEN}ok${R}      matugen template\n" || printf "    ${DIM}skip${R}    matugen template\n"
$did_toml      && printf "    ${GREEN}ok${R}      matugen toml\n"     || printf "    ${DIM}skip${R}    matugen toml\n"
$did_autostart && printf "    ${GREEN}ok${R}      autostart\n"        || printf "    ${DIM}skip${R}    autostart\n"
$did_update    && printf "    ${GREEN}ok${R}      auto-update timer\n" || printf "    ${DIM}skip${R}    auto-update timer\n"
if $has_qs && $qs_modules_ok; then
    printf "\n  restart Hyprland to launch silere\n"
elif $has_qs; then
    printf "\n  ${YELLOW}install a complete current Quickshell build${R}, then restart Hyprland\n"
else
    printf "\n  ${YELLOW}install Quickshell${R}, then restart Hyprland to launch silere\n"
fi
printf "  to uninstall: ${DIM}%s/scripts/uninstall.sh${R}\n\n" "$ROOT"
