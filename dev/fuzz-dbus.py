#!/usr/bin/env python3
# What no well-behaved app sends, one case at a time: notifications, a media player and a tray item, on the private bus
# of dev/test-faults.sh. After each case the shell has to be alive, not restarted by its crash handler, and answering.
# SILERE_FUZZ_KNOWN=1 adds the cases that crash Quickshell itself, to see whether an upstream fix has landed.
import os
import subprocess
import sys
import threading
import time

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

SHELL, PID, CRASHES, MARKER = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
KNOWN = os.environ.get("SILERE_FUZZ_KNOWN") == "1"
ZALGO = "a" + "́" * 60000
String, Int32, Int64, Double, UInt32 = dbus.String, dbus.Int32, dbus.Int64, dbus.Double, dbus.UInt32


def connect():
    return dbus.bus.BusConnection(os.environ["DBUS_SESSION_BUS_ADDRESS"])


def ipc(*args):
    return subprocess.run(["qs", "ipc", "-p", SHELL, "call", *args], capture_output=True, text=True, timeout=10)


def die(reason):
    print(f"FAIL: {reason}", file=sys.stderr, flush=True)
    os._exit(1)


def check(label, slow_ms=1500):
    if os.path.isdir(CRASHES) and os.listdir(CRASHES):
        die(f"{label}: the shell crashed")
    try:
        os.kill(PID, 0)
    except OSError:
        die(f"{label}: the shell exited")
    started = time.time()
    try:
        answered = ipc("settings", "get", "barHeight").returncode == 0
    except subprocess.TimeoutExpired:
        answered = False
    if not answered or (time.time() - started) * 1000 > slow_ms:
        die(f"{label}: the shell stopped answering")


def image(width, height, stride, alpha, bits, channels, data):
    return dbus.Struct((Int32(width), Int32(height), Int32(stride), dbus.Boolean(alpha), Int32(bits), Int32(channels),
                        dbus.ByteArray(data)), signature="iiibiiay")


def notifications():
    server = dbus.Interface(connect().get_object("org.freedesktop.Notifications", "/org/freedesktop/Notifications"),
                            "org.freedesktop.Notifications")

    def send(app="fuzz", replaces=0, icon="", summary="s", body="b", actions=(), hints=None, expire=1500):
        return server.Notify(app, UInt32(replaces), icon, summary, body, dbus.Array(list(actions), signature="s"),
                             dbus.Dictionary(hints or {}, signature="sv"), Int32(expire), timeout=8)

    def close(notification):
        server.CloseNotification(UInt32(notification))

    def replace_after(first, wait=0.0):
        time.sleep(wait)
        send(replaces=first, summary="again", expire=300)

    cases = [
        ("empty", lambda: send(app="", summary="", body="")),
        ("1 MB summary", lambda: send(summary="S" * 1_000_000)),
        ("5 MB body", lambda: send(body="B" * 5_000_000)),
        ("a million lines", lambda: send(body="line\n" * 1_000_000)),
        ("60K combining marks", lambda: send(summary=ZALGO, body=ZALGO)),
        ("bidi and joiners", lambda: send(summary="\u202E" + "evil" * 200, body="\u200D" * 50000)),
        ("emoji flood", lambda: send(body="\U0001F469\u200D\U0001F469\u200D\U0001F467\u200D\U0001F466" * 20000)),
        ("markup and links", lambda: send(summary='<img src="https://example.invalid/x">', body='<a href="javascript:x">y</a>')),
        ("control characters", lambda: send(summary="\x1b[31m\x07\x08", body="\r\r\n\t\x0b\x0c\x7f")),
        ("longest timeout", lambda: send(expire=2147483647)),
        ("negative timeout", lambda: send(expire=-2147483648)),
        ("unknown replaced id", lambda: send(replaces=4294967295)),
        ("odd action list", lambda: send(actions=["only-key"])),
        ("1000 actions", lambda: send(actions=[x for i in range(1000) for x in (f"k{i}", f"label {i}")])),
        ("urgency of the wrong type", lambda: [send(hints={"urgency": v}) for v in (String("high"), dbus.Byte(255), Int32(-5))]),
        ("progress of the wrong type", lambda: [send(hints={"value": v}) for v in (String("x"), Int32(-1), Double(float("nan")))]),
        ("image of the wrong type", lambda: send(hints={"image-data": String("not an image")})),
        ("image with bad channels", lambda: send(hints={"image-data": image(16, 16, 64, True, 3, 7, b"\0" * 1024)})),
        ("image with no size", lambda: send(hints={"image-data": image(0, 0, 0, False, 8, 3, b"")})),
        ("image paths", lambda: [send(hints={"image-path": String(v)}) for v in ("/nonexistent", "/dev/zero", "https://example.invalid/x")]),
        ("icons", lambda: [send(icon=v) for v in ("../../../../etc/passwd", "file:///dev/zero", "i" * 200000)]),
        ("desktop entry traversal", lambda: send(hints={"desktop-entry": String("../../../etc/passwd")})),
        ("10K hints", lambda: send(hints={f"h{i}": Int32(i) for i in range(10000)})),
        ("replace in place 200 times", lambda: [send(replaces=777, summary=f"p{i}", hints={"value": Int32(i % 100)}, expire=500) for i in range(200)]),
        ("replace then close 80 times", lambda: [close(send(replaces=send(summary=f"f{i}", expire=400), summary="a", expire=400)) for i in range(80)]),
        ("replace after expiry", lambda: [replace_after(send(summary=f"e{i}", expire=100), 0.3) for i in range(8)]),
        ("close unknown ids", lambda: [close(v) for v in (0, 99999, 4294967295)]),
        ("burst of 150", lambda: [send(app=f"a{i % 7}", summary=f"burst {i}", expire=300) for i in range(150)]),
    ]
    if KNOWN:
        # quickshell#1313: the size is trusted without a length check
        cases.append(("image larger than its data", lambda: send(hints={"image-data": image(65536, 65536, 262144, True, 8, 4, b"\0" * 64)})))
    for label, case in cases:
        try:
            case()
        except dbus.exceptions.DBusException as error:
            if "NoReply" in str(error) or "Timeout" in str(error):
                die(f"notification {label}: no reply")
        time.sleep(0.4)
        check(f"notification {label}")
    return len(cases)


PLAYER_PATH = "/org/mpris/MediaPlayer2"
PLAYER = "org.mpris.MediaPlayer2.Player"
ROOT = "org.mpris.MediaPlayer2"


class Player(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, PLAYER_PATH)
        self.metadata = dbus.Dictionary({"xesam:title": String("Song")}, signature="sv")

    def all_properties(self, interface):
        none = dbus.Array([], signature="s")
        return {
            ROOT: {"CanQuit": True, "CanRaise": True, "Identity": String("Fuzz"), "HasTrackList": False,
                   "SupportedUriSchemes": none, "SupportedMimeTypes": none},
            PLAYER: {"PlaybackStatus": String("Playing"), "Metadata": self.metadata, "Position": Int64(1000), "Rate": Double(1),
                     "MinimumRate": Double(1), "MaximumRate": Double(1), "Volume": Double(1), "CanGoNext": True, "CanGoPrevious": True,
                     "CanPlay": True, "CanPause": True, "CanSeek": True, "CanControl": True},
        }.get(interface, {})

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        return self.all_properties(interface)[name]

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return self.all_properties(interface)

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ssv")
    def Set(self, interface, name, value):
        pass

    @dbus.service.signal(dbus.PROPERTIES_IFACE, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    def set_metadata(self, metadata):
        self.metadata = metadata
        self.PropertiesChanged(PLAYER, {"Metadata": metadata}, dbus.Array([], signature="s"))


def track(**fields):
    fields = {k.replace("__", ":"): v for k, v in fields.items()}
    fields.setdefault("mpris:trackid", dbus.ObjectPath("/fuzz/1"))
    return dbus.Dictionary(fields, signature="sv")


def media(bus, player):
    artist = lambda *v: dbus.Array([String(x) for x in v], signature="s")
    tracks = [
        ("empty", dbus.Dictionary({}, signature="sv")),
        ("title of the wrong type", track(xesam__title=Int32(5), xesam__artist=Int32(7))),
        ("artist of the wrong shape", track(xesam__title=String("t"), xesam__artist=String("flat"))),
        ("artist list of numbers", track(xesam__title=String("t"), xesam__artist=dbus.Array([Int32(1)], signature="i"))),
        ("negative length", track(xesam__title=String("t"), mpris__length=Int64(-5))),
        ("huge length", track(xesam__title=String("t"), mpris__length=Int64(2 ** 62))),
        ("length of the wrong type", track(xesam__title=String("t"), mpris__length=String("long"))),
        ("60K combining marks", track(xesam__title=String(ZALGO), xesam__artist=artist(ZALGO), xesam__album=String(ZALGO))),
        ("control and bidi", track(xesam__title=String("\x1b[31m\u202Eevil\n\r\t"), xesam__artist=artist("<img src=https://example.invalid/x>"))),
        ("art at /dev/zero", track(xesam__title=String("t"), mpris__artUrl=String("file:///dev/zero"))),
        ("art traversal", track(xesam__title=String("t"), mpris__artUrl=String("file:///../../etc/passwd"))),
        ("art on another host", track(xesam__title=String("t"), mpris__artUrl=String("file://evil.example/x.png"))),
        ("art over http", track(xesam__title=String("t"), mpris__artUrl=String("http://example.invalid/x.png"))),
        ("art that injects", track(xesam__title=String("t2"), mpris__artUrl=String(f"https://x/ -o {MARKER} --next $(touch {MARKER}) `touch {MARKER}`;touch {MARKER}"))),
        ("art that is an option", track(xesam__title=String("t3"), mpris__artUrl=String(f"--output={MARKER}"))),
        ("art of the wrong type", track(xesam__title=String("t5"), mpris__artUrl=Int32(3))),
        ("bad track id", dbus.Dictionary({"mpris:trackid": String("not a path"), "xesam:title": String("t6")}, signature="sv")),
    ]
    if KNOWN:
        # after a notification storm these end in Qt::endPropertyUpdateGroup in about 1 run in 8, the fault site of
        # quickshell#1398. Ordinary metadata does not: 5400 track changes under 3000 notifications never crashed
        tracks += [("1 MB title", track(xesam__title=String("T" * 1000000), xesam__artist=artist("A" * 1000000))),
                   ("1 MB art url", track(xesam__title=String("t4"), mpris__artUrl=String("https://x/" + "y" * 1000000)))]
    ipc("menu", "tab", "3")
    time.sleep(1)
    for label, metadata in tracks:
        GLib.idle_add(player.set_metadata, metadata)
        time.sleep(0.5)
        check(f"player {label}")

    # a signal flood, then a player that keeps leaving
    began = time.time()

    def flood():
        if time.time() - began > 3:
            return False
        for i in range(20):
            player.PropertiesChanged(PLAYER, {"Position": Int64(i * 1000), "Rate": Double(1 + i % 2)}, dbus.Array([], signature="s"))
        return True

    GLib.timeout_add(5, flood)
    time.sleep(3.3)
    check("player signal flood", 3000)

    def bounce():
        bus.release_name("org.mpris.MediaPlayer2.fuzz")
        bus.request_name("org.mpris.MediaPlayer2.fuzz")

    for _ in range(40):
        GLib.idle_add(bounce)
        time.sleep(0.05)
    time.sleep(0.5)
    check("player leaving and returning")
    ipc("menu", "close")
    return len(tracks) + 2


ITEM = "org.kde.StatusNotifierItem"
NO_PIXMAPS = dbus.Array([], signature="(iiay)")
GOOD_ICON = b"\xff\x40\x80\xc0" * (32 * 32)


def pixmap(width, height, data):
    return dbus.Array([dbus.Struct((Int32(width), Int32(height), dbus.ByteArray(data)), signature="iiay")], signature="(iiay)")


class TrayItem(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, "/StatusNotifierItem")
        self.state = {}

    def all_properties(self):
        s = {"name": "", "pixmap": pixmap(32, 32, GOOD_ICON), "title": "fuzz", "status": "Active", "attention": NO_PIXMAPS, **self.state}
        return {"Category": String("ApplicationStatus"), "Id": String("fuzztray"), "Title": String(s["title"]), "Status": String(s["status"]),
                "WindowId": Int32(0), "IconName": String(s["name"]), "IconPixmap": s["pixmap"], "AttentionIconName": String(""),
                "AttentionIconPixmap": s["attention"], "OverlayIconName": String(""), "OverlayIconPixmap": NO_PIXMAPS,
                "ToolTip": dbus.Struct((String(""), NO_PIXMAPS, String("t"), String("b")), signature="sa(iiay)ss"),
                "ItemIsMenu": dbus.Boolean(False), "Menu": dbus.ObjectPath("/NoMenu")}

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        return self.all_properties()[name]

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return self.all_properties()

    @dbus.service.signal(ITEM)
    def NewIcon(self):
        pass

    @dbus.service.signal(ITEM)
    def NewAttentionIcon(self):
        pass

    @dbus.service.signal(ITEM)
    def NewTitle(self):
        pass

    @dbus.service.signal(ITEM, signature="s")
    def NewStatus(self, status):
        pass

    def apply(self, state):
        self.state = state
        self.NewIcon()
        self.NewAttentionIcon()
        self.NewTitle()
        self.NewStatus(state.get("status", "Active"))


def tray(bus):
    if ipc("settings", "set", "trayWidget", "true").returncode != 0:
        die("could not turn the tray on")
    time.sleep(1.5)
    service = f"org.kde.StatusNotifierItem-{os.getpid()}-1"
    name = dbus.service.BusName(service, bus=bus)
    item = TrayItem(bus)
    bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher").RegisterStatusNotifierItem(
        service, dbus_interface="org.kde.StatusNotifierWatcher")
    time.sleep(1)
    many = dbus.Array([dbus.Struct((Int32(16 + i), Int32(16 + i), dbus.ByteArray(b"\0" * ((16 + i) * (16 + i) * 4))), signature="iiay")
                       for i in range(200)], signature="(iiay)")
    cases = [
        ("valid icon", {}),
        ("missing icon name", {"name": "no-such-icon-anywhere", "pixmap": NO_PIXMAPS}),
        ("icon name traversal", {"name": "../../../../etc/passwd", "pixmap": NO_PIXMAPS}),
        ("icon name as an image url", {"name": "image://icon/x?path=/etc", "pixmap": NO_PIXMAPS}),
        ("icon name /dev/zero", {"name": "/dev/zero", "pixmap": NO_PIXMAPS}),
        ("60K combining marks", {"title": ZALGO}),
        ("1 MB title", {"title": "T" * 1000000}),
        ("no pixmaps", {"pixmap": NO_PIXMAPS}),
        ("pixmap with no size", {"pixmap": pixmap(0, 0, b"")}),
        ("negative pixmap size", {"pixmap": pixmap(-1, -1, b"\0" * 64)}),
        ("200 pixmaps", {"pixmap": many}),
        ("unknown status", {"status": "NotAStatus"}),
    ]
    if KNOWN:
        # the same trust as quickshell#1313, in DBusSniIconPixmap::createImage
        cases.append(("pixmap larger than its data", {"pixmap": pixmap(65536, 65536, b"\0" * 64)}))
    for label, state in cases:
        GLib.idle_add(item.apply, state)
        time.sleep(0.8)
        check(f"tray {label}")
    del name
    return len(cases)


def main():
    bus = connect()
    name = dbus.service.BusName("org.mpris.MediaPlayer2.fuzz", bus=bus, do_not_queue=True)
    player = Player(bus)
    loop = GLib.MainLoop()

    def run():
        try:
            only = os.environ.get("SILERE_FUZZ_ONLY", "")
            total = 0
            if only in ("", "notifications"):
                total += notifications()
            if only in ("", "media"):
                total += media(bus, player)
            if only in ("", "tray"):
                total += tray(bus)
            print(f"hostile input passed ({total} cases)", flush=True)
        except Exception as error:  # a fuzzer bug must not read as a pass
            die(f"fuzzer: {type(error).__name__}: {error}")
        GLib.idle_add(loop.quit)

    threading.Thread(target=run, daemon=True).start()
    loop.run()
    del name


main()
