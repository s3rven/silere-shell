pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property int maxWindowIdentityChars: 512
    readonly property int maxWindowTitleChars: 2048

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
    readonly property string specialOutput:   _be ? _be.specialOutput : ""
    readonly property bool activeFullscreen:  !!(activeToplevel && activeToplevel.fullscreen)

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

    function moveActiveToWorkspace(wsId): void {
        if (wsId === undefined || wsId === null || wsId < 1 || !root._be) return
        root._be.moveActiveToWorkspace(wsId)
    }

    function focusToplevel(c): void {
        if (!c || !root._be) return
        root._be.focusToplevel(c)
    }

    function refreshToplevels(): void {
        if (root._be) root._be.refreshToplevels()
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
