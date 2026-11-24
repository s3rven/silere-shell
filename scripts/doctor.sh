#!/usr/bin/env bash
# Read-only installation diagnostics. Keep this focused on a running install;
# dev/check.sh owns developer lint and regression probes.
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "$#" -eq 1 ] && [ "$1" = --json ]; then
    exec bash "$ROOT/scripts/doctor-json.sh"
fi
source "$ROOT/scripts/lib/xdg.sh"
source "$ROOT/scripts/lib/qml-modules.sh"
source "$ROOT/scripts/lib/ui.sh"
source "$ROOT/scripts/lib/unit.sh"
source "$ROOT/scripts/lib/instances.sh"

if [ "$#" -gt 0 ]; then
    if [ "$#" -eq 1 ] && [[ "$1" = -h || "$1" = --help ]]; then
        printf 'Usage: silere doctor [--json]\n       bash scripts/install.sh --check\n'
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
    printf '%s== %s ==%s\n' "$BOLD" "$1" "$R"
}
# wide enough for the longest name, nm-connection-editor
ok()   { printf '%sok%s   %-20s %s\n' "$GREEN" "$R" "$1" "$2"; }
info() { printf '     %-20s %s\n' "$1" "$2"; }
warn() { printf '%swarn%s %-20s %s\n' "$YELLOW" "$R" "$1" "$2"; }
fail() { printf '%sfail%s %-20s %s\n' "$ERED" "$ER" "$1" "$2" >&2; status=1; }

package_family="$(_silere_package_family)"

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
        pacman:nmcli|pacman:nmtui) printf 'networkmanager' ;;
        apt:nmcli)          printf 'network-manager' ;;
        dnf:nmcli|zypper:nmcli) printf 'NetworkManager' ;;
        *:pwvucontrol) printf 'pavucontrol' ;;
        *:wpctl)       printf 'wireplumber' ;;
        pacman:pw-dump) printf 'pipewire' ;;
        pacman:hyprsunset|pacman:matugen|pacman:xdg-terminal-exec|pacman:fakeroot) printf '%s' "$tool" ;;
        pacman:nm-connection-editor|dnf:nm-connection-editor) printf '%s' "$tool" ;;
        apt:nm-connection-editor) printf 'network-manager-gnome' ;;
        *:blueman-manager) printf 'blueman' ;;
        *:wireplumber|*:pipewire|*:upower|*:brightnessctl|*:cava|*:pavucontrol|*:wlsunset|*:ddcutil)
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
    if [ -r "$ROOT/package-version" ]; then
        info "installation" "package-managed at $ROOT"
    else
        info "installation" "copy without Git at $ROOT"
    fi
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
elif qs_text="$(env -u LC_ALL qs --version 2>&1)"; then
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
        hypr_version="$(hyprctl version -j 2>/dev/null \
            | sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([0-9.]*\)".*/\1/p' | head -n 1)"
        # 0.57 gives only numbered workspaces an id; Quickshell 0.3.1 reads special and named ones as id 0
        if [ -n "$hypr_version" ] && [ -n "${qs_version:-}" ] \
            && _silere_version_at_least "$hypr_version" 0.57 \
            && ! _silere_version_at_least "$qs_version" 0.3.2; then
            warn "workspaces" "Quickshell $qs_version may mix up special and named workspaces on Hyprland $hypr_version"
        fi
        # translucent surfaces ask Hyprland to blur behind them; these are the two things that quietly stop it
        blur_opt="$(hyprctl -j getoption decoration:blur:enabled 2>/dev/null || true)"
        if [ -n "$hypr_version" ] && ! _silere_version_at_least "$hypr_version" 0.56; then
            info "blur" "needs Hyprland 0.56; translucent surfaces show what is behind them unblurred"
        else
            case "$blur_opt" in
                *'"bool": false'*|*'"bool":false'*) info "blur" "off in Hyprland (decoration:blur:enabled)" ;;
                *) ok "blur" "Hyprland blurs behind translucent surfaces" ;;
            esac
        fi
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

other_bars="$(_silere_other_bars | paste -sd ' ')"
if [ -n "$other_bars" ]; then
    warn "other bars" "$other_bars still running, and will draw beside Silere's; stop it and remove it from autostart"
fi

missing_modules=0
for module in "${SILERE_REQUIRED_QML_MODULES[@]}"; do
    if ! _qml_module_available "$module"; then
        fail "QML module" "$module is missing"
        missing_modules=$((missing_modules + 1))
    fi
done
[ "$missing_modules" -gt 0 ] || ok "QML modules" "all ${#SILERE_REQUIRED_QML_MODULES[@]} required imports found"
qt_floor=0
_qt_floor_met || qt_floor=$?
case "$qt_floor" in
    0) ok "Qt" "$SILERE_MIN_QT or newer" ;;
    1) fail "Qt" "older than $SILERE_MIN_QT; the menu, notifications and popups cannot load" ;;
esac

# a dev checkout beside an installed copy: the shell on screen is Silere, just not this one
other_silere=""
if [ "$qs_usable" -eq 1 ]; then
    while IFS= read -r _cfg; do
        [ -n "$_cfg" ] && [ "$_cfg" != "$ROOT/shell.qml" ] && [ -x "$(dirname "$_cfg")/scripts/silere" ] || continue
        other_silere="$(dirname "$_cfg")"; break
    done < <(_silere_running_configs)
fi

if [ "$qs_usable" -eq 1 ]; then
    if command -v timeout >/dev/null 2>&1; then
        ipc_probe=(timeout 5 env -u LC_ALL qs ipc -p "$ROOT/shell.qml" show)
    else
        ipc_probe=(env -u LC_ALL qs ipc -p "$ROOT/shell.qml" show)
    fi
    if "${ipc_probe[@]}" >/dev/null 2>&1; then
        ok "shell IPC" "Silere is running and answers"
        shell_pid="$(_silere_shell_pid "$ROOT/shell.qml" || true)"
        shell_nice="$(ps -o ni= -p "${shell_pid:-0}" 2>/dev/null | tr -d ' ')" || shell_nice=""
        if [ "${shell_nice:-0}" -gt 0 ] 2>/dev/null; then
            warn "shell priority" "running at nice $shell_nice, so the bar and menus stutter under load; start it with silere run"
        fi
        # Mesa names its CPU rasterizer threads llvmpipe-N; with a GPU present that is a fallback, not a choice,
        # and the usual cause is an EGL vendor pinned to Mesa while an NVIDIA GPU drives the display
        if [ -n "$shell_pid" ] && compgen -G '/dev/dri/renderD*' >/dev/null \
                && grep -qsx 'llvmpipe-[0-9]*' /proc/"$shell_pid"/task/*/comm; then
            egl_pin="$(tr '\0' '\n' < /proc/"$shell_pid"/environ 2>/dev/null \
                | sed -n 's/^__EGL_VENDOR_LIBRARY_FILENAMES=//p')" || egl_pin=""
            warn "rendering" "drawn on the CPU (llvmpipe), so every animation frame costs CPU${egl_pin:+; __EGL_VENDOR_LIBRARY_FILENAMES=$egl_pin in its environment may not support this GPU}"
        fi
        # the stale build only says so in its own log, so read it while the shell runs
        qt_drift="$(_silere_quickshell_qt_drift "$ROOT/shell.qml" || true)"
        if [ -n "$qt_drift" ]; then
            warn "Qt build" "Quickshell was built for Qt ${qt_drift% *} but runs on ${qt_drift#* }; update or rebuild it"
        fi
    elif [ -n "$other_silere" ]; then
        info "shell IPC" "Silere is running from $other_silere, not this copy"
    else warn "shell IPC" "Silere from $ROOT is not running or does not answer"
    fi
fi

# another daemon holding the name is the usual reason notifications never appear
if command -v busctl >/dev/null 2>&1; then
    _silere_notification_owner
    if [ -z "$notif_owner" ]; then
        warn "notifications" "no notification daemon is running"
    elif [ "$notif_comm" = qs ] && [[ "$notif_cmd" == *"$ROOT/shell.qml"* || "$notif_cmd" == *"$ROOT "* ]]; then
        ok "notifications" "served by Silere"
    elif [ "$notif_comm" = qs ] && [ -n "$other_silere" ] && [[ "$notif_cmd" == *"$other_silere/shell.qml"* ]]; then
        ok "notifications" "served by Silere from $other_silere"
    elif [ "$notif_comm" = qs ]; then
        warn "notifications" "owned by another Quickshell config; stop it to use Silere's notifications"
    else
        warn "notifications" "owned by ${notif_comm:-another process}; stop it to use Silere's notifications"
    fi
fi
# stopped for this session, such a daemon still comes back at a later login, before Silere has the name
while IFS=$'\t' read -r notif_daemon notif_unit; do
    [ -n "$notif_daemon" ] || continue
    if [ -n "$notif_unit" ]; then
        warn "notification daemon" "$notif_daemon can start itself before Silere; keep it off: systemctl --user mask $notif_unit"
    else
        warn "notification daemon" "$notif_daemon can start itself before Silere; uninstall it to keep Silere's notifications"
    fi
done < <(_silere_notification_autostarters)
# the running check above misses one stopped for now; the compositor config starts it again at the next login
doctor_config_home="$(_silere_xdg_home "${XDG_CONFIG_HOME:-}" .config 2>/dev/null || true)"
if [ -n "$doctor_config_home" ]; then
    while IFS=$'\t' read -r started where; do
        [ -n "$started" ] || continue
        warn "at login" "$started starts from ${where/#"$HOME"/\~}, beside Silere; remove that line"
    done < <(_silere_config_autostarts "$doctor_config_home/hypr" "$doctor_config_home/niri")
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
# Quickshell reads networks through NetworkManager only: iwd or systemd-networkd alone leave the widget hidden
if command -v busctl >/dev/null 2>&1; then
    if busctl --system --no-pager --timeout=2 get-property org.freedesktop.NetworkManager \
            /org/freedesktop/NetworkManager org.freedesktop.NetworkManager Version >/dev/null 2>&1; then
        ok "NetworkManager" "network widget + Wi-Fi controls"
    else
        warn "NetworkManager" "not running: network widget + Wi-Fi controls hidden (optional)"
        optional_missing=$((optional_missing + 1))
    fi
fi
optional_tool brightnessctl "brightness control"
optional_tool matugen "wallpaper theming"
if ! command -v powerprofilesctl >/dev/null 2>&1 && command -v busctl >/dev/null 2>&1 \
        && busctl --system --no-pager --timeout=2 get-property net.hadess.PowerProfiles \
            /net/hadess/PowerProfiles net.hadess.PowerProfiles ActiveProfile >/dev/null 2>&1; then
    ok "power profiles" "served over D-Bus (tuned-ppd or similar)"
else
    optional_tool powerprofilesctl "power profiles"
fi
# hyprsunset needs a hyprland-only protocol
if [ "$compositor" = niri ]; then optional_any "night light" "warm display" wlsunset
else optional_any "night light" "warm display" hyprsunset wlsunset
fi
# loginctl lock-session locks nothing itself: only an idle daemon such as hypridle can answer it with a locker
if command -v loginctl >/dev/null 2>&1 && ! command -v hyprlock >/dev/null 2>&1 \
        && ! command -v swaylock >/dev/null 2>&1 && ! command -v gtklock >/dev/null 2>&1; then
    warn "screen lock" "lock action relies on an idle daemon answering loginctl lock-session (optional; need one of: hyprlock swaylock gtklock)"
    optional_missing=$((optional_missing + 1))
    if [ "$compositor" = niri ]; then _remember_package swaylock; else _remember_package hyprlock; fi
else
    optional_any "screen lock" "lock action" hyprlock swaylock gtklock
fi
optional_any "sound settings" "per-app routing UI" pwvucontrol pavucontrol
# Quickshell 0.3.2 sets bluetooth volume itself; headset modes still need both pipewire tools
if [ -z "${qs_version:-}" ] || ! _silere_version_at_least "$qs_version" 0.3.2; then
    optional_tool wpctl "headset modes + bluetooth volume on Quickshell 0.3.1"
else
    optional_tool wpctl "headset modes"
fi
optional_tool pw-dump "headset modes"
optional_tool curl "cover art from the web + installer downloads"
optional_tool xdg-open "network sign-in page"
optional_tool cava "audio visualizer"
optional_tool notify-send "update alerts (the shell's own alerts also go through busctl)"
optional_tool fc-list "font verification"
if command -v fc-list >/dev/null 2>&1; then
    # stderr rides along, so a fontconfig failure names itself instead of reading as no font
    font_families="$(fc-list : family 2>&1)"
    font_status=$?
    font_error="$(grep -m1 -i '^fontconfig' <<<"$font_families")"
    if grep -qi 'nerd font' <<<"$font_families"; then ok "Nerd Font" "installed"
    elif [ "$font_status" -ne 0 ] || [ -n "$font_error" ]; then
        fail "Nerd Font" "fc-list could not list fonts (exit $font_status)${font_error:+: $font_error}"
    else fail "Nerd Font" "none installed; bar and menu icons render as boxes"
    fi
fi
optional_tool inotifywait "screenshot feedback + Hyprland restart recovery"
optional_tool nmcli "VPN indicator + saved VPN controls"
optional_tool blueman-manager "PIN and passkey pairing"
# the shell takes either, nmtui in a terminal
optional_any "network settings" "advanced Wi-Fi + VPN settings" nm-connection-editor nmtui
# the order Settings.terminalPrefix tries: xdg-terminal-exec honours the user's own choice
optional_any "terminal" "terminal tools such as nmtui open in it" xdg-terminal-exec kitty foot ghostty alacritty wezterm konsole
optional_tool ddcutil "optional external monitor brightness"
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
        && ! python3 -I -c 'import json, sys; json.load(open(sys.argv[1]))' "$settings" 2>/dev/null; then
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
        if printf '%s\n' "$transaction" | grep -q '^quarantined=1$'; then
            transaction_path="$(printf '%s\n' "$transaction" | sed -n 's/^path=//p')"
            warn "update recovery" "damaged journal preserved at $transaction_path; inspect it before another update"
        elif printf '%s\n' "$transaction" | grep -q '^pending=1$'; then
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

autostart="$(_silere_autostart_entry "$ROOT" "$config_home")"
if [ "$autostart" = service ]; then ok "autostart" "silere-shell.service enabled"
elif [ -n "$autostart" ]; then ok "autostart" "$autostart"
else warn "autostart" "no compositor entry or enabled user service found"
fi

# a bind that runs qs ipc starts a process on every press; named only once the running shell holds silere:menu
if [ "$compositor" = Hyprland ] && [ -n "$config_home" ] \
        && [[ "$(hyprctl globalshortcuts 2>/dev/null)" == *"silere:menu "* ]]; then
    old_bind="$(grep -rnE --include='*.conf' --include='*.lua' '^[[:space:]]*[^#[:space:]-].*call menu toggle' \
        "$config_home/hypr" 2>/dev/null | head -n 1)" || old_bind=""
    if [[ "$old_bind" =~ ^([^:]+:[0-9]+):(.*)$ ]]; then
        bind_where="${BASH_REMATCH[1]}" bind_line="${BASH_REMATCH[2]}"
        bind_new="a bind to global, silere:menu"
        if [[ "$bind_line" =~ ^[[:space:]]*(hl\.bind\([^,]*,) ]]; then
            bind_new="${BASH_REMATCH[1]} hl.dsp.global(\"silere:menu\"))"
        elif [[ "$bind_line" =~ ^[[:space:]]*(bind[a-ce-z]*[[:space:]]*=[^,]*,[^,]*,)[[:space:]]*exec[[:space:]]*, ]]; then
            bind_new="${BASH_REMATCH[1]} global, silere:menu"
        fi
        info "menu keybind" "$bind_where starts a qs process on each press; this one does not: $bind_new"
    fi
fi

if command -v systemctl >/dev/null 2>&1 \
        && systemctl --user show-environment >/dev/null 2>&1; then
    if _silere_unit_uses_transient_images; then
        warn "tray rendering" "remove QSG_TRANSIENT_IMAGES from silere-shell.service, use silere run, then reload the unit and restart Silere"
    fi
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
    printf '%sSilere has required components that need attention.%s\n' "$RED" "$R"
elif [ "$optional_missing" -gt 0 ]; then
    printf '%sSilere is usable%s; %d optional feature%s unavailable.\n' "$GREEN" "$R" \
        "$optional_missing" "$([ "$optional_missing" -eq 1 ] || printf s)"
else
    printf '%sSilere is ready.%s\n' "$GREEN" "$R"
fi
exit "$status"
