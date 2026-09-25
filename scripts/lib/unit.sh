# shellcheck shell=bash

# systemd prints ExecStart as "{ path=... ; argv[]=prog args ; ... }"; a `silere` link resolves via readlink
_silere_unit_runs_checkout() {
    local root="$1" exec_start argv prog
    exec_start="$(systemctl --user show silere-shell.service -p ExecStart --value 2>/dev/null)" || return 1
    case "$exec_start" in *"argv[]="*) ;; *) return 1 ;; esac
    argv="${exec_start#*"argv[]="}"
    argv="${argv%% ;*}"
    case " $argv " in
        *" $root/shell.qml "*|*" $root "*|*" $root/ "*) return 0 ;;
        *" run "*) ;;
        *) return 1 ;;
    esac
    prog="$(readlink -f -- "${argv%% *}" 2>/dev/null)" || return 1
    [ "$prog" = "$root/scripts/silere" ]
}
