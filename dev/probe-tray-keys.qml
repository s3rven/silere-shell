pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "config"
import "services"
import "modules/bar"
import "modules/traymenu"

// run through test-tray-keys.sh: a virtual KWin, a private bus and dev/fake-tray-menu.py's two apps.
// Real key events go to the menu's own window, so the timers a pointer drives also run here.
ShellRoot {
    id: root
    readonly property var screen0: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    property int checks: 0
    property int fails: 0
    property var keys: null
    property var trayWidget: null

    Bar { id: bar; targetScreen: root.screen0 }
    TrayMenuPopup { id: tray; targetScreen: root.screen0 }

    Process {
        id: ipc
        property string answer: ""
        stdout: StdioCollector { onStreamFinished: ipc.answer = text.trim() }
    }

    function find(item, predicate): var {
        if (!item) return null
        if (predicate(item)) return item
        const children = item.children || []
        for (let i = 0; i < children.length; i++) {
            const found = root.find(children[i], predicate)
            if (found) return found
        }
        return null
    }
    function check(ok: bool, message: string): void {
        root.checks++
        if (ok) return
        root.fails++
        console.warn("PROBE-FAIL tray keys :: " + message + " (focus on " + root.focused()
            + ", submenus open: " + (root.openFlyouts() || "none") + ")")
    }
    function focused(): string {
        const card = tray.popupCard
        const item = card ? card.Window.activeFocusItem : null
        if (!item) return "nothing"
        if (item === card) return "the card"
        if (item.trayId !== undefined) return "Hide from bar"
        return item.label !== undefined ? String(item.label) : String(item)
    }
    function openFlyouts(): string {
        const names = []
        const kids = tray.stage.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i] && kids[i].opened === true && kids[i].ownerRow) names.push(kids[i].ownerRow.label)
        return names.sort().join(",")
    }
    function source(): string { return String(TrayMenuState.sourceItem?.id ?? "") }
    function wait(ms: int): void { root.keys.wait(ms) }
    // past the 180 ms a pointer-opened submenu waits before it closes
    function key(k: int, settle: int): void { root.keys.keyClick(k); root.wait(settle ?? 60) }
    function call(): string {
        ipc.answer = ""
        ipc.command = ["qs", "ipc", "-p", Quickshell.env("SILERE_PROBE_SELF"), "call", "tray", "toggle"]
        ipc.running = true
        for (let i = 0; i < 200 && (ipc.running || ipc.answer === ""); i++) root.wait(50)
        root.wait(300)
        return ipc.answer
    }

    function run(): void {
        root.keys = Qt.createQmlObject('import QtTest; TestCase { when: false }', tray.stage)
        ShellSettings.trayWidget = true
        let tiles = []
        for (let i = 0; i < 300; i++) {
            root.wait(50)
            root.trayWidget = root.find(bar.contentItem ?? null,
                item => item.accessibleName === "System tray" && typeof item._tiles === "function")
            tiles = root.trayWidget ? root.trayWidget._tiles().filter(t => t && t.keyboardStop) : []
            if (tiles.length === 2 && tiles.every(t => t.modelData.hasMenu)) break
        }
        root.check(tiles.length === 2, "both fake tray apps show on the bar (" + tiles.length + ")")
        if (tiles.length !== 2) return
        const ids = tiles.map(t => String(t.modelData.id))
        root.check(ids.join(",") === "labapp,plainapp", "tray order follows registration (" + ids + ")")
        const lab = tiles[ids.indexOf("labapp")]

        root.check(root.call() === "ok" && TrayMenuState.open && root.source() === "labapp",
            "tray toggle opens the first app's menu")
        root.check(root.focused() === "Open", "a menu opened from the keyboard lands on its first entry")
        root.key(Qt.Key_Down)
        root.check(root.focused() === "Settings", "Down moves to the next entry")
        root.key(Qt.Key_Right, 500)
        root.check(root.focused() === "Theme" && root.openFlyouts() === "Settings",
            "Right opens a submenu on its first entry, and it stays open")
        root.key(Qt.Key_Down)
        root.check(root.focused() === "Sync now", "Down walks the submenu")
        root.key(Qt.Key_Down)
        root.check(root.focused() === "Theme", "Down wraps inside the submenu, never into the menu behind it")
        root.key(Qt.Key_Up)
        root.check(root.focused() === "Sync now", "Up wraps back")
        root.key(Qt.Key_Up)
        root.key(Qt.Key_Right, 500)
        root.check(root.focused() === "Dark" && root.openFlyouts() === "Settings,Theme",
            "a nested submenu opens on its first entry, and both stay open")
        root.key(Qt.Key_Escape, 400)
        root.check(TrayMenuState.open && root.focused() === "Theme" && root.openFlyouts() === "Settings",
            "Escape closes only the innermost submenu and returns to its entry")
        root.key(Qt.Key_Left, 400)
        root.check(TrayMenuState.open && root.focused() === "Settings" && root.openFlyouts() === "",
            "Left closes the submenu and returns to its entry")
        root.key(Qt.Key_Return, 500)
        root.check(root.focused() === "Theme" && root.openFlyouts() === "Settings",
            "Enter on a submenu entry opens it with focus inside, and it stays open")
        root.key(Qt.Key_Escape, 300)
        root.key(Qt.Key_Escape, 400)
        root.check(!TrayMenuState.open, "Escape from the menu's own level closes it")

        root.trayWidget._openMenu(lab.modelData, lab)
        root.wait(400)
        root.check(TrayMenuState.open && root.focused() === "the card", "a menu opened by pointer focuses no entry")
        root.key(Qt.Key_Down)
        root.check(root.focused() === "Open", "Down from a pointer-opened menu reaches its first entry")
        root.key(Qt.Key_Up)
        root.check(root.focused() === "Hide from bar", "Up wraps to Hide from bar")
        root.key(Qt.Key_Right, 500)
        root.check(root.source() === "plainapp" && root.focused() === "Hide from bar",
            "Right on a plain entry opens the next app's menu, and an app with no entries lands on Hide from bar")
        root.key(Qt.Key_Right, 400)
        root.check(root.source() === "labapp" && root.focused() === "Open", "Right wraps back to the first app")
        root.key(Qt.Key_Left, 500)
        root.check(root.source() === "plainapp", "Left opens the previous app's menu")
        root.key(Qt.Key_Left, 400)
        root.check(root.source() === "labapp" && root.focused() === "Open", "Left wraps too")
        root.key(Qt.Key_Up)
        root.key(Qt.Key_Up)
        root.key(Qt.Key_Right, 500)
        root.check(root.focused() === "Recent" && root.openFlyouts() === "Recent",
            "a submenu the app never fills opens and keeps the focus on its entry")
        root.key(Qt.Key_Left, 400)
        root.check(root.source() === "labapp" && root.focused() === "Recent" && root.openFlyouts() === "",
            "Left closes that submenu rather than leaving for the previous app")
        root.key(Qt.Key_Right, 500)
        root.key(Qt.Key_Escape, 400)
        root.check(TrayMenuState.open && root.focused() === "Recent" && root.openFlyouts() === "",
            "Escape closes that submenu rather than the menu")
        root.key(Qt.Key_Down)
        root.key(Qt.Key_Down)
        root.key(Qt.Key_Down)
        root.key(Qt.Key_Down)
        root.check(root.focused() === "Quit", "Down skips a separator")
        root.key(Qt.Key_Return, 400)
        root.check(!TrayMenuState.open, "Enter on an entry without a submenu closes the menu")

        root.call()
        root.check(TrayMenuState.open, "tray toggle opens the menu again")
        root.check(root.call() === "ok" && !TrayMenuState.open, "a second tray toggle closes it")
        ShellSettings.trayWidget = false
        root.wait(200)
        const hidden = root.call()
        root.check(hidden.indexOf("error:") === 0 && !TrayMenuState.open,
            "tray toggle with the tray hidden answers with an error (" + hidden + ")")
    }

    Timer {
        interval: 500
        running: true
        onTriggered: {
            try { root.run() } catch (error) { root.fails++; console.warn("PROBE-FAIL tray keys :: aborted: " + String(error)) }
            console.log("PROBE-TRAY-KEYS done " + root.checks + " checks, " + root.fails + " failed")
            Qt.quit()
        }
    }
}
