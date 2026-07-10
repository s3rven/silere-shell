#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

_usage() {
    cat <<'EOF'
Usage:
  bash scripts/repair.sh             Preview local changes
  bash scripts/repair.sh --apply     Save local changes and restore shipped files
  bash scripts/repair.sh --undo      Restore the latest repair stash

Add --yes after --apply or --undo to skip the confirmation prompt.
EOF
}

_die() {
    printf 'silere-repair: %s\n' "$*" >&2
    exit 1
}

_changes() {
    git status --short --untracked-files=normal
}

_latest_repair_stash() {
    local line
    while IFS= read -r line; do
        case "$line" in
            *"silere-repair "*)
                printf '%s\n' "${line%%$'\t'*}"
                return 0
                ;;
        esac
    done < <(git stash list --format='%gd%x09%gs')
    return 1
}

_confirm() {
    local prompt="$1" reply
    if [ "${ASSUME_YES:-0}" = "1" ]; then
        return 0
    fi
    [ -r /dev/tty ] || _die "confirmation needs a terminal; add --yes to run non-interactively"
    printf '%s [y/N] ' "$prompt" >/dev/tty
    read -r reply </dev/tty
    [[ "$reply" =~ ^[Yy]$ ]]
}

[ -d .git ] || _die "not a Git checkout: $ROOT"

action="${1:---preview}"
case "${2:-}" in
    "") ;;
    --yes) ASSUME_YES=1 ;;
    *) _usage; exit 2 ;;
esac

case "$action" in
    -h|--help)
        _usage
        ;;

    --preview)
        changes="$(_changes)"
        if [ -z "$changes" ]; then
            printf 'Silere files already match the installed revision.\n'
            if stash_ref="$(_latest_repair_stash 2>/dev/null)"; then
                printf 'Latest saved repair: %s (restore with --undo)\n' "$stash_ref"
            fi
            exit 0
        fi
        printf 'Local changes that would be saved:\n%s\n\n' "$changes"
        printf 'Nothing was changed. Run `bash scripts/repair.sh --apply` to repair the checkout.\n'
        ;;

    --apply)
        changes="$(_changes)"
        if [ -z "$changes" ]; then
            printf 'Silere files already match the installed revision.\n'
            exit 0
        fi
        printf 'Local changes to save:\n%s\n\n' "$changes"
        _confirm "Save these edits and restore the installed Silere files?" || {
            printf 'Cancelled; nothing was changed.\n'
            exit 0
        }

        label="silere-repair $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        git stash push --include-untracked -m "$label" >/dev/null \
            || _die "could not save local changes"
        [ -z "$(_changes)" ] || _die "some local changes remain; inspect them with git status"

        stash_ref="$(_latest_repair_stash)" || _die "changes were saved, but the repair stash could not be located"
        printf 'Silere restored to the installed revision.\n'
        printf 'Your edits are safe in %s; restore them with `bash scripts/repair.sh --undo`.\n' "$stash_ref"
        ;;

    --undo)
        [ -z "$(_changes)" ] || _die "the checkout has new local changes; save or remove them before restoring an older repair"
        stash_ref="$(_latest_repair_stash 2>/dev/null)" || _die "no repair stash found"
        _confirm "Restore edits from $stash_ref?" || {
            printf 'Cancelled; nothing was changed.\n'
            exit 0
        }

        if git stash pop "$stash_ref" >/dev/null; then
            printf 'Restored edits from %s.\n' "$stash_ref"
        else
            _die "the edits conflict with this revision; Git kept $stash_ref so nothing is lost"
        fi
        ;;

    *)
        _usage
        exit 2
        ;;
esac
