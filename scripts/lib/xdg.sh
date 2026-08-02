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
