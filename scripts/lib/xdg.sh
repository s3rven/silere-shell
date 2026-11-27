# shellcheck shell=bash
# Shared by install.sh, uninstall.sh, update.sh, and check.sh: one XDG path rule

# a path for a hint to paste: single quotes read the same in bash, zsh and fish, where printf %q under the scripts'
# C locale writes a non-ASCII name as $'\303\251', which fish cannot read
_silere_pasteable() {
    local s="$1"
    printf "'%s'" "${s//\'/\'\\\'\'}"
}

# sudo and doas run a script as root with root's home and user services, none of which the person's session reads, and
# leave root-owned files in their checkout that their own updates then cannot replace. Root without them (CI) is fine
_silere_refuse_elevated() { # $1 = the script's name in its messages
    local from="${SUDO_USER:-${DOAS_USER:-}}"
    [ -n "$from" ] && [ "$from" != root ] && [ "$(id -u)" = 0 ] || return 0
    printf '%s: run this as %s, without sudo or doas; Silere works on your own session and never needs root\n' \
        "$1" "$from" >&2
    exit 1
}

_silere_xdg_home() {
    local configured="${1:-}" fallback="$2"
    case "$configured" in
        /*) printf '%s\n' "$configured" ;;
        *)
            case "${HOME:-}" in
                /*) printf '%s/%s\n' "$HOME" "$fallback" ;;
                *) return 1 ;;
            esac
            ;;
    esac
}
