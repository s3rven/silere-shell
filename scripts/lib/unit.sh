# shellcheck shell=bash

# Qt checks whether this variable exists, including empty and zero values.
_silere_unit_uses_transient_images() {
    local unit_env
    unit_env="$(systemctl --user show silere-shell.service -p Environment --value 2>/dev/null)" || return 1
    [[ "$unit_env" =~ (^|[[:space:]\"])QSG_TRANSIENT_IMAGES= ]]
}

# systemd prints ExecStart as "{ path=... ; argv[]=prog args ; ... }"; a `silere` link resolves via readlink
_silere_unit_runs_checkout() {
    local root="$1" exec_start argv prog
    exec_start="$(systemctl --user show silere-shell.service -p ExecStart --value 2>/dev/null)" || return 1
    case "$exec_start" in *"argv[]="*) ;; *) return 1 ;; esac
    argv="${exec_start#*"argv[]="}"
    argv="${argv%% ;*}"
    case " $argv " in
        *" $root/scripts/silere run "*) return 0 ;;
        *" $root/shell.qml "*|*" $root "*|*" $root/ "*) return 0 ;;
        *" run "*) ;;
        *) return 1 ;;
    esac
    prog="$(readlink -f -- "${argv%% *}" 2>/dev/null)" || return 1
    [ "$prog" = "$root/scripts/silere" ]
}

# the checkout the user unit starts: a silere launcher (or a link to one), or qs -p <dir|shell.qml>
_silere_unit_checkout() {
    local exec_start argv prog root=""
    exec_start="$(systemctl --user show silere-shell.service -p ExecStart --value 2>/dev/null)" || return 1
    case "$exec_start" in *"argv[]="*) ;; *) return 1 ;; esac
    argv="${exec_start#*"argv[]="}"
    argv="${argv%% ;*}"
    prog="${argv%% *}"
    case "$prog" in
        */silere) prog="$(readlink -f -- "$prog" 2>/dev/null)" || return 1
            root="${prog%/scripts/silere}" ;;
        *) case " $argv " in *" -p "*) ;; *) return 1 ;; esac
            root="${argv#* -p }"; root="${root%% *}"; root="${root%/}"; root="${root%/shell.qml}" ;;
    esac
    [ -n "$root" ] && [ -f "$root/shell.qml" ] || return 1
    printf '%s\n' "$root"
}

# a path inside a quoted ExecStart argument: systemd expands \ " % and $ there
_silere_unit_exec_quote() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//%/%%}"
    s="${s//\$/\$\$}"
    printf '"%s"' "$s"
}
