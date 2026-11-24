# shellcheck shell=bash
# Shared by install.sh, uninstall.sh, doctor.sh and silere: one set of status lines and one
# TTY test. Colors are the terminal's own ANSI palette, off when piped or NO_COLOR is set.

_silere_color_fd() { [ -t "$1" ] && [ -z "${NO_COLOR:-}" ]; }

# the sourcing scripts read these
# shellcheck disable=SC2034
if _silere_color_fd 1; then
    R=$'\033[0m' BOLD=$'\033[1m'
    GREEN=$'\033[0;32m' CYAN=$'\033[0;36m' YELLOW=$'\033[1;33m' DIM=$'\033[2m' RED=$'\033[0;31m'
else
    R='' BOLD='' GREEN='' CYAN='' YELLOW='' DIM='' RED=''
fi
# stderr is tested on its own, so a redirected error log never collects escape codes
# shellcheck disable=SC2034
if _silere_color_fd 2; then
    ER=$'\033[0m' ERED=$'\033[0;31m' EYELLOW=$'\033[1;33m'
else
    ER='' ERED='' EYELLOW=''
fi

# shellcheck disable=SC2059
_ok()   { printf "    ${GREEN}ok${R}      %s\n" "$*"; }
# shellcheck disable=SC2059
_skip() { printf "    ${DIM}skip${R}    %s\n" "$*"; }
# shellcheck disable=SC2059
_warn() { printf "    ${YELLOW}warn${R}    %s\n" "$*"; }
# shellcheck disable=SC2059
_err()  { printf "    ${ERED}error${ER}   %s\n" "$*" >&2; }
_die()  { _err "$*"; exit 1; }
# shellcheck disable=SC2059
_info() { printf "  ${CYAN}::${R}  %s\n" "$*"; }
# shellcheck disable=SC2059
_section() { printf "\n${BOLD}==> %s${R}\n" "$1"; }

# -r only stats the device node: it succeeds with no controlling terminal, where
# opening it fails with ENXIO. Open it for real, or every prompt dies on an unset
# reply instead of reporting the missing terminal.
_need_tty() { # $1 = what to tell the user to do instead
    { : </dev/tty; } 2>/dev/null || _die "$1"
}

# 0 when $1 has exactly one $2...$3 marker pair, in that order. Missing,
# reversed, nested, or duplicate markers are ambiguous and must fail closed.
_silere_marker_pair_valid() {
    awk -v begin="$2" -v end="$3" '
        $0 == begin { begins++; begin_line = NR }
        $0 == end   { ends++; end_line = NR }
        END { exit !(begins == 1 && ends == 1 && begin_line < end_line) }
    ' "$1"
}

# 0 when two files hold the same bytes, trailing newlines included; cmp is not in every base install
_silere_same_text() {
    [ -f "$1" ] && [ -f "$2" ] || return 1
    [ "$(cat -- "$1"; printf x)" = "$(cat -- "$2"; printf x)" ]
}

_silere_package_family() {
    local id="" like=""
    if [ -r /etc/os-release ]; then
        # os-release is shell syntax by specification. Read only the two fields
        # used here, in a subshell so a distro cannot change this script's state.
        read -r id like < <(sh -c '. /etc/os-release 2>/dev/null; printf "%s %s\n" "${ID:-}" "${ID_LIKE:-}"')
    fi
    case " $id $like " in
        *' arch '*|*' cachyos '*|*' manjaro '*) printf 'pacman\n' ;;
        *' fedora '*|*' rhel '*|*' centos '*)   printf 'dnf\n' ;;
        *' debian '*|*' ubuntu '*)              printf 'apt\n' ;;
        *' opensuse '*|*' suse '*)              printf 'zypper\n' ;;
        *' void '*)                             printf 'xbps\n' ;;
        *)                                      printf 'unknown\n' ;;
    esac
}

# the one command that gets Quickshell on this system, as its own install guide gives it
_silere_quickshell_install_hint() {
    local candidate=""
    case "$(_silere_package_family)" in
        pacman) printf 'sudo pacman -S --needed quickshell\n'; return ;;
        dnf)    printf 'sudo dnf copr enable errornointernet/quickshell && sudo dnf install quickshell\n'; return ;;
        xbps)   printf 'sudo xbps-install -S quickshell\n'; return ;;
        apt)
            # Debian 14 and Ubuntu 27.04 package it; older releases have none, or a 0.3.0 Silere cannot run on
            candidate="$(LC_ALL=C apt-cache policy quickshell 2>/dev/null \
                | awk '$1 == "Candidate:" && !seen { print $2; seen = 1 }')" || candidate=""
            if [ -n "$candidate" ] && [ "$candidate" != "(none)" ] \
                    && dpkg --compare-versions "$candidate" ge 0.3.2 2>/dev/null; then
                printf 'sudo apt install quickshell %s\n' "$(_silere_qml_module_package QtQuick.Effects)"
                return
            fi ;;
    esac
    printf 'see https://quickshell.org/docs/v0.3.2/guide/install-setup/\n'
}

# the package that provides a command on a package family, as the doctor and the installer suggest it; nothing
# where that family has none or its name is unknown
_silere_package_for() { # $1 = package family, $2 = command
    local tool="$2"
    case "$1:$tool" in
        pacman:notify-send|dnf:notify-send|xbps:notify-send) printf 'libnotify' ;;
        apt:notify-send)    printf 'libnotify-bin' ;;
        zypper:notify-send) printf 'libnotify-tools' ;;
        *:fc-list|*:fc-match|*:fc-cache) printf 'fontconfig' ;;
        pacman:checkupdates) printf 'pacman-contrib' ;;
        apt:checkupdates|dnf:checkupdates|zypper:checkupdates|xbps:checkupdates) return 1 ;;
        *:powerprofilesctl) printf 'power-profiles-daemon' ;;
        *:inotifywait)      printf 'inotify-tools' ;;
        pacman:ssh-keygen|zypper:ssh-keygen|xbps:ssh-keygen) printf 'openssh' ;;
        apt:ssh-keygen)     printf 'openssh-client' ;;
        dnf:ssh-keygen)     printf 'openssh-clients' ;;
        pacman:nmcli|pacman:nmtui) printf 'networkmanager' ;;
        apt:nmcli)          printf 'network-manager' ;;
        dnf:nmcli|zypper:nmcli|xbps:nmcli) printf 'NetworkManager' ;;
        *:pwvucontrol) printf 'pavucontrol' ;;
        *:wpctl)       printf 'wireplumber' ;;
        pacman:pw-dump) printf 'pipewire' ;;
        # an apt or dnf line stops at the first name its release lacks, so hyprlock is named only where it is packaged
        pacman:hyprsunset|pacman:matugen|pacman:xdg-terminal-exec|pacman:fakeroot|pacman:hyprlock|zypper:hyprlock|zypper:hyprsunset|xbps:matugen)
            printf '%s' "$tool" ;;
        *:xdg-open) printf 'xdg-utils' ;;
        pacman:nm-connection-editor|dnf:nm-connection-editor) printf '%s' "$tool" ;;
        apt:nm-connection-editor) printf 'network-manager-gnome' ;;
        *:blueman-manager) printf 'blueman' ;;
        *:wireplumber|*:pipewire|*:upower|*:brightnessctl|*:cava|*:pavucontrol|*:wlsunset|*:ddcutil|*:swaylock|*:curl|*:git)
            printf '%s' "$tool" ;;
        *:Quickshell*|*:QtQuick*) _silere_qml_module_package "$tool" ;;
        *) return 1 ;;
    esac
}

# the one command that installs these packages on a family; fails for a family it does not know
_silere_install_command() { # $1 = package family, $2... = packages
    local family="$1"
    shift
    case "$family" in
        pacman) printf 'sudo pacman -S %s\n' "$*" ;;
        dnf)    printf 'sudo dnf install %s\n' "$*" ;;
        apt)    printf 'sudo apt install %s\n' "$*" ;;
        zypper) printf 'sudo zypper install %s\n' "$*" ;;
        xbps)   printf 'sudo xbps-install %s\n' "$*" ;;
        *) return 1 ;;
    esac
}

# the package holding a QML module, where the distro ships Qt's modules one per package. Debian and Ubuntu's
# quickshell pulls in QtQuick, Layouts and Controls (Shapes with it), never Effects
_silere_qml_module_package() {
    local module="${1,,}"
    case "$(_silere_package_family):$module" in
        apt:quickshell*) printf 'quickshell\n' ;;
        apt:qtquick*)    printf 'qml6-module-%s\n' "${module//./-}" ;;
        *) return 1 ;;
    esac
}

# another bar left running draws beside Silere's, which reads as Silere being broken. Named one per line
_silere_other_bars() {
    local bar line config="" qs_bin
    if command -v pgrep >/dev/null 2>&1; then
        # HyprPanel execs its bundled app, so its process is hyprpanel-app
        for bar in waybar hyprpanel-app ashell ironbar yambar nwg-panel; do
            pgrep -x "$bar" >/dev/null 2>&1 && printf '%s\n' "${bar%-app}"
        done
    fi
    # another Quickshell shell on this display, such as Noctalia or DankMaterialShell, named by its config folder.
    # Another Silere checkout is for silere use to name
    qs_bin="$(command -v qs || command -v quickshell)" || return 0
    while IFS= read -r line; do
        case "$line" in
            *"Config path: "*) config="${line#*Config path: }" ;;
            *"Display connection: "*)
                [ "${config##*/}" = shell.qml ] && [ ! -e "${config%/*}/scripts/silere" ] || continue
                [ -z "${WAYLAND_DISPLAY:-}" ] || [ "${line##*/}" = "${WAYLAND_DISPLAY##*/}" ] || continue
                config="${config%/*}"
                printf '%s\n' "${config##*/}" ;;
        esac
    done < <(env -u LC_ALL "$qs_bin" list --all 2>/dev/null)
    return 0
}

# a notification daemon D-Bus starts on its own (mako, dunst, swaync ship such a file) takes the name whenever an app
# notifies before Silere is up, at any later login. One "program<TAB>systemd unit" line each; the unit may be empty.
# Plasma's file only waits for the name, and Silere's own never comes from a D-Bus file
# stopped now, a bar or notification daemon the compositor config starts is back at the next login, beside Silere and
# holding the notification name. Prints "name<TAB>file:line" for each start line in the given folders: Hyprland's
# exec-once/exec and hl.exec_cmd (not a bind's hl.dsp.exec_cmd), niri's spawn-at-startup; comments are skipped
_silere_config_autostarts() {
    local hit where names='waybar|hyprpanel|ashell|ironbar|yambar|nwg-panel|mako|dunst|swaync|fnott|deadd-notification-center'
    [ "$#" -gt 0 ] || return 0
    grep -rnE --include='*.conf' --include='*.lua' --include='*.kdl' \
        "^[[:space:]]*(exec(-once)?[[:space:]]*=|hl\.exec_cmd[[:space:]]*\(|spawn(-sh)?-at-startup[[:space:]]).*(^|[^A-Za-z0-9_.-])($names)([^A-Za-z0-9_-]|$)" \
        "$@" 2>/dev/null | while IFS= read -r hit; do
            [[ "$hit" =~ ^([^:]+:[0-9]+):(.*)$ ]] || continue
            where="${BASH_REMATCH[1]}"
            [[ "${BASH_REMATCH[2]}" =~ (^|[^A-Za-z0-9_.-])($names)([^A-Za-z0-9_-]|$) ]] || continue
            printf '%s\t%s\n' "${BASH_REMATCH[2]}" "$where"
        done
    return 0
}

# who holds org.freedesktop.Notifications, for doctor and its shareable report: sets notif_owner (the bus name, empty
# when no one holds it), notif_comm and notif_cmd. Needs busctl
# shellcheck disable=SC2034
_silere_notification_owner() {
    local pid=""
    notif_owner="" notif_comm="" notif_cmd=""
    read -r _ notif_owner < <(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus GetNameOwner s org.freedesktop.Notifications 2>/dev/null) || true
    notif_owner="${notif_owner//\"/}"
    if [ -n "$notif_owner" ]; then
        read -r _ pid < <(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
            org.freedesktop.DBus GetConnectionUnixProcessID s "$notif_owner" 2>/dev/null) || true
    fi
    case "$pid" in ''|*[!0-9]*) pid="" ;; esac
    if [ -n "$pid" ]; then
        IFS= read -r notif_comm < "/proc/$pid/comm" 2>/dev/null || true
        notif_cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
    fi
    # silere run starts qs under its real name, quickshell, to dodge ananicy's rule for qs
    case "$notif_comm" in quickshell) notif_comm=qs ;; esac
    return 0
}

# the compositor config line that starts Silere, else "service" for the enabled user unit, else nothing.
# $1 = checkout, $2 = XDG config home
_silere_autostart_entry() {
    local root="$1" config_home="$2" active_config found=""
    local autostart_re='silere-shell begin|^[[:space:]]*(exec-once[[:space:]]*=|spawn(-sh)?-at-startup|hl\.exec_cmd).*(silere-shell|scripts/silere|silere run)'
    if [ -f "$root/scripts/install.sh" ]; then
        for active_config in \
            "$(bash "$root/scripts/install.sh" --hypr-config-path 2>/dev/null || true)" \
            "$(bash "$root/scripts/install.sh" --niri-config-path 2>/dev/null || true)"
        do
            [ -f "$active_config" ] || continue
            if grep -qE "$autostart_re" "$active_config" 2>/dev/null; then
                found="$active_config"
                break
            fi
        done
    fi
    if [ -z "$found" ] && [ -n "$config_home" ]; then
        found="$(grep -rliE "$autostart_re" "$config_home/hypr" "$config_home/niri" 2>/dev/null | head -n 1 || true)"
    fi
    if [ -z "$found" ] && command -v systemctl >/dev/null 2>&1 \
            && systemctl --user is-enabled --quiet silere-shell.service 2>/dev/null; then
        found=service
    fi
    [ -z "$found" ] || printf '%s\n' "$found"
    return 0
}

_silere_notification_autostarters() {
    local data_home dir file cmd unit name seen=" "
    local -a dirs=() data_dirs=()
    data_home="$(_silere_xdg_home "${XDG_DATA_HOME:-}" .local/share 2>/dev/null)" && dirs+=("$data_home")
    IFS=: read -r -a data_dirs <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    dirs+=("${data_dirs[@]}")
    for dir in "${dirs[@]}"; do
        [ -n "$dir" ] || continue
        for file in "$dir"/dbus-1/services/*.service; do
            [ -r "$file" ] || continue
            grep -qx 'Name=org.freedesktop.Notifications' "$file" 2>/dev/null || continue
            cmd="$(awk 'sub(/^Exec=/, "") { print; exit }' "$file" 2>/dev/null)"
            unit="$(awk 'sub(/^SystemdService=/, "") { print; exit }' "$file" 2>/dev/null)"
            case "$cmd" in ""|*plasma_waitforname*|*quickshell*|*silere*) continue ;; esac
            name="${cmd%% *}"; name="${name##*/}"
            case "$seen" in *" $name "*) continue ;; esac
            seen="$seen$name "
            printf '%s\t%s\n' "$name" "$unit"
        done
    done
}
