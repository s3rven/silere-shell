#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/xdg.sh"
source "$ROOT/scripts/lib/qml-modules.sh"
source "$ROOT/scripts/lib/unit.sh"
cd "$ROOT"

CACHE_HOME="$(_silere_xdg_home "${XDG_CACHE_HOME:-}" .cache)" || {
    printf 'silere-update: HOME must be an absolute path\n' >&2
    exit 1
}
CONFIG_HOME="$(_silere_xdg_home "${XDG_CONFIG_HOME:-}" .config)" || {
    printf 'silere-update: HOME must be an absolute path\n' >&2
    exit 1
}
STATE_HOME="$(_silere_xdg_home "${XDG_STATE_HOME:-}" .local/state)" || {
    printf 'silere-update: HOME must be an absolute path\n' >&2
    exit 1
}
CACHE_DIR="$CACHE_HOME/silere-shell"
FLAG="$CACHE_DIR/update-pending"
NOTIFIED="$CACHE_DIR/update-notified"
CHECKED="$CACHE_DIR/update-checked"
ERROR_FLAG="$CACHE_DIR/update-error"
RELEASE_NOTES="$CACHE_DIR/release-notes"
TIMER_UNIT="silere-update.timer"
SERVICE_UNIT="silere-update.service"
SYSTEMD_USER_DIR="$CONFIG_HOME/systemd/user"
TRUSTED_SIGNERS="$ROOT/security/update-signers"
REQUESTED_MODE="${1:-}"
# Keep transactions independent when a developer has more than one checkout.
# cksum only selects the filename; the lossless hex root inside the journal is
# also compared before recovery, so a collision can never reset another tree.
ROOT_HEX="$(printf '%s' "$ROOT" | od -An -tx1 | tr -d ' \n')"
ROOT_KEY="$(printf '%s' "$ROOT" | cksum | awk '{ print $1 "-" $2 }')"
STATE_DIR="$STATE_HOME/silere-shell"
APPLY_JOURNAL="$STATE_DIR/update-transaction-$ROOT_KEY"
APPLY_TRUSTED_SIGNERS="$STATE_DIR/update-transaction-$ROOT_KEY.signers"
INSTALL_RECEIPT="$STATE_DIR/install-receipt"
STAGE_PARENT=""
STAGE_DIR=""
# a candidate check that cannot run is reported, never silently counted as a pass
CANDIDATE_GATE_NOTE=""

_notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    # Notifications are advisory. A missing/stale session bus must never turn a
    # successful update check or apply into a failed systemd unit.
    notify-send -a "Silere Shell" "$@" >/dev/null 2>&1 || true
}

# The periodic pass runs unattended and its failures are routine (a laptop
# offline, a branch left diverged), so it exits quietly and lets the shell
# surface the reason. Only user-initiated work is worth a critical popup.
_quiet_fail() {
    case "$REQUESTED_MODE" in
        ""|--apply) _record_update_error "$1" || true ;;
    esac
    echo "silere-update: $1" >&2
    exit 1
}

_fail() {
    _notify -u critical "Silere update failed" "$1"
    _quiet_fail "$1"
}

_clear_flag() {
    rm -f "$FLAG" "$NOTIFIED" "$RELEASE_NOTES"
}

_ensure_cache_dir() {
    [ ! -L "$CACHE_DIR" ] || return 1
    (umask 077 && mkdir -p "$CACHE_DIR") || return 1
    chmod 0700 "$CACHE_DIR"
}

_write_cache_file() {
    local target="$1" tmp
    shift
    _ensure_cache_dir || return 1
    tmp="$(mktemp "$CACHE_DIR/.${target##*/}.XXXXXX")" || return 1
    if ! printf '%s\n' "$@" > "$tmp" || ! mv -- "$tmp" "$target"; then
        rm -f -- "$tmp"
        return 1
    fi
}

_ensure_state_dir() {
    [ ! -L "$STATE_DIR" ] || return 1
    (umask 077 && mkdir -p "$STATE_DIR") || return 1
    chmod 0700 "$STATE_DIR"
}

_write_state_file() {
    local target="$1" tmp
    shift
    _ensure_state_dir || return 1
    tmp="$(mktemp "$STATE_DIR/.${target##*/}.XXXXXX")" || return 1
    chmod 0600 "$tmp" || { rm -f -- "$tmp"; return 1; }
    if ! printf '%s\n' "$@" > "$tmp" || ! mv -- "$tmp" "$target"; then
        rm -f -- "$tmp"
        return 1
    fi
}

_snapshot_trusted_signers() {
    local tmp
    [ -r "$TRUSTED_SIGNERS" ] || return 1
    _ensure_state_dir || return 1
    tmp="$(mktemp "$STATE_DIR/.update-signers.XXXXXX")" || return 1
    if ! cp -- "$TRUSTED_SIGNERS" "$tmp" || ! chmod 0600 "$tmp" \
            || ! mv -- "$tmp" "$APPLY_TRUSTED_SIGNERS"; then
        rm -f -- "$tmp"
        return 1
    fi
}

_write_apply_journal() {
    local phase="$1" old_rev="$2" new_rev="$3" tag="$4"
    [[ "$phase" =~ ^(prepared|merged|validated)$ ]] || return 1
    [[ "$old_rev" =~ ^[0-9a-f]{40,64}$ && "$new_rev" =~ ^[0-9a-f]{40,64}$ ]] || return 1
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    _write_state_file "$APPLY_JOURNAL" \
        version=1 "phase=$phase" "rootHex=$ROOT_HEX" \
        "from=$old_rev" "to=$new_rev" "tag=$tag" || return 1
    # recovery trusts a recorded phase, so it has to be on disk before the next step
    sync -f -- "$APPLY_JOURNAL" 2>/dev/null || true
}

_start_apply_transaction() {
    local old_rev="$1" new_rev="$2" tag="$3"
    _snapshot_trusted_signers || return 1
    if ! _write_apply_journal prepared "$old_rev" "$new_rev" "$tag"; then
        rm -f -- "$APPLY_TRUSTED_SIGNERS"
        return 1
    fi
}

_clear_apply_transaction() {
    # The signer snapshot must outlive the journal. If removing the journal
    # fails, retaining the key keeps the next recovery attempt authenticatable.
    rm -f -- "$APPLY_JOURNAL" || return 1
    rm -f -- "$APPLY_TRUSTED_SIGNERS"
}

_cleanup_candidate_stage() {
    local stage="${STAGE_DIR:-}" parent="${STAGE_PARENT:-}"
    STAGE_DIR=""
    STAGE_PARENT=""
    if [ -n "$stage" ]; then
        git -C "$ROOT" worktree remove --force "$stage" >/dev/null 2>&1 || true
    fi
    if [ -n "$parent" ] && [ -d "$parent" ]; then
        rmdir -- "$parent" >/dev/null 2>&1 || true
    fi
}

_create_candidate_stage() {
    STAGE_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/silere-stage.XXXXXX")" || return 1
    chmod 0700 "$STAGE_PARENT" || { _cleanup_candidate_stage; return 1; }
    STAGE_DIR="$STAGE_PARENT/tree"
    if ! git -C "$ROOT" worktree add --detach --quiet "$STAGE_DIR" "$release_rev"; then
        _cleanup_candidate_stage
        return 1
    fi
}

_read_apply_journal() {
    local -a lines=()
    mapfile -t lines < "$APPLY_JOURNAL" || return 1
    [ "${#lines[@]}" -eq 6 ] || return 1
    [ "${lines[0]}" = version=1 ] || return 1
    JOURNAL_PHASE="${lines[1]#phase=}"
    JOURNAL_ROOT_HEX="${lines[2]#rootHex=}"
    JOURNAL_FROM="${lines[3]#from=}"
    JOURNAL_TO="${lines[4]#to=}"
    JOURNAL_TAG="${lines[5]#tag=}"
    [ "${lines[1]}" = "phase=$JOURNAL_PHASE" ] \
        && [ "${lines[2]}" = "rootHex=$JOURNAL_ROOT_HEX" ] \
        && [ "${lines[3]}" = "from=$JOURNAL_FROM" ] \
        && [ "${lines[4]}" = "to=$JOURNAL_TO" ] \
        && [ "${lines[5]}" = "tag=$JOURNAL_TAG" ] \
        && [[ "$JOURNAL_PHASE" =~ ^(prepared|merged|validated)$ ]] \
        && [[ "$JOURNAL_ROOT_HEX" =~ ^[0-9a-f]+$ ]] \
        && [[ "$JOURNAL_FROM" =~ ^[0-9a-f]{40,64}$ ]] \
        && [[ "$JOURNAL_TO" =~ ^[0-9a-f]{40,64}$ ]] \
        && [[ "$JOURNAL_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

_journal_release_is_trusted() {
    local kind resolved
    [ "$JOURNAL_ROOT_HEX" = "$ROOT_HEX" ] || return 1
    [ -r "$APPLY_TRUSTED_SIGNERS" ] || return 1
    kind="$(git -C "$ROOT" cat-file -t "$JOURNAL_TAG" 2>/dev/null || true)"
    [ "$kind" = tag ] || return 1
    git -C "$ROOT" -c gpg.format=ssh \
        -c gpg.ssh.allowedSignersFile="$APPLY_TRUSTED_SIGNERS" \
        verify-tag "$JOURNAL_TAG" >/dev/null 2>&1 || return 1
    resolved="$(git -C "$ROOT" rev-parse "$JOURNAL_TAG^{}" 2>/dev/null || true)"
    [ "$resolved" = "$JOURNAL_TO" ] || return 1
    git -C "$ROOT" cat-file -e "$JOURNAL_FROM^{commit}" 2>/dev/null || return 1
    git -C "$ROOT" merge-base --is-ancestor "$JOURNAL_FROM" "$JOURNAL_TO"
}

# A completed update is only known-good once the shell is up on it. With no unit
# installed there is nothing this script can watch, so absence counts as running.
_updated_shell_is_running() {
    command -v systemctl >/dev/null 2>&1 || return 0
    systemctl --user is-enabled --quiet silere-shell.service 2>/dev/null || return 0
    systemctl --user is-active --quiet silere-shell.service 2>/dev/null
}

# A SIGKILL or power loss can land after the fast-forward but before validation.
# Never infer success from HEAD alone: the last durable phase decides whether to
# keep the signed target or return to the known-good revision.
_recover_interrupted_apply() {
    local head
    if [ ! -e "$APPLY_JOURNAL" ]; then
        rm -f -- "$APPLY_TRUSTED_SIGNERS"
        return 0
    fi
    _read_apply_journal \
        || _quiet_fail "the interrupted-update journal is malformed — inspect $APPLY_JOURNAL"
    _journal_release_is_trusted \
        || _quiet_fail "the interrupted-update journal could not be authenticated — inspect $APPLY_JOURNAL"
    head="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
    if [ "$head" = "$JOURNAL_FROM" ]; then
        _clear_apply_transaction \
            || _quiet_fail "could not clear the completed update recovery journal"
        echo "silere-update: cleared an interrupted update that had not changed the checkout" >&2
        return 0
    fi
    [ "$head" = "$JOURNAL_TO" ] \
        || _quiet_fail "checkout moved during an interrupted update — inspect $APPLY_JOURNAL"
    if [ "$JOURNAL_PHASE" = validated ]; then
        # The journal is kept until the shell is seen running on the new revision; a
        # release that passes the candidate gate can still fail in the live session,
        # and --rollback needs the journal to restore it.
        if _updated_shell_is_running; then
            _clear_apply_transaction \
                || _quiet_fail "could not clear the completed update recovery journal"
            echo "silere-update: retained the signed update that completed validation before interruption" >&2
        else
            echo "silere-update: the updated shell is not running; run --rollback to restore $JOURNAL_FROM" >&2
        fi
        return 0
    fi
    _has_local_changes \
        && _quiet_fail "local changes prevent recovery of an interrupted update — inspect $APPLY_JOURNAL"
    git -C "$ROOT" reset --hard --quiet "$JOURNAL_FROM" \
        || _quiet_fail "could not restore the checkout after an interrupted update — reset to $JOURNAL_FROM manually"
    _clear_apply_transaction \
        || _quiet_fail "the checkout was restored but its update recovery journal could not be cleared"
    echo "silere-update: restored the previous revision after an interrupted update" >&2
}

# A release can pass the candidate smoke and still fail under the live session.
# This puts the checkout back on the revision the journal recorded; the user runs
# it from a working terminal when the shell no longer starts.
_rollback_applied_update() {
    [ -e "$APPLY_JOURNAL" ] \
        || _fail "no completed update to roll back"
    _read_apply_journal \
        || _fail "the update journal is malformed — inspect $APPLY_JOURNAL"
    _journal_release_is_trusted \
        || _fail "the update journal could not be authenticated — inspect $APPLY_JOURNAL"
    [ "$JOURNAL_PHASE" = validated ] \
        || _fail "the last update did not reach a validated state"
    [ "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)" = "$JOURNAL_TO" ] \
        || _fail "the checkout moved since the update — roll back manually"
    _has_local_changes \
        && _fail "local changes block the rollback — run: bash $ROOT/scripts/repair.sh --apply"
    git -C "$ROOT" reset --hard --quiet "$JOURNAL_FROM" \
        || _fail "could not restore $JOURNAL_FROM"
    _clear_apply_transaction \
        || _fail "the checkout was restored but the journal could not be cleared"
    # Only restart a unit that actually runs this checkout; the test suite and a
    # throwaway checkout share one user manager, where is-enabled alone would
    # reach whatever shell is live.
    if command -v systemctl >/dev/null 2>&1 \
            && systemctl --user is-enabled --quiet silere-shell.service 2>/dev/null \
            && _unit_runs_this_checkout; then
        systemctl --user --no-block restart silere-shell.service || true
    fi
    _notify "Silere Shell rolled back" "restored $JOURNAL_FROM"
    printf 'silere-update: rolled back to %s\n' "$JOURNAL_FROM"
}

_record_update_error() {
    local message="${1//$'\n'/ }"
    _write_cache_file "$ERROR_FLAG" "$(date +%s)" "$message"
}

_clear_update_error() {
    rm -f -- "$ERROR_FLAG"
}

_has_local_changes() {
    # tracked only: an untracked file cannot block a fast-forward, and git refuses collisions itself
    [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]
}

# A blackholed network keeps a fetch running past the shell's own check timeout,
# and the orphan inherits the update lock's fd — wedging every later run behind
# it. 9>&- is what closes that: a fetch nothing can signal any more still cannot
# hold the lock. --kill-after covers one that sits on SIGTERM.
_git_fetch() {
    if _silere_timeout_kill_after_ok; then
        GIT_TERMINAL_PROMPT=0 timeout --kill-after=5 90 git fetch --quiet "$@" 9>&-
    elif command -v timeout >/dev/null 2>&1; then
        GIT_TERMINAL_PROMPT=0 timeout 90 git fetch --quiet "$@" 9>&-
    else
        GIT_TERMINAL_PROMPT=0 git fetch --quiet "$@" 9>&-
    fi
}

_fetch_main() {
    local shallow
    shallow="$(git -C "$ROOT" rev-parse --is-shallow-repository 2>/dev/null || true)"
    # A release withdrawn upstream must stop being eligible here too. --prune-tags
    # does nothing beside an explicit refspec, so the tag refspec is spelled out;
    # its + lets a moved signed tag replace the local one.
    if [ "$shallow" = true ]; then
        # Older installer releases used --depth 1. Tags alone do not cross that
        # boundary, so git describe cannot recover the installed release until
        # the main-branch history is completed once.
        _git_fetch --unshallow --prune origin main '+refs/tags/v*:refs/tags/v*'
    else
        _git_fetch --prune origin main '+refs/tags/v*:refs/tags/v*'
    fi
}

_latest_release_tag() {
    local tag
    while IFS= read -r tag; do
        if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            printf '%s\n' "$tag"
            return 0
        fi
    done < <(git -C "$ROOT" tag --merged refs/remotes/origin/main --list 'v*' --sort=-v:refname)
    return 1
}

_release_fail() {
    local mode="$1" message="$2"
    if [ "$mode" = apply ]; then _fail "$message"; fi
    _clear_flag
    _quiet_fail "$message"
}

_manifest_string() {
    local key="$1"
    printf '%s\n' "$release_manifest" | sed -n \
        "s/^[[:space:]]*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\"[[:space:]]*,\{0,1\}[[:space:]]*$/\1/p"
}

_manifest_number() {
    local key="$1"
    printf '%s\n' "$release_manifest" | sed -n \
        "s/^[[:space:]]*\"$key\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\)[[:space:]]*,\{0,1\}[[:space:]]*$/\1/p"
}

# Compatibility data is read only after the annotated tag has passed the
# installed trust root. Releases before the manifest existed remain installable;
# once a release carries one, malformed or contradictory data fails closed.
_check_release_manifest() {
    local mode="$1" manifest_version manifest_schema manifest_qs compositor="" qs_version
    if ! git -C "$ROOT" cat-file -e "$release_rev:release.json" 2>/dev/null; then
        return 0
    fi
    release_manifest="$(git -C "$ROOT" show "$release_rev:release.json" 2>/dev/null)" \
        || _release_fail "$mode" "$release_tag compatibility manifest could not be read"
    manifest_version="$(_manifest_string version)"
    manifest_schema="$(_manifest_number settingsSchema)"
    manifest_qs="$(_manifest_string quickshellMin)"
    [ "$manifest_version" = "${release_tag#v}" ] \
        || _release_fail "$mode" "$release_tag has a mismatched compatibility manifest"
    [[ "$manifest_schema" =~ ^[0-9]+$ ]] \
        || _release_fail "$mode" "$release_tag has an invalid settings schema"
    [[ "$manifest_qs" =~ ^[0-9]+(\.[0-9]+)*$ ]] \
        || _release_fail "$mode" "$release_tag has an invalid Quickshell requirement"
    printf '%s\n' "$release_manifest" \
        | grep -Eq '^[[:space:]]*"compositors"[[:space:]]*:[[:space:]]*\[[[:space:]]*"(hyprland|niri)"([[:space:]]*,[[:space:]]*"(hyprland|niri)")*[[:space:]]*\][[:space:]]*,?[[:space:]]*$' \
        || _release_fail "$mode" "$release_tag has an invalid compositor list"

    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then compositor=hyprland
    elif [ -n "${NIRI_SOCKET:-}" ]; then compositor=niri
    fi
    if [ -n "$compositor" ] && ! printf '%s\n' "$release_manifest" \
            | grep -Eq "\"compositors\"[^]]*\"$compositor\""; then
        _release_fail "$mode" "$release_tag does not support the active $compositor session"
    fi

    qs_version="$(_silere_quickshell_version || true)"
    if [ -z "$qs_version" ]; then
        # A fresh install may intentionally stage Silere before Quickshell is
        # installed. A running shell check/apply cannot use that exception.
        [ "$mode" = pin ] && return 0
        _release_fail "$mode" "$release_tag requires Quickshell $manifest_qs or newer; the installed version could not be read"
    fi
    _silere_version_at_least "$qs_version" "$manifest_qs" \
        || _release_fail "$mode" "$release_tag requires Quickshell $manifest_qs or newer; installed: $qs_version"
}

_release_note_rows() {
    local version="${release_tag#v}"
    git -C "$ROOT" show "$release_rev:docs/releases/$version.md" 2>/dev/null | awk '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }
        function emit() {
            if (category != "" && text != "" && count < 40) {
                gsub(/[\t\r\n]+/, " ", text)
                print category "\t" trim(text)
                count++
            }
            text = ""
        }
        /^## (Added|Changed|Fixed|Removed|Security)[[:space:]]*$/ {
            emit()
            category = substr($0, 4)
            next
        }
        /^## / { emit(); category = ""; next }
        /^### / { emit(); next }
        category != "" && /^- / { emit(); text = substr($0, 3); next }
        category != "" && text != "" && /^[[:space:]]+/ {
            line = trim($0)
            if (line != "") text = text " " line
            next
        }
        { emit() }
        END { emit() }
    '
}

_write_release_notes() {
    local rows
    rows="$(_release_note_rows || true)"
    if [ -n "$rows" ]; then
        _write_cache_file "$RELEASE_NOTES" "target $release_tag" "$rows"
    else
        rm -f -- "$RELEASE_NOTES"
    fi
}

# Verification uses the key shipped by the already-installed revision. The
# fetched tree cannot replace this trust root before its tag has been checked.
_resolve_trusted_release() {
    local mode="$1" kind
    release_tag="$(_latest_release_tag)" \
        || _release_fail "$mode" "origin/main has no stable Silere release"
    kind="$(git -C "$ROOT" cat-file -t "$release_tag" 2>/dev/null || true)"
    [ "$kind" = tag ] \
        || _release_fail "$mode" "$release_tag is not an annotated release tag"
    [ -r "$TRUSTED_SIGNERS" ] \
        || _release_fail "$mode" "the Silere release trust key is missing"
    command -v ssh-keygen >/dev/null 2>&1 \
        || _release_fail "$mode" "ssh-keygen is required to verify Silere releases"
    git -C "$ROOT" -c gpg.format=ssh \
        -c gpg.ssh.allowedSignersFile="$TRUSTED_SIGNERS" \
        verify-tag "$release_tag" >/dev/null 2>&1 \
        || _release_fail "$mode" "$release_tag is not signed by the trusted Silere release key"
    release_rev="$(git -C "$ROOT" rev-parse "$release_tag^{}" 2>/dev/null)" \
        || _release_fail "$mode" "could not resolve $release_tag"
    git -C "$ROOT" merge-base --is-ancestor "$release_rev" refs/remotes/origin/main \
        || _release_fail "$mode" "$release_tag is not part of origin/main"
    _check_release_manifest "$mode"
}

# A failed load makes qs exit non-zero at once, and the service restarts it every
# few seconds forever — no bar, no menu, and no UI left to roll back from. Type-check
# a detached candidate tree first (~15s) and only activate it if it actually loads.
# Skipping the gate when the checker or qs is missing keeps the updater usable without them.
# The unit name is fixed, so a --apply run from a second checkout would otherwise
# restart whichever shell is live, not the one it just updated.
_unit_runs_this_checkout() {
    _silere_unit_runs_checkout "$ROOT"
}

# the type-check never loads shell.qml; skipped without a display, timeout or theme
_candidate_tree_starts() {
    local candidate_root="$1"
    _silere_timeout_kill_after_ok || { CANDIDATE_GATE_NOTE="startup check skipped (timeout --kill-after unsupported)"; return 0; }
    [ -n "${WAYLAND_DISPLAY:-}" ] || { CANDIDATE_GATE_NOTE="startup check skipped (no display)"; return 0; }
    [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ] || { CANDIDATE_GATE_NOTE="startup check skipped (no runtime directory)"; return 0; }
    [ -f "$candidate_root/config/MatugenPalette.qml" ] || { CANDIDATE_GATE_NOTE="startup check skipped (incomplete checkout)"; return 0; }
    local sandbox log code=0 verdict=0
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/silere-update-runtime.XXXXXX")" || return 1
    chmod 0700 "$sandbox" || { rmdir -- "$sandbox"; return 1; }
    mkdir -p "$sandbox/config/silere-shell" "$sandbox/cache" "$sandbox/state" \
        || { rm -rf -- "$sandbox"; return 1; }
    # Exercise the candidate against the user's current on-disk shape without
    # allowing a migration or startup write to touch the real configuration.
    if [ -f "$CONFIG_HOME/silere-shell/settings.json" ] \
            && [ ! -L "$CONFIG_HOME/silere-shell/settings.json" ]; then
        cp -- "$CONFIG_HOME/silere-shell/settings.json" \
            "$sandbox/config/silere-shell/settings.json" \
            || { rm -rf -- "$sandbox"; return 1; }
    fi
    log="$(mktemp "${TMPDIR:-/tmp}/silere-update-smoke.XXXXXX.log")" \
        || { rm -rf -- "$sandbox"; return 1; }
    XDG_CONFIG_HOME="$sandbox/config" XDG_CACHE_HOME="$sandbox/cache" \
        XDG_STATE_HOME="$sandbox/state" SILERE_SMOKE_TEST=1 \
        timeout --kill-after=5 5s qs -p "$candidate_root/shell.qml" --no-color \
        >"$log" 2>&1 9>&- || code=$?
    # 124 is the timeout firing, i.e. it stayed up for the whole window
    if [ "$code" -ne 0 ] && [ "$code" -ne 124 ]; then
        # an unreachable display is not the update's fault; never roll back over it
        grep -qE 'Failed to create wl_display|could not connect to display|no Qt platform plugin could be initialized' "$log" \
            || verdict=1
    elif grep -qE 'Failed to load configuration|Type [^ ]+ unavailable|module ".*" is not installed' "$log"; then
        verdict=1
    fi
    rm -f "$log"
    rm -rf -- "$sandbox"
    return "$verdict"
}

_candidate_tree_loads() {
    local candidate_root="$1"
    [ -r "$candidate_root/scripts/test-qml-headless.sh" ] \
        || { CANDIDATE_GATE_NOTE="load check skipped (candidate has no type-checker)"; return 0; }
    command -v qs >/dev/null 2>&1 \
        || { CANDIDATE_GATE_NOTE="load check skipped (qs is not on PATH)"; return 0; }
    # unbounded and holding the update lock's fd open is how a stuck qmllint
    # wedges every later run behind this one; same guard as _git_fetch
    local check_out type_note="" rc=0
    if _silere_timeout_kill_after_ok; then
        check_out="$(timeout --kill-after=5 60 bash "$candidate_root/scripts/test-qml-headless.sh" \
            2>&1 9>&-)" || return 1
    elif command -v timeout >/dev/null 2>&1; then
        check_out="$(timeout 60 bash "$candidate_root/scripts/test-qml-headless.sh" \
            2>&1 9>&-)" || return 1
    else
        check_out="$(bash "$candidate_root/scripts/test-qml-headless.sh" 2>&1 9>&-)" || return 1
    fi
    # the checker exits 0 when Qt's QML tools are missing; that is not a pass
    case "$check_out" in
        *"SKIP: "*) type_note="type-check skipped (Qt QML tools not installed)" ;;
    esac
    _candidate_tree_starts "$candidate_root" || rc=$?
    [ -z "$type_note" ] || CANDIDATE_GATE_NOTE="$type_note${CANDIDATE_GATE_NOTE:+; $CANDIDATE_GATE_NOTE}"
    return "$rc"
}

_acquire_update_lock() {
    # util-linux is part of the normal Linux base. Keep the updater functional
    # on unusually minimal systems, but serialize check/apply whenever flock is
    # available so a timer run cannot race a manual install over refs/cache.
    command -v flock >/dev/null 2>&1 || return 0
    _ensure_cache_dir \
        || _quiet_fail "could not create the update cache directory"
    exec 9>>"$CACHE_DIR/update.lock" \
        || _quiet_fail "could not open the update lock"
    flock -n 9 \
        || _quiet_fail "another update check or install is already running"
}

_systemd_execstart() {
    local escaped="$ROOT/scripts/update.sh"
    escaped="${escaped//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    # ExecStart expands ${NAME} even inside a quoted argument. A custom
    # checkout path may contain those bytes literally; systemd spells a
    # literal dollar as $$.
    escaped="${escaped//\$/\$\$}"
    escaped="${escaped//%/%%}"
    printf '/bin/sh -c '\''exec "$1"'\'' silere-update "%s"\n' "$escaped"
}

_render_update_service() {
    local line exec_start
    exec_start="$(_systemd_execstart)"
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$line" = 'ExecStart=__ROOT__/scripts/update.sh' ]; then
            printf 'ExecStart=%s\n' "$exec_start"
        else
            printf '%s\n' "$line"
        fi
    done < "$ROOT/scripts/$SERVICE_UNIT"
}

_timer_status() {
    if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
        echo supported=1
        if systemctl --user is-enabled --quiet "$TIMER_UNIT" 2>/dev/null; then
            echo enabled=1
            # without --timestamp=unix systemctl renders a locale date here; empty on
            # systemd older than 247, and empty whenever the timer is not scheduled
            local next
            next="$(systemctl --user show "$TIMER_UNIT" -p NextElapseUSecRealtime \
                --value --timestamp=unix 2>/dev/null || true)"
            printf 'next=%s\n' "${next#@}"
        else
            echo enabled=0
        fi
    else
        echo supported=0
        echo enabled=0
    fi
}

_version_info() {
    local head tag ahead=0 branch dirty=0 mode
    head="$(git -C "$ROOT" log -1 --format='%h %cs')"
    tag="$(git -C "$ROOT" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
    if [ -n "$tag" ]; then
        ahead="$(git -C "$ROOT" rev-list --count "$tag..HEAD" 2>/dev/null || echo 0)"
    fi
    branch="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if _has_local_changes; then dirty=1; fi
    mode="$(_installation_mode "$branch")"
    printf 'sha=%s\ndate=%s\ntag=%s\nahead=%s\nbranch=%s\ndirty=%s\nmode=%s\n' \
        "${head%% *}" "${head##* }" "$tag" "$ahead" "$branch" "$dirty" "$mode"
}

_receipt_install_mode() {
    local mode encoded checkout
    [ -r "$INSTALL_RECEIPT" ] && [ ! -L "$INSTALL_RECEIPT" ] || return 1
    mode="$(sed -n 's/^installMode=//p' "$INSTALL_RECEIPT")"
    encoded="$(sed -n 's/^checkoutPath=//p' "$INSTALL_RECEIPT")"
    [[ "$mode" =~ ^(managed|development)$ ]] || return 1
    [[ "$encoded" =~ ^(\\[0-7]{3})+$ ]] || return 1
    checkout="$(printf '%b' "$encoded")"
    [ "$checkout" = "$ROOT" ] || return 1
    printf '%s\n' "$mode"
}

# Ownership, not blockers. The installer's receipt is authoritative; without one,
# a branch the user drives is the only signal that this checkout is theirs. Local
# changes are deliberately not part of it — a dirty tree is a state the apply path
# already refuses by name, and demoting the whole installation over it would leave
# the Updates page inert every time a file is edited.
_installation_mode() {
    local branch="${1:-$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)}"
    local mode
    mode="$(_receipt_install_mode 2>/dev/null || true)"
    if [ -n "$mode" ]; then printf '%s\n' "$mode"; return 0; fi
    [ "$branch" = main ] || { printf 'development\n'; return 0; }
    printf 'managed\n'
}

_write_update_units() {
    local service_tmp timer_tmp
    service_tmp="$(mktemp "$SYSTEMD_USER_DIR/.silere-update.service.XXXXXX")" || return 1
    timer_tmp="$(mktemp "$SYSTEMD_USER_DIR/.silere-update.timer.XXXXXX")" || {
        rm -f "$service_tmp"
        return 1
    }

    if ! _render_update_service > "$service_tmp" \
        || ! cp "$ROOT/scripts/$TIMER_UNIT" "$timer_tmp"; then
        rm -f "$service_tmp" "$timer_tmp"
        return 1
    fi
    chmod --reference="$ROOT/scripts/$SERVICE_UNIT" "$service_tmp" 2>/dev/null || true
    chmod --reference="$ROOT/scripts/$TIMER_UNIT" "$timer_tmp" 2>/dev/null || true

    if ! mv -- "$service_tmp" "$SYSTEMD_USER_DIR/$SERVICE_UNIT"; then
        rm -f "$service_tmp" "$timer_tmp"
        return 1
    fi
    service_tmp=""
    if ! mv -- "$timer_tmp" "$SYSTEMD_USER_DIR/$TIMER_UNIT"; then
        rm -f "$timer_tmp"
        return 1
    fi
}

_set_timer() {
    local want="$1"
    command -v systemctl >/dev/null 2>&1 || _fail "systemctl not found"
    if [ "$want" = "1" ]; then
        mkdir -p "$SYSTEMD_USER_DIR"
        _write_update_units || _fail "failed to install systemd user units"
        systemctl --user daemon-reload || _fail "systemctl daemon-reload failed"
        systemctl --user enable --now "$TIMER_UNIT" >/dev/null \
            || _fail "could not enable $TIMER_UNIT"
    else
        systemctl --user disable --now "$TIMER_UNIT" >/dev/null 2>&1 || true
        systemctl --user daemon-reload
    fi
}

# Exits 0 (clearing the pending-update flag) when local is already at or ahead
# of remote. Exits 1 when the branches have diverged; the periodic pass also
# clears the flag there so a non-actionable badge doesn't linger, while an
# --apply retry keeps showing pending until the divergence is resolved.
_exit_if_not_behind() {
    local local_rev="$1" remote_rev="$2" periodic="$3"
    if git merge-base --is-ancestor "$remote_rev" "$local_rev"; then
        _clear_flag
        _clear_update_error
        exit 0
    fi
    if ! git merge-base --is-ancestor "$local_rev" "$remote_rev"; then
        if [ "$periodic" = "1" ]; then
            _clear_flag
            _quiet_fail "local branch has diverged from origin/main — update manually"
        fi
        _fail "local branch has diverged from origin/main — update manually"
    fi
}

if [ "${SILERE_SCRIPT_LIB_ONLY:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

trap _cleanup_candidate_stage EXIT
trap 'exit 130' INT TERM

# a distro package ships no .git, which is a supported install shape and not a
# failure — answer the read-only queries and never raise a critical popup for it
if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    case "${1:-}" in
        --version)
            # only a distro package writes package-version; a plain download has no updater at all
            if [ -r "$ROOT/package-version" ]; then
                packaged_version="$(head -n 1 "$ROOT/package-version")"
                packaged_mode=package
            else
                packaged_version="$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
                    "$ROOT/release.json" 2>/dev/null | head -n 1)"
                packaged_mode=copy
            fi
            printf 'packaged=1\nversion=%s\nmode=%s\n' "$packaged_version" "$packaged_mode"
            exit 0
            ;;
        --transaction-status) printf 'pending=0\n'; exit 0 ;;
        --recent|--timer-status) exit 0 ;;
    esac
    [ -r "$ROOT/package-version" ] \
        || _quiet_fail "$ROOT is not a git checkout — reinstall with scripts/install.sh to get updates"
    _quiet_fail "$ROOT is not a git checkout — update it through your package manager"
fi

case "${1:-}" in
    --version)
        _version_info
        exit 0
        ;;
    # read-only, so it runs outside the update lock like --version does
    --recent)
        git -C "$ROOT" log -10 --oneline --no-decorate HEAD 2>/dev/null || true
        exit 0
        ;;
    --timer-status)
        _timer_status
        exit 0
        ;;
    --transaction-status)
        if [ ! -e "$APPLY_JOURNAL" ]; then
            printf 'pending=0\n'
            exit 0
        fi
        if _read_apply_journal && _journal_release_is_trusted; then
            printf 'pending=1\nauthenticated=1\nphase=%s\nfrom=%s\nto=%s\ntag=%s\n' \
                "$JOURNAL_PHASE" "$JOURNAL_FROM" "$JOURNAL_TO" "$JOURNAL_TAG"
            exit 0
        fi
        printf 'pending=1\nauthenticated=0\nphase=unknown\n'
        exit 1
        ;;
    --timer-enable)
        _set_timer 1
        exit $?
        ;;
    --timer-disable)
        _set_timer 0
        exit $?
        ;;
esac

_acquire_update_lock

if [ "${1:-}" = "--rollback" ]; then
    _rollback_applied_update
    exit 0
fi
_recover_interrupted_apply

if [ "${1:-}" != --pin-release ] && [ "$(_installation_mode)" = development ]; then
    if [ "${1:-}" = --apply ]; then
        _fail "development checkout — updates are managed with Git"
    fi
    _clear_flag
    _clear_update_error
    printf 'silere-update: development checkout; updates are managed with Git\n'
    exit 0
fi

# --pin-release: land a fresh clone exactly on the newest signed release. --apply
# cannot do this: main carries commits past the tag, so the fast-forward path sees
# the clone as already ahead and returns without moving it.
if [ "${1:-}" = "--pin-release" ]; then
    pin_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [ "$pin_branch" = main ] \
        || _fail "checkout is on ${pin_branch:-a detached HEAD} — switch to main before pinning a release"
    if _has_local_changes; then
        _fail "local changes block pinning a release — run: bash $ROOT/scripts/repair.sh --apply"
    fi
    _fetch_main || _fail "git fetch failed (check network / connectivity)"
    _resolve_trusted_release pin
    if [ "$(git rev-parse HEAD)" != "$release_rev" ]; then
        git -C "$ROOT" reset --hard --quiet "$release_rev" \
            || _fail "could not move the checkout to $release_tag"
    fi
    _clear_flag
    _clear_update_error
    printf 'silere-update: pinned to %s\n' "$release_tag"
    exit 0
fi

# --apply: validate the already-fetched, signed release outside the live checkout,
# then fast-forward and restart. The trust check runs again so the cache flag is
# never authoritative.
if [ "${1:-}" = "--apply" ]; then
    apply_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [ -n "$apply_branch" ] \
        || _fail "checkout is on a detached HEAD — switch to main before applying"
    [ "$apply_branch" = main ] \
        || _fail "checkout is on branch $apply_branch — switch to main before applying"
    local_rev="$(git rev-parse HEAD)"
    git rev-parse --verify --quiet refs/remotes/origin/main >/dev/null 2>&1 \
        || _fail "origin/main is unavailable — check for updates again"
    _resolve_trusted_release apply
    remote_rev="$release_rev"
    _exit_if_not_behind "$local_rev" "$remote_rev" 0
    # The confirm screen names one release. A newer signed tag landing between the check
    # and the press is still trusted, but it is not what was agreed to — send it back
    # through a check rather than installing something the user never saw.
    cached_target="$(sed -n '2p' "$FLAG" 2>/dev/null || true)"
    if [[ ! "$cached_target" =~ ^target\ ([0-9a-f]{40}|[0-9a-f]{64})\ (v[0-9]+\.[0-9]+\.[0-9]+)\ verified$ ]]; then
        _fail "the confirmed release is missing or malformed — check for updates again"
    fi
    cached_rev="${BASH_REMATCH[1]}"
    cached_tag="${BASH_REMATCH[2]}"
    if [ "$cached_tag" != "$release_tag" ] || [ "$cached_rev" != "$release_rev" ]; then
        _fail "$release_tag is not the release that was confirmed ($cached_tag) — check for updates again"
    fi
    if _has_local_changes; then
        _fail "local changes block the update — run: bash $ROOT/scripts/repair.sh --apply"
    fi
    _create_candidate_stage \
        || _fail "could not create a detached staging worktree for $release_tag"
    if ! _candidate_tree_loads "$STAGE_DIR"; then
        _cleanup_candidate_stage
        _fail "the staged update does not load; the live installation was not changed"
    fi
    _cleanup_candidate_stage
    if [ -n "$CANDIDATE_GATE_NOTE" ]; then
        echo "silere-update: $CANDIDATE_GATE_NOTE" >&2
    fi

    # Validation takes long enough for an editor or a separate Git command to
    # change this checkout. The updater lock serializes Silere, not the user.
    [ "$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)" = main ] \
        || _fail "the checkout branch changed during staging — check for updates again"
    [ "$(git rev-parse HEAD 2>/dev/null || true)" = "$local_rev" ] \
        || _fail "the checkout revision changed during staging — check for updates again"
    if _has_local_changes; then
        _fail "local changes appeared during staging — review them before updating"
    fi
    _start_apply_transaction "$local_rev" "$remote_rev" "$release_tag" \
        || _fail "could not create the durable update recovery journal"
    # The candidate has already passed its gate. Recording that fact before the
    # fast-forward means an interruption after HEAD moves retains the proven tree;
    # an interruption while HEAD is still old simply clears the transaction.
    if ! _write_apply_journal validated "$local_rev" "$remote_rev" "$release_tag"; then
        _clear_apply_transaction || true
        _fail "could not record staged validation; the checkout was not changed"
    fi
    # git names the real reason here; "diverged" would point at the wrong thing
    if ! merge_err="$(git -C "$ROOT" merge --ff-only "$remote_rev" 2>&1)"; then
        # A normal fast-forward refusal leaves HEAD unchanged. Clear the journal
        # only when that is actually true; an unusual partial failure is safer
        # with recovery state retained.
        if [ "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)" = "$local_rev" ]; then
            _clear_apply_transaction || true
        fi
        merge_line="$(printf '%s\n' "$merge_err" \
            | sed -n 's/^error: //p; s/^fatal: //p' | head -n1)"
        [ -z "$merge_line" ] \
            && _fail "fast-forward merge failed — local branch diverged"
        # git lists offending paths tab-indented on the next lines
        merge_file="$(printf '%s\n' "$merge_err" | sed -n 's/^\t//p' | head -n1)"
        _fail "$merge_line${merge_file:+ $merge_file} — bash $ROOT/scripts/repair.sh --apply clears blocking files"
    fi
    sync -f -- "$ROOT" 2>/dev/null || true
    _clear_flag
    _clear_update_error
    new_rev="$(git rev-parse HEAD)"
    count="$(git rev-list --count "${local_rev}..${new_rev}")"
    plural="change"; [ "$count" -ne 1 ] && plural="changes"
    note_suffix=""
    [ -n "$CANDIDATE_GATE_NOTE" ] && note_suffix=" (${CANDIDATE_GATE_NOTE})"
    # systemd unit only exists on dev installs; exec-once users restart by hand
    if systemctl --user is-active --quiet silere-shell.service 2>/dev/null \
            && _unit_runs_this_checkout; then
        # Do not wait inside the shell's own process tree for systemd to stop that tree.
        # The journal stays until a later run sees the shell up on the new revision, so
        # a release that fails to come back can be restored with --rollback.
        if systemctl --user --no-block restart silere-shell.service; then
            printf 'silere-update: the shell was restarted; if it does not come back, run: bash %s --rollback\n' \
                "$ROOT/scripts/update.sh" >&2
        else
            _clear_apply_transaction || true
            _notify "Silere Shell updated" "$count new $plural$note_suffix — restart the shell to use it"
        fi
    else
        _clear_apply_transaction \
            || echo "silere-update: could not clear the completed update recovery journal" >&2
        _notify "Silere Shell updated" "$count new $plural$note_suffix — restart the shell to use it"
    fi
    exit 0
fi

# Default (check): fetch and flag a pending update; never restarts on its own, so
# the shell can surface an indicator instead of vanishing mid-session.

_fetch_main || _quiet_fail "git fetch failed (check network / connectivity)"

# Records a successful check whatever its outcome, so the shell can report when
# it last reached origin even after a restart or an unattended timer run.
local_rev="$(git rev-parse HEAD)"
_resolve_trusted_release check
remote_rev="$release_rev"

_write_cache_file "$CHECKED" "$(date +%s)" \
    || echo "silere-update: could not record the update check time" >&2

_exit_if_not_behind "$local_rev" "$remote_rev" 1

count="$(git rev-list --count "${local_rev}..${remote_rev}")"
summary="$(git log -5 --oneline --no-decorate "${local_rev}..${remote_rev}")"
target_tag="$release_tag"

_write_cache_file "$FLAG" "$count" \
    "target $remote_rev $target_tag verified" "$summary" \
    || _quiet_fail "failed to write update status"

_write_release_notes \
    || echo "silere-update: could not cache release notes; commit details remain available" >&2

_clear_update_error

# The badge is the persistent reminder. Notify once per pending revision, or a
# daily timer re-announces the same commits until they are installed.
if [ "$(cat "$NOTIFIED" 2>/dev/null || true)" != "$remote_rev" ]; then
    plural="change"; [ "$count" -ne 1 ] && plural="changes"
    _notify "Silere Shell $target_tag ready" \
        "$count $plural · release signature verified — review and install from the bar"
    # If this bookkeeping write fails, keep the successful update check and
    # simply allow the next periodic pass to retry the advisory notification.
    _write_cache_file "$NOTIFIED" "$remote_rev" \
        || echo "silere-update: could not record update notification" >&2
fi
