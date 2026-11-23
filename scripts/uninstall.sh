#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/xdg.sh"
source "$SCRIPT_DIR/lib/completions.sh"
CONFIG_HOME="$(_silere_xdg_home "${XDG_CONFIG_HOME:-}" .config)" || {
    printf 'silere-uninstall: HOME must be an absolute path\n' >&2
    exit 1
}
STATE_HOME="$(_silere_xdg_home "${XDG_STATE_HOME:-}" .local/state)" || {
    printf 'silere-uninstall: HOME must be an absolute path\n' >&2
    exit 1
}
INSTALL_RECEIPT="$STATE_HOME/silere-shell/install-receipt"

source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/instances.sh"

# same convention as install.sh's _assume_yes: one env var, no CLI flag
_assume_yes() { [ "${SILERE_ASSUME_YES:-0}" = "1" ]; }

_ask() {
    local reply
    if _assume_yes; then
        printf "  ${CYAN}::${R}  %s ${DIM}[y/N]${R} y\n" "$1"
        return 0
    fi
    _need_tty "interactive uninstall requires a TTY — run scripts/uninstall.sh from a terminal, or set SILERE_ASSUME_YES=1"
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

    if ! _silere_marker_pair_valid "$target" "$begin" "$end"; then
        _warn "markers malformed or ambiguous in $(basename "$file") — left untouched"
        return 1
    fi

    tmp="$(mktemp "$(dirname -- "$target")/.silere-uninstall.XXXXXX")" || return 1
    # the installer puts one blank line ahead of each block; take it back too, or every
    # install and uninstall leaves the file a line longer
    if ! awk -v begin="$begin" -v end="$end" '
        function flush() { while (blank > 0) { print ""; blank-- } }
        !removing && $0 == "" { blank++; next }
        $0 == begin { if (blank > 0) blank--; flush(); removing = 1; next }
        $0 == end   { removing = 0; next }
        removing    { next }
        { flush(); print }
        END { flush() }
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

_receipt_value() {
    local key="$1" value
    [ -r "$INSTALL_RECEIPT" ] && [ ! -L "$INSTALL_RECEIPT" ] || return 1
    value="$(sed -n "s/^$key=//p" "$INSTALL_RECEIPT")"
    [ -n "$value" ] || return 1
    printf '%s\n' "$value"
}

_receipt_path() {
    local encoded
    encoded="$(_receipt_value "$1")" || return 1
    [[ "$encoded" =~ ^(\\[0-7]{3})+$ ]] || return 1
    printf '%b' "$encoded"
}

if [ "${SILERE_SCRIPT_LIB_ONLY:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

# ── header ───────────────────────────────────────────────────────────────────────
printf "\n${BOLD}:: silere-shell uninstaller${R}\n"

RECEIPT_CHECKOUT="$(_receipt_path checkoutPath 2>/dev/null || true)"
RECEIPT_AUTOSTART="$(_receipt_path autostartPath 2>/dev/null || true)"
RECEIPT_KEYBIND="$(_receipt_path keybindPath 2>/dev/null || true)"
RECEIPT_LAYERS="$(_receipt_path layersPath 2>/dev/null || true)"
RECEIPT_MOTION="$(_receipt_path motionPath 2>/dev/null || true)"
RECEIPT_MODE="$(_receipt_value installMode 2>/dev/null || true)"
if [[ "$RECEIPT_MODE" =~ ^(managed|development)$ ]] && [ -n "$RECEIPT_CHECKOUT" ]; then
    _info "using $RECEIPT_MODE install receipt for $RECEIPT_CHECKOUT"
else
    RECEIPT_CHECKOUT=""
    RECEIPT_AUTOSTART=""
    RECEIPT_KEYBIND=""
    RECEIPT_LAYERS=""
    RECEIPT_MOTION=""
    _info "no usable install receipt; using defensive discovery"
fi

# ── maintenance command ──────────────────────────────────────────────────────────
_section "maintenance command"
CLI_LINK="$HOME/.local/bin/silere"
# the receipt names the checkout that made the link; this script may be running
# from a second one, so a match against either counts as ours
CLI_TARGETS=("$SCRIPT_DIR/silere")
[ -z "$RECEIPT_CHECKOUT" ] || CLI_TARGETS+=("$RECEIPT_CHECKOUT/scripts/silere")
CLI_RESOLVED="$(readlink -f -- "$CLI_LINK" 2>/dev/null || true)"
cli_owned=false
for target in "${CLI_TARGETS[@]}"; do
    if [ "$CLI_RESOLVED" = "$target" ]; then cli_owned=true; fi
done
if [ -L "$CLI_LINK" ] && $cli_owned; then
    if _ask "Remove $CLI_LINK?"; then
        rm -f -- "$CLI_LINK"
        _ok "removed owned command link"
    else
        _skip "kept"
    fi
elif [ -e "$CLI_LINK" ] || [ -L "$CLI_LINK" ]; then
    _skip "$CLI_LINK is not owned by this install"
else
    _skip "not found"
fi
for target in "${CLI_TARGETS[@]}"; do
    while IFS=$'\t' read -r comp_src comp_dest; do
        [ -L "$comp_dest" ] || continue
        [ "$(readlink -f -- "$comp_dest" 2>/dev/null || true)" = "$comp_src" ] || continue
        rm -f -- "$comp_dest"
        _ok "removed $comp_dest"
    done < <(_silere_completion_links "${target%/scripts/silere}" all)
done

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
TMPL_DST="$CONFIG_HOME/matugen/templates/silere-shell/Theme.json"
LEGACY_TMPL_DST="$CONFIG_HOME/matugen/templates/silere-shell/Theme.qml"

if [ -f "$TMPL_DST" ] || [ -f "${TMPL_DST}.bak" ]; then
    if _ask "Remove $TMPL_DST?"; then
        # a second install backs up Silere's own template; restoring that would leave it behind
        if _silere_same_text "${TMPL_DST}.bak" "$TMPL_DST" \
                || _silere_same_text "${TMPL_DST}.bak" "$SCRIPT_DIR/../assets/matugen-theme.json"; then
            rm -f -- "${TMPL_DST}.bak"
        fi
        _restore_or_remove "$TMPL_DST"
        rmdir "$(dirname "$TMPL_DST")" 2>/dev/null || true
    else
        _skip "kept"
    fi
else
    _skip "not found"
fi

if [ -f "$LEGACY_TMPL_DST" ] || [ -f "${LEGACY_TMPL_DST}.bak" ]; then
    if _ask "Remove legacy $LEGACY_TMPL_DST?"; then
        _restore_or_remove "$LEGACY_TMPL_DST"
        rmdir "$(dirname "$LEGACY_TMPL_DST")" 2>/dev/null || true
    else
        _skip "legacy template kept"
    fi
fi

# ── generated matugen palette ────────────────────────────────────────────────────
_section "matugen palette"
MATUGEN_PALETTE="$CONFIG_HOME/matugen/silere-shell.json"

if [ -f "$MATUGEN_PALETTE" ]; then
    if _ask "Remove $MATUGEN_PALETTE?"; then
        rm -f -- "$MATUGEN_PALETTE"
        _ok "removed"
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

ACTIVE_NIRI_CONFIG="$(bash "$SCRIPT_DIR/install.sh" --niri-config-path 2>/dev/null || true)"
AUTOSTART_FILES=(
    "$RECEIPT_AUTOSTART"
    "$RECEIPT_KEYBIND"
    "$RECEIPT_LAYERS"
    "$RECEIPT_MOTION"
    "$CONFIG_HOME/hypr/custom/execs.lua"
    "$CONFIG_HOME/hypr/hyprland/execs.lua"
    "$CONFIG_HOME/hypr/execs.lua"
    "$CONFIG_HOME/hypr/hyprland.lua"
    "$CONFIG_HOME/hypr/hyprland.conf"
    "$ACTIVE_NIRI_CONFIG"
)
# Include custom layouts under the Hyprland config tree. The same session-aware
# resolver as the installer also covers external --config paths and their Lua
# execs.lua candidates.
if [ -d "$CONFIG_HOME/hypr" ]; then
    while IFS= read -r -d '' f; do AUTOSTART_FILES+=("$f"); done < <(
        grep -rlZF --include='*.conf' --include='*.lua' \
            -e 'silere-shell begin' -e 'silere-shell keybind begin' -e 'silere-shell layers begin' \
            -e 'silere-shell motion begin' \
            "$CONFIG_HOME/hypr" 2>/dev/null || true
    )
fi
ACTIVE_HYPR_CONFIG="$(bash "$SCRIPT_DIR/install.sh" --hypr-config-path 2>/dev/null || true)"
_append_hypr_config_targets "$ACTIVE_HYPR_CONFIG"

found_any=false
declare -A _seen_autostart=()
for f in "${AUTOSTART_FILES[@]}"; do
    [ -n "$f" ] || continue
    [ -n "${_seen_autostart[$f]:-}" ] && continue
    _seen_autostart[$f]=1
    has_block=false
    has_keybind=false
    has_layers=false
    has_motion=false
    has_backup=false
    grep -qF 'silere-shell begin' "$f" 2>/dev/null && has_block=true
    grep -qF 'silere-shell keybind begin' "$f" 2>/dev/null && has_keybind=true
    grep -qF 'silere-shell layers begin' "$f" 2>/dev/null && has_layers=true
    grep -qF 'silere-shell motion begin' "$f" 2>/dev/null && has_motion=true
    [ -f "${f}.bak" ] && has_backup=true

    if ! $has_block && ! $has_keybind && ! $has_layers && ! $has_motion && ! $has_backup; then continue; fi
    found_any=true

    # Remove only our marked block when the live file still exists. Restoring
    # the install-time backup here would discard unrelated edits made later.
    if $has_block; then
        _info "silere-shell block found in $f"
        if _ask "Remove autostart block from $(basename "$f")?"; then
            if [[ "$f" == *.lua ]]; then
                _remove_block "$f" '-- silere-shell begin' '-- silere-shell end' && _ok "removed from $f"
            elif { [ -n "$ACTIVE_NIRI_CONFIG" ] &&
                    [ "$(readlink -m -- "$f")" = "$(readlink -m -- "$ACTIVE_NIRI_CONFIG")" ]; } \
                    || grep -qxF '// silere-shell begin' "$f" 2>/dev/null; then
                _remove_block "$f" '// silere-shell begin' '// silere-shell end' && _ok "removed from $f"
            else
                _remove_block "$f" '# silere-shell begin' '# silere-shell end' && _ok "removed from $f"
            fi
        else
            _skip "kept"
        fi
    fi

    if $has_keybind; then
        _info "silere-shell keybind found in $f"
        if _ask "Remove the menu keybind from $(basename "$f")?"; then
            if [[ "$f" == *.lua ]]; then
                _remove_block "$f" '-- silere-shell keybind begin' \
                    '-- silere-shell keybind end' && _ok "removed the keybind from $f"
            else
                _remove_block "$f" '# silere-shell keybind begin' \
                    '# silere-shell keybind end' && _ok "removed the keybind from $f"
            fi
        else
            _skip "kept"
        fi
    fi

    if $has_layers; then
        _info "silere-shell layer rule found in $f"
        if _ask "Remove the rule that turns off Hyprland's fade for Silere's popups from $(basename "$f")?"; then
            if [[ "$f" == *.lua ]]; then
                _remove_block "$f" '-- silere-shell layers begin' \
                    '-- silere-shell layers end' && _ok "removed the layer rule from $f"
            else
                _remove_block "$f" '# silere-shell layers begin' \
                    '# silere-shell layers end' && _ok "removed the layer rule from $f"
            fi
        else
            _skip "kept"
        fi
    fi

    if $has_motion; then
        _info "silere-shell window motion found in $f"
        if _ask "Remove Silere's window motion from $(basename "$f")? Hyprland's own animations come back"; then
            _remove_block "$f" '-- silere-shell motion begin' \
                '-- silere-shell motion end' && _ok "removed Silere's window motion from $f"
        else
            _skip "kept"
        fi
    fi

    if ! $has_block && ! $has_keybind && ! $has_layers; then
        if _backup_restore_allowed "$f"; then
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
    fi
done

$found_any || _skip "no autostart entries found"

# ── update-check timer ─────────────────────────────────────────────────────────────
_section "update-check timer"
SYSTEMD_USER="$CONFIG_HOME/systemd/user"

if [ -f "$SYSTEMD_USER/silere-update.timer" ] || [ -f "$SYSTEMD_USER/silere-update.service" ]; then
    if _ask "Remove update-check timer?"; then
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

# only remove the service this installer generated; an externally managed unit belongs to its owner
if [ -f "$SYSTEMD_USER/silere-shell.service" ] \
    && grep -qx '# generated by silere-shell' "$SYSTEMD_USER/silere-shell.service"; then
    _section "supervised shell"
    if _ask "Stop and remove the supervised shell service?"; then
        bash "$SCRIPT_DIR/service.sh" remove || _warn "service was left in place"
    fi
fi

# silere use points a unit it did not write at this checkout with a drop-in; left behind,
# that unit keeps starting the checkout this uninstall is leaving
USE_DROPIN="$SYSTEMD_USER/silere-shell.service.d/silere-use.conf"
if [ -f "$USE_DROPIN" ] && [ ! -L "$USE_DROPIN" ] && grep -qx '# generated by silere use' "$USE_DROPIN"; then
    use_root="$(sed -n 's|^ConditionPathExists=\(..*\)/shell\.qml$|\1|p' "$USE_DROPIN" | head -n 1)"
    use_root="${use_root//%%/%}"
    use_owned=false
    for target in "${CLI_TARGETS[@]}"; do
        if [ -n "$use_root" ] \
                && [ "$(readlink -f -- "$use_root")" = "$(readlink -f -- "${target%/scripts/silere}")" ]; then
            use_owned=true
        fi
    done
    if $use_owned; then
        _section "service override"
        if _ask "Stop silere-shell.service from starting this checkout?"; then
            rm -f -- "$USE_DROPIN"
            rmdir -- "${USE_DROPIN%/*}" 2>/dev/null || true
            command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload 2>/dev/null || true
            _ok "removed the silere use drop-in; the unit runs its own command again"
        else
            _skip "kept"
        fi
    fi
fi

# ── done ─────────────────────────────────────────────────────────────────────────
CHECKOUT="$(cd "$SCRIPT_DIR/.." && pwd)"
printf "\n${BOLD}==> done${R}\n"
_info "kept the checkout, settings, notification history and font, in case you come back"
printf "    checkout  ${DIM}%s${R}\n" "$CHECKOUT"
[ "$CONFIG_HOME/silere-shell" = "$CHECKOUT" ] \
    || printf "    settings  ${DIM}%s${R}\n" "$CONFIG_HOME/silere-shell"
printf "    history   ${DIM}%s${R}\n" "$STATE_HOME/silere-shell"
# nothing above touches the shell on screen, which reads as the uninstall having failed
if command -v qs >/dev/null 2>&1 && _silere_shell_running "$CHECKOUT/shell.qml"; then
    printf "\n  Silere keeps running until you log out, or stop it now: ${DIM}%s/scripts/silere stop${R}\n" "$CHECKOUT"
fi
printf '\n'
