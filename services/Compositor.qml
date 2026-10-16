pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property int maxWindowIdentityChars: 512
    readonly property int maxWindowTitleChars: 2048

    // a terminal's spinner glyph changes its title every frame without changing what it says
    function windowTitle(value): string {
        return SafeText.singleLineText(value, root.maxWindowTitleChars)
            .replace(/^[⠀-⣿◐-◓◴-◷✢-✽] +/, "")
    }

    readonly property string backend: {
        if (String(Quickshell.env("NIRI_SOCKET") || "").length > 0) return "niri"
        if (String(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "").length > 0) return "hyprland"
        return "none"
    }
    readonly property bool isNiri: backend === "niri"
    readonly property bool isHyprland: backend === "hyprland"

    readonly property bool hasSpecialWorkspaces: isHyprland
    readonly property bool perOutputWorkspaceIds: isNiri
    readonly property bool overviewIsLive: isNiri

    readonly property var _be: _backend.item

    readonly property var workspaces:         _be ? _be.workspaces : []
    readonly property var toplevels:          _be ? _be.toplevels : []
    // off the live title path: an animated title would wake every bar per frame
    readonly property var workspaceToplevels: _be ? _be.workspaceToplevels : []
    readonly property var activeToplevel:     _be ? _be.activeToplevel : null
    readonly property string focusedMonitor:  _be ? _be.focusedMonitor : ""
    readonly property int focusedWorkspaceRef: _be ? _be.focusedWorkspaceRef : -1
    readonly property bool overviewActive:    _be ? _be.overviewActive : false
    readonly property Component popupGrab:    _be ? _be.popupGrab : null
    readonly property var specialOutputs:     _be ? _be.specialOutputs : []
    readonly property var keyboardLayouts:    _be && _be.keyboardLayouts ? _be.keyboardLayouts : []
    readonly property int keyboardLayoutIndex: _be && _be.keyboardLayoutIndex !== undefined ? _be.keyboardLayoutIndex : -1
    function nextKeyboardLayout(): void { if (_be && _be.nextKeyboardLayout) _be.nextKeyboardLayout() }
    // the main keyboard is the one a switch applies to; a virtual or headset "keyboard" lists the default layout
    function keyboardLayoutsFromDevices(raw: string): var {
        let devices
        try { devices = JSON.parse(raw) } catch (e) { return { layouts: [], index: -1 } }
        const boards = Array.isArray(devices?.keyboards) ? devices.keyboards : []
        const main = boards.find(k => k && k.main) ?? boards[0]
        if (!main) return { layouts: [], index: -1 }
        const codes = String(main.layout ?? "").split(",")
        const variants = String(main.variant ?? "").split(",")
        const layouts = codes.map((c, i) => ({ code: c.trim(), variant: String(variants[i] ?? "").trim(),
            name: i === Number(main.active_layout_index) ? String(main.active_keymap ?? "") : "" }))
            .filter(l => l.code.length > 0)
        const index = Number(main.active_layout_index)
        return { layouts: layouts, index: isFinite(index) && index >= 0 && index < layouts.length ? index : -1 }
    }
    // an xkb code reads as is ("us" -> US); niri only names the layout, so use its bracketed variant or the first letters
    function _keyboardLayoutBase(layout): string {
        const code = String(layout?.code ?? "").trim()
        if (code.length > 0) return code.slice(0, 4).toUpperCase()
        const name = String(layout?.name ?? "").trim()
        const tag = name.match(/\(([A-Za-z]{2,3})\)/)
        return tag ? tag[1].toUpperCase() : name.slice(0, 2).toUpperCase()
    }
    // two variants of one layout (us and us dvorak) read alike, so later ones take a subscript as GNOME's do
    function keyboardLayoutLabel(layout, layouts): string {
        const base = root._keyboardLayoutBase(layout)
        const list = Array.isArray(layouts) ? layouts : []
        const at = list.indexOf(layout)
        let rank = 1
        for (let i = 0; i < at; i++) if (root._keyboardLayoutBase(list[i]) === base) rank++
        return rank > 1 ? base + String(rank).replace(/[0-9]/g, d => "₀₁₂₃₄₅₆₇₈₉"[d]) : base
    }
    readonly property bool activeFullscreen: isNiri ? !!(_be && _be.activeFullscreen)
        : !!(activeToplevel && activeToplevel.fullscreen)

    // why a translucent surface would show no blur, empty when nothing is known to stop it; niri has no check
    readonly property string blurBlocker: _be && _be.blurBlocker !== undefined ? _be.blurBlocker : ""
    function checkBlur(): void {
        if (root._be && root._be.checkBlur) root._be.checkBlur()
    }

    signal workspaceActivated(string output)
    signal overviewRaw(bool open)

    function monitorName(screen): string {
        if (!screen || !root._be) return ""
        return root._be.monitorName(screen)
    }

    function activeWorkspaceId(output): int {
        const ws = root.workspaces
        for (let i = 0; i < ws.length; i++)
            if (ws[i].output === output && ws[i].active) return ws[i].wsId
        return -1
    }

    function focusWorkspace(wsId, output): void {
        if (wsId === undefined || wsId === null || wsId < 0 || !root._be) return
        root._be.focusWorkspace(wsId, output || "")
    }

    function moveActiveToWorkspace(wsId, output): void {
        if (wsId === undefined || wsId === null || wsId < 1 || !root._be) return
        root._be.moveActiveToWorkspace(wsId, output || "")
    }

    function focusToplevel(c): void {
        if (!c || !root._be) return
        root._be.focusToplevel(c)
    }

    function refreshToplevels(): void {
        if (root._be) root._be.refreshToplevels()
    }

    // apps start in the session, not in this service: a shell restart or crash would close them, the lock screen included
    function launch(argv): void {
        if (!argv || argv.length === 0) return
        const words = []
        for (let i = 0; i < argv.length; i++) words.push(String(argv[i]))
        if (root.isHyprland) HyprDispatch.launch(words)
        else if (root.isNiri)
            Quickshell.execDetached(["sh", "-c", "niri msg action spawn -- \"$@\" >/dev/null 2>&1 || exec \"$@\"", "sh"].concat(words))
        else Quickshell.execDetached(words)
    }

    // the adapter is built with the facade, not on first read: its event socket and
    // rawEvent subscription have to be live before anything asks for a workspace
    Loader {
        id: _backend
        source: root.isNiri ? "CompositorNiri.qml"
              : root.isHyprland ? "CompositorHyprland.qml" : ""
    }

    Connections {
        target: root._be
        ignoreUnknownSignals: true
        function onWorkspaceActivated(output) { root.workspaceActivated(output) }
        function onOverviewRaw(open) { root.overviewRaw(open) }
    }
}
