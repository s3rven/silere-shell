import QtQuick
import Quickshell

// a bind to `global, silere:menu` reaches the shell without starting a qs ipc client, about 150 ms on a
// 2015 laptop. Only the shell `silere run` started registers: the protocol crashes whichever client takes
// a name last, and previews, smoke starts and probes run beside the live shell. Like the focus grab, global
// shortcuts are an optional Quickshell plugin, so a build without them loses only these binds
QtObject {
    id: root

    readonly property bool owns: Quickshell.env("SILERE_GLOBAL_SHORTCUTS") === "1"
        && Quickshell.env("SILERE_SMOKE_TEST") !== "1"
    // the shortcuts are children of root; holding them here keeps the engine from collecting them
    property list<QtObject> _held

    // built from source text: the linter has no type data for GlobalShortcut's base, PostReloadHook
    function _register(name: string, description: string): void {
        let shortcut = null
        try {
            shortcut = Qt.createQmlObject(
                "import Quickshell.Hyprland\nGlobalShortcut { appid: \"silere\"; name: \"" + name
                    + "\"; description: \"" + description + "\" }",
                root, "CompositorHyprlandShortcuts")
        } catch (e) {
            console.warn("Hyprland global shortcuts are unavailable in this Quickshell build:", e.message ?? e)
            return
        }
        // `pressed` is also a bool property, which JavaScript reads first: the signal is out of reach by name
        shortcut.pressedChanged.connect(() => { if (shortcut.pressed) ControlSurfaces.keybindToggle(name) })
        root._held.push(shortcut)
    }

    Component.onCompleted: {
        if (!root.owns) return
        root._register("menu", "Open or close the Silere menu")
        root._register("tray", "Open the first tray app's menu")
    }
}
