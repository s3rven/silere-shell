#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

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
_info() { printf "  ${CYAN}::${R}  %s\n" "$*"; }

_section() { printf "\n${BOLD}==> %s${R}\n" "$1"; }

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

_ask() {
    local reply
    printf "  ${CYAN}::${R}  %s ${DIM}[y/N]${R} " "$1"
    read -r reply </dev/tty
    [[ "$reply" =~ ^[Yy] ]]
}

_restore_or_remove() {
    local file="$1"
    if [ -f "${file}.bak" ]; then
        mv "${file}.bak" "$file"
        _ok "restored from backup"
    else
        rm -f "$file"
        _ok "removed"
    fi
}

_remove_block() {
    local file="$1" begin="$2" end="$3" target tmp
    [ -f "$file" ] || return 1
    target="$file"
    if [ -L "$file" ]; then
        target="$(readlink -f -- "$file" 2>/dev/null)" || return 1
    fi

    # Only edit one exact, ordered marker pair. Missing, reversed, nested, or
    # duplicate markers are ambiguous and must leave the file byte-for-byte intact.
    if ! awk -v begin="$begin" -v end="$end" '
        $0 == begin { begins++; begin_line = NR }
        $0 == end   { ends++; end_line = NR }
        END { exit !(begins == 1 && ends == 1 && begin_line < end_line) }
    ' "$target"; then
        _warn "markers malformed or ambiguous in $(basename "$file") — left untouched"
        return 1
    fi

    tmp="$(mktemp "$(dirname -- "$target")/.silere-uninstall.XXXXXX")" || return 1
    if ! awk -v begin="$begin" -v end="$end" '
        $0 == begin { removing = 1; next }
        $0 == end   { removing = 0; next }
        !removing
    ' "$target" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    chmod --reference="$target" "$tmp" 2>/dev/null || true
    if ! mv -- "$tmp" "$target"; then
        rm -f "$tmp"
        return 1
    fi
}

_backup_restore_allowed() {
    [ ! -e "$1" ] && [ ! -L "$1" ] && [ -f "${1}.bak" ]
}

_append_hypr_config_targets() {
    local config="$1" dir
    [ -n "$config" ] || return 0
    AUTOSTART_FILES+=("$config")
    if [[ "$config" == *.lua ]]; then
        dir="$(dirname -- "$config")"
        AUTOSTART_FILES+=(
            "$dir/custom/execs.lua"
            "$dir/hyprland/execs.lua"
            "$dir/execs.lua"
        )
    fi
}

if [ "${SILERE_SCRIPT_LIB_ONLY:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

# ── header ───────────────────────────────────────────────────────────────────────
printf "\n${BOLD}:: silere-shell uninstaller${R}\n"

# ── legacy cava config ───────────────────────────────────────────────────────────
_section "legacy cava config"
CAVA_DST="$CONFIG_HOME/cava/silere-shell.conf"

if [ -f "$CAVA_DST" ] || [ -f "${CAVA_DST}.bak" ]; then
    if _ask "Remove $CAVA_DST?"; then
        _restore_or_remove "$CAVA_DST"
    else
        _skip "kept"
    fi
else
    _skip "not found"
fi

# ── matugen template ─────────────────────────────────────────────────────────────
_section "matugen template"
TMPL_DST="$CONFIG_HOME/matugen/templates/silere-shell/Theme.qml"

if [ -f "$TMPL_DST" ] || [ -f "${TMPL_DST}.bak" ]; then
    if _ask "Remove $TMPL_DST?"; then
        _restore_or_remove "$TMPL_DST"
        rmdir "$(dirname "$TMPL_DST")" 2>/dev/null || true
    else
        _skip "kept"
    fi
else
    _skip "not found"
fi

# ── matugen config.toml ──────────────────────────────────────────────────────────
_section "matugen config.toml"
MATUGEN_CFG="$CONFIG_HOME/matugen/config.toml"

if [ -f "$MATUGEN_CFG" ] && grep -qF '# silere-shell begin' "$MATUGEN_CFG"; then
    _info "will remove silere-shell block from $MATUGEN_CFG"
    if _ask "Remove silere-shell entry?"; then
        if _remove_block "$MATUGEN_CFG" '# silere-shell begin' '# silere-shell end'; then
            _ok "entry removed"
        fi
    else
        _skip "kept"
    fi
elif _backup_restore_allowed "$MATUGEN_CFG"; then
    _info "live config is missing; backup is available"
    if _ask "Restore $MATUGEN_CFG from backup?"; then
        mv "${MATUGEN_CFG}.bak" "$MATUGEN_CFG"
        _ok "restored"
    else
        _skip "kept"
    fi
elif [ -f "${MATUGEN_CFG}.bak" ]; then
    _skip "live config has no Silere block; retained backup without restoring it"
else
    _skip "no silere-shell entry found"
fi

# ── autostart ────────────────────────────────────────────────────────────────────
_section "autostart"

AUTOSTART_FILES=(
    "$CONFIG_HOME/hypr/custom/execs.lua"
    "$CONFIG_HOME/hypr/hyprland/execs.lua"
    "$CONFIG_HOME/hypr/execs.lua"
    "$CONFIG_HOME/hypr/hyprland.lua"
    "$CONFIG_HOME/hypr/hyprland.conf"
    "${SILERE_NIRI_CONFIG:-$CONFIG_HOME/niri/config.kdl}"
)
# Include custom layouts under the Hyprland config tree. The same session-aware
# resolver as the installer also covers external --config paths and their Lua
# execs.lua candidates.
if [ -d "$CONFIG_HOME/hypr" ]; then
    while IFS= read -r -d '' f; do AUTOSTART_FILES+=("$f"); done < <(
        grep -rlZF --include='*.conf' --include='*.lua' 'silere-shell begin' "$CONFIG_HOME/hypr" 2>/dev/null || true
    )
fi
ACTIVE_HYPR_CONFIG="$(bash "$SCRIPT_DIR/install.sh" --hypr-config-path 2>/dev/null || true)"
_append_hypr_config_targets "$ACTIVE_HYPR_CONFIG"

found_any=false
declare -A _seen_autostart=()
for f in "${AUTOSTART_FILES[@]}"; do
    [ -n "${_seen_autostart[$f]:-}" ] && continue
    _seen_autostart[$f]=1
    has_block=false
    has_backup=false
    grep -qF 'silere-shell begin' "$f" 2>/dev/null && has_block=true
    [ -f "${f}.bak" ] && has_backup=true

    if ! $has_block && ! $has_backup; then continue; fi
    found_any=true

    # Remove only our marked block when the live file still exists. Restoring
    # the install-time backup here would discard unrelated edits made later.
    if $has_block; then
        _info "silere-shell block found in $f"
        if _ask "Remove autostart block from $(basename "$f")?"; then
            if [[ "$f" == *.lua ]]; then
                _remove_block "$f" '-- silere-shell begin' '-- silere-shell end' && _ok "removed from $f"
            elif [[ "$f" == *.kdl ]]; then
                _remove_block "$f" '// silere-shell begin' '// silere-shell end' && _ok "removed from $f"
            else
                _remove_block "$f" '# silere-shell begin' '# silere-shell end' && _ok "removed from $f"
            fi
        else
            _skip "kept"
        fi
    elif _backup_restore_allowed "$f"; then
        _info "live config is missing; backup found for $f"
        if _ask "Restore $(basename "$f") from backup?"; then
            mv "${f}.bak" "$f"
            _ok "restored $f"
        else
            _skip "kept"
        fi
    elif $has_backup; then
        _skip "live file has no Silere block; retained backup without restoring it"
    fi
done

$found_any || _skip "no autostart entries found"

# ── auto-update timer ──────────────────────────────────────────────────────────────
_section "auto-update timer"
SYSTEMD_USER="$CONFIG_HOME/systemd/user"

if [ -f "$SYSTEMD_USER/silere-update.timer" ] || [ -f "$SYSTEMD_USER/silere-update.service" ]; then
    if _ask "Remove auto-update timer?"; then
        if command -v systemctl >/dev/null 2>&1; then
            systemctl --user disable --now silere-update.timer 2>/dev/null || true
        fi
        rm -f "$SYSTEMD_USER/silere-update.timer" "$SYSTEMD_USER/silere-update.service"
        command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload || true
        _ok "removed"
    else
        _skip "kept"
    fi
else
    _skip "not found"
fi

# ── done ─────────────────────────────────────────────────────────────────────────
printf "\n${BOLD}==> done${R}\n"
_warn "the repo directory was not deleted"
printf "  to fully remove silere: ${DIM}rm -rf %s${R}\n\n" "$(cd "$(dirname "$0")/.." && pwd)"
