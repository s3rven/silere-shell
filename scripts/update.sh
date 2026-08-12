#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/xdg.sh"
cd "$ROOT"

CACHE_HOME="$(_silere_xdg_home "${XDG_CACHE_HOME:-}" .cache)" || {
    printf 'silere-update: HOME must be an absolute path\n' >&2
    exit 1
}
CONFIG_HOME="$(_silere_xdg_home "${XDG_CONFIG_HOME:-}" .config)" || {
    printf 'silere-update: HOME must be an absolute path\n' >&2
    exit 1
}
CACHE_DIR="$CACHE_HOME/silere-shell"
FLAG="$CACHE_DIR/update-pending"
NOTIFIED="$CACHE_DIR/update-notified"
CHECKED="$CACHE_DIR/update-checked"
TIMER_UNIT="silere-update.timer"
SERVICE_UNIT="silere-update.service"
SYSTEMD_USER_DIR="$CONFIG_HOME/systemd/user"
TRUSTED_SIGNERS="$ROOT/security/update-signers"

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
    echo "silere-update: $1" >&2
    exit 1
}

_fail() {
    _notify -u critical "Silere update failed" "$1"
    _quiet_fail "$1"
}

_clear_flag() {
    rm -f "$FLAG" "$NOTIFIED"
}

_ensure_cache_dir() {
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

_has_local_changes() {
    [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=normal)" ]
}

# A blackholed network keeps a fetch running past the shell's own check timeout,
# and the orphan inherits the update lock's fd — wedging every later run behind
# it. The systemd path is already capped by TimeoutStartSec; this covers the rest.
_git_fetch() {
    if command -v timeout >/dev/null 2>&1; then
        GIT_TERMINAL_PROMPT=0 timeout 90 git fetch --quiet "$@"
    else
        GIT_TERMINAL_PROMPT=0 git fetch --quiet "$@"
    fi
}

_fetch_main() {
    local shallow
    shallow="$(git -C "$ROOT" rev-parse --is-shallow-repository 2>/dev/null || true)"
    if [ "$shallow" = true ]; then
        # Older installer releases used --depth 1. Tags alone do not cross that
        # boundary, so git describe cannot recover the installed release until
        # the main-branch history is completed once.
        _git_fetch --unshallow --tags origin main
    else
        _git_fetch --tags origin main
    fi
}

_latest_release_tag() {
    local tag
    while IFS= read -r tag; do
        if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            printf '%s\n' "$tag"
            return 0
        fi
    done < <(git -C "$ROOT" tag --merged origin/main --list 'v*' --sort=-v:refname)
    return 1
}

_release_fail() {
    local mode="$1" message="$2"
    if [ "$mode" = apply ]; then _fail "$message"; fi
    _clear_flag
    _quiet_fail "$message"
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
    git -C "$ROOT" merge-base --is-ancestor "$release_rev" origin/main \
        || _release_fail "$mode" "$release_tag is not part of origin/main"
}

# A failed load makes qs exit non-zero at once, and the service restarts it every
# few seconds forever — no bar, no menu, and no UI left to roll back from. Type-check
# the merged tree first (~15s) and only restart into it if it actually loads. Skipping
# the gate when the checker or qs is missing keeps the updater usable without them.
# The unit name is fixed, so a --apply run from a second checkout would otherwise
# restart whichever shell is live, not the one it just updated. systemd expands %h
# in ExecStart before reporting it, so the resolved path is safe to match on.
_unit_runs_this_checkout() {
    local exec_start
    exec_start="$(systemctl --user show silere-shell.service -p ExecStart --value 2>/dev/null || true)"
    case "$exec_start" in
        *" $ROOT/shell.qml"*) return 0 ;;
        *) return 1 ;;
    esac
}

# The type-check compiles every file but never loads shell.qml, and a missing
# property or unresolvable type surfaces only at load — which is precisely the
# break this gate exists to catch. Launching for real is the only thing that
# sees it. Offscreen cannot stand in: with no PanelWindow backend every tree
# fails alike. Skipped when a display, timeout or the theme is missing, so a
# headless or bare checkout is never rolled back over a condition of its own.
_merged_tree_starts() {
    command -v timeout >/dev/null 2>&1 || return 0
    [ -n "${WAYLAND_DISPLAY:-}" ] || return 0
    [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ] || return 0
    [ -f "$ROOT/config/MatugenPalette.qml" ] || return 0
    local log code=0 verdict=0
    log="$(mktemp "${TMPDIR:-/tmp}/silere-update-smoke.XXXXXX.log")" || return 0
    timeout 5s qs -p "$ROOT/shell.qml" --no-color >"$log" 2>&1 || code=$?
    # 124 is the timeout firing, i.e. it stayed up for the whole window
    if [ "$code" -ne 0 ] && [ "$code" -ne 124 ]; then
        # an unreachable display is not the update's fault; never roll back over it
        grep -qE 'Failed to create wl_display|could not connect to display|no Qt platform plugin could be initialized' "$log" \
            || verdict=1
    elif grep -qE 'Failed to load configuration|Type [^ ]+ unavailable|module ".*" is not installed' "$log"; then
        verdict=1
    fi
    rm -f "$log"
    return "$verdict"
}

_merged_tree_loads() {
    [ -r "$ROOT/scripts/test-qml-headless.sh" ] || return 0
    command -v qs >/dev/null 2>&1 || return 0
    bash "$ROOT/scripts/test-qml-headless.sh" >/dev/null 2>&1 || return 1
    _merged_tree_starts
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
    local head tag ahead=0 branch dirty=0
    head="$(git -C "$ROOT" log -1 --format='%h %cs')"
    tag="$(git -C "$ROOT" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
    if [ -n "$tag" ]; then
        ahead="$(git -C "$ROOT" rev-list --count "$tag..HEAD" 2>/dev/null || echo 0)"
    fi
    branch="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if _has_local_changes; then dirty=1; fi
    printf 'sha=%s\ndate=%s\ntag=%s\nahead=%s\nbranch=%s\ndirty=%s\n' \
        "${head%% *}" "${head##* }" "$tag" "$ahead" "$branch" "$dirty"
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

# a distro package ships no .git, which is a supported install shape and not a
# failure — answer the read-only queries and never raise a critical popup for it
if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    case "${1:-}" in
        --version)               printf 'packaged=1\n'; exit 0 ;;
        --recent|--timer-status) exit 0 ;;
    esac
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

# --apply: fast-forward to the already-fetched, signed release and restart the
# shell. The trust check runs again so the cache flag is never authoritative.
if [ "${1:-}" = "--apply" ]; then
    apply_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [ -n "$apply_branch" ] \
        || _fail "checkout is on a detached HEAD — switch to main before applying"
    [ "$apply_branch" = main ] \
        || _fail "checkout is on branch $apply_branch — switch to main before applying"
    local_rev="$(git rev-parse HEAD)"
    git rev-parse origin/main >/dev/null 2>&1 \
        || _fail "origin/main is unavailable — check for updates again"
    _resolve_trusted_release apply
    remote_rev="$release_rev"
    _exit_if_not_behind "$local_rev" "$remote_rev" 0
    if _has_local_changes; then
        _fail "local changes detected — commit or stash them before applying the update"
    fi
    if ! git -C "$ROOT" merge --ff-only --quiet "$remote_rev"; then
        _fail "fast-forward merge failed — local branch diverged"
    fi
    if ! _merged_tree_loads; then
        git -C "$ROOT" reset --hard --quiet "$local_rev" \
            || _fail "the update does not load and the checkout could not be rolled back — reset to $local_rev by hand"
        _fail "the update does not load and was rolled back — the shell was left running"
    fi
    _clear_flag
    new_rev="$(git rev-parse HEAD)"
    count="$(git rev-list --count "${local_rev}..${new_rev}")"
    plural="change"; [ "$count" -ne 1 ] && plural="changes"
    # systemd unit only exists on dev installs; exec-once users restart by hand
    if systemctl --user is-active --quiet silere-shell.service 2>/dev/null \
            && _unit_runs_this_checkout; then
        systemctl --user restart silere-shell.service
    else
        _notify "Silere Shell updated" "$count new $plural — restart the shell to use it"
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
    "target $(git rev-parse --short "$remote_rev") $target_tag verified" "$summary" \
    || _quiet_fail "failed to write update status"

# The badge is the persistent reminder. Notify once per pending revision, or a
# daily timer re-announces the same commits until they are installed.
if [ "$(cat "$NOTIFIED" 2>/dev/null || true)" != "$remote_rev" ]; then
    plural="change"; [ "$count" -ne 1 ] && plural="changes"
    _notify "Silere Shell update ready" "$count new $plural ready — install from the bar$([ -n "$summary" ] && printf '\n%s' "$summary")"
    # If this bookkeeping write fails, keep the successful update check and
    # simply allow the next periodic pass to retry the advisory notification.
    _write_cache_file "$NOTIFIED" "$remote_rev" \
        || echo "silere-update: could not record update notification" >&2
fi
