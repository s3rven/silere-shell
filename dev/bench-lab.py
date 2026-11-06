#!/usr/bin/env python3
# Repeatable measurements of a whole shell in a private nested session: kwin --virtual, Hyprland, its own bus and PipeWire.
# Run it through dev/bench-lab.sh, which provides the private environment this file refuses to start without.
# Timings come from the compositor's own event socket, so reading them costs the shell nothing. Trials run in a
# shuffled order, so drift over a long run lands on every arm alike. One lab at a time: a second shell moves shared
# pages out of this one's PSS (about 7 MB each), which is why long runs judge growth on Pss_Anon, which it cannot touch
import argparse
import json
import os
import random
import shutil
import signal
import socket
import statistics
import subprocess
import sys
import threading
import time

EGL_VENDOR = "/usr/share/glvnd/egl_vendor.d/50_mesa.json"
ALLOCATOR = {"MALLOC_CONF": "narenas:1,tcache:false,background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:0"}
NO_KDE_THEME = {"QT_QPA_PLATFORMTHEME": "", "QT_QUICK_CONTROLS_STYLE": ""}
GRAY_TEXT = {"QSG_DISTANCEFIELD_ANTIALIASING": "gray"}
SURFACES = [
    ("home", "silere-menu", ("menu", "tab", "0"), ("menu", "close")),
    ("settings", "silere-menu", ("menu", "tab", "1"), ("menu", "close")),
    ("history", "silere-menu", ("menu", "tab", "2"), ("menu", "close")),
    ("calendar", "silere-calendar", ("calendar", "toggle"), ("calendar", "toggle")),
    ("quick actions", "silere-quickactions", ("quickActions", "toggle"), ("quickActions", "toggle")),
    # these two open by themselves and leave by themselves, so they are started by what triggers them
    ("notification", "silere-notifications", None, None),
    ("volume osd", "silere-osd", None, None),
]

PLAYER = r'''
import dbus, dbus.mainloop.glib, dbus.service
from gi.repository import GLib
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
P = "org.mpris.MediaPlayer2.Player"
R = "org.mpris.MediaPlayer2"
I = "org.freedesktop.DBus.Properties"
class Player(dbus.service.Object):
    def __init__(self, bus):
        self.n = 0
        super().__init__(dbus.service.BusName("org.mpris.MediaPlayer2.benchlab", bus), "/org/mpris/MediaPlayer2")
    def meta(self):
        return dbus.Dictionary({"mpris:trackid": dbus.ObjectPath(f"/lab/{self.n}"), "xesam:title": dbus.String(f"Track {self.n}"),
            "xesam:artist": dbus.Array([dbus.String(f"Artist {self.n % 7}")], signature="s"),
            "mpris:length": dbus.Int64(180000000)}, signature="sv")
    def props(self):
        return {"PlaybackStatus": dbus.String("Playing"), "Metadata": self.meta(), "Position": dbus.Int64(self.n * 1000000),
            "Rate": dbus.Double(1.0), "Volume": dbus.Double(1.0), "CanGoNext": True, "CanGoPrevious": True, "CanPlay": True,
            "CanPause": True, "CanSeek": True, "CanControl": True}
    def root(self):
        return {"Identity": dbus.String("Bench"), "CanRaise": False, "CanQuit": False, "HasTrackList": False}
    @dbus.service.method(I, in_signature="ss", out_signature="v")
    def Get(self, i, p):
        return (self.props() if i == P else self.root())[p]
    @dbus.service.method(I, in_signature="s", out_signature="a{sv}")
    def GetAll(self, i):
        return self.props() if i == P else self.root()
    @dbus.service.signal(I, signature="sa{sv}as")
    def PropertiesChanged(self, i, c, inv):
        pass
    @dbus.service.method(P)
    def Next(self):
        self.tick()
    @dbus.service.method(P)
    def Previous(self):
        pass
    @dbus.service.method(P)
    def PlayPause(self):
        pass
    def tick(self):
        self.n += 1
        self.PropertiesChanged(P, {"Metadata": self.meta(), "PlaybackStatus": dbus.String("Playing")}, [])
        return True
player = Player(dbus.SessionBus())
GLib.timeout_add_seconds(15, player.tick)
GLib.MainLoop().run()
'''


def refuse_real_session():
    run = os.environ.get("XDG_RUNTIME_DIR", "")
    bus = os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")
    if os.environ.get("SILERE_BENCH_LAB") != run or not run or "/run/user/" in run:
        sys.exit("run this through dev/bench-lab.sh")
    if not bus or "/run/user/" in bus or os.environ.get("SILERE_SANDBOX") != "1" or os.environ.get("XDG_SESSION_ID"):
        sys.exit("refusing to run with anything of the real session in reach")


def quantile(values, q):
    ordered = sorted(values)
    k = (len(ordered) - 1) * q
    low, high = int(k), min(int(k) + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (k - low)


def summary(values):
    values = [v for v in values if v is not None]
    if not values:
        return {"n": 0}
    return {"n": len(values), "median": round(statistics.median(values), 2), "p95": round(quantile(values, 0.95), 2),
            "min": round(min(values), 2), "max": round(max(values), 2)}


def slope(xs, ys):
    mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
    spread = sum((x - mx) ** 2 for x in xs)
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / spread if spread else 0.0


def read_process(pid):
    out = {}
    with open(f"/proc/{pid}/smaps_rollup") as f:
        for line in f:
            parts = line.split()
            if parts[0] in ("Pss:", "Pss_Anon:"):
                out[parts[0][:-1].lower()] = int(parts[1]) / 1024
    js, inside = 0, False
    with open(f"/proc/{pid}/smaps") as f:
        for line in f:
            first = line.split(None, 1)[0]
            if "-" in first and not first.endswith(":"):
                inside = "memfd:JSGCHeap" in line
            elif inside and first == "Pss:":
                js += int(line.split()[1])
    out["js"] = js / 1024
    out["fds"] = len(os.listdir(f"/proc/{pid}/fd"))
    with open(f"/proc/{pid}/status") as f:
        out["threads"] = next(int(line.split()[1]) for line in f if line.startswith("Threads:"))
    seen, vram, gtt = set(), 0, 0
    for fd in os.listdir(f"/proc/{pid}/fdinfo"):
        try:
            with open(f"/proc/{pid}/fdinfo/{fd}") as f:
                info = dict(line.split(":", 1) for line in f if ":" in line)
        except OSError:
            continue
        client = info.get("drm-client-id", "").strip()
        if client and client not in seen:
            seen.add(client)
            vram += int(info.get("drm-memory-vram", "0 KiB").split()[0])
            gtt += int(info.get("drm-memory-gtt", "0 KiB").split()[0])
    out["gpu"] = (vram + gtt) / 1024
    return out


class Lab:
    def __init__(self, args):
        self.root = os.environ["XDG_RUNTIME_DIR"]
        self.procs, self.events, self.lock = [], [], threading.Lock()
        self.shell, self.tree, self.log_path = None, None, None
        self.env = dict(os.environ)
        for key in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "NIRI_SOCKET", "PIPEWIRE_REMOTE"):
            self.env.pop(key, None)
        self.env.update({"__EGL_VENDOR_LIBRARY_FILENAMES": EGL_VENDOR, "PIPEWIRE_RUNTIME_DIR": self.root,
                         "MESA_SHADER_CACHE_DIR": self.root + "/shadercache", "LC_ALL": "C.UTF-8"})
        os.makedirs(self.root + "/logs", exist_ok=True)
        self._write_settings(args.settings)

    def _write_settings(self, source):
        folder = os.environ["XDG_CONFIG_HOME"] + "/silere-shell"
        os.makedirs(folder, exist_ok=True)
        data = {"__version": 2}
        if source:
            with open(source) as f:
                data = json.load(f)
        # the system bus stays real: nothing here may write the power mode, and there is no real night light to adopt
        data.update({"powerProfileRemember": False, "nightLightAuto": False, "nightLightOn": False})
        with open(folder + "/settings.json", "w") as f:
            json.dump(data, f)

    def _spawn(self, argv, env, name):
        log = open(f"{self.root}/logs/{name}.log", "wb")
        proc = subprocess.Popen(argv, env=env, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        self.procs.append(proc)
        return proc

    def _until(self, check, timeout, what):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            value = check()
            if value:
                return value
            time.sleep(0.05)
        raise RuntimeError("timed out waiting for " + what)

    def up(self):
        self._spawn(["kwin_wayland", "--virtual", "--no-lockscreen", "--no-global-shortcuts", "--width", "2560", "--height", "1600",
                     "--socket", "bench-parent"], self.env, "kwin")
        self._until(lambda: os.path.exists(self.root + "/bench-parent"), 15, "kwin")
        config = self.root + "/hypr.lua"
        with open(config, "w") as f:
            f.write('hl.monitor({ output = "", mode = "2560x1600@60", position = "auto", scale = 1.25 })\n'
                    'hl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true, disable_watchdog_warning = true } })\n')
        self._spawn(["Hyprland", "--config", config], dict(self.env, WAYLAND_DISPLAY="bench-parent", AQ_BACKEND="wayland"), "hyprland")

        def instance():
            folder = self.root + "/hypr"
            if os.path.isdir(folder):
                return next((name for name in os.listdir(folder) if os.path.exists(f"{folder}/{name}/.socket2.sock")), None)
            return None
        signature = self._until(instance, 20, "Hyprland")
        display = self._until(lambda: next((name for name in sorted(os.listdir(self.root))
                                            if name.startswith("wayland-") and not name.endswith(".lock")), None), 10, "its socket")
        self.env.update({"WAYLAND_DISPLAY": display, "HYPRLAND_INSTANCE_SIGNATURE": signature, "QT_QPA_PLATFORM": "wayland"})
        threading.Thread(target=self._listen, args=(f"{self.root}/hypr/{signature}/.socket2.sock",), daemon=True).start()
        self._audio_up()
        time.sleep(1)

    def _audio_up(self):
        config = self.root + "/pipewire.conf"
        with open(config, "w") as f:
            f.write("""context.properties = { core.daemon = true, core.name = pipewire-0, default.clock.rate = 48000, support.dbus = false }
context.spa-libs = { audio.convert.* = audioconvert/libspa-audioconvert, support.* = support/libspa-support }
context.modules = [
  { name = libpipewire-module-protocol-native }
  { name = libpipewire-module-metadata }
  { name = libpipewire-module-spa-node-factory }
  { name = libpipewire-module-client-node }
  { name = libpipewire-module-client-device }
  { name = libpipewire-module-adapter }
  { name = libpipewire-module-link-factory }
  { name = libpipewire-module-access, args = { } }
]
context.objects = [
  { factory = spa-node-factory, args = { factory.name = support.node.driver, node.name = Dummy-Driver, node.group = pipewire.dummy, priority.driver = 20000 } }
]
""")
        folder = os.environ["XDG_CONFIG_HOME"] + "/wireplumber/wireplumber.conf.d"
        os.makedirs(folder, exist_ok=True)
        with open(folder + "/90-no-hardware.conf", "w") as f:
            f.write("""wireplumber.profiles = { main = {
  monitor.alsa = disabled, monitor.alsa-midi = disabled, monitor.bluez = disabled, monitor.bluez-midi = disabled,
  monitor.libcamera = disabled, monitor.v4l2 = disabled, support.reserve-device = disabled,
  support.portal-permissionstore = disabled, support.logind = disabled
} }
""")
        self._spawn(["pipewire", "-c", config], self.env, "pipewire")
        self._spawn(["wireplumber"], self.env, "wireplumber")
        self._until(lambda: self.run("wpctl", "status", timeout=2).returncode == 0, 20, "PipeWire")
        self.run("pw-cli", "create-node", "adapter", "{ factory.name=support.null-audio-sink node.name=Bench_Output node.description=Bench_Output "
                 "media.class=Audio/Sink object.linger=true audio.position=[FL,FR] monitor.channel-volumes=true }", timeout=4)

    def _listen(self, path):
        sock = socket.socket(socket.AF_UNIX)
        sock.connect(path)
        pending = b""
        while chunk := sock.recv(65536):
            now = time.monotonic()
            pending += chunk
            while b"\n" in pending:
                line, pending = pending.split(b"\n", 1)
                with self.lock:
                    self.events.append((now, line.decode("utf-8", "replace")))
                    if len(self.events) > 4000:
                        del self.events[:2000]

    def await_event(self, prefix, since, timeout=10.0):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            with self.lock:
                for at, line in self.events:
                    if at >= since and line.startswith(prefix):
                        return at
            time.sleep(0.002)
        return None

    def down(self):
        self.stop_shell()
        for proc in reversed(self.procs):
            if proc.poll() is None:
                proc.terminate()
        end = time.monotonic() + 5
        for proc in self.procs:
            try:
                proc.wait(max(0.1, end - time.monotonic()))
            except subprocess.TimeoutExpired:
                proc.kill()

    def run(self, *argv, timeout=8):
        return subprocess.run(["timeout", str(timeout), *argv], env=self.env, capture_output=True, text=True)

    def start_shell(self, tree, env=None):
        self.tree = tree
        launch = dict(self.env, SILERE_WATCH_FILES="0", QS_PIPEWIRE_IMMEDIATE_RECONNECT="1")
        launch.update(env or {})
        self.log_path = f"{self.root}/logs/shell.log"
        log = open(self.log_path, "wb")
        started = time.monotonic()
        self.shell = subprocess.Popen(["quickshell", "--no-duplicate", "--no-detailed-logs", "-p", tree + "/shell.qml"],
                                      env=launch, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, start_new_session=True)
        mapped = self.await_event("openlayer>>silere-bar", started, 20)
        return None if mapped is None else (mapped - started) * 1000

    def stop_shell(self):
        shell, self.shell = self.shell, None
        if not shell or shell.poll() is not None:
            return
        os.killpg(shell.pid, signal.SIGTERM)
        try:
            shell.wait(6)
        except subprocess.TimeoutExpired:
            os.killpg(shell.pid, signal.SIGKILL)
            shell.wait(3)

    def ipc(self, *args):
        return self.run("qs", "ipc", "-p", self.tree + "/shell.qml", "call", *args).stdout.strip()

    def timed_open(self, namespace, *call):
        # from starting the ipc client, as a keybind does, to the surface's first mapped frame
        started = time.monotonic()
        self.ipc(*call)
        mapped = self.await_event(f"openlayer>>{namespace}", started, 8)
        return None if mapped is None else (mapped - started) * 1000

    def timed_trigger(self, surface, namespace, attempt):
        # from the trigger to the first frame, and then until it has gone again so the next attempt maps afresh
        started = time.monotonic()
        if surface == "notification":
            self.run("notify-send", "-a", "bench", "-t", "900", f"Latency {attempt}", "A short body")
        else:
            self.run("wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{30 + attempt * 5}%")
        mapped = self.await_event(f"openlayer>>{namespace}", started, 8)
        self.await_event(f"closelayer>>{namespace}", started, 12)
        return None if mapped is None else (mapped - started) * 1000

    def close_wait(self, namespace, *call):
        started = time.monotonic()
        self.ipc(*call)
        self.await_event(f"closelayer>>{namespace}", started, 4)

    def errors(self):
        if not self.log_path or not os.path.exists(self.log_path):
            return []
        marks = ("TypeError", "ReferenceError", "Binding loop", "Unable to assign", "Cannot assign", "is not a type")
        with open(self.log_path, errors="replace") as f:
            return [line.rstrip()[:200] for line in f if any(mark in line for mark in marks)]


def forget_caches(tree):
    # shared libraries stay mapped by the desktop around this lab, so this is as cold as a start gets without root
    for folder in (os.environ["XDG_RUNTIME_DIR"] + "/shadercache", os.environ["XDG_CACHE_HOME"] + "/quickshell"):
        shutil.rmtree(folder, ignore_errors=True)
    for base, _, files in os.walk(tree):
        for name in files:
            try:
                fd = os.open(os.path.join(base, name), os.O_RDONLY)
                os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)
                os.close(fd)
            except OSError:
                pass


def trial(lab, tree, env=None):
    # one fresh process: bar up, cold reading, first menu open, warm reading, repeat opens
    row = {"bar_ms": lab.start_shell(tree, env)}
    time.sleep(8)
    cold = read_process(lab.shell.pid)
    row["first_open_ms"] = lab.timed_open("silere-menu", "menu", "tab", "0")
    time.sleep(1.2)
    lab.close_wait("silere-menu", "menu", "close")
    time.sleep(6)
    warm = read_process(lab.shell.pid)
    row.update({"cold_pss": cold["pss"], "cold_anon": cold["pss_anon"], "warm_pss": warm["pss"], "warm_anon": warm["pss_anon"]})
    row["repeat_open_ms"] = []
    for _ in range(3):
        row["repeat_open_ms"].append(lab.timed_open("silere-menu", "menu", "tab", "0"))
        time.sleep(0.7)
        lab.close_wait("silere-menu", "menu", "close")
        time.sleep(0.4)
    row["errors"] = len(lab.errors())
    lab.stop_shell()
    time.sleep(0.5)
    return row


def table(arms, fields):
    width = max(len(name) for name in arms)
    print(" " * width, *(f"{field:>20}" for field in fields))
    for name, rows in arms.items():
        cells = []
        for field in fields:
            values = [v for row in rows for v in (row[field] if isinstance(row[field], list) else [row[field]])]
            stat = summary(values)
            cells.append(f"{stat.get('median', '-'):>10} /{stat.get('p95', '-'):>8}")
        print(f"{name:<{width}}", *cells)
    print("median / p95; ms and MB. Errors logged:", {name: sum(row["errors"] for row in rows) for name, rows in arms.items()})


def run_startup(lab, args, arms):
    plan = [(name, tree, mode) for name, tree in arms.items() for mode in ("no caches", "caches")] * args.n
    random.Random(args.seed).shuffle(plan)
    for tree in arms.values():
        lab.start_shell(tree)
        time.sleep(3)
        lab.stop_shell()
    results = {f"{name}, {mode}": [] for name, _, mode in plan}
    for i, (name, tree, mode) in enumerate(plan, 1):
        if mode == "no caches":
            forget_caches(tree)
        row = trial(lab, tree)
        results[f"{name}, {mode}"].append(row)
        print(f"{i}/{len(plan)} {name}, {mode}: bar {row['bar_ms']:.0f} ms, first open {row['first_open_ms']:.0f} ms, "
              f"{row['cold_pss']:.1f} MB cold, {row['warm_pss']:.1f} MB warm", flush=True)
    table(results, ("bar_ms", "first_open_ms", "repeat_open_ms", "cold_pss", "warm_pss"))
    return results


def run_latency(lab, args, arms):
    plan = list(arms.items()) * args.n
    random.Random(args.seed).shuffle(plan)
    results = {name: {surface[0]: {"first": [], "repeat": []} for surface in SURFACES} for name in arms}
    order = random.Random(args.seed + 1)
    for name, tree in plan:
        lab.start_shell(tree)
        time.sleep(6)
        for surface, namespace, opening, closing in order.sample(SURFACES, len(SURFACES)):
            for attempt in range(4):
                bucket = results[name][surface]["first" if attempt == 0 else "repeat"]
                if opening is None:
                    bucket.append(lab.timed_trigger(surface, namespace, attempt))
                    time.sleep(0.6)
                    continue
                bucket.append(lab.timed_open(namespace, *opening))
                time.sleep(0.7)
                lab.close_wait(namespace, *closing)
                time.sleep(0.45)
        lab.stop_shell()
        time.sleep(0.5)
    print(f"{'':<24}{'first open':>20}{'later opens':>20}   (median / p95 ms, first frame on screen)")
    for name in arms:
        for surface in results[name]:
            first, repeat = summary(results[name][surface]["first"]), summary(results[name][surface]["repeat"])
            print(f"{name + ' ' + surface:<24}{first.get('median', '-'):>11} /{first.get('p95', '-'):>7}{repeat.get('median', '-'):>11} /{repeat.get('p95', '-'):>7}")
    return results


def run_cycles(lab, args, arms):
    plan = [(name, tree, mode) for name, tree in arms.items() for mode in ("home", "every page")] * args.n
    random.Random(args.seed).shuffle(plan)
    results = {}
    for name, tree, mode in plan:
        lab.start_shell(tree)
        time.sleep(8)
        rows = [read_process(lab.shell.pid)]
        for _ in range(args.cycles):
            lab.timed_open("silere-menu", "menu", "tab", "0")
            time.sleep(0.45)
            if mode == "every page":
                for tab in ("1", "2", "0"):
                    lab.ipc("menu", "tab", tab)
                    time.sleep(0.45)
            lab.close_wait("silere-menu", "menu", "close")
            time.sleep(0.35)
            rows.append(read_process(lab.shell.pid))
        time.sleep(60)
        settled = read_process(lab.shell.pid)
        late = range(len(rows) // 2, len(rows))
        growth = slope(list(late), [rows[i]["pss_anon"] for i in late]) * 1024
        results.setdefault(f"{name}, {mode}", []).append({"anon": [round(r["pss_anon"], 1) for r in rows], "settled_anon": settled["pss_anon"],
                                                          "kb_per_cycle": round(growth, 1), "fds": [rows[0]["fds"], rows[-1]["fds"]], "errors": len(lab.errors())})
        print(f"{name}, {mode}: Pss_Anon {rows[0]['pss_anon']:.1f} at start, {rows[1]['pss_anon']:.1f} after one, {rows[-1]['pss_anon']:.1f} after "
              f"{args.cycles}, {settled['pss_anon']:.1f} settled; {growth:+.1f} KB per cycle over the second half; "
              f"fds {rows[0]['fds']} to {rows[-1]['fds']}; JS heap {rows[-1]['js']:.1f} MB", flush=True)
        lab.stop_shell()
        time.sleep(1)
    return results


def run_settings(lab, args, arms):
    tree = next(iter(arms.values()))
    configs = {"session": {}, "+allocator": ALLOCATOR, "+no KDE theme": NO_KDE_THEME, "+gray text": GRAY_TEXT,
               "+allocator, no KDE theme": dict(ALLOCATOR, **NO_KDE_THEME), "all three": dict(ALLOCATOR, **NO_KDE_THEME, **GRAY_TEXT)}
    plan = list(configs) * args.n
    random.Random(args.seed).shuffle(plan)
    results = {name: [] for name in configs}
    for i, name in enumerate(plan, 1):
        results[name].append(trial(lab, tree, configs[name]))
        print(f"{i}/{len(plan)} {name}", flush=True)
    table(results, ("bar_ms", "first_open_ms", "repeat_open_ms", "cold_pss", "warm_pss"))
    return results


def soak_round(lab, i):
    rng = random.Random(i)
    lab.run("notify-send", "-a", "bench", f"Round {i}", "short body")
    lab.run("notify-send", "-a", f"app{i % 6}", f"Long {i}", " ".join(f"word{rng.randrange(9999)}" for _ in range(300)))
    lab.run("notify-send", "-a", "progress", "-r", "4242", f"Progress {i}", f"{i % 100}%")
    for workspace in rng.sample(range(1, 7), 4):
        lab.run("hyprctl", "dispatch", f"hl.dsp.focus({{ workspace = {workspace} }})")
        time.sleep(0.15)
    if i % 3 == 0:
        subprocess.Popen(["timeout", "9", "es2gears_wayland"], env=lab.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(3):
        lab.run("wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{rng.randrange(20, 90)}%")
        time.sleep(0.2)
    lab.ipc("menu", "tab", "0")
    time.sleep(0.5)
    for tab in ("1", "2", "0"):
        lab.ipc("menu", "tab", tab)
        time.sleep(0.5)
    lab.ipc("menu", "close")
    time.sleep(0.5)
    for target in ("calendar", "quickActions"):
        lab.ipc(target, "toggle")
        time.sleep(0.5)
        lab.ipc(target, "toggle")
        time.sleep(0.4)
    if i % 5 == 0:
        lab.ipc("settings", "toggle", "wsShowNumbers")
        time.sleep(0.3)
        lab.ipc("settings", "toggle", "wsShowNumbers")


def run_soak(lab, args, arms):
    # Keep Awake stays on: a nested session gets no input, so the shell would drop into its idle mode after four minutes
    # and most of what could grow would stop running. The same round every minute, one sample per round
    name, tree = next(iter(arms.items()))
    print("bar ms", lab.start_shell(tree), flush=True)
    time.sleep(4)
    lab.ipc("quickActions", "keepAwake")
    if args.workload:
        path = os.environ["XDG_RUNTIME_DIR"] + "/player.py"
        with open(path, "w") as f:
            f.write(PLAYER)
        lab._spawn(["python3", path], lab.env, "player")
    time.sleep(4)
    started = time.monotonic()
    crashes = os.environ["XDG_CACHE_HOME"] + "/quickshell/crashes"
    rows, round_n = [], 0
    while time.monotonic() - started < args.hours * 3600:
        round_n += 1
        round_started = time.monotonic()
        if args.workload:
            soak_round(lab, round_n)
        time.sleep(max(1.0, 60 - (time.monotonic() - round_started) - 0.5))
        if lab.shell.poll() is not None or (os.path.isdir(crashes) and os.listdir(crashes)):
            print(f"the shell went away in round {round_n}", flush=True)
            break
        row = dict(read_process(lab.shell.pid), round=round_n, minutes=round((time.monotonic() - started) / 60, 1), errors=len(lab.errors()))
        rows.append(row)
        if args.out:
            with open(args.out + ".jsonl", "a") as f:
                f.write(json.dumps(row) + "\n")
    for minutes in (5, 30, 120, 360):
        row = next((r for r in rows if r["minutes"] >= minutes), None)
        if row:
            print(f"{name} at {minutes} min: Pss_Anon {row['pss_anon']:.1f} MB, PSS {row['pss']:.1f}, JS heap {row['js']:.1f}, GPU {row['gpu']:.0f}, "
                  f"fds {row['fds']}, threads {row['threads']}, errors {row['errors']}", flush=True)
    return rows


def main():
    parser = argparse.ArgumentParser(description="measure a whole shell in a private nested session")
    parser.add_argument("test", choices=("startup", "latency", "cycles", "settings", "soak"))
    parser.add_argument("--arm", action="append", default=[], metavar="NAME=DIR", help="a checkout to measure, repeatable; default: this one")
    parser.add_argument("--n", type=int, default=None, help="trials per arm; default 20 for startup, 12 for latency, 10 for settings, 2 for cycles")
    parser.add_argument("--cycles", type=int, default=50, help="menu opens per cycles run")
    parser.add_argument("--hours", type=float, default=6.0, help="length of a soak")
    parser.add_argument("--idle", dest="workload", action="store_false", help="soak with Keep Awake on and nothing happening")
    parser.add_argument("--settings", metavar="FILE", help="a settings.json to copy in; default: all defaults")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--out", metavar="FILE", help="write the raw results here as JSON")
    args = parser.parse_args()
    refuse_real_session()
    if args.n is None:
        args.n = {"startup": 20, "latency": 12, "settings": 10, "cycles": 2}.get(args.test, 1)
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    arms = dict(arm.split("=", 1) for arm in args.arm) or {"this checkout": here}
    arms = {name: os.path.abspath(tree) for name, tree in arms.items()}
    lab = Lab(args)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    try:
        lab.up()
        results = globals()["run_" + args.test](lab, args, arms)
        if args.out and args.test != "soak":
            with open(args.out, "w") as f:
                json.dump(results, f, indent=1)
    finally:
        lab.down()


if __name__ == "__main__":
    main()
