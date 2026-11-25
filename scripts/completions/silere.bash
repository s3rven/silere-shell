# shellcheck shell=bash

# ipc targets, functions and settings come from the running shell, so they match its version; Settings pages are
# MenuState's ids, which ci-lint holds this list to
_silere_pages=(clock devices history indicators interface keybinds media osd popups separators surface theme underline
    updates warnings widgets workspaces)

_silere() {
    local cur="${COMP_WORDS[COMP_CWORD]}" words=() line target current=""
    COMPREPLY=()
    if [ "$COMP_CWORD" -eq 1 ]; then
        words=(try reset run stop restart use status log doctor ipc link update repair service version uninstall help
            menu calendar quick tray toggle volume mic dismiss osd theme indicator get set settings)
    else
        case "${COMP_WORDS[1]}" in
            menu)
                if [ "$COMP_CWORD" -eq 2 ]; then words=(home settings notifications playing close "${_silere_pages[@]}")
                elif [ "$COMP_CWORD" -eq 3 ] && [ "${COMP_WORDS[2]}" = settings ]; then words=("${_silere_pages[@]}")
                fi ;;
            calendar|quick|tray) [ "$COMP_CWORD" -eq 2 ] && words=(close) ;;
            # as for use: readline quotes names with spaces and adds a slash to folders
            theme) [ "$COMP_CWORD" -eq 2 ] && { compopt -o filenames 2>/dev/null || true
                mapfile -t COMPREPLY < <(compgen -f -- "$cur"); return; } ;;
            indicator) [ "$COMP_CWORD" -eq 2 ] && words=(set clear list) ;;
            volume|mic) [ "$COMP_CWORD" -eq 2 ] && words=(up down mute next) ;;
            dismiss) [ "$COMP_CWORD" -eq 2 ] && words=(all) ;;
            settings) [ "$COMP_CWORD" -eq 2 ] && words=(--changed "${_silere_pages[@]}") ;;
            toggle|get|set)
                [ "$COMP_CWORD" -eq 2 ] && [ "${COMP_WORDS[1]}" = toggle ] \
                    && words=(dnd wifi bluetooth airplane night-light keep-awake presentation power-mode)
                if [ "$COMP_CWORD" -eq 2 ] || { [ "$COMP_CWORD" -eq 3 ] && [ "${COMP_WORDS[1]}" = set ]; }; then
                    while IFS= read -r line; do
                        if [ "$COMP_CWORD" -eq 3 ]; then
                            [ "${line%%=*}" = "${COMP_WORDS[2]}" ] && [[ "$line" =~ \ \ \[([^/][^]]*[|][^]]*)\]$ ]] \
                                && IFS='|' read -r -a words <<< "${BASH_REMATCH[1]}"
                        elif [ "${COMP_WORDS[1]}" != toggle ] || [[ "$line" == *"  [true|false]" ]]; then
                            words+=("${line%%=*}")
                        fi
                    done < <(command silere ipc settings list '' 2>/dev/null)
                fi ;;
            run) [ "$COMP_CWORD" -eq 2 ] && words=(--startup --supervised) ;;
            use)
                words=(--dry-run)
                # readline adds directories and quotes names containing spaces
                compopt -o plusdirs -o filenames 2>/dev/null || true
                ;;
            log) [ "$COMP_CWORD" -eq 2 ] && words=(--follow) ;;
            doctor) [ "$COMP_CWORD" -eq 2 ] && words=(--json --help) ;;
            update) [ "$COMP_CWORD" -eq 2 ] && words=(--apply --rollback) ;;
            repair) words=(--apply --undo --yes) ;;
            reset) words=(--apply --undo --history --yes) ;;
            service)
                # one of its words, then --dry-run only after install
                if [ "$COMP_CWORD" -eq 2 ]; then words=(install status remove)
                elif [ "$COMP_CWORD" -eq 3 ] && [ "${COMP_WORDS[2]}" = install ]; then words=(--dry-run)
                fi ;;
            ipc)
                if [ "$COMP_CWORD" -eq 2 ]; then
                    while IFS= read -r line; do
                        [[ "$line" =~ ^target\ ([^[:space:]]+)$ ]] && words+=("${BASH_REMATCH[1]}")
                    done < <(command silere ipc show 2>/dev/null)
                elif [ "$COMP_CWORD" -eq 3 ]; then
                    target="${COMP_WORDS[2]}"
                    while IFS= read -r line; do
                        if [[ "$line" =~ ^target\ ([^[:space:]]+)$ ]]; then
                            current="${BASH_REMATCH[1]}"
                        elif [ "$current" = "$target" ] \
                                && [[ "$line" =~ ^[[:space:]]+function\ ([A-Za-z0-9_]+)\( ]]; then
                            words+=("${BASH_REMATCH[1]}")
                        fi
                    done < <(command silere ipc show 2>/dev/null)
                elif [ "${COMP_WORDS[2]}" = settings ]; then
                    while IFS= read -r line; do
                        if [ "$COMP_CWORD" -eq 4 ]; then
                            case "${COMP_WORDS[3]}" in get|set|toggle) words+=("${line%%=*}") ;; esac
                        elif [ "$COMP_CWORD" -eq 5 ] && [ "${COMP_WORDS[3]}" = set ] \
                                && [ "${line%%=*}" = "${COMP_WORDS[4]}" ] \
                                && [[ "$line" =~ \ \ \[([^/][^]]*[|][^]]*)\]$ ]]; then
                            IFS='|' read -r -a words <<< "${BASH_REMATCH[1]}"
                        fi
                    done < <(command silere ipc settings list '' 2>/dev/null)
                fi
                ;;
        esac
    fi
    mapfile -t COMPREPLY < <(compgen -W "${words[*]}" -- "$cur")
}
complete -F _silere silere
