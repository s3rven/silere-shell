#!/usr/bin/env python3
# Two tray apps for dev/test-tray-keys.sh, on its private bus: one with a real DBus menu that nests two levels
# of submenus plus one it never fills, and one with KDE's "/NoMenu", which Quickshell still asks for a menu. Menu events go to argv[1].
import os
import sys
import time

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
LOG = sys.argv[1]
Int32, String = dbus.Int32, dbus.String
NO_PIXMAPS = dbus.Array([], signature="(iiay)")
ICON = dbus.Array([dbus.Struct((Int32(32), Int32(32), dbus.ByteArray(b"\xff\x40\x80\xc0" * 1024)), signature="iiay")],
                  signature="(iiay)")
MENU_IFACE = "com.canonical.dbusmenu"
ITEM_IFACE = "org.kde.StatusNotifierItem"

# id: (properties, children)
MENU = {
    0: ({}, [1, 2, 3, 4, 5]),
    1: ({"label": "Open"}, []),
    2: ({"label": "Settings", "children-display": "submenu"}, [21, 22]),
    21: ({"label": "Theme", "children-display": "submenu"}, [211, 212]),
    211: ({"label": "Dark"}, []),
    212: ({"label": "Light"}, []),
    22: ({"label": "Sync now"}, []),
    3: ({"type": "separator"}, []),
    4: ({"label": "Quit"}, []),
    # a submenu the app never fills
    5: ({"label": "Recent", "children-display": "submenu"}, []),
}


def log(line):
    with open(LOG, "a") as f:
        f.write(line + "\n")


def layout(node, depth):
    props, kids = MENU[node]
    children = [] if depth == 0 else [layout(k, depth - 1) for k in kids]
    return dbus.Struct((Int32(node), dbus.Dictionary(props, signature="sv"), dbus.Array(children, signature="v")),
                       signature="ia{sv}av")


class Menu(dbus.service.Object):
    @dbus.service.method(MENU_IFACE, in_signature="iias", out_signature="u(ia{sv}av)")
    def GetLayout(self, parent, depth, names):
        return (dbus.UInt32(1), layout(int(parent), int(depth)))

    @dbus.service.method(MENU_IFACE, in_signature="aias", out_signature="a(ia{sv})")
    def GetGroupProperties(self, ids, names):
        return dbus.Array([dbus.Struct((Int32(i), dbus.Dictionary(MENU[int(i)][0], signature="sv")), signature="ia{sv}")
                           for i in ids if int(i) in MENU], signature="(ia{sv})")

    @dbus.service.method(MENU_IFACE, in_signature="is", out_signature="v")
    def GetProperty(self, node, name):
        return MENU[int(node)][0].get(name, "")

    @dbus.service.method(MENU_IFACE, in_signature="isvu", out_signature="")
    def Event(self, node, event, data, timestamp):
        log(f"event {int(node)} {event}")

    @dbus.service.method(MENU_IFACE, in_signature="a(isvu)", out_signature="ai")
    def EventGroup(self, events):
        for node, event, data, timestamp in events:
            log(f"event {int(node)} {event}")
        return dbus.Array([], signature="i")

    @dbus.service.method(MENU_IFACE, in_signature="i", out_signature="b")
    def AboutToShow(self, node):
        return False

    @dbus.service.method(MENU_IFACE, in_signature="ai", out_signature="aiai")
    def AboutToShowGroup(self, ids):
        return (dbus.Array([], signature="i"), dbus.Array([], signature="i"))

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        return self.GetAll(interface)[name]

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return {"Version": dbus.UInt32(3), "TextDirection": String("ltr"), "Status": String("normal"),
                "IconThemePath": dbus.Array([], signature="s")}


class Item(dbus.service.Object):
    def __init__(self, bus, ident, title, menu):
        super().__init__(bus, "/StatusNotifierItem")
        self.props = {"Category": String("ApplicationStatus"), "Id": String(ident), "Title": String(title),
                      "Status": String("Active"), "WindowId": Int32(0), "IconName": String(""), "IconPixmap": ICON,
                      "AttentionIconName": String(""), "AttentionIconPixmap": NO_PIXMAPS,
                      "OverlayIconName": String(""), "OverlayIconPixmap": NO_PIXMAPS,
                      "ToolTip": dbus.Struct((String(""), NO_PIXMAPS, String(title), String("")), signature="sa(iiay)ss"),
                      "ItemIsMenu": dbus.Boolean(False), "Menu": dbus.ObjectPath(menu)}

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        return self.props[name]

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return self.props

    @dbus.service.method(ITEM_IFACE, in_signature="ii", out_signature="")
    def Activate(self, x, y):
        log("activate")

    @dbus.service.method(ITEM_IFACE, in_signature="ii", out_signature="")
    def SecondaryActivate(self, x, y):
        log("secondary")

    @dbus.service.method(ITEM_IFACE, in_signature="ii", out_signature="")
    def ContextMenu(self, x, y):
        log("context menu")

    @dbus.service.method(ITEM_IFACE, in_signature="is", out_signature="")
    def Scroll(self, delta, orientation):
        pass


def connect():
    return dbus.bus.BusConnection(os.environ["DBUS_SESSION_BUS_ADDRESS"])


# the probe's own tray hosts the watcher, so wait for it rather than for a fixed time
watcher = connect()
for _ in range(400):
    if watcher.name_has_owner("org.kde.StatusNotifierWatcher"):
        break
    time.sleep(0.05)
else:
    log("no watcher")
    sys.exit(1)

held = []
# one connection each: both serve /StatusNotifierItem
for n, (ident, title, menu) in enumerate([("labapp", "Lab App", "/MenuBar"), ("plainapp", "Plain App", "/NoMenu")], 1):
    bus = connect()
    service = f"org.kde.StatusNotifierItem-{os.getpid()}-{n}"
    held += [bus, dbus.service.BusName(service, bus=bus), Item(bus, ident, title, menu)]
    if menu != "/NoMenu":
        held.append(Menu(bus, menu))
    bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher").RegisterStatusNotifierItem(
        service, dbus_interface="org.kde.StatusNotifierWatcher")
    # registration order is tray order
    time.sleep(0.3)
log("registered")
GLib.MainLoop().run()
