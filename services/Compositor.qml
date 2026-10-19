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
    readonly property bool activeFullscreen: isNiri ? !!(_be && _be.activeFullscreen)
        : !!(activeToplevel && activeToplevel.fullscreen)

    // why a translucent surface would show no blur, empty when nothing is known to stop it; niri has no check
    readonly property string blurBlocker: _be && _be.blurBlocker !== undefined ? _be.blurBlocker : ""
    function checkBlur(): void {
        if (root._be && root._be.checkBlur) root._be.checkBlur()
    }

    signal workspaceActivated(string output)
    signal overviewRaw(bool open)

    // hyprland fires a start per shared frame but also a 250 ms start/stop burst per screenshot
    readonly property int castArmMs: 1500
    readonly property int castReleaseMs: 2000
    readonly property int castForgetMs: 1000
    function castStep(state, kind: string, nowMs: real): var {
        let casts = state.casts, since = state.since, last = state.last, sharing = state.sharing
        if (kind === "start") {
            casts++
            if (since === 0) since = nowMs
            last = nowMs
        } else if (kind === "stop") {
            casts = Math.max(0, casts - 1)
            last = nowMs
        }
        if (casts > 0) {
            if (nowMs - since >= root.castArmMs) sharing = true
        } else if (nowMs - last >= (sharing ? root.castReleaseMs : root.castForgetMs)) {
            sharing = false
            since = 0
        }
        return { casts: casts, since: since, last: last, sharing: sharing }
    }

    property bool screenSharing: false
    // mutated in place: frames arrive at the display rate
    readonly property var _castBox: ({ state: { casts: 0, since: 0, last: 0, sharing: false } })
    property bool _castWatched: false
    function _castApply(kind: string): void {
        const next = root.castStep(root._castBox.state, kind, Date.now())
        root._castBox.state = next
        root.screenSharing = next.sharing
        root._castWatched = next.since > 0 || next.sharing
    }
    Timer {
        interval: 500
        repeat: true
        running: root._castWatched
        onTriggered: root._castApply("tick")
    }

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
        function onScreencast(started) { root._castApply(started ? "start" : "stop") }
    }
}
