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
    property var workspaceAppCounts: Object.create(null)

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

    // only identities on the drawn page can change these icons
    readonly property string _workspaceAppsKey: {
        if (!ShellSettings.wsShowAppIcons) return ""
        const parts = [root._generation, root.monitorName, root.visibleIdsKey]
        const tops = root.workspaceToplevels
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            if (!t || t.output !== root.monitorName || !root._isVisible(t.wsId ?? 0)) continue
            parts.push((t.wsId ?? 0) + ":" + SafeText.singleLineText(
                t.appId, Compositor.maxWindowIdentityChars))
        }
        return parts.join("|")
    }
    on_WorkspaceAppsKeyChanged: root.rebuild()

    function _sameApps(a, b): bool {
        if (!a || a.length !== b.length) return false
        for (let i = 0; i < a.length; i++) {
            if (a[i].appId !== b[i].appId || a[i].icon !== b[i].icon || a[i].name !== b[i].name
                    || a[i].fallback !== b[i].fallback || a[i].count !== b[i].count) return false
        }
        return true
    }

    function rebuild(): void {
        const map = Object.create(null)
        const totals = Object.create(null)
        if (!ShellSettings.wsShowAppIcons) {
            root.workspaceApps = map
            root.workspaceAppCounts = totals
            return
        }
        const groups = Object.create(null)
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
            if (!groups[wid]) groups[wid] = { order: [], apps: Object.create(null) }
            const group = groups[wid]
            if (group.apps[cls]) group.apps[cls].count++
            else {
                group.order.push(cls)
                group.apps[cls] = { raw: rawCls, count: 1 }
            }
        }
        const previous = root.workspaceApps
        for (const wid of Object.keys(groups)) {
            const group = groups[wid]
            totals[wid] = group.order.length
            // keep surviving icons in place; resolve metadata only for the three drawn apps
            const selected = (previous[wid] || []).map(app => app.appId)
                .filter(id => group.apps[id] !== undefined)
            for (const id of group.order) {
                if (selected.length >= 3) break
                if (selected.indexOf(id) < 0) selected.push(id)
            }
            map[wid] = selected.map(id => {
                const app = group.apps[id]
                const meta = root._appMeta(app.raw)
                return { appId: id, icon: meta.icon, name: meta.name,
                    fallback: meta.fallback, count: app.count }
            })
        }
        // a fresh array rebuilds that workspace's icon delegates, which reload and blink; keep every one that did not change
        const ids = Object.keys(map)
        let changed = ids.length !== Object.keys(previous).length
        for (let i = 0; i < ids.length; i++) {
            const old = previous[ids[i]]
            if (root._sameApps(old, map[ids[i]])) map[ids[i]] = old
            else changed = true
        }
        if (changed) root.workspaceApps = map
        const oldTotals = root.workspaceAppCounts
        if (Object.keys(oldTotals).length !== Object.keys(totals).length
                || Object.keys(totals).some(id => oldTotals[id] !== totals[id]))
            root.workspaceAppCounts = totals
    }

    function appsFor(id: int): var { return root.workspaceApps[id] ?? [] }
    function appCountFor(id: int): int { return root.workspaceAppCounts[id] ?? 0 }

    property Connections _applicationsConnection: Connections {
        target: ShellSettings.wsShowAppIcons ? DesktopEntries : null
        function onApplicationsChanged() {
            root._clearAppMetaCache()
            root._generation++
        }
    }

    Component.onCompleted: root.rebuild()
}
