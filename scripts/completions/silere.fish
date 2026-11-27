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

# the short verbs complete by position: `silere menu settings` holds a command's name as an argument
function __silere_verb_at --argument-names verb n
    set -l args (__silere_args)
    test "$args[2]" = $verb; and test (count $args) -eq (math $n + 2)
end

function __silere_menu_page
    set -l args (__silere_args)
    test (count $args) -eq 3; and test "$args[2]" = menu; and test "$args[3]" = settings
end

function __silere_set_value
    set -l args (__silere_args)
    test (count $args) -eq 3; and test "$args[2]" = set
end

function __silere_bool_keys
    command silere ipc settings list '' 2>/dev/null | string replace -rf '^(\w+)=(.*)  \[true\|false\]$' '$1\t$2'
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

function __silere_setting_values --argument-names at
    test -n "$at"; or set at 5
    set -l args (__silere_args)
    set -l key $args[$at]
    command silere ipc settings list '' 2>/dev/null \
        | string replace -rf "^$key=.*  \[([^/].*\|.*)\]\$" '$1' | string split '|'
end

set -l commands try reset run stop restart use status log doctor ipc link update repair service version uninstall help \
    menu calendar quick tray toggle volume mic dismiss osd theme indicator get set settings
# Settings pages are the rail's ids in services/SettingsTree.js, which ci-lint holds this list to
set -l pages clock devices history indicators interface keybinds media osd popups separators surface theme underline \
    updates warnings widgets workspaces

complete -c silere -f
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a menu -d 'Open or close the menu'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a calendar -d 'Open or close the calendar'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a quick -d 'Open or close quick actions'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a tray -d "The first tray app's menu"
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a toggle -d 'Flip a quick action or an on/off setting'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a volume -d 'Output volume'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a mic -d 'Microphone volume'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a dismiss -d 'Dismiss the newest notification popup'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a osd -d "Show a script's message in the OSD"
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a theme -d 'Take the accent from a picture'
complete -c silere -n '__silere_verb_at theme 0' -F
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a indicator -d "A script's own mark in the bar"
complete -c silere -n '__silere_verb_at indicator 0' -a 'set clear list'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a get -d 'Print a setting'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a set -d 'Change a setting'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a settings -d 'List settings and their values'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a run -d 'Start Silere once'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a stop -d 'Stop Silere and its user service'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a restart -d 'Stop the running shell and start it again'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a use -d 'Switch the checkout that runs'
complete -c silere -n '__fish_seen_subcommand_from use' -a '(__fish_complete_directories)'
complete -c silere -n '__fish_seen_subcommand_from use' -l dry-run -d 'Preview switching checkouts'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a status -d 'Installation and updater state'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a log -d "The running shell's log"
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a doctor -d 'Read-only installation diagnostics'
complete -c silere -n '__fish_seen_subcommand_from doctor' -l json -d 'Print a diagnostic summary as JSON'
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
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a try -d 'Preview Silere in a window, changing nothing'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a reset -d 'Reset settings, edited files and caches'
complete -c silere -n '__fish_seen_subcommand_from reset' -l apply -d 'Do the reset'
complete -c silere -n '__fish_seen_subcommand_from reset' -l undo -d 'Put back what the last reset replaced'
complete -c silere -n '__fish_seen_subcommand_from reset' -l history -d 'Also clear notification history'
complete -c silere -n '__fish_seen_subcommand_from reset' -l yes -d 'Skip the confirmation'
complete -c silere -n '__fish_seen_subcommand_from repair' -l apply -d 'Save local changes, restore shipped files'
complete -c silere -n '__fish_seen_subcommand_from repair' -l undo -d 'Restore the latest repair stash'
complete -c silere -n '__fish_seen_subcommand_from repair; and __fish_seen_subcommand_from --apply --undo' -l yes -d 'Skip the confirmation'

complete -c silere -n '__silere_ipc_at 0' -a '(__silere_ipc_targets)'
complete -c silere -n '__silere_ipc_at 1' -a '(__silere_ipc_functions)'
complete -c silere -n __silere_setting_key -a '(__silere_setting_keys)'
complete -c silere -n __silere_setting_value -a '(__silere_setting_values)'

complete -c silere -n '__fish_seen_subcommand_from run' -l supervised -d 'Start through the user service'
complete -c silere -n "not __fish_seen_subcommand_from $commands" -a service -d 'Manage supervised startup'
complete -c silere -n '__fish_seen_subcommand_from service; and not __fish_seen_subcommand_from install status remove' -a 'install status remove'
complete -c silere -n '__fish_seen_subcommand_from service; and __fish_seen_subcommand_from install; and not contains -- --dry-run (commandline -opc)' -l dry-run -d 'Preview service installation'

complete -c silere -n '__silere_verb_at menu 0' -a 'home settings notifications playing close' -d 'Menu tab'
complete -c silere -n '__silere_verb_at menu 0' -a "$pages" -d 'Settings page'
complete -c silere -n __silere_menu_page -a "$pages" -d 'Settings page'
complete -c silere -n '__silere_verb_at calendar 0; or __silere_verb_at quick 0; or __silere_verb_at tray 0' -a close
complete -c silere -n '__silere_verb_at volume 0; or __silere_verb_at mic 0' -a 'up down mute next'
complete -c silere -n '__silere_verb_at dismiss 0' -a all -d 'Every popup on screen'
complete -c silere -n '__silere_verb_at toggle 0' -a 'dnd wifi bluetooth airplane night-light keep-awake presentation power-mode' \
    -d 'Quick action'
complete -c silere -n '__silere_verb_at toggle 0' -a '(__silere_bool_keys)'
complete -c silere -n '__silere_verb_at get 0; or __silere_verb_at set 0' -a '(__silere_setting_keys)'
complete -c silere -n __silere_set_value -a '(__silere_setting_values 3)'
complete -c silere -n '__silere_verb_at settings 0' -l changed -d 'Only the settings you changed'
complete -c silere -n '__silere_verb_at settings 0' -a "$pages" -d 'Settings page'
