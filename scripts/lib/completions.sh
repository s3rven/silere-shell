# shellcheck shell=bash

# prints "source<TAB>link" per shell; fish and bash-completion read these per-user dirs on their own.
# "all" also lists shells that are not installed, so an uninstall still finds their links
_silere_completion_links() {
    local root="$1" scope="${2:-}" data_home
    data_home="$(_silere_xdg_home "${XDG_DATA_HOME:-}" .local/share)" || return 1
    if [ "$scope" = all ] || command -v fish >/dev/null 2>&1; then
        printf '%s\t%s\n' "$root/scripts/completions/silere.fish" \
            "$data_home/fish/vendor_completions.d/silere.fish"
    fi
    if [ "$scope" = all ] || [ -f /usr/share/bash-completion/bash_completion ]; then
        printf '%s\t%s\n' "$root/scripts/completions/silere.bash" \
            "$data_home/bash-completion/completions/silere"
    fi
}
