#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/s3rven/silere-shell.git"
DEFAULT_DIR="$HOME/.config/silere-shell"

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

# Always read from /dev/tty so curl | bash works
_ask() {
    local reply
    printf "  ${CYAN}::${R}  %s ${DIM}[Y/n]${R} " "$1"
    read -r reply </dev/tty
    [[ ! "$reply" =~ ^[Nn] ]]
}

_ask_path() {
    local reply
    printf "  ${CYAN}::${R}  Use a different install path? ${DIM}[y/N]${R} " >&2
    read -r reply </dev/tty
    if [[ "$reply" =~ ^[Yy] ]]; then
        printf "  ${CYAN}::${R}  Install to: " >&2
        read -r reply </dev/tty
        reply="${reply/#\~/$HOME}"
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

_optdep pipewire      "volume + sound popup"
_optdep brightnessctl "brightness control + popup"
_optdep inotifywait   "instant brightness, screenshot flash"
_optdep nmcli         "Wi-Fi name, signal, VPN"
_optdep cava          "audio visualizer"
_optdep_any updates   "update count" checkupdates apt dnf zypper xbps-install
_optdep_any "AUR helper" "AUR update count" paru yay
_optdep busctl        "notification daemon check"
_optdep upower        "battery percentage + warnings"
_optdep hyprsunset    "night light toggle"
_optdep pgrep         "night light state check"
_optdep pkill         "night light fallback stop"
_optdep hyprlock      "lock screen"
_optdep systemctl     "suspend / reboot / shutdown"
_optdep notify-send   "low-battery + hot-CPU alerts"

# ── font ─────────────────────────────────────────────────────────────────────────
_section "JetBrainsMono Nerd Font"

_font_installed() {
    command -v fc-list >/dev/null 2>&1 && fc-list : family 2>/dev/null | grep -qi "JetBrainsMono Nerd"
}

did_font=false

if _font_installed; then
    _ok "already installed"
else
    _warn "JetBrainsMono Nerd Font not found"
    if _ask "Download and install it now?"; then
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

# The path is later embedded into Hyprland/matugen config as a quoted string.
# Quotes, backslashes, spaces, or newlines would break that quoting, so reject them.
case "$INSTALL_DIR" in
    *[\"\\]* | *"'"* | *\ *) _die "install path may not contain quotes, backslashes, or spaces: $INSTALL_DIR" ;;
esac
[ "$INSTALL_DIR" = "$(printf '%s' "$INSTALL_DIR" | tr -d '\n')" ] || _die "install path may not contain newlines"

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
    _die "$INSTALL_DIR exists but is not a git repo — pick a different path"
else
    spin_start "cloning..."
    if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 --single-branch --quiet "$REPO_URL" "$INSTALL_DIR"; then
        spin_stop; _die "git clone failed — check your connection"
    fi
    spin_stop; _ok "cloned to $INSTALL_DIR"
fi

ROOT="$INSTALL_DIR"
did_cava=false did_tmpl=false did_toml=false did_autostart=false

# Seed the generated theme from the bundled default so the shell themes
# correctly before matugen has run. matugen later overwrites this file.
if [ ! -f "$ROOT/config/MatugenTheme.qml" ] && [ -f "$ROOT/config/MatugenTheme.default.qml" ]; then
    cp "$ROOT/config/MatugenTheme.default.qml" "$ROOT/config/MatugenTheme.qml"
fi

# ── cava config ──────────────────────────────────────────────────────────────────
_section "cava config"
CAVA_SRC="$ROOT/assets/cava.conf"
CAVA_DST="$HOME/.config/cava/silere-shell.conf"
if _install_file "cava config" "$CAVA_SRC" "$CAVA_DST"; then did_cava=true; fi

# ── matugen template ─────────────────────────────────────────────────────────────
_section "matugen template"
TMPL_SRC="$ROOT/assets/matugen-theme.qml"
TMPL_DST="$HOME/.config/matugen/templates/silere-shell/Theme.qml"
if ! $has_matugen; then
    _skip "matugen not installed"
elif _install_file "matugen template" "$TMPL_SRC" "$TMPL_DST"; then
    did_tmpl=true
fi

# ── matugen config.toml ──────────────────────────────────────────────────────────
_section "matugen config.toml"
MATUGEN_CFG="$HOME/.config/matugen/config.toml"

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
input_path  = '~/.config/matugen/templates/silere-shell/Theme.qml'
output_path = '$ROOT/config/MatugenTheme.qml'
# silere-shell end
EOF
        _ok "entry added"; did_toml=true
    else
        _skip "skipped"
    fi
fi

# ── Hyprland autostart ───────────────────────────────────────────────────────────
_section "Hyprland autostart"
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
HYPR_LUA="$HOME/.config/hypr/hyprland.lua"
# Quickshell links jemalloc, which defaults to 4×nCPU arenas and no purge thread,
# so memory freed after a spike (menu close, wifi scan, notification burst) is
# retained rather than returned to the OS — RSS only ever climbs. Fewer arenas
# plus a background decay thread hand it back. ~50 MB reclaimed per spike here;
# drop the env to revert. Override by exporting MALLOC_CONF before launch.
MALLOC_TUNE="narenas:2,background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:1000"

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
LAUNCH_CMD="{ sleep 1; env MALLOC_CONF=$MALLOC_TUNE ${EGL_PIN}qs -p '$ROOT/shell.qml'; }"

_already_present() { grep -qF 'silere-shell begin' "$1" 2>/dev/null; }

if [ -f "$HYPR_LUA" ]; then
    LUA_EXEC_FILE=""
    for candidate in \
        "$HOME/.config/hypr/custom/execs.lua" \
        "$HOME/.config/hypr/hyprland/execs.lua" \
        "$HOME/.config/hypr/execs.lua"
    do
        [ -f "$candidate" ] && { LUA_EXEC_FILE="$candidate"; break; }
    done

    if [ -n "$LUA_EXEC_FILE" ] && _already_present "$LUA_EXEC_FILE"; then
        _ok "already present in $LUA_EXEC_FILE"
    elif [ -n "$LUA_EXEC_FILE" ]; then
        if _ask "Add autostart to ${LUA_EXEC_FILE##*/}?"; then
            _backup "$LUA_EXEC_FILE"
            cat >> "$LUA_EXEC_FILE" <<EOF

-- silere-shell begin
local _silere_lib = require("hyprland.lib")
hl.on("hyprland.start", function()
    _silere_lib.exec("$LAUNCH_CMD")
end)
-- silere-shell end
EOF
            _ok "added to $LUA_EXEC_FILE"; did_autostart=true
        else
            _skip "skipped — add manually: _silere_lib.exec(\"$LAUNCH_CMD\")"
        fi
    else
        _warn "Lua config detected but no execs.lua found"
        _warn "add manually: local h = require(\"hyprland.lib\"); h.exec(\"$LAUNCH_CMD\")"
    fi

elif [ -f "$HYPR_CONF" ]; then
    if _already_present "$HYPR_CONF"; then
        _ok "already present in $HYPR_CONF"
    else
        if _ask "Add exec-once to hyprland.conf?"; then
            _backup "$HYPR_CONF"
            cat >> "$HYPR_CONF" <<EOF

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

# ── summary ──────────────────────────────────────────────────────────────────────
printf "\n${BOLD}==> done${R}\n"
printf "    ${GREEN}ok${R}      installed at %s\n" "$ROOT"
$did_font      && printf "    ${GREEN}ok${R}      JetBrainsMono Nerd Font\n" || printf "    ${DIM}skip${R}    JetBrainsMono Nerd Font\n"
$did_cava      && printf "    ${GREEN}ok${R}      cava config\n"      || printf "    ${DIM}skip${R}    cava config\n"
$did_tmpl      && printf "    ${GREEN}ok${R}      matugen template\n" || printf "    ${DIM}skip${R}    matugen template\n"
$did_toml      && printf "    ${GREEN}ok${R}      matugen toml\n"     || printf "    ${DIM}skip${R}    matugen toml\n"
$did_autostart && printf "    ${GREEN}ok${R}      autostart\n"        || printf "    ${DIM}skip${R}    autostart\n"
if $has_qs; then
    printf "\n  restart Hyprland to launch silere\n"
else
    printf "\n  ${YELLOW}install Quickshell${R}, then restart Hyprland to launch silere\n"
fi
printf "  to uninstall: ${DIM}%s/scripts/uninstall.sh${R}\n\n" "$ROOT"
