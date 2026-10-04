pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../../services"

QtObject {
    id: root

    required property string monitorName
    required property string visibleIdsKey
    required property var visibleIndexById
    required property var workspaceToplevels

    property var _appMetaCache: Object.create(null)
    property int _appMetaCacheSize: 0
    readonly property int _appMetaCacheLimit: 256
    property int _generation: 0
    property var workspaceApps: Object.create(null)

    function _clearAppMetaCache(): void {
        root._appMetaCache = Object.create(null)
        root._appMetaCacheSize = 0
    }

    function _appMeta(cls: string): var {
        const raw = SafeText.singleLineText(
            cls, Compositor.maxWindowIdentityChars).trim()
        const key = raw.toLowerCase()
        if (!key) return null
        if (root._appMetaCache[key] !== undefined) return root._appMetaCache[key]
        if (root._appMetaCacheSize >= root._appMetaCacheLimit)
            root._clearAppMetaCache()
        const meta = IconResolver.appMeta(raw)
        root._appMetaCache[key] = meta
        root._appMetaCacheSize++
        return meta
    }

    function _isVisible(wsId: int): bool {
        return root.visibleIndexById[wsId] !== undefined
    }

    // Niri refreshes its whole window snapshot on a title change; key off identity.
    readonly property string _workspaceAppsKey: {
        if (!ShellSettings.wsShowAppIcons) return ""
        const parts = [root._generation, root.monitorName, root.visibleIdsKey]
        const tops = root.workspaceToplevels
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            if (!t || t.output !== root.monitorName) continue
            parts.push((t.wsId ?? 0) + ":" + SafeText.singleLineText(
                t.appId, Compositor.maxWindowIdentityChars))
        }
        return parts.join("|")
    }
    on_WorkspaceAppsKeyChanged: root.rebuild()
    onVisibleIndexByIdChanged: if (root.workspaceToplevels && root.visibleIndexById)
        root.rebuild()

    function rebuild(): void {
        const map = Object.create(null)
        if (!ShellSettings.wsShowAppIcons) {
            root.workspaceApps = map
            return
        }
        const seen = Object.create(null)
        const tops = root.workspaceToplevels
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            if (!t || t.output !== root.monitorName) continue
            const wid = t.wsId ?? 0
            if (!root._isVisible(wid)) continue
            const rawCls = SafeText.singleLineText(
                t.appId, Compositor.maxWindowIdentityChars)
            const cls = rawCls.toLowerCase()
            if (!cls) continue
            if (!map[wid]) map[wid] = []
            const key = wid + "|" + cls
            if (seen[key] !== undefined) {
                map[wid][seen[key]].count++
                continue
            }
            if (map[wid].length >= 3) continue
            const meta = root._appMeta(rawCls)
            if (!meta) continue
            seen[key] = map[wid].length
            map[wid].push({
                icon: meta.icon,
                name: meta.name,
                fallback: meta.fallback,
                count: 1
            })
        }
        root.workspaceApps = map
    }

    function appsFor(id: int): var { return root.workspaceApps[id] ?? [] }

    property Connections _applicationsConnection: Connections {
        target: ShellSettings.wsShowAppIcons ? DesktopEntries : null
        function onApplicationsChanged() {
            root._clearAppMetaCache()
            root._generation++
        }
    }

    Component.onCompleted: root.rebuild()
}
