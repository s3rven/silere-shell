#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/silere-daily-driver.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/config" "$scratch/drm/card1-DP-1/ddc/i2c-dev/i2c-7"
export SILERE_SANDBOX=1 SILERE_TEST_DRM_ROOT="$scratch/drm" SILERE_TEST_LOG="$scratch/actions"
export SILERE_TEST_COUNT="$scratch/count" SILERE_TEST_ROOT="$ROOT"
export PATH="$scratch/bin:$PATH" XDG_CONFIG_HOME="$scratch/config" XDG_SESSION_ID=fixture

cat > "$scratch/bin/loginctl" <<'EOF'
#!/usr/bin/env bash
[ "${SILERE_TEST_LOCK_MODE:-yes}" != error ] || exit 1
case "$*" in *' -p Id '*) echo fixture; exit 0 ;; esac
count=0
[ ! -f "$SILERE_TEST_COUNT" ] || read -r count < "$SILERE_TEST_COUNT"
count=$((count+1)); printf '%s\n' "$count" > "$SILERE_TEST_COUNT"
if [ "${SILERE_TEST_LOCK_MODE:-yes}" = delayed ] && [ "$count" -lt 3 ]; then echo no
elif [ "${SILERE_TEST_LOCK_MODE:-yes}" = no ]; then echo no
else echo yes; fi
EOF
cat > "$scratch/bin/ddcutil" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *' getvcp '*)
        case " $* " in *' --bus 9 '*) exit 1 ;; esac
        [ "${SILERE_TEST_REPLACE:-0}" != 1 ] || printf changed > "$SILERE_TEST_DRM_ROOT/card1-DP-1/edid"
        echo 'VCP 10 C 20 80' ;;
    *' setvcp '*) printf '%s\n' "$*" >> "$SILERE_TEST_LOG" ;;
    *) exit 2 ;;
esac
EOF
cat > "$scratch/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *' show '*) printf '{ path=%s/scripts/silere ; argv[]=%s/scripts/silere run ; }\n' "$SILERE_TEST_ROOT" "$SILERE_TEST_ROOT" ;;
    *' is-active '*) exit "${SILERE_TEST_SERVICE_ACTIVE:-1}" ;;
    *' import-environment '*)
        printf '%s\n' "$*" >> "$SILERE_TEST_LOG"
        printf 'LC_ALL=%s\n' "${LC_ALL-unset}" >> "$SILERE_TEST_LOG" ;;
    *) printf '%s\n' "$*" >> "$SILERE_TEST_LOG" ;;
esac
EOF
cat > "$scratch/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$scratch/bin/"*

checks=0
check() { "$@" || { printf 'FAIL: daily-driver fixture: %s\n' "$*" >&2; exit 1; }; checks=$((checks+1)); }
check bash "$ROOT/scripts/session.sh" status
SILERE_TEST_LOCK_MODE=delayed bash "$ROOT/scripts/session.sh" wait-locked
check test "$(cat "$SILERE_TEST_COUNT")" -ge 3
if SILERE_TEST_LOCK_MODE=no bash "$ROOT/scripts/session.sh" wait-locked 2>/dev/null; then exit 1; fi
checks=$((checks+1))
if SILERE_TEST_LOCK_MODE=error bash "$ROOT/scripts/session.sh" status; then exit 1; fi
checks=$((checks+1))

# a tool of another session is neither found nor stopped; one that names no session counts as ours
decoy="sdecoy$$"
cp "$(command -v bash)" "$scratch/bin/$decoy"
mkfifo "$scratch/decoy.fifo"
# a read on a fifo nobody writes: no child process, and a failed run's decoys still end on their own
decoy_wait="read -r -t 60 _ <> '$scratch/decoy.fifo'"
decoy_up() { for _ in $(seq 1 300); do [ "$(cat "/proc/$1/comm" 2>/dev/null)" = "$decoy" ] && return 0; sleep 0.01; done; return 1; }
gone() { for _ in $(seq 1 300); do kill -0 "$1" 2>/dev/null || return 0; sleep 0.01; done; return 1; }
own=(WAYLAND_DISPLAY=fixture-1 XDG_RUNTIME_DIR=/run/fixture)
env WAYLAND_DISPLAY=other-1 XDG_RUNTIME_DIR=/run/fixture "$scratch/bin/$decoy" -c "$decoy_wait" & other_display=$!
env WAYLAND_DISPLAY=fixture-1 XDG_RUNTIME_DIR=/run/other "$scratch/bin/$decoy" -c "$decoy_wait" & other_runtime=$!
check decoy_up "$other_display"; check decoy_up "$other_runtime"
if env "${own[@]}" bash "$ROOT/scripts/session.sh" tool-find "$decoy"; then echo 'FAIL: adopted another session tool' >&2; exit 1; fi
checks=$((checks+1))
if env "${own[@]}" bash "$ROOT/scripts/session.sh" tool-stop "$decoy"; then echo 'FAIL: claimed to stop another session tool' >&2; exit 1; fi
checks=$((checks+1))
check kill -0 "$other_display"; check kill -0 "$other_runtime"
env "${own[@]}" "$scratch/bin/$decoy" -c "$decoy_wait" & ours=$!
check decoy_up "$ours"
check env "${own[@]}" bash "$ROOT/scripts/session.sh" tool-find "$decoy"
check env "${own[@]}" bash "$ROOT/scripts/session.sh" tool-stop "$decoy"
check gone "$ours"; check kill -0 "$other_display"
env -u WAYLAND_DISPLAY -u XDG_RUNTIME_DIR "$scratch/bin/$decoy" -c "$decoy_wait" & unnamed=$!
check decoy_up "$unnamed"
check env "${own[@]}" bash "$ROOT/scripts/session.sh" tool-find "$decoy"
kill "$other_display" "$other_runtime" "$unnamed" 2>/dev/null || true
wait "$other_display" "$other_runtime" "$ours" "$unnamed" 2>/dev/null || true

printf connected > "$scratch/drm/card1-DP-1/status"
printf 'fixture-edid' > "$scratch/drm/card1-DP-1/edid"
fingerprint="$(sha256sum "$scratch/drm/card1-DP-1/edid" | cut -d' ' -f1)"
listed="$(bash "$ROOT/scripts/display-brightness.sh" list)"
check test "$listed" = "$(printf 'card1-DP-1\t7\t%s\t20\t80' "$fingerprint")"
# a second display whose DDC read fails: the first still lists, and the exit status says the list is short
mkdir -p "$scratch/drm/card1-DP-2/ddc/i2c-dev/i2c-9"
printf connected > "$scratch/drm/card1-DP-2/status"
printf 'silent-edid' > "$scratch/drm/card1-DP-2/edid"
if short="$(bash "$ROOT/scripts/display-brightness.sh" list)"; then echo 'FAIL: a display that failed its DDC read was dropped without a word' >&2; exit 1; fi
silent_fp="$(sha256sum "$scratch/drm/card1-DP-2/edid" | cut -d' ' -f1)"
# listed as unreadable so it can be switched off; switched off, it is not asked and the list is whole
check test "$short" = "$(printf '%s\ncard1-DP-2\t9\t%s\t-2\t100' "$listed" "$silent_fp")"
off="$(bash "$ROOT/scripts/display-brightness.sh" list "card1-DP-2:$silent_fp")"
check test "$off" = "$(printf '%s\ncard1-DP-2\t9\t%s\t-1\t100' "$listed" "$silent_fp")"
rm -rf -- "$scratch/drm/card1-DP-2"
check bash "$ROOT/scripts/display-brightness.sh" write card1-DP-1 7 "$fingerprint" 75
check grep -qx -- '--bus 7 setvcp 10 60' "$SILERE_TEST_LOG"
before="$(wc -l < "$SILERE_TEST_LOG")"
if bash "$ROOT/scripts/display-brightness.sh" write card1-DP-1 7 "$fingerprint" 0; then exit 1; fi
checks=$((checks+1))
if SILERE_TEST_REPLACE=1 bash "$ROOT/scripts/display-brightness.sh" write card1-DP-1 7 "$fingerprint" 50; then exit 1; fi
check test "$(wc -l < "$SILERE_TEST_LOG")" = "$before"
printf disconnected > "$scratch/drm/card1-DP-1/status"
if bash "$ROOT/scripts/display-brightness.sh" write card1-DP-1 7 "$fingerprint" 50; then exit 1; fi
checks=$((checks+1))

bash "$ROOT/scripts/service.sh" install --dry-run > "$scratch/unit-preview"
check test ! -d "$scratch/config/systemd"
check grep -qx 'Restart=on-failure' "$scratch/unit-preview"
check grep -qx 'StartLimitBurst=3' "$scratch/unit-preview"
bash "$ROOT/scripts/service.sh" install > /dev/null
check test -f "$scratch/config/systemd/user/silere-shell.service"
check test "$(tail -1 "$SILERE_TEST_LOG")" = '--user daemon-reload'
WAYLAND_DISPLAY=wayland-fixture NIRI_SOCKET=/tmp/niri-fixture \
    bash "$ROOT/scripts/service.sh" start
check grep -q '^--user unset-environment .*DISPLAY.*XDG_SESSION_ID.*HYPRLAND_INSTANCE_SIGNATURE.*NIRI_SOCKET' "$SILERE_TEST_LOG"
check grep -q '^--user import-environment .*WAYLAND_DISPLAY.*NIRI_SOCKET.*PATH' "$SILERE_TEST_LOG"
check grep -qx -- '--user reset-failed silere-shell.service' "$SILERE_TEST_LOG"
check test "$(tail -1 "$SILERE_TEST_LOG")" = '--user start silere-shell.service'
before="$(wc -l < "$SILERE_TEST_LOG")"
SILERE_TEST_SERVICE_ACTIVE=0 bash "$ROOT/scripts/service.sh" start
check test "$(wc -l < "$SILERE_TEST_LOG")" = "$((before+1))"
check test "$(tail -1 "$SILERE_TEST_LOG")" = '--user start silere-shell.service'
if env -u WAYLAND_DISPLAY bash "$ROOT/scripts/service.sh" start 2>/dev/null; then exit 1; fi
checks=$((checks+1))

# The command wrapper uses C for parsing, but a supervised shell needs the caller's locale.
cat > "$scratch/bin/qs" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$scratch/bin/qs"
env -u LC_ALL WAYLAND_DISPLAY=wayland-fixture bash "$ROOT/scripts/silere" run --supervised
check grep -qx 'LC_ALL=unset' "$SILERE_TEST_LOG"
LC_ALL=C WAYLAND_DISPLAY=wayland-fixture bash "$ROOT/scripts/silere" run --supervised
check grep -qx 'LC_ALL=C' "$SILERE_TEST_LOG"

printf 'unmanaged\n' > "$scratch/config/systemd/user/silere-shell.service"
if bash "$ROOT/scripts/service.sh" install 2>/dev/null; then exit 1; fi
check grep -qx unmanaged "$scratch/config/systemd/user/silere-shell.service"
printf 'daily-driver helper fixtures passed (%s checks)\n' "$checks"

PATH="${PATH#"$scratch/bin:"}" bash "$ROOT/dev/test-daily-driver-qml.sh"
