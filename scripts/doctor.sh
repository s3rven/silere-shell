#!/usr/bin/env bash
# Read-only installation diagnostics. Keep this focused on a running install;
# scripts/check.sh owns developer lint and regression probes.
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/xdg.sh"
source "$ROOT/scripts/lib/qml-modules.sh"

if [ "$#" -gt 0 ]; then
    if [ "$#" -eq 1 ] && [[ "$1" = -h || "$1" = --help ]]; then
        printf 'Usage: silere doctor\n       bash scripts/install.sh --check\n'
        exit 0
    fi
    printf 'silere-doctor: unexpected argument: %s\n' "$1" >&2
    exit 2
fi

status=0
optional_missing=0
seen_section=0
missing_packages=()

section() {
    [ "$seen_section" -eq 0 ] || printf '\n'
    seen_section=1
    printf '== %s ==\n' "$1"
}
ok()   { printf 'ok   %-18s %s\n' "$1" "$2"; }
info() { printf '     %-18s %s\n' "$1" "$2"; }
warn() { printf 'warn %-18s %s\n' "$1" "$2"; }
fail() { printf 'fail %-18s %s\n' "$1" "$2" >&2; status=1; }

_package_family() {
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

package_family="$(_package_family)"

_package_for() {
    local tool="$1"
    case "$package_family:$tool" in
        pacman:notify-send) printf 'libnotify' ;;
        apt:notify-send)    printf 'libnotify-bin' ;;
        dnf:notify-send)    printf 'libnotify' ;;
        *:fc-list|*:fc-match|*:fc-cache) printf 'fontconfig' ;;
        pacman:checkupdates) printf 'pacman-contrib' ;;
        apt:checkupdates|dnf:checkupdates|zypper:checkupdates|xbps:checkupdates) return 1 ;;
        *:powerprofilesctl) printf 'power-profiles-daemon' ;;
        *:inotifywait)      printf 'inotify-tools' ;;
        pacman:ssh-keygen|zypper:ssh-keygen|xbps:ssh-keygen) printf 'openssh' ;;
        apt:ssh-keygen)     printf 'openssh-client' ;;
        dnf:ssh-keygen)     printf 'openssh-clients' ;;
        pacman:nmcli)       printf 'networkmanager' ;;
        apt:nmcli)          printf 'network-manager' ;;
        dnf:nmcli|zypper:nmcli) printf 'NetworkManager' ;;
        *:pwvucontrol) printf 'pavucontrol' ;;
        *:wireplumber|*:pipewire|*:upower|*:brightnessctl|*:cava|*:pavucontrol)
            printf '%s' "$tool" ;;
        *) return 1 ;;
    esac
}

_remember_package() {
    local package existing
    package="$(_package_for "$1" 2>/dev/null || true)"
    [ -n "$package" ] || return 0
    for existing in "${missing_packages[@]}"; do
        [ "$existing" = "$package" ] && return 0
    done
    missing_packages+=("$package")
}

required_tool() {
    local tool="$1" desc="$2"
    if command -v "$tool" >/dev/null 2>&1; then ok "$tool" "$desc"
    else fail "$tool" "$desc (not found in PATH)"; _remember_package "$tool"
    fi
}

optional_tool() {
    local tool="$1" desc="$2"
    if command -v "$tool" >/dev/null 2>&1; then ok "$tool" "$desc"
    else
        warn "$tool" "$desc unavailable (optional)"
        optional_missing=$((optional_missing + 1))
        _remember_package "$tool"
    fi
}

optional_any() {
    local label="$1" desc="$2" tool found=""
    shift 2
    for tool in "$@"; do
        if command -v "$tool" >/dev/null 2>&1; then found="$tool"; break; fi
    done
    if [ -n "$found" ]; then ok "$label" "$desc ($found)"
    else
        warn "$label" "$desc unavailable (optional; need one of: $*)"
        optional_missing=$((optional_missing + 1))
        _remember_package "$1"
    fi
}

_manifest_value() {
    local key="$1"
    sed -n "s/^[[:space:]]*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\"[[:space:]]*,\{0,1\}[[:space:]]*$/\1/p" \
        "$ROOT/release.json" 2>/dev/null | head -n 1
}

section "Silere"
git_install=0
if [ -e "$ROOT/.git" ]; then
    git_install=1
fi
if [ "$git_install" -eq 1 ] && command -v git >/dev/null 2>&1; then
    version="$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || true)"
    info "version" "${version:-unknown}"
    install_mode="$(bash "$ROOT/scripts/update.sh" --version 2>/dev/null \
        | sed -n 's/^mode=//p' | head -n 1)"
    if [ "$install_mode" = managed ]; then
        info "installation" "managed release at $ROOT"
    else
        info "installation" "development checkout at $ROOT"
    fi
elif [ "$git_install" -eq 1 ]; then
    info "version" "unknown (git is unavailable)"
    info "installation" "Git checkout at $ROOT"
elif [ -r "$ROOT/release.json" ]; then
    version="$(_manifest_value version)"
    info "version" "${version:-package build}"
    info "installation" "package-managed at $ROOT"
else
    info "version" "unknown"
    info "installation" "$ROOT"
fi

section "Core"
if [ "$git_install" -eq 1 ]; then
    required_tool git "checkout updates and repair"
fi
qs_usable=0
if ! command -v qs >/dev/null 2>&1; then
    fail "Quickshell" "runtime is required"
elif qs_text="$(qs --version 2>&1)"; then
    qs_usable=1
    qs_version="$(_silere_quickshell_version || true)"
    if [ -z "$qs_version" ]; then
        warn "Quickshell" "version could not be parsed; need $SILERE_MIN_QUICKSHELL or newer"
    elif _silere_version_at_least "$qs_version" "$SILERE_MIN_QUICKSHELL"; then
        ok "Quickshell" "$qs_version"
    else
        fail "Quickshell" "$qs_version is older than required $SILERE_MIN_QUICKSHELL"
    fi
else
    fail "Quickshell" "installed but could not start: ${qs_text%%$'\n'*}"
fi

compositor=""
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then compositor="Hyprland"
elif [ -n "${NIRI_SOCKET:-}" ]; then compositor="niri"
fi
if [ "$compositor" = Hyprland ]; then
    if command -v hyprctl >/dev/null 2>&1 && hyprctl monitors >/dev/null 2>&1; then
        ok "compositor" "Hyprland IPC reachable"
    else fail "compositor" "Hyprland session detected but IPC is unavailable"
    fi
elif [ "$compositor" = niri ]; then
    if command -v niri >/dev/null 2>&1 && niri msg version >/dev/null 2>&1; then
        ok "compositor" "niri IPC reachable"
    else fail "compositor" "niri session detected but IPC is unavailable"
    fi
else
    warn "compositor" "no live Hyprland or niri session detected"
fi

missing_modules=0
for module in "${SILERE_REQUIRED_QML_MODULES[@]}"; do
    if ! _qml_module_available "$module"; then
        fail "QML module" "$module is missing"
        missing_modules=$((missing_modules + 1))
    fi
done
[ "$missing_modules" -gt 0 ] || ok "QML modules" "all ${#SILERE_REQUIRED_QML_MODULES[@]} required imports found"

if [ "$qs_usable" -eq 1 ]; then
    if command -v timeout >/dev/null 2>&1; then
        ipc_probe=(timeout 5 qs ipc -p "$ROOT/shell.qml" show)
    else
        ipc_probe=(qs ipc -p "$ROOT/shell.qml" show)
    fi
    if "${ipc_probe[@]}" >/dev/null 2>&1; then ok "shell IPC" "Silere is running and answers"
    else warn "shell IPC" "Silere from $ROOT is not running or does not answer"
    fi
fi

# another daemon holding the name is the usual reason notifications never appear
if command -v busctl >/dev/null 2>&1; then
    notif_owner="" notif_pid="" notif_comm="" notif_cmd=""
    read -r _ notif_owner < <(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus GetNameOwner s org.freedesktop.Notifications 2>/dev/null) || true
    notif_owner="${notif_owner//\"/}"
    if [ -n "$notif_owner" ]; then
        read -r _ notif_pid < <(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
            org.freedesktop.DBus GetConnectionUnixProcessID s "$notif_owner" 2>/dev/null) || true
    fi
    case "$notif_pid" in ''|*[!0-9]*) notif_pid="" ;; esac
    if [ -n "$notif_pid" ]; then
        IFS= read -r notif_comm < "/proc/$notif_pid/comm" 2>/dev/null || true
        notif_cmd="$(tr '\0' ' ' < "/proc/$notif_pid/cmdline" 2>/dev/null || true)"
    fi
    if [ -z "$notif_owner" ]; then
        warn "notifications" "no notification daemon is running"
    elif [ "$notif_comm" = qs ] && [[ "$notif_cmd" == *"$ROOT/shell.qml"* || "$notif_cmd" == *"$ROOT "* ]]; then
        ok "notifications" "served by Silere"
    elif [ "$notif_comm" = qs ]; then
        warn "notifications" "owned by another Quickshell config; stop it to use Silere's notifications"
    else
        warn "notifications" "owned by ${notif_comm:-another process}; stop it to use Silere's notifications"
    fi
fi

section "Audio"
optional_tool pipewire "audio service"
optional_tool wireplumber "PipeWire session manager"
if command -v systemctl >/dev/null 2>&1; then
    for unit in pipewire.service wireplumber.service; do
        if systemctl --user is-active --quiet "$unit" 2>/dev/null; then ok "$unit" "active"
        elif command -v "${unit%%.*}" >/dev/null 2>&1; then warn "$unit" "installed but not active"
        fi
    done
fi

section "Optional features"
optional_tool upower "battery"
optional_tool brightnessctl "brightness control"
optional_tool matugen "wallpaper theming"
if ! command -v powerprofilesctl >/dev/null 2>&1 && command -v busctl >/dev/null 2>&1 \
        && busctl --system --no-pager --timeout=2 get-property net.hadess.PowerProfiles \
            /net/hadess/PowerProfiles net.hadess.PowerProfiles ActiveProfile >/dev/null 2>&1; then
    ok "power profiles" "served over D-Bus (tuned-ppd or similar)"
else
    optional_tool powerprofilesctl "power profiles"
fi
optional_any "night light" "warm display" hyprsunset wlsunset
optional_any "screen lock" "lock action" hyprlock swaylock gtklock
optional_any "sound settings" "per-app routing UI" pwvucontrol pavucontrol
optional_tool cava "audio visualizer"
optional_tool notify-send "desktop alerts"
optional_tool fc-list "font verification"
if command -v fc-list >/dev/null 2>&1; then
    if fc-list : family 2>/dev/null | grep -qi 'nerd font'; then ok "Nerd Font" "installed"
    else fail "Nerd Font" "none installed; bar and menu icons render as boxes"
    fi
fi
optional_tool inotifywait "screenshot feedback + Hyprland restart recovery"
optional_tool nmcli "VPN indicator"
optional_tool busctl "notification daemon check"
optional_any "power actions" "suspend, reboot, shut down" systemctl loginctl
optional_any "updates" "update count widget" checkupdates apt dnf zypper xbps-install
[ "$package_family" != pacman ] \
    || optional_any "AUR helper" "AUR update count" paru yay
if command -v checkupdates >/dev/null 2>&1 && ! command -v fakeroot >/dev/null 2>&1; then
    warn "fakeroot" "checkupdates needs it; the update badge reports an error without it"
    optional_missing=$((optional_missing + 1))
    _remember_package fakeroot
fi

section "Integration"
config_home="$(_silere_xdg_home "${XDG_CONFIG_HOME:-}" .config 2>/dev/null || true)"
state_home="$(_silere_xdg_home "${XDG_STATE_HOME:-}" .local/state 2>/dev/null || true)"
settings="${config_home:+$config_home/silere-shell/settings.json}"
if [ -z "$config_home" ]; then fail "XDG config" "HOME must be absolute"
elif [ ! -e "$settings" ]; then info "settings" "not created yet"
elif [ ! -r "$settings" ]; then fail "settings" "not readable at $settings"
elif command -v python3 >/dev/null 2>&1 \
        && ! python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$settings" 2>/dev/null; then
    fail "settings" "not valid JSON; Silere keeps its defaults and leaves the file alone"
else ok "settings" "readable at $settings"
fi

if [ -r "$ROOT/security/update-signers" ]; then ok "release trust" "installed signer list is readable"
elif [ "$git_install" -eq 1 ]; then fail "release trust" "security/update-signers is missing"
else info "release trust" "package manager owns updates"
fi

# update.sh refuses to apply a release it cannot verify, so a git install without
# ssh-keygen has a trust chain that ends here rather than at the signer list
if [ "$git_install" -eq 1 ]; then
    if command -v ssh-keygen >/dev/null 2>&1; then
        ok "ssh-keygen" "release signatures can be verified"
    else
        warn "ssh-keygen" "signed updates cannot be verified (optional)"
        optional_missing=$((optional_missing + 1))
        _remember_package ssh-keygen
    fi
fi

if [ "$git_install" -eq 1 ]; then
    transaction=""
    if transaction="$(bash "$ROOT/scripts/update.sh" --transaction-status 2>/dev/null)"; then
        if printf '%s\n' "$transaction" | grep -q '^pending=1$'; then
            transaction_phase="$(printf '%s\n' "$transaction" | sed -n 's/^phase=//p')"
            transaction_tag="$(printf '%s\n' "$transaction" | sed -n 's/^tag=//p')"
            warn "update recovery" "${transaction_tag:-release} interrupted at ${transaction_phase:-apply}; run silere update"
        else
            ok "update recovery" "no interrupted transaction"
        fi
    elif printf '%s\n' "$transaction" | grep -q '^pending=1$'; then
        fail "update recovery" "transaction journal is damaged; run silere update for details"
    else
        warn "update recovery" "transaction state could not be checked"
    fi
fi

autostart=""
if [ -x "$ROOT/scripts/install.sh" ]; then
    for active_config in \
        "$(bash "$ROOT/scripts/install.sh" --hypr-config-path 2>/dev/null || true)" \
        "$(bash "$ROOT/scripts/install.sh" --niri-config-path 2>/dev/null || true)"
    do
        [ -f "$active_config" ] || continue
        if grep -qE 'silere-shell begin|^[[:space:]]*(exec-once[[:space:]]*=|spawn-at-startup).*silere-shell' \
                "$active_config" 2>/dev/null; then
            autostart="$active_config"
            break
        fi
    done
fi
if [ -n "$config_home" ]; then
    if [ -z "$autostart" ]; then
        autostart="$(grep -rliE \
            'silere-shell begin|^[[:space:]]*(exec-once[[:space:]]*=|spawn-at-startup).*silere-shell' \
            "$config_home/hypr" "$config_home/niri" 2>/dev/null | head -n 1 || true)"
    fi
fi
if [ -n "$autostart" ]; then ok "autostart" "$autostart"
elif command -v systemctl >/dev/null 2>&1 \
        && systemctl --user is-enabled --quiet silere-shell.service 2>/dev/null; then
    ok "autostart" "silere-shell.service enabled"
else warn "autostart" "no compositor entry or enabled user service found"
fi

if command -v systemctl >/dev/null 2>&1 \
        && systemctl --user show-environment >/dev/null 2>&1; then
    if systemctl --user is-enabled --quiet silere-update.timer 2>/dev/null; then
        ok "update timer" "enabled"
    else info "update timer" "disabled (optional)"
    fi
else info "update timer" "systemd user manager unavailable"
fi
[ -z "$state_home" ] || info "state home" "$state_home/silere-shell"

if [ "${#missing_packages[@]}" -gt 0 ]; then
    section "Install suggestions"
    case "$package_family" in
        pacman) printf '     sudo pacman -S %s\n' "${missing_packages[*]}" ;;
        dnf)    printf '     sudo dnf install %s\n' "${missing_packages[*]}" ;;
        apt)    printf '     sudo apt install %s\n' "${missing_packages[*]}" ;;
        zypper) printf '     sudo zypper install %s\n' "${missing_packages[*]}" ;;
        xbps)   printf '     sudo xbps-install %s\n' "${missing_packages[*]}" ;;
        *)      info "packages" "install the missing commands with your package manager" ;;
    esac
    info "note" "Silere never runs these commands or elevates privileges"
fi

printf '\n'
if [ "$status" -ne 0 ]; then
    printf 'Silere has required components that need attention.\n'
elif [ "$optional_missing" -gt 0 ]; then
    printf 'Silere is usable; %d optional feature%s unavailable.\n' \
        "$optional_missing" "$([ "$optional_missing" -eq 1 ] || printf s)"
else
    printf 'Silere is ready.\n'
fi
exit "$status"
