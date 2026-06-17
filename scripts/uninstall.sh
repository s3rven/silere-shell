#!/usr/bin/env bash
set -euo pipefail

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
    local file="$1" begin="$2" end="$3"
    [ -f "$file" ] || return 1
    grep -qF "$begin" "$file" || return 1
    # Without a matching end marker, a sed range would delete from begin to EOF.
    if ! grep -qF "$end" "$file"; then
        _warn "end marker missing in $(basename "$file") — left untouched to avoid deleting to EOF"
        return 1
    fi
    sed -i "\|$(printf '%s' "$begin" | sed 's/[[\.*^$()+?{|]/\\&/g')|,\|$(printf '%s' "$end" | sed 's/[[\.*^$()+?{|]/\\&/g')|d" "$file"
    sed -i '/^$/N;/^\n$/d' "$file"
}

# ── header ───────────────────────────────────────────────────────────────────────
printf "\n${BOLD}:: silere-shell uninstaller${R}\n"

# ── cava config ──────────────────────────────────────────────────────────────────
_section "cava config"
CAVA_DST="$HOME/.config/cava/silere-shell.conf"

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
TMPL_DST="$HOME/.config/matugen/templates/silere-shell/Theme.qml"

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
MATUGEN_CFG="$HOME/.config/matugen/config.toml"

if [ -f "${MATUGEN_CFG}.bak" ]; then
    _info "backup available — will restore full file"
    if _ask "Restore $MATUGEN_CFG from backup?"; then
        mv "${MATUGEN_CFG}.bak" "$MATUGEN_CFG"
        _ok "restored"
    else
        _skip "kept"
    fi
elif [ -f "$MATUGEN_CFG" ] && grep -qF '# silere-shell begin' "$MATUGEN_CFG"; then
    _info "will remove silere-shell block from $MATUGEN_CFG"
    if _ask "Remove silere-shell entry?"; then
        if _remove_block "$MATUGEN_CFG" '# silere-shell begin' '# silere-shell end'; then
            _ok "entry removed"
        fi
    else
        _skip "kept"
    fi
else
    _skip "no silere-shell entry found"
fi

# ── Hyprland autostart ───────────────────────────────────────────────────────────
_section "Hyprland autostart"

AUTOSTART_FILES=(
    "$HOME/.config/hypr/custom/execs.lua"
    "$HOME/.config/hypr/hyprland/execs.lua"
    "$HOME/.config/hypr/execs.lua"
    "$HOME/.config/hypr/hyprland.conf"
)

found_any=false
for f in "${AUTOSTART_FILES[@]}"; do
    has_block=false
    has_backup=false
    grep -qF 'silere-shell begin' "$f" 2>/dev/null && has_block=true
    [ -f "${f}.bak" ] && has_backup=true

    if ! $has_block && ! $has_backup; then continue; fi
    found_any=true

    if $has_backup; then
        _info "backup found for $f"
        if _ask "Restore $(basename "$f") from backup?"; then
            mv "${f}.bak" "$f"
            _ok "restored $f"
        else
            _skip "kept"
        fi
    elif $has_block; then
        _info "silere-shell block found in $f"
        if _ask "Remove autostart block from $(basename "$f")?"; then
            if [[ "$f" == *.lua ]]; then
                _remove_block "$f" '-- silere-shell begin' '-- silere-shell end' && _ok "removed from $f"
            else
                _remove_block "$f" '# silere-shell begin' '# silere-shell end' && _ok "removed from $f"
            fi
        else
            _skip "kept"
        fi
    fi
done

$found_any || _skip "no autostart entries found"

# ── auto-update timer ──────────────────────────────────────────────────────────────
_section "auto-update timer"
SYSTEMD_USER="$HOME/.config/systemd/user"

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
