#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

REPO_URL="https://github.com/s3rven/silere-shell.git"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/xdg.sh"
CONFIG_HOME="$(_silere_xdg_home "${XDG_CONFIG_HOME:-}" .config)" || {
    printf 'silere: HOME must be an absolute path\n' >&2
    exit 1
}
STATE_HOME="$(_silere_xdg_home "${XDG_STATE_HOME:-}" .local/state)" || {
    printf 'silere: HOME must be an absolute path\n' >&2
    exit 1
}
DEFAULT_DIR="$CONFIG_HOME/silere-shell"

source "$SCRIPT_DIR/lib/ui.sh"
TTY_HINT="interactive install requires a TTY — clone the repo and run scripts/install.sh from a terminal"

_reject_unsafe_path() {
    if printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        _die "install path may not contain control characters or newlines: $1"
    fi
}

_normalized_install_path() {
    local path source_root home_root config_root
    _reject_unsafe_path "$1"
    path="$(readlink -m -- "$1" 2>/dev/null)" || _die "could not resolve install path: $1"
    home_root="$(readlink -m -- "$HOME" 2>/dev/null)" || _die "could not resolve home directory"
    config_root="$(readlink -m -- "$CONFIG_HOME" 2>/dev/null)" || _die "could not resolve config directory"
    case "$path" in
        /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/media|/mnt|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var|"$home_root"|"$config_root")
            _die "refusing unsafe install path: $path"
            ;;
    esac
    source_root="$(readlink -m -- "$SCRIPT_DIR/..")"
    if [ "$path" != "$source_root" ]; then
        case "$source_root/" in
            "$path/"*) _die "install path may not contain the running installer: $path" ;;
        esac
    fi
    printf '%s\n' "$path"
}

_move_aside_path() {
    local source="$1" stamp candidate suffix=0
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    candidate="${source}.silere-backup-$stamp"
    while [ -e "$candidate" ] || [ -L "$candidate" ]; do
        suffix=$((suffix + 1))
        candidate="${source}.silere-backup-$stamp-$suffix"
    done
    mv -- "$source" "$candidate" || return 1
    printf '%s\n' "$candidate"
}

_secure_fresh_default_install() {
    [ "$1" = "$DEFAULT_DIR" ] || return 0
    chmod 0700 "$1" || _warn "could not restrict permissions on $1"
}

_is_silere_checkout() {
    local path="$1"
    [ -f "$path/shell.qml" ] \
        && [ -f "$path/services/qmldir" ] \
        && [ -f "$path/scripts/update.sh" ]
}

_matugen_table_present() {
    [ -f "$1" ] && grep -Eq '^[[:space:]]*\[templates\.silere-shell\][[:space:]]*(#.*)?$' "$1"
}

readonly -a SILERE_FONT_FILES=(
    JetBrainsMonoNerdFont-Regular.ttf
    JetBrainsMonoNerdFont-Medium.ttf
    JetBrainsMonoNerdFont-SemiBold.ttf
    JetBrainsMonoNerdFont-Bold.ttf
)

_extract_silere_fonts() {
    local archive="$1" destination="$2"
    tar -xJ -f "$archive" -C "$destination" \
        --no-same-owner --no-same-permissions --no-overwrite-dir \
        --wildcards --no-anchored "${SILERE_FONT_FILES[@]}"
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

# A write-ahead install ledger owns rollback for this invocation and becomes the
# durable receipt when the transaction commits. Paths are octal-escaped so one
# record remains one line even under an unusual but valid home directory.
TXN_ACTIVE=0
TXN_COMMITTED=0
TXN_DIR=""
TXN_JOURNAL=""
INSTALL_STATE_DIR="$STATE_HOME/silere-shell"
INSTALL_RECEIPT="$INSTALL_STATE_DIR/install-receipt"
declare -A _TXN_FILES=()
TXN_FILE_COUNT=0
install_mode=development
receipt_compositor=unknown
receipt_autostart=""
receipt_keybind=""

_txn_escape() { _shell_printf_bytes "$1"; }
_txn_unescape() { printf '%b' "$1"; }

_txn_append() {
    [ "$TXN_ACTIVE" = 1 ] || return 0
    printf '%s\n' "$*" >> "$TXN_JOURNAL"
}

# every transaction directory holds pre-images of the files that run touched, so
# the ledger would otherwise grow with each install
_txn_prune_old() {
    local dir="$INSTALL_STATE_DIR/install-transactions" old
    [ -d "$dir" ] && [ ! -L "$dir" ] || return 0
    while IFS= read -r old; do
        [[ "$old" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9]+(-[0-9]+)?$ ]] || continue
        [ -L "${dir:?}/$old" ] || rm -rf -- "${dir:?}/$old"
    done < <(ls -1t "$dir" 2>/dev/null | tail -n +6)
}

_txn_begin() {
    [ "${_dry_run:-0}" = 0 ] || return 0
    local id base suffix=0
    id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
    [ ! -L "$INSTALL_STATE_DIR" ] || _die "refusing symlinked install state directory"
    (umask 077 && mkdir -p "$INSTALL_STATE_DIR/install-transactions") \
        || _die "could not create install transaction state"
    chmod 0700 "$INSTALL_STATE_DIR" "$INSTALL_STATE_DIR/install-transactions" \
        || _die "could not secure install transaction state"
    base="$id"
    while [ -e "$INSTALL_STATE_DIR/install-transactions/$id" ]; do
        suffix=$((suffix + 1))
        id="$base-$suffix"
    done
    TXN_DIR="$INSTALL_STATE_DIR/install-transactions/$id"
    (umask 077 && mkdir "$TXN_DIR") || _die "could not start install transaction"
    _txn_prune_old
    TXN_JOURNAL="$TXN_DIR/journal"
    (umask 077 && printf 'version=1\nstatus=active\ntransaction=%s\n' "$id" \
        > "$TXN_JOURNAL") || _die "could not write install transaction"
    chmod 0600 "$TXN_JOURNAL"
    _TXN_FILES=()
    TXN_FILE_COUNT=0
    TXN_COMMITTED=0
    TXN_ACTIVE=1
}

_txn_before_file() {
    local requested="$1" path="$1" key backup existed=0
    [ "$TXN_ACTIVE" = 1 ] || return 0
    if [ -L "$path" ]; then
        path="$(readlink -f -- "$path" 2>/dev/null)" || return 1
    fi
    [ -n "$path" ] || return 1
    key="$path"
    [ -z "${_TXN_FILES[$key]:-}" ] || return 0
    _TXN_FILES[$key]=1
    TXN_FILE_COUNT=$((TXN_FILE_COUNT + 1))
    backup="file-$TXN_FILE_COUNT"
    if [ -e "$path" ] || [ -L "$path" ]; then
        [ ! -d "$path" ] || return 1
        cp -a --no-dereference -- "$path" "$TXN_DIR/$backup" || return 1
        existed=1
    else
        backup="-"
    fi
    _txn_append $'file\t'"$(_txn_escape "$path")"$'\t'"$existed"$'\t'"$backup"$'\t'"$(_txn_escape "$requested")"
}

_txn_before_mode() {
    local path="$1" mode
    [ "$TXN_ACTIVE" = 1 ] || return 0
    [ -e "$path" ] || return 0
    mode="$(stat -c '%a' -- "$path" 2>/dev/null)" || return 1
    _txn_append $'mode\t'"$(_txn_escape "$path")"$'\t'"$mode"
}

_txn_tree_created() {
    [ "$TXN_ACTIVE" = 1 ] || return 0
    _txn_append $'tree-created\t'"$(_txn_escape "$1")"
}

_txn_tree_replaced() {
    [ "$TXN_ACTIVE" = 1 ] || return 0
    _txn_append $'tree-replaced\t'"$(_txn_escape "$1")"$'\t'"$(_txn_escape "$2")"
}

_txn_timer_state() {
    local enabled=0
    [ "$TXN_ACTIVE" = 1 ] || return 0
    command -v systemctl >/dev/null 2>&1 \
        && systemctl --user is-enabled --quiet silere-update.timer 2>/dev/null \
        && enabled=1
    _txn_append $'timer\t'"$enabled"
}

_txn_remove_created_tree() {
    local path="$1"
    # Only normalized installer targets recorded by this process reach here.
    [ -n "$path" ] && [ "$path" != / ] && [ "$path" != "$HOME" ] \
        && [ "$path" != "$CONFIG_HOME" ] || return 1
    rm -rf -- "$path"
}

_txn_rollback() {
    local -a records=()
    local i kind a b c requested path backup
    [ "$TXN_ACTIVE" = 1 ] && [ "$TXN_COMMITTED" = 0 ] || return 0
    mapfile -t records < "$TXN_JOURNAL" || return 1
    _warn "install failed; rolling back transaction ${TXN_DIR##*/}"
    for ((i=${#records[@]} - 1; i >= 0; i--)); do
        IFS=$'\t' read -r kind a b c requested <<< "${records[i]}"
        case "$kind" in
            file)
                path="$(_txn_unescape "$a")"
                if [ "$b" = 1 ]; then
                    backup="$TXN_DIR/$c"
                    mkdir -p "${path%/*}" || continue
                    rm -f -- "$path"
                    cp -a --no-dereference -- "$backup" "$path" || true
                else
                    [ -d "$path" ] || rm -f -- "$path"
                fi
                ;;
            mode)
                path="$(_txn_unescape "$a")"
                [ ! -e "$path" ] || chmod "$b" -- "$path" 2>/dev/null || true
                ;;
            tree-created)
                _txn_remove_created_tree "$(_txn_unescape "$a")" || true
                ;;
            tree-replaced)
                path="$(_txn_unescape "$a")"
                backup="$(_txn_unescape "$b")"
                # a caller may already have restored the backup by hand before dying;
                # a missing backup here means path already holds the right content
                if [ -e "$backup" ]; then
                    _txn_remove_created_tree "$path" || true
                    mv -- "$backup" "$path" || true
                fi
                ;;
            timer)
                if [ "$a" = 0 ] && command -v systemctl >/dev/null 2>&1; then
                    systemctl --user disable --now silere-update.timer >/dev/null 2>&1 || true
                    systemctl --user daemon-reload >/dev/null 2>&1 || true
                fi
                ;;
        esac
    done
    printf 'status=rolled-back\n' >> "$TXN_JOURNAL"
    TXN_ACTIVE=0
}

_txn_commit() {
    local tmp
    [ "$TXN_ACTIVE" = 1 ] || return 0
    tmp="$(mktemp "$INSTALL_STATE_DIR/.install-receipt.XXXXXX")" || return 1
    chmod 0600 "$tmp" || { rm -f -- "$tmp"; return 1; }
    if ! printf '%s\n' \
            version=1 \
            "transaction=${TXN_DIR##*/}" \
            "installMode=$install_mode" \
            "checkoutPath=$(_txn_escape "$ROOT")" \
            "compositor=$receipt_compositor" \
            "autostartPath=$(_txn_escape "$receipt_autostart")" \
            "keybindPath=$(_txn_escape "$receipt_keybind")" \
            "fontInstalled=$($did_font && printf 1 || printf 0)" \
            "cliInstalled=$($did_cli && printf 1 || printf 0)" \
            "matugenTemplate=$($did_tmpl && printf 1 || printf 0)" \
            "matugenConfig=$($did_toml && printf 1 || printf 0)" \
            "updateTimer=$($did_update && printf 1 || printf 0)" \
            "journal=$(_txn_escape "$TXN_JOURNAL")" > "$tmp" \
            || ! mv -- "$tmp" "$INSTALL_RECEIPT"; then
        rm -f -- "$tmp"
        return 1
    fi
    printf 'status=committed\n' >> "$TXN_JOURNAL" || return 1
    TXN_COMMITTED=1
    return 0
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

# Resolve the compositor process that owns this shell session. Prefer an ancestor
# (Quickshell and terminals are normally descendants of their compositor), then
# accept a same-user process only when it is the sole candidate. Never guess
# between multiple sessions.
_PROC_ROOT="${SILERE_PROC_ROOT:-/proc}"

_proc_ppid() {
    local pid="$1" stat rest
    stat="$(cat "$_PROC_ROOT/$pid/stat" 2>/dev/null)" || return 1
    rest="${stat##*) }"
    [ "$rest" != "$stat" ] || return 1
    rest="${rest#* }"
    printf '%s\n' "${rest%% *}"
}

_same_user_process() {
    [ "$(stat -c '%u' "$_PROC_ROOT/$1" 2>/dev/null)" = "$(id -u)" ]
}

_find_compositor_pid() {
    local want="$1" pid="${SILERE_PARENT_PID:-$PPID}" parent comm candidate="" count=0

    while [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" -gt 1 ]; do
        if _same_user_process "$pid"; then
            comm="$(cat "$_PROC_ROOT/$pid/comm" 2>/dev/null || true)"
            if [ "$comm" = "$want" ]; then
                printf '%s\n' "$pid"
                return 0
            fi
        fi
        parent="$(_proc_ppid "$pid" 2>/dev/null || true)"
        [[ "$parent" =~ ^[0-9]+$ ]] && [ "$parent" != "$pid" ] || break
        pid="$parent"
    done

    for comm in "$_PROC_ROOT"/[0-9]*/comm; do
        [ -r "$comm" ] || continue
        [ "$(cat "$comm" 2>/dev/null)" = "$want" ] || continue
        pid="${comm%/comm}"
        pid="${pid##*/}"
        _same_user_process "$pid" || continue
        candidate="$pid"
        count=$((count + 1))
    done
    [ "$count" -eq 1 ] || return 1
    printf '%s\n' "$candidate"
}

_normalize_config_path() {
    local path="$1" base="$2"
    path="${path/#\~/$HOME}"
    case "$path" in
        /*) ;;
        *) path="$base/$path" ;;
    esac
    readlink -m -- "$path" 2>/dev/null || printf '%s\n' "$path"
}

_compositor_config_for_pid() {
    local pid="$1" cwd raw="" i
    local -a args=()
    mapfile -d '' -t args 2>/dev/null < "$_PROC_ROOT/$pid/cmdline" || return 1
    for ((i = 0; i < ${#args[@]}; i++)); do
        if [ "${args[i]}" = "--config" ] || [ "${args[i]}" = "-c" ]; then
            ((i + 1 < ${#args[@]})) || return 1
            raw="${args[i + 1]}"
            break
        fi
    done
    [ -n "$raw" ] || return 1
    cwd="$(readlink -f -- "$_PROC_ROOT/$pid/cwd" 2>/dev/null)" || return 1
    _normalize_config_path "$raw" "$cwd"
}

_hypr_config_path() {
    local config pid
    if [ -n "${SILERE_HYPR_CONFIG:-}" ]; then
        _normalize_config_path "$SILERE_HYPR_CONFIG" "$PWD"
        return
    fi
    pid="$(_find_compositor_pid Hyprland 2>/dev/null || true)"
    if [ -n "$pid" ]; then
        config="$(_compositor_config_for_pid "$pid" 2>/dev/null || true)"
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

_niri_config_path() {
    local config pid
    if [ -n "${SILERE_NIRI_CONFIG:-}" ]; then
        _normalize_config_path "$SILERE_NIRI_CONFIG" "$PWD"
        return
    fi
    # a running niri's --config beats NIRI_CONFIG, matching niri's own precedence
    pid="$(_find_compositor_pid niri 2>/dev/null || true)"
    if [ -n "$pid" ]; then
        config="$(_compositor_config_for_pid "$pid" 2>/dev/null || true)"
        if [ -n "$config" ]; then
            printf '%s\n' "$config"
            return
        fi
    fi
    _normalize_config_path "${NIRI_CONFIG:-$CONFIG_HOME/niri/config.kdl}" "$PWD"
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
    --niri-config-path)
        _niri_config_path
        exit 0
        ;;
esac
_answered_yes() {
    [[ "$1" =~ ^[Yy] ]]
}

_replace_matugen_block() {
    local file="$1" input="$2" output="$3" target tmp
    [ -f "$file" ] || return 1
    target="$file"
    if [ -L "$file" ]; then
        target="$(readlink -f -- "$file" 2>/dev/null)" || return 1
    fi
    if ! _silere_marker_pair_valid "$target" "# silere-shell begin" "# silere-shell end"; then
        _warn "silere-shell markers are malformed or ambiguous — left config.toml unchanged"
        return 1
    fi
    tmp="$(mktemp "$(dirname -- "$target")/.silere-matugen.XXXXXX")" || return 1
    if ! awk '
        $0 == "# silere-shell begin" { removing = 1; next }
        $0 == "# silere-shell end"   { removing = 0; next }
        !removing
    ' "$target" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    printf '\n# silere-shell begin\n[templates.silere-shell]\ninput_path  = %s\noutput_path = %s\n# silere-shell end\n' \
        "$input" "$output" >> "$tmp"
    chmod --reference="$target" "$tmp" 2>/dev/null || true
    if ! mv -- "$tmp" "$target"; then
        rm -f "$tmp"
        return 1
    fi
}

_owned_block_contains() {
    local file="$1" begin="$2" end="$3" needle="$4"
    [ -f "$file" ] || return 1
    _silere_marker_pair_valid "$file" "$begin" "$end" || return 1
    awk -v begin="$begin" -v end="$end" -v needle="$needle" '
        $0 == begin { inside = 1; next }
        $0 == end   { inside = 0; next }
        inside && index($0, needle) { found = 1 }
        END { exit !found }
    ' "$file"
}

_bind_taken() {
    local file="$1"
    [ -f "$file" ] || return 1
    awk -v mods="$MENU_BIND_MODS" -v key="$MENU_BIND_KEY" '
        function norm(s) { gsub(/[ \t]/, "", s); return tolower(s) }
        {
            line = $0
            sub(/#.*/, "", line)
            if (line !~ /^[ \t]*bind[a-z]*[ \t]*=/) next
            sub(/^[ \t]*bind[a-z]*[ \t]*=[ \t]*/, "", line)
            n = split(line, f, ",")
            if (n < 2) next
            if (norm(f[2]) != norm(key)) next
            # $mainMod and friends cannot be compared literally, so a matching key
            # behind any variable modifier counts as taken
            if (norm(f[1]) == norm(mods) || f[1] ~ /\$/) found = 1
        }
        END { exit !found }
    ' "$file"
}

_menu_bind_taken() {
    local dir f
    _bind_taken "$HYPR_CONFIG" && return 0
    dir="$(dirname -- "$HYPR_CONFIG")"
    [ -d "$dir" ] || return 1
    while IFS= read -r -d '' f; do
        _bind_taken "$f" && return 0
    done < <(find "$dir" -type f -name '*.conf' -print0 2>/dev/null)
    return 1
}

_replace_owned_block() {
    local file="$1" begin="$2" end="$3" body="$4" target tmp line removing=false
    [ -f "$file" ] || return 1
    target="$file"
    if [ -L "$file" ]; then
        target="$(readlink -f -- "$file" 2>/dev/null)" || return 1
    fi
    if ! _silere_marker_pair_valid "$target" "$begin" "$end"; then
        _warn "silere-shell markers are malformed or ambiguous in $file — left untouched"
        return 1
    fi
    tmp="$(mktemp "$(dirname -- "$target")/.silere-autostart.XXXXXX")" || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$line" = "$begin" ]; then
            printf '%s\n%s\n%s\n' "$begin" "$body" "$end"
            removing=true
        elif $removing; then
            [ "$line" = "$end" ] && removing=false
        else
            printf '%s\n' "$line"
        fi
    done < "$target" > "$tmp"
    chmod --reference="$target" "$tmp" 2>/dev/null || true
    if ! mv -- "$tmp" "$target"; then
        rm -f -- "$tmp"
        return 1
    fi
}

# Always read from /dev/tty so curl | bash works
# an assumed yes never overrides a refusal: the [y/N] prompts guard an unsupported
# compositor and an opt-in timer, so they stay no
# a dry run reports the plan the assumed-yes answers would produce, so the two
# share one answer path and only the writes are gated
_dry_run=0
_dry() { [ "$_dry_run" = "1" ]; }
# shellcheck disable=SC2059
_would() { printf "    ${CYAN}dry${R}     %s\n" "$*"; }
_assume_yes() { [ "${SILERE_ASSUME_YES:-0}" = "1" ] || _dry; }

_ask() {
    local reply
    if _assume_yes; then
        printf "  ${CYAN}::${R}  %s ${DIM}[Y/n]${R} yes\n" "$1"
        return 0
    fi
    _need_tty "$TTY_HINT"
    printf "  ${CYAN}::${R}  %s ${DIM}[Y/n]${R} " "$1"
    read -r reply </dev/tty
    [[ ! "$reply" =~ ^[Nn] ]]
}

_ask_no() {
    local reply
    if _assume_yes; then
        printf "  ${CYAN}::${R}  %s ${DIM}[y/N]${R} no\n" "$1"
        return 1
    fi
    _need_tty "$TTY_HINT"
    printf "  ${CYAN}::${R}  %s ${DIM}[y/N]${R} " "$1"
    read -r reply </dev/tty
    _answered_yes "$reply"
}

_ask_path() {
    local reply
    if _assume_yes; then
        printf '%s' "$DEFAULT_DIR"
        return 0
    fi
    _need_tty "$TTY_HINT"
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

if [ "${SILERE_SCRIPT_LIB_ONLY:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

_usage() {
    cat <<'EOF'
Usage:
  bash scripts/install.sh        Install Silere Shell (interactive)
  bash scripts/install.sh --help Show this message

  bash scripts/install.sh --dry-run
        Report every file the install would create or edit, and the autostart
        and keybind lines it would add, then exit without writing anything.
        Answers the prompts the way SILERE_ASSUME_YES=1 does, so it shows the
        fullest plan.

  bash scripts/install.sh --check
        Run focused, read-only installation diagnostics. This does not install,
        update, or edit anything. The installed `silere doctor` command runs the
        same check.

  bash scripts/install.sh --repair-matugen
        Rewire Matugen without reinstalling. Writes only Silere's own template
        and its marked block in config.toml, and refuses an entry it does not
        own. This is what Settings > Maintenance runs.

Silere runs on Hyprland and niri only. The installer asks before it writes
anything and backs up every file it edits.

Environment:
  SILERE_HYPR_CONFIG   Hyprland config to wire autostart into
  SILERE_NIRI_CONFIG   niri config to wire autostart into
  SILERE_MENU_BIND_MODS
                       Modifiers for the menu keybind, default SUPER
  SILERE_MENU_BIND_KEY Key for the menu keybind, default slash
  SILERE_ASSUME_YES=1  Answer the [Y/n] prompts yes and install to the default
                       path, for dotfiles bootstraps and containers. Files are
                       still backed up before editing, and the [y/N] prompts
                       still answer no, so an unsupported compositor still stops
                       the install.
EOF
}

# Anything the helper case above recognises has already exited, so a surviving
# argument is a typo. Left unhandled it used to start a real install, and
# --help is the first thing a careful reader types before running a script.
_repair_matugen=0
_check_only=0
case "${1:-}" in
    "") ;;
    -h|--help) _usage; exit 0 ;;
    --repair-matugen) _repair_matugen=1 ;;
    --dry-run) _dry_run=1 ;;
    --check) _check_only=1 ;;
    *)
        _err "unknown option: $1"
        _usage >&2
        exit 2
        ;;
esac
# the case above only reads $1, so a trailing typo would otherwise be dropped
if [ "$#" -gt 1 ]; then
    _err "unexpected argument: $2"
    _usage >&2
    exit 2
fi

if [ "$_check_only" = "1" ]; then
    exec bash "$SCRIPT_DIR/doctor.sh"
fi

_backup() {
    local file="$1"
    if [ -f "$file" ]; then
        if _dry && [ ! -f "${file}.bak" ]; then
            _would "back up $file → ${file##*/}.bak"
            return 0
        fi
        _txn_before_file "$file" || _die "could not journal $file"
        if [ ! -f "${file}.bak" ]; then
            _txn_before_file "${file}.bak" || _die "could not journal ${file}.bak"
            cp -p "$file" "${file}.bak"
            _skip "backed up existing → ${file##*/}.bak"
        fi
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
        if _dry; then _would "overwrite $dst"; return 0; fi
        cp "$src" "$dst" || _die "could not write $dst"
        _ok "updated"
    else
        _ask "Install $label?" || { _skip "skipped"; return 1; }
        if _dry; then _would "create $dst"; return 0; fi
        _txn_before_file "$dst" || _die "could not journal $dst"
        mkdir -p "${dst%/*}" || _die "could not create ${dst%/*}"
        cp "$src" "$dst" || _die "could not write $dst"
        _ok "installed"
    fi
}

# ── matugen repair ───────────────────────────────────────────────────────────────
# Reached from the shell's health card, so it cannot prompt. It takes only the
# steps the installer would take unprompted and refuses the same configs the
# installer refuses, which keeps one set of rules for one job.
if [ "$_repair_matugen" = "1" ]; then
    command -v matugen >/dev/null 2>&1 || _die "matugen is not installed"
    ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
    MATUGEN_CFG="$CONFIG_HOME/matugen/config.toml"
    MATUGEN_OUTPUT_TOML="$(_toml_basic_string "$CONFIG_HOME/matugen/silere-shell.json")"
    MATUGEN_INPUT_TOML="$(_toml_basic_string "$CONFIG_HOME/matugen/templates/silere-shell/Theme.json")"
    TMPL_SRC="$ROOT/assets/matugen-theme.json"
    TMPL_DST="$CONFIG_HOME/matugen/templates/silere-shell/Theme.json"

    [ -r "$TMPL_SRC" ] || _die "template missing at $TMPL_SRC"
    mkdir -p "${TMPL_DST%/*}" || _die "could not create ${TMPL_DST%/*}"
    _backup "$TMPL_DST"
    cp "$TMPL_SRC" "$TMPL_DST" || _die "could not write $TMPL_DST"
    _ok "template written"

    if [ -f "$MATUGEN_CFG" ] && grep -q '# silere-shell begin' "$MATUGEN_CFG"; then
        if grep -qF "input_path  = $MATUGEN_INPUT_TOML" "$MATUGEN_CFG" \
                && grep -qF "output_path = $MATUGEN_OUTPUT_TOML" "$MATUGEN_CFG"; then
            _ok "entry already correct"
        else
            _backup "$MATUGEN_CFG"
            _replace_matugen_block "$MATUGEN_CFG" "$MATUGEN_INPUT_TOML" "$MATUGEN_OUTPUT_TOML" \
                || _die "could not update $MATUGEN_CFG"
            _ok "entry updated"
        fi
    elif _matugen_table_present "$MATUGEN_CFG"; then
        _die "an unmanaged [templates.silere-shell] entry exists; edit $MATUGEN_CFG by hand"
    else
        mkdir -p "${MATUGEN_CFG%/*}" || _die "could not create ${MATUGEN_CFG%/*}"
        if [ -f "$MATUGEN_CFG" ]; then
            _backup "$MATUGEN_CFG"
        else
            printf '[config]\nversion_check = false\n' > "$MATUGEN_CFG"
        fi
        cat >> "$MATUGEN_CFG" <<EOF

# silere-shell begin
[templates.silere-shell]
input_path  = $MATUGEN_INPUT_TOML
output_path = $MATUGEN_OUTPUT_TOML
# silere-shell end
EOF
        _ok "entry added"
    fi
    # matugen writes the palette on its next run, so colours follow the next wallpaper change
    printf 'repaired\n'
    exit 0
fi

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
    local code=$?
    spin_stop
    [ -n "$font_tmp" ] && rm -f "$font_tmp"
    if [ "$code" -ne 0 ]; then _txn_rollback || true; fi
    return "$code"
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
    qs_version="$(_silere_quickshell_version || true)"
    if [ -n "$qs_version" ] && ! _silere_version_at_least "$qs_version" "$SILERE_MIN_QUICKSHELL"; then
        _warn "quickshell $qs_version is older than the required $SILERE_MIN_QUICKSHELL"
    else
        _ok "quickshell${qs_version:+ $qs_version}"
    fi
else
    _warn "quickshell not found — install it before launching silere"
    has_qs=false
fi

qs_modules_ok=true
if $has_qs; then
    for module in "${SILERE_REQUIRED_QML_MODULES[@]}"; do
        if ! _qml_module_available "$module"; then
            _warn "required QML module missing: $module"
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
_optdep fc-list       "font picker + font checks"
_optdep brightnessctl "brightness control + popup"
_optdep inotifywait   "screenshot flash"
_optdep nmcli         "VPN name fallback"
_optdep cava          "audio visualizer (auto-configured at runtime)"
_optdep_any "updates" "update count" checkupdates apt dnf zypper xbps-install
_optdep_any "AUR helper" "AUR update count" paru yay
_optdep busctl        "notification daemon check"
_optdep upower        "battery percentage + warnings"
_optdep_any "night light" "night light toggle" hyprsunset wlsunset
_optdep pgrep         "optional night light external state check"
_optdep pkill         "optional night light external stop fallback"
_optdep powerprofilesctl "power profile selector"
_optdep_any "lock screen" "lock action" hyprlock swaylock gtklock
_optdep_any "sound settings" "per-app routing hand-off" pwvucontrol pavucontrol
_optdep_any "power actions" "suspend / reboot / shutdown" systemctl loginctl
_optdep notify-send   "low-battery + hot-CPU alerts"
_optdep timeout       "bounded update checks"
_optdep ssh-keygen    "signed shell updates"

# ── compositor ───────────────────────────────────────────────────────────────────
# The whole install can succeed on a session Silere cannot run on: every step
# writes its own files, and only the autostart step notices, where it reads as a
# missing Hyprland config rather than an unsupported compositor. A config on disk
# counts, so installing from a TTY or over SSH before the compositor is up works.
_section "compositor"

_supported_compositor() {
    [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && return 0
    [ -n "${NIRI_SOCKET:-}" ] && return 0
    _find_compositor_pid Hyprland >/dev/null 2>&1 && return 0
    _find_compositor_pid niri >/dev/null 2>&1 && return 0
    [ -n "$(_hypr_config_path)" ] && return 0
    [ -f "$(_niri_config_path)" ] && return 0
    return 1
}

if _supported_compositor; then
    _ok "Hyprland or niri found"
else
    _session="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}"
    _warn "no Hyprland or niri found — this session reports \"$_session\""
    _warn "Silere runs on Hyprland and niri only. It will install here, but the"
    _warn "bar will not start and the menu will not open."
    if ! _ask_no "Install anyway?"; then
        printf "\n  nothing was written\n"
        printf "  to install for a compositor you have not started yet, point the\n"
        printf "  installer at its config: ${DIM}SILERE_HYPR_CONFIG=... scripts/install.sh${R}\n\n"
        exit 0
    fi
fi

_txn_begin

# ── font ─────────────────────────────────────────────────────────────────────────
_section "JetBrainsMono Nerd Font"

# grep -q exits on the first match and SIGPIPEs fc-list, which pipefail then reports
# as a failure — so a font that is installed reads as missing. Let grep drain it all.
_font_installed() {
    command -v fc-list >/dev/null 2>&1 || return 1
    fc-list : family 2>/dev/null | grep -i "JetBrainsMono Nerd" >/dev/null
}

# pinned release, not "latest": the hash below is only meaningful against a fixed artifact
FONT_VERSION="v3.4.0"
FONT_SHA256="ef552a3e638f25125c6ad4c51176a6adcdce295ab1d2ffacf0db060caf8c1582"
FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/$FONT_VERSION/JetBrainsMono.tar.xz"

_font_download_tools_ready() {
    local -a missing=()
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v tar  >/dev/null 2>&1 || missing+=("tar")
    # the release artifact is .tar.xz and tar shells out to xz to read it, so a
    # missing xz otherwise surfaces as "extract failed" after a 30 MB download
    command -v xz   >/dev/null 2>&1 || missing+=("xz")
    command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || missing+=("sha256sum")
    if [ "${#missing[@]}" -eq 0 ]; then
        return 0
    fi
    _warn "font auto-install needs: ${missing[*]}"
    _warn "install those tools or install JetBrainsMono Nerd Font manually"
    return 1
}

_font_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -- "$1" | awk '{print $1}'
    else
        shasum -a 256 -- "$1" | awk '{print $1}'
    fi
}

did_font=false

FONT_DIR="$HOME/.local/share/fonts/JetBrainsMono"

if _font_installed; then
    _ok "already installed"
else
    _warn "JetBrainsMono Nerd Font not found"
    if _dry; then
        if _font_download_tools_ready; then
            _would "download JetBrainsMono $FONT_VERSION and install 4 faces to $FONT_DIR"
        fi
    elif _font_download_tools_ready && _ask "Download and install it now?"; then
        for font_file in "${SILERE_FONT_FILES[@]}"; do
            _txn_before_file "$FONT_DIR/$font_file" \
                || _die "could not journal $FONT_DIR/$font_file"
        done
        mkdir -p "$FONT_DIR"
        font_tmp="$(mktemp "${TMPDIR:-/tmp}/silere-font.XXXXXX.tar.xz")"
        spin_start "downloading..."
        if ! curl -fsSL --proto '=https' --tlsv1.2 \
                --connect-timeout 10 --max-time 60 -o "$font_tmp" "$FONT_URL"; then
            spin_stop
            rm -f "$font_tmp"
            _warn "download failed — install JetBrainsMono Nerd Font manually"
        elif [ "$(_font_sha256 "$font_tmp")" != "$FONT_SHA256" ]; then
            spin_stop
            rm -f "$font_tmp"
            # fail closed: a hash mismatch means the artifact is not the reviewed one
            _warn "checksum mismatch on the font download — refusing to install it"
            _warn "expected $FONT_SHA256"
            _warn "install JetBrainsMono Nerd Font manually, or report this if it persists"
        elif _extract_silere_fonts "$font_tmp" "$FONT_DIR" 2>/dev/null; then
            spin_stop
            rm -f "$font_tmp"
            fc-cache -f "$FONT_DIR" 2>/dev/null || true
            if ! command -v fc-list >/dev/null 2>&1 || _font_installed; then
                _ok "installed $FONT_VERSION to $FONT_DIR"
                did_font=true
            else
                _warn "wrote $FONT_VERSION to $FONT_DIR but fontconfig does not list it"
                _warn "run fc-cache -fr, then re-check with fc-match monospace"
            fi
        else
            spin_stop
            rm -f "$font_tmp"
            _warn "extract failed — install JetBrainsMono Nerd Font manually"
        fi
    else
        _skip "skipped — install a Nerd Font manually before launching silere"
    fi
fi

# ── clone ────────────────────────────────────────────────────────────────────────
_section "silere-shell"

printf "  ${CYAN}::${R}  Install to: ${CYAN}%s${R}\n" "$DEFAULT_DIR"
INSTALL_DIR="$(_ask_path)"
INSTALL_DIR="$(_normalized_install_path "$INSTALL_DIR")"
fresh_clone=false

if [ "$INSTALL_DIR" = "$DEFAULT_DIR" ] && _dry; then
    if [ ! -d "$CONFIG_HOME" ]; then
        _would "create $CONFIG_HOME with mode 0700"
    elif [ "$(stat -c '%a' "$CONFIG_HOME" 2>/dev/null)" != 700 ]; then
        _would "restrict $CONFIG_HOME to mode 0700"
    fi
elif [ "$INSTALL_DIR" = "$DEFAULT_DIR" ]; then
    # -m with -p only applies to the deepest directory, so any parent this
    # creates would land at the umask default; clamp it for the whole path.
    _txn_before_mode "$CONFIG_HOME" || _die "could not journal permissions for $CONFIG_HOME"
    (umask 077 && mkdir -p "$CONFIG_HOME") || _die "could not create $CONFIG_HOME"
    chmod 0700 "$CONFIG_HOME" || _die "could not secure $CONFIG_HOME"
fi

if [ -d "$INSTALL_DIR/.git" ]; then
    _is_silere_checkout "$INSTALL_DIR" \
        || _die "$INSTALL_DIR is a Git repository but not a Silere checkout — choose another path"
    _ok "already cloned at $INSTALL_DIR"
    install_has_changes=false
    if [ -n "$(git -C "$INSTALL_DIR" status --porcelain --untracked-files=normal)" ]; then
        install_has_changes=true
        _warn "local Silere edits detected; the installer will not remove them"
        [ -x "$INSTALL_DIR/scripts/repair.sh" ] \
            && _warn "preview a safe restore with: bash $INSTALL_DIR/scripts/repair.sh"
    fi
    if _dry; then
        _would "update $INSTALL_DIR to the latest signed release"
    elif _ask "Install the latest signed release?"; then
        spin_start "checking release..."
        if ! GIT_TERMINAL_PROMPT=0 bash "$INSTALL_DIR/scripts/update.sh" >/dev/null \
                || ! GIT_TERMINAL_PROMPT=0 bash "$INSTALL_DIR/scripts/update.sh" --apply >/dev/null; then
            spin_stop
            if $install_has_changes; then
                _die "the signed update could not preserve the local edits — repair or stash them, then retry"
            fi
            _die "signed release update failed — check the connection or update manually"
        fi
        install_mode=managed
        spin_stop; _ok "up to date"
    else
        _skip "using existing clone"
    fi
elif [ -e "$INSTALL_DIR" ] || [ -L "$INSTALL_DIR" ]; then
    if _dry; then
        _would "move $INSTALL_DIR aside and clone $REPO_URL in its place"
        fresh_clone=true
    elif _ask "Path exists but is not a git repo. Move it aside and clone fresh?"; then
        install_backup="$(_move_aside_path "$INSTALL_DIR")" \
            || _die "could not preserve existing path: $INSTALL_DIR"
        _txn_tree_replaced "$INSTALL_DIR" "$install_backup" \
            || _die "could not journal checkout replacement"
        _ok "preserved existing path at $install_backup"
        spin_start "cloning..."
        if ! GIT_TERMINAL_PROMPT=0 git clone --single-branch --quiet "$REPO_URL" "$INSTALL_DIR"; then
            spin_stop
            if [ ! -e "$INSTALL_DIR" ] && [ ! -L "$INSTALL_DIR" ] \
                    && mv -- "$install_backup" "$INSTALL_DIR"; then
                _warn "clone failed; restored the original path"
            else
                _warn "clone failed; the original remains at $install_backup"
            fi
            _die "git clone failed — check your connection"
        fi
        fresh_clone=true
        spin_stop; _ok "cloned to $INSTALL_DIR"
    else
        _die "$INSTALL_DIR exists but is not a git repo — pick a different path or clean it up manually"
    fi
elif _dry; then
    _would "clone $REPO_URL → $INSTALL_DIR"
    fresh_clone=true
else
    _txn_tree_created "$INSTALL_DIR" || _die "could not journal checkout creation"
    spin_start "cloning..."
    if ! GIT_TERMINAL_PROMPT=0 git clone --single-branch --quiet "$REPO_URL" "$INSTALL_DIR"; then
        spin_stop; _die "git clone failed — check your connection"
    fi
    fresh_clone=true
    spin_stop; _ok "cloned to $INSTALL_DIR"
fi

if $fresh_clone && _dry; then
    _would "check out the latest signed release in $INSTALL_DIR"
elif $fresh_clone; then
    _secure_fresh_default_install "$INSTALL_DIR"
    # a clone this installer made is Silere's to update either way; declining the
    # pin only chooses main over the tag, and main still moves on signed releases
    install_mode=managed
    if _ask "Install the latest signed release?"; then
        spin_start "checking release..."
        if ! GIT_TERMINAL_PROMPT=0 bash "$INSTALL_DIR/scripts/update.sh" --pin-release >/dev/null; then
            spin_stop
            _die "signed release checkout failed — check the connection or update manually"
        fi
        spin_stop; _ok "on the latest signed release"
    else
        _skip "tracking main"
    fi
fi

ROOT="$INSTALL_DIR"
did_tmpl=false did_toml=false did_autostart=false did_update=false did_cli=false
did_keybind=false
autostart_ready=false
ROOT_PRINTF_BYTES="$(_shell_quote "$(_shell_printf_bytes "$ROOT")")"
MATUGEN_OUTPUT_TOML="$(_toml_basic_string "$CONFIG_HOME/matugen/silere-shell.json")"
MATUGEN_INPUT_TOML="$(_toml_basic_string "$CONFIG_HOME/matugen/templates/silere-shell/Theme.json")"

# ── maintenance command ──────────────────────────────────────────────────────────
_section "maintenance command"
CLI_DIR="$HOME/.local/bin"
CLI_LINK="$CLI_DIR/silere"
CLI_TARGET="$ROOT/scripts/silere"
if [ ! -x "$CLI_TARGET" ] && ! _dry; then
    _warn "maintenance command is missing from $ROOT"
elif [ -L "$CLI_LINK" ] \
        && [ "$(readlink -f -- "$CLI_LINK" 2>/dev/null || true)" = "$CLI_TARGET" ]; then
    _ok "already available at $CLI_LINK"
elif [ -e "$CLI_LINK" ] || [ -L "$CLI_LINK" ]; then
    _warn "$CLI_LINK already exists and is not owned by this Silere install"
    _skip "left it untouched; run $CLI_TARGET directly"
elif _ask "Install the silere doctor/update/repair command?"; then
    if _dry; then
        _would "create $CLI_LINK → $CLI_TARGET"
    else
        (umask 077 && mkdir -p "$CLI_DIR") || _die "could not create $CLI_DIR"
        _txn_before_file "$CLI_LINK" || _die "could not journal $CLI_LINK"
        ln -s -- "$CLI_TARGET" "$CLI_LINK" || _die "could not create $CLI_LINK"
        _ok "installed at $CLI_LINK"
        did_cli=true
    fi
else
    _skip "run it directly: $CLI_TARGET"
fi

# ── matugen template ─────────────────────────────────────────────────────────────
_section "matugen template"
TMPL_SRC="$ROOT/assets/matugen-theme.json"
TMPL_DST="$CONFIG_HOME/matugen/templates/silere-shell/Theme.json"
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
    if grep -qF "input_path  = $MATUGEN_INPUT_TOML" "$MATUGEN_CFG" \
            && grep -qF "output_path = $MATUGEN_OUTPUT_TOML" "$MATUGEN_CFG"; then
        _ok "entry already present"
    elif _dry; then
        _would "rewrite the silere-shell block in $MATUGEN_CFG"
    elif _ask "Update the existing Silere entry for this install?"; then
        _backup "$MATUGEN_CFG"
        if _replace_matugen_block "$MATUGEN_CFG" "$MATUGEN_INPUT_TOML" "$MATUGEN_OUTPUT_TOML"; then
            _ok "entry updated"; did_toml=true
        else
            _warn "could not update $MATUGEN_CFG"
        fi
    else
        _skip "existing entry left unchanged"
    fi
elif _matugen_table_present "$MATUGEN_CFG"; then
    _warn "an unmanaged [templates.silere-shell] entry already exists"
    _skip "left $MATUGEN_CFG unchanged"
else
    if _dry; then
        _would "add a silere-shell block to $MATUGEN_CFG"
    elif _ask "Add entry to $MATUGEN_CFG?"; then
        cfg_existed=false
        [ -f "$MATUGEN_CFG" ] && cfg_existed=true
        _txn_before_file "$MATUGEN_CFG" || _die "could not journal $MATUGEN_CFG"
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
_section "autostart"
HYPR_CONF="$CONFIG_HOME/hypr/hyprland.conf"
HYPR_LUA="$CONFIG_HOME/hypr/hyprland.lua"

# A compositor launched with `Hyprland --config /custom/path` does not expose
# that choice through XDG_CONFIG_HOME. Prefer an explicit installer override,
# then inspect the current same-user Hyprland session, and only then use the
# standard roots. Relative process arguments are resolved via /proc/PID/cwd.
HYPR_CONFIG="$(_hypr_config_path)"
if [ -n "$HYPR_CONFIG" ]; then
    _reject_unsafe_path "$HYPR_CONFIG"
    # warn rather than die, the way the niri branch already does: the clone, font and
    # matugen wiring are done by now, so a bad SILERE_HYPR_CONFIG must drop to the
    # manual-autostart path instead of aborting on top of a half-finished install
    if [ ! -f "$HYPR_CONFIG" ]; then
        _warn "Hyprland config not found: $HYPR_CONFIG"
        HYPR_CONFIG=""
    else
        case "$HYPR_CONFIG" in
            *.lua|*.conf) ;;
            *) _warn "Hyprland config must end in .lua or .conf: $HYPR_CONFIG"
               HYPR_CONFIG="" ;;
        esac
    fi
fi
# `silere run` owns allocator/image/GPU defaults and execs Quickshell with its
# duplicate guard. Keeping compositor config this small means a later update can
# improve startup without rewriting the user's Hyprland or niri file.
# --startup retains the one-second Wayland-socket grace needed at compositor boot.
LAUNCH_CMD="exec \"\$(printf '%b' $ROOT_PRINTF_BYTES)/scripts/silere\" run --startup"
LAUNCH_CMD_LUA="$(_lua_string "$LAUNCH_CMD")"

_already_present() { grep -qF 'silere-shell begin' "$1" 2>/dev/null; }

# autostart targets sit several levels deep and there can be more than one
# execs.lua candidate, so every prompt below names the file it will append to
_tilde() {
    case "$1" in
        "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
        *) printf '%s' "$1" ;;
    esac
}

# niri documents NIRI_CONFIG as its own config override; SILERE_NIRI_CONFIG wins over it
NIRI_CONFIG_OVERRIDE="${SILERE_NIRI_CONFIG:-${NIRI_CONFIG:-}}"
NIRI_CONFIG="$(_niri_config_path)"
_autostart_done=false

# niri session wins; fall back to a niri config only when no Hyprland session is live
if [ -n "${NIRI_SOCKET:-}" ] || [ "${XDG_CURRENT_DESKTOP:-}" = "niri" ] \
    || [ -n "$NIRI_CONFIG_OVERRIDE" ] \
    || { [ -z "$HYPR_CONFIG" ] && [ -f "$NIRI_CONFIG" ]; }; then
    NIRI_SPAWN="spawn-at-startup \"sh\" \"-c\" $(_lua_string "$LAUNCH_CMD")"
    receipt_compositor=niri
    receipt_autostart="$NIRI_CONFIG"
    if [ ! -f "$NIRI_CONFIG" ]; then
        _warn "no niri config at $(_tilde "$NIRI_CONFIG")"
        _warn "add manually: $NIRI_SPAWN"
    else
        _ok "found niri config at $(_tilde "$NIRI_CONFIG")"
        if _already_present "$NIRI_CONFIG"; then
            if _owned_block_contains "$NIRI_CONFIG" '// silere-shell begin' \
                    '// silere-shell end' '/scripts/silere' \
                    && _owned_block_contains "$NIRI_CONFIG" '// silere-shell begin' \
                    '// silere-shell end' 'run --startup'; then
                _ok "already present in $(_tilde "$NIRI_CONFIG")"
            elif _dry; then
                _would "migrate the Silere block in $NIRI_CONFIG to the shared launcher"
            elif _ask "Update the existing Silere autostart command in $(_tilde "$NIRI_CONFIG")?"; then
                _backup "$NIRI_CONFIG"
                _replace_owned_block "$NIRI_CONFIG" '// silere-shell begin' \
                    '// silere-shell end' "$NIRI_SPAWN" \
                    || _die "could not update $NIRI_CONFIG"
                _ok "autostart command updated"; did_autostart=true
            else
                _skip "kept the existing Silere autostart command"
            fi
            autostart_ready=true
        elif _dry; then
            _would "append to $NIRI_CONFIG: $NIRI_SPAWN"
        elif _ask "Add spawn-at-startup to $(_tilde "$NIRI_CONFIG")?"; then
            _reject_unsafe_path "$NIRI_CONFIG"
            _backup "$NIRI_CONFIG"
            printf '\n// silere-shell begin\n%s\n// silere-shell end\n' "$NIRI_SPAWN" >> "$NIRI_CONFIG"
            _ok "added to $(_tilde "$NIRI_CONFIG")"; did_autostart=true autostart_ready=true
        else
            _skip "skipped — add manually: $NIRI_SPAWN"
        fi
    fi
    _autostart_done=true
fi

if ! $_autostart_done; then
receipt_compositor=hyprland
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

    _ok "found Hyprland Lua config at $(_tilde "$HYPR_CONFIG")"

    if [ -n "$LUA_EXEC_FILE" ] && _already_present "$LUA_EXEC_FILE"; then
        receipt_autostart="$LUA_EXEC_FILE"
        LUA_AUTOSTART_BODY="$(printf 'hl.on(\"hyprland.start\", function()\n    hl.exec_cmd(%s)\nend)' "$LAUNCH_CMD_LUA")"
        if _owned_block_contains "$LUA_EXEC_FILE" '-- silere-shell begin' \
                '-- silere-shell end' '/scripts/silere' \
                && _owned_block_contains "$LUA_EXEC_FILE" '-- silere-shell begin' \
                '-- silere-shell end' 'run --startup'; then
            _ok "already present in $(_tilde "$LUA_EXEC_FILE")"
        elif _dry; then
            _would "migrate the Silere block in $LUA_EXEC_FILE to the shared launcher"
        elif _ask "Update the existing Silere autostart command in $(_tilde "$LUA_EXEC_FILE")?"; then
            _backup "$LUA_EXEC_FILE"
            _replace_owned_block "$LUA_EXEC_FILE" '-- silere-shell begin' \
                '-- silere-shell end' "$LUA_AUTOSTART_BODY" \
                || _die "could not update $LUA_EXEC_FILE"
            _ok "autostart command updated"; did_autostart=true
        else
            _skip "kept the existing Silere autostart command"
        fi
        autostart_ready=true
    elif [ -n "$LUA_EXEC_FILE" ] && _dry; then
        _would "append to $LUA_EXEC_FILE: hl.exec_cmd($LAUNCH_CMD_LUA)"
    elif [ -n "$LUA_EXEC_FILE" ]; then
        receipt_autostart="$LUA_EXEC_FILE"
        if _ask "Add autostart to $(_tilde "$LUA_EXEC_FILE")?"; then
            _backup "$LUA_EXEC_FILE"
            cat >> "$LUA_EXEC_FILE" <<EOF

-- silere-shell begin
hl.on("hyprland.start", function()
    hl.exec_cmd($LAUNCH_CMD_LUA)
end)
-- silere-shell end
EOF
            _ok "added to $(_tilde "$LUA_EXEC_FILE")"; did_autostart=true autostart_ready=true
        else
            _skip "skipped — add manually: hl.exec_cmd($LAUNCH_CMD_LUA)"
        fi
    else
        # appending to hyprland.lua itself is not safe: Lua requires `return` to end
        # a block, so a snippet after it is a syntax error that breaks the whole config
        _warn "Lua config detected but no execs.lua found — looked in:"
        _warn "  $(_tilde "$HYPR_DIR")/{custom,hyprland}/execs.lua and $(_tilde "$HYPR_DIR")/execs.lua"
        _warn "create one of those and re-run, or add manually:"
        _warn "  hl.on(\"hyprland.start\", function() hl.exec_cmd($LAUNCH_CMD_LUA) end)"
    fi

elif [[ "$HYPR_CONFIG" == *.conf ]]; then
    receipt_autostart="$HYPR_CONFIG"
    _ok "found Hyprland config at $(_tilde "$HYPR_CONFIG")"
    if _already_present "$HYPR_CONFIG"; then
        if _owned_block_contains "$HYPR_CONFIG" '# silere-shell begin' \
                '# silere-shell end' '/scripts/silere' \
                && _owned_block_contains "$HYPR_CONFIG" '# silere-shell begin' \
                '# silere-shell end' 'run --startup'; then
            _ok "already present in $(_tilde "$HYPR_CONFIG")"
        elif _dry; then
            _would "migrate the Silere block in $HYPR_CONFIG to the shared launcher"
        elif _ask "Update the existing Silere autostart command in $(_tilde "$HYPR_CONFIG")?"; then
            _backup "$HYPR_CONFIG"
            _replace_owned_block "$HYPR_CONFIG" '# silere-shell begin' \
                '# silere-shell end' "exec-once = $LAUNCH_CMD" \
                || _die "could not update $HYPR_CONFIG"
            _ok "autostart command updated"; did_autostart=true
        else
            _skip "kept the existing Silere autostart command"
        fi
        autostart_ready=true
    elif _dry; then
        _would "append to $HYPR_CONFIG: exec-once = $LAUNCH_CMD"
    else
        if _ask "Add exec-once to $(_tilde "$HYPR_CONFIG")?"; then
            _backup "$HYPR_CONFIG"
            cat >> "$HYPR_CONFIG" <<EOF

# silere-shell begin
exec-once = $LAUNCH_CMD
# silere-shell end
EOF
            _ok "added"; did_autostart=true autostart_ready=true
        else
            _skip "skipped — add manually: exec-once = $LAUNCH_CMD"
        fi
    fi
else
    _warn "no Hyprland config found"
    _warn "add manually: exec-once = $LAUNCH_CMD"
fi
fi

# ── menu keybind ────────────────────────────────────────────────────────────────
_section "menu keybind"

MENU_BIND_MODS="${SILERE_MENU_BIND_MODS:-SUPER}"
MENU_BIND_KEY="${SILERE_MENU_BIND_KEY:-slash}"
MENU_BIND_CMD="qs ipc -p \"\$(printf '%b' $ROOT_PRINTF_BYTES)/shell.qml\" call menu toggle"
MENU_BIND_SHOWN="qs ipc -p $(_shell_quote "$ROOT/shell.qml") call menu toggle"
HYPR_BIND="bind = $MENU_BIND_MODS, $MENU_BIND_KEY, exec, $MENU_BIND_CMD"
HYPR_BIND_SHOWN="bind = $MENU_BIND_MODS, $MENU_BIND_KEY, exec, $MENU_BIND_SHOWN"
NIRI_BIND_SHOWN="Mod+Slash { spawn \"sh\" \"-c\" \"$MENU_BIND_SHOWN\"; }"

if [ "$receipt_compositor" = niri ]; then
    # niri takes one binds block, so a second one appended at the top level is a
    # config error rather than a merge
    _skip "niri keeps every bind in one block — add inside yours:"
    _info "  $NIRI_BIND_SHOWN"
elif [[ "$HYPR_CONFIG" == *.lua ]]; then
    _skip "Lua config — add a bind the way your wrapper declares them:"
    _info "  $HYPR_BIND_SHOWN"
elif [ -z "$HYPR_CONFIG" ]; then
    _skip "no Hyprland config found — add manually:"
    _info "  $HYPR_BIND_SHOWN"
elif _owned_block_contains "$HYPR_CONFIG" '# silere-shell keybind begin' \
        '# silere-shell keybind end' 'call menu toggle'; then
    _ok "already present in $(_tilde "$HYPR_CONFIG")"
    did_keybind=true
    receipt_keybind="$HYPR_CONFIG"
elif _menu_bind_taken; then
    _warn "$MENU_BIND_MODS + $MENU_BIND_KEY is already bound in your Hyprland config"
    _warn "re-run with SILERE_MENU_BIND_KEY set to a free key, or add manually:"
    _warn "  $HYPR_BIND_SHOWN"
elif _dry; then
    _would "append to $HYPR_CONFIG: $HYPR_BIND_SHOWN"
elif _ask "Bind $MENU_BIND_MODS + $MENU_BIND_KEY to open the Silere menu?"; then
    _reject_unsafe_path "$HYPR_CONFIG"
    _backup "$HYPR_CONFIG"
    printf '\n# silere-shell keybind begin\n%s\n# silere-shell keybind end\n' \
        "$HYPR_BIND" >> "$HYPR_CONFIG" || _die "could not write $HYPR_CONFIG"
    _ok "$MENU_BIND_MODS + $MENU_BIND_KEY opens the menu"
    did_keybind=true
    receipt_keybind="$HYPR_CONFIG"
else
    _skip "skipped — add manually: $HYPR_BIND_SHOWN"
fi

# ── update-check timer ──────────────────────────────────────────────────────────────
_section "update-check timer"

if ! command -v systemctl >/dev/null 2>&1; then
    _skip "systemctl not found"
elif _ask_no "Install daily update-check timer (flags pending updates in the bar)?"; then
    _txn_timer_state || _die "could not journal update timer state"
    _txn_before_file "$CONFIG_HOME/systemd/user/silere-update.service" \
        || _die "could not journal silere-update.service"
    _txn_before_file "$CONFIG_HOME/systemd/user/silere-update.timer" \
        || _die "could not journal silere-update.timer"
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
if _dry; then
    printf "\n${BOLD}==> dry run${R}\n"
    printf "    ${DIM}nothing was written${R}\n"
    printf "\n  re-run without --dry-run to apply this plan\n\n"
    exit 0
fi

_txn_commit || _die "could not commit the install receipt; the install was rolled back"

printf "\n${BOLD}==> done${R}\n"
printf "    ${GREEN}ok${R}      installed at %s\n" "$ROOT"
$did_font      && printf "    ${GREEN}ok${R}      JetBrainsMono Nerd Font\n" || printf "    ${DIM}skip${R}    JetBrainsMono Nerd Font\n"
$did_tmpl      && printf "    ${GREEN}ok${R}      matugen template\n" || printf "    ${DIM}skip${R}    matugen template\n"
$did_toml      && printf "    ${GREEN}ok${R}      matugen toml\n"     || printf "    ${DIM}skip${R}    matugen toml\n"
$did_autostart && printf "    ${GREEN}ok${R}      autostart\n"        || printf "    ${DIM}skip${R}    autostart\n"
$did_keybind   && printf "    ${GREEN}ok${R}      menu keybind\n"     || printf "    ${DIM}skip${R}    menu keybind\n"
$did_update    && printf "    ${GREEN}ok${R}      update-check timer\n" || printf "    ${DIM}skip${R}    update-check timer\n"
$did_cli       && printf "    ${GREEN}ok${R}      silere maintenance command\n" || printf "    ${DIM}skip${R}    silere maintenance command\n"
# a missing runtime and an unwired autostart are independent, so report them
# separately — chaining them tells a user to restart into a shell nothing launches
printf '\n'
if ! $has_qs; then
    printf "  ${YELLOW}install Quickshell${R}\n"
elif ! $qs_modules_ok; then
    printf "  ${YELLOW}install a complete current Quickshell build${R}\n"
fi
if $autostart_ready; then
    printf "  restart your compositor to launch silere\n"
else
    printf "  ${YELLOW}autostart is not set up${R} — silere will not start on its own\n"
    printf "  add the line above to your Hyprland or niri config, or run it now:\n"
    printf "    ${DIM}%s/scripts/silere run${R}\n" "$ROOT"
fi
if [ -f "$ROOT/scripts/check.sh" ]; then
    printf "  if a surface does not appear: ${DIM}bash %s/scripts/check.sh${R}\n" "$ROOT"
fi
if $did_keybind; then
    printf "  press ${DIM}%s + %s${R} or click the active workspace diamond to open the menu\n" \
        "$MENU_BIND_MODS" "$MENU_BIND_KEY"
else
    printf "  click the active workspace diamond to open the menu and settings\n"
    printf "  or bind it: ${DIM}%s${R}\n" "$MENU_BIND_SHOWN"
fi
# a packaged install ships no uninstall.sh: pointing at it there sends the user
# to a path that does not exist and would fight their package manager if it did
if [ -f "$ROOT/scripts/uninstall.sh" ]; then
    printf "  to uninstall: ${DIM}%s/scripts/uninstall.sh${R}\n" "$ROOT"
fi
printf "\n"
