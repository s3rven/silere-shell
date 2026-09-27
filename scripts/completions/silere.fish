# ipc targets, functions and settings come from the running shell, so they match its version

function __silere_args
    commandline -xpc 2>/dev/null; or commandline -opc
end

function __silere_ipc_at --argument-names n
    set -l args (__silere_args)
    test "$args[2]" = ipc; and test (count $args) -eq (math $n + 2)
end

function __silere_setting_key
    set -l args (__silere_args)
    test (count $args) -eq 4; and test "$args[2]" = ipc; and test "$args[3]" = settings
    and contains -- "$args[4]" get set toggle
end

function __silere_setting_value
    set -l args (__silere_args)
    test (count $args) -eq 5; and test "$args[2]" = ipc; and test "$args[3]" = settings
    and test "$args[4]" = set
end

function __silere_ipc_targets
    command silere ipc show 2>/dev/null | string replace -rf '^target (\S+)$' '$1'
end

function __silere_ipc_functions
    set -l target (__silere_args)[3]
    set -l current
    command silere ipc show 2>/dev/null | while read -l line
        if string match -qr '^target ' -- $line
            set current (string replace 'target ' '' -- $line)
        else if test "$current" = "$target"
            string replace -rf '^\s+function (\w+)\((.*)\).*$' '$1\t$2' -- $line
        end
    end
end

function __silere_setting_keys
    command silere ipc settings list '' 2>/dev/null | string replace -rf '^(\w+)=(.*)  \[.*\]$' '$1\t$2'
end

function __silere_setting_values
    set -l key (__silere_args)[5]
    command silere ipc settings list '' 2>/dev/null \
        | string replace -rf "^$key=.*  \[([^/].*\|.*)\]\$" '$1' | string split '|'
end

set -l commands run restart status log doctor ipc link update repair version uninstall help

complete -c silere -f
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a run -d 'Start Silere once'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a restart -d 'Stop the running shell and start it again'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a status -d 'Installation and updater state'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a log -d "The running shell's log"
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a doctor -d 'Read-only installation diagnostics'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a ipc -d 'Call the running shell'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a link -d 'Put silere on PATH'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a update -d 'Check for a signed release'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a repair -d 'Restore shipped files'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a version -d 'Installed version'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a uninstall -d 'Remove installer integrations'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a help -d 'List the commands'

complete -c silere -n '__fish_seen_subcommand_from run' -l startup -d 'Wait for the compositor'
complete -c silere -n '__fish_seen_subcommand_from log' -s f -l follow -d 'Keep printing new lines'
complete -c silere -n '__fish_seen_subcommand_from update' -l apply -d 'Install the confirmed release'
complete -c silere -n '__fish_seen_subcommand_from update' -l rollback -d 'Restore the replaced revision'
complete -c silere -n '__fish_seen_subcommand_from repair' -l apply -d 'Save local changes, restore shipped files'
complete -c silere -n '__fish_seen_subcommand_from repair' -l undo -d 'Restore the latest repair stash'
complete -c silere -n '__fish_seen_subcommand_from repair' -l yes -d 'Skip the confirmation'

complete -c silere -n '__silere_ipc_at 0' -a '(__silere_ipc_targets)'
complete -c silere -n '__silere_ipc_at 1' -a '(__silere_ipc_functions)'
complete -c silere -n __silere_setting_key -a '(__silere_setting_keys)'
complete -c silere -n __silere_setting_value -a '(__silere_setting_values)'
