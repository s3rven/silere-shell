# shellcheck shell=bash

_silere_network_metered() {
    local service=org.freedesktop.NetworkManager status
    if status="$(busctl --system --auto-start=no --timeout=2 call "$service" \
            /org/freedesktop/NetworkManager org.freedesktop.DBus.Properties Get ss \
            "$service" Metered 2>/dev/null)"; then
        # NetworkManager reports both explicit and inferred metering on the primary connection.
        case "$status" in
            'v u 1'|'v u 3') return 0 ;;
            'v u 0'|'v u 2'|'v u 4') return 1 ;;
        esac
    fi

    # On systems without busctl, nmcli reads the same property from the running daemon.
    status="$(LC_ALL=C nmcli --wait 2 --colors no --get-values METERED general status 2>/dev/null)" \
        || return 1
    [ "$status" = yes ] || [ "$status" = 'yes (guessed)' ]
}
