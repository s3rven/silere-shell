# shellcheck shell=bash
# The newest Quickshell crash report of this shell as "<epoch>\t<report>\t<version>\t<signal>"; fails when there is none.
# $1 is the shell's own shell.qml: a report naming another config, such as another Quickshell app's, is not this one
_silere_last_crash() {
    local dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/crashes" report config
    # shellcheck disable=SC2012
    report="$(ls -t "$dir"/report.txt "$dir"/*/report.txt 2>/dev/null | head -n 1)"
    [ -n "$report" ] && [ -r "$report" ] || return 1
    config="$(sed -n 's/^Config Path: //p' "$report" | head -n 1)"
    # Quickshell 0.3.2 leaves the instance fields empty; the log it saves beside the report names the config it ran
    if [ -z "$config" ] && [ -r "${report%/*}/log.qslog.log" ]; then
        config="$(grep -a -o -m 1 'Launching config: "[^"]*"' -- "${report%/*}/log.qslog.log" || true)"
        config="${config%%$'\n'*}"
        config="${config#Launching config: \"}"
        config="${config%\"}"
    fi
    case "$config" in ''|"${1:-}"|"$(dirname -- "${1:-/}")") ;; *) return 1 ;; esac
    printf '%s\t%s\t%s\t%s\n' "$(stat -c %Y -- "$report")" "$report" \
        "$(sed -n 's/^Quickshell: \([0-9][0-9.]*\).*/\1/p' "$report" | head -n 1)" \
        "$(sed -n 's/^Signal: //p' "$report" | head -n 1)"
}
