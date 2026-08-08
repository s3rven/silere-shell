pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../config"
import "../../../services"

Item {
    id: root

    property bool barActive: true
    property bool compact: ShellSettings.barCompact

    required property ShellScreen screen

    readonly property int minVisible: ShellSettings.wsMinVisible
    readonly property int btnH:       Metrics.barRowHeight
    readonly property int btnW:       btnH + 2
    readonly property int _iconSz:    Settings.iconSize + 2
    readonly property int gap:        3

    readonly property bool _menuTargetsThisBar: {
        const self = root.screen
        if (!self) return false
        const target = MenuState.triggerScreen
        return target ? target.name === self.name
                      : Monitors.activeName === self.name
    }

    readonly property int effectiveWsCount: Math.max(1, minVisible)
    property int _lastNormalActiveId: 1
    property bool _initialized: false

    implicitWidth:  wsRow.implicitWidth + (urgentOffPage > 0 ? 12 : 0)
    implicitHeight: btnH

    MotionBehavior on implicitWidth {NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic } }

    readonly property string monitorName: Compositor.monitorName(root.screen)
    readonly property bool monitorReady: monitorName.length > 0 && Compositor.activeWorkspaceId(monitorName) > 0
    readonly property bool show: true
    readonly property int  rawActiveId:  Compositor.activeWorkspaceId(root.monitorName)
    readonly property int  activeId:     rawActiveId > 0 ? rawActiveId : _lastNormalActiveId

    readonly property bool inSpecial: Compositor.hasSpecialWorkspaces && Compositor.specialOutput === root.monitorName

    readonly property var _workspaceOwners: {
        const owners = {}
        if (Compositor.isNiri) return owners
        const vals = Compositor.workspaces
        for (let i = 0; i < vals.length; i++) {
            const ws = vals[i]
            if (ws && ws.wsId > 0) owners[ws.wsId] = ws.output
        }
        return owners
    }
    readonly property int _monitorAnchorId: {
        let first = root.activeId > 0 ? root.activeId : 1
        const vals = Compositor.workspaces
        for (let i = 0; i < vals.length; i++) {
            const ws = vals[i]
            if (ws && ws.output === root.monitorName && ws.wsId > 0)
                first = Math.min(first, ws.wsId)
        }
        return first
    }

    function _knownOnOtherMonitor(id: int): bool {
        if (root.monitorName.length === 0) return false
        const owner = root._workspaceOwners[id]
        return owner !== undefined && owner !== root.monitorName
    }

    readonly property var _wsMap: {
        const m = {}
        const vals = Compositor.workspaces
        for (let i = 0; i < vals.length; i++) {
            const ws = vals[i]
            if (ws && ws.output === root.monitorName) m[ws.wsId] = ws
        }
        return m
    }

    function wsObjFor(id) { return root._wsMap[id] ?? null }
    function appsFor(id) { return root._wsApps[id] ?? [] }
    function occupied(id: int): bool {
        const ws = root.wsObjFor(id)
        return (ws !== null && ws.occupied) || root.appsFor(id).length > 0
    }
    function urgent(id: int): bool {
        const ws = root.wsObjFor(id)
        return ws !== null && ws.urgent
    }

    readonly property int urgentOffPage: {
        const vals = Compositor.workspaces
        for (let i = 0; i < vals.length; i++) {
            const ws = vals[i]
            if (ws && ws.output === root.monitorName && ws.urgent && ws.wsId > 0
                && root.visibleIds.indexOf(ws.wsId) < 0)
                return ws.wsId
        }
        return 0
    }

    // Window classes are compositor-supplied, so they must not inherit keys
    // such as "constructor" from Object.prototype.
    property var _appMetaCache: Object.create(null)
    function _appMeta(cls: string): var {
        const raw = String(cls || "").trim()
        const key = raw.toLowerCase()
        if (!key) return null
        if (root._appMetaCache[key] !== undefined) return root._appMetaCache[key]
        const de = DesktopEntries.heuristicLookup(raw)
        const tail = key.indexOf(".") >= 0 ? key.split(".").pop() : ""
        const candidates = [de && de.icon, key, tail].filter(Boolean)
        let src = ""
        for (let i = 0; i < candidates.length && !src; i++)
            src = Quickshell.iconPath(candidates[i], true)
        const meta = { icon: src, name: (de && de.name) || tail || key }
        root._appMetaCache[key] = meta
        return meta
    }
    property int _wsAppsTick: 0
    Connections {
        target: ShellSettings
        function onWsShowAppIconsChanged() {
            root._paging = true
            _pagingReset.restart()
        }
        function onWsMinVisibleChanged() {
            root._paging = true
            _pagingReset.restart()
        }
        function onWorkspaceShiftChanged() {
            if (!ShellSettings.workspaceShift) {
                _groupFadeAnim.stop()
                root.opacity = 1
                root._pageShift = 0
            }
        }
    }

    // DesktopEntries loads async: a class resolved before it's ready caches an empty entry, so drop the cache once entries land
    Connections {
        target: ShellSettings.wsShowAppIcons ? DesktopEntries : null
        function onApplicationsChanged() {
            root._appMetaCache = Object.create(null)
            root._wsAppsTick++
        }
    }

    // niri refreshes its whole window snapshot on a title change; key off identity
    readonly property string _wsAppsKey: {
        if (!ShellSettings.wsShowAppIcons) return ""
        const parts = [root._wsAppsTick, root.monitorName, root.visibleIds.join(",")]
        const tops = Compositor.workspaceToplevels
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            if (!t || t.output !== root.monitorName) continue
            parts.push((t.wsId ?? 0) + ":" + String(t.appId || ""))
        }
        return parts.join("|")
    }

    property var _wsApps: ({})
    on_WsAppsKeyChanged: root._rebuildWsApps()

    function _rebuildWsApps(): void {
        const map = {}
        if (!ShellSettings.wsShowAppIcons) { root._wsApps = map; return }
        const seen = {}
        const shown = {}
        for (let i = 0; i < root.visibleIds.length; i++) shown[root.visibleIds[i]] = true
        const tops = Compositor.workspaceToplevels
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            if (!t || t.output !== root.monitorName) continue
            const wid = t.wsId ?? 0
            if (shown[wid] !== true) continue
            const rawCls = String(t.appId || "")
            const cls = rawCls.toLowerCase()
            if (!cls) continue
            if (!map[wid]) map[wid] = []
            const key = wid + "|" + cls
            if (seen[key] !== undefined) { map[wid][seen[key]].count++; continue }
            if (map[wid].length >= 3) continue
            const meta = root._appMeta(rawCls)
            if (!meta || !meta.icon) continue
            seen[key] = map[wid].length
            map[wid].push({ icon: meta.icon, name: meta.name, count: 1 })
        }
        root._wsApps = map
    }

    readonly property bool markerCovers: ShellSettings.wsActiveMarker !== "bar"

    function _btnW(wsId: int): int {
        if (ShellSettings.wsShowAppIcons && !(wsId === activeId && root.markerCovers)) {
            const apps = root.appsFor(wsId)
            if (apps && apps.length > 0)
                return (root.compact ? 1 : apps.length) * _iconSz
                    + (root.compact ? 0 : (apps.length - 1) * 4) + 10
        }
        return btnW
    }
    function _markerX(markerW: real): real {
        let acc = 0
        const ids = visibleIds
        for (let i = 0; i < ids.length && ids[i] !== activeId; i++)
            acc += _btnW(ids[i]) + gap
        return acc + (_btnW(activeId) - markerW) / 2
    }

    // niri indices are per-output and dynamic, and it always keeps one trailing empty workspace;
    // padding past the last one renders slots focus-workspace cannot resolve. 0 = hyprland, no cap
    readonly property int _idCap: {
        if (!Compositor.isNiri) return 0
        let last = 0
        const vals = Compositor.workspaces
        for (let i = 0; i < vals.length; i++) {
            const ws = vals[i]
            if (ws && ws.output === root.monitorName && ws.wsId > last) last = ws.wsId
        }
        return last
    }

    // hyprland ids are global: skip ids owned by another output or a wide page turns a monitor-local bar into a cross-monitor switcher
    readonly property string _visibleIdsKey: {
        const ids = []
        const anchor = Math.max(1, root._monitorAnchorId)
        const active = Math.max(anchor, root.activeId)
        const cap = root._idCap
        let activeLogicalIndex = 0
        for (let id = anchor; id < active; id++)
            if (!root._knownOnOtherMonitor(id)) activeLogicalIndex++
        const pageStart = Math.floor(activeLogicalIndex / root.effectiveWsCount)
            * root.effectiveWsCount
        let logicalIndex = 0
        for (let id = anchor; ids.length < root.effectiveWsCount; id++) {
            if (cap > 0 && id > cap) break
            if (root._knownOnOtherMonitor(id)) continue
            if (logicalIndex >= pageStart) ids.push(id)
            logicalIndex++
        }
        return ids.join(",")
    }
    readonly property var visibleIds: {
        if (root._visibleIdsKey.length === 0) return []
        const parts = root._visibleIdsKey.split(",")
        const ids = []
        for (let i = 0; i < parts.length; i++) {
            const id = Number(parts[i])
            if (isFinite(id)) ids.push(id)
        }
        return ids
    }

    readonly property int activeIndex: visibleIds.indexOf(activeId)
    readonly property int pageKey: visibleIds.length > 0 ? visibleIds[0] : _monitorAnchorId

    Component.onCompleted: {
        _lastNormalActiveId = activeId
        _prevPageKey = pageKey
        _initialized = monitorReady
        root._rebuildWsApps()
    }

    onRawActiveIdChanged: {
        if (rawActiveId > 0) _lastNormalActiveId = rawActiveId
    }

    onMonitorReadyChanged: {
        if (monitorReady) {
            _lastNormalActiveId = activeId
            _initialized = true
        }
    }

    property bool _paging: false
    Timer { id: _pagingReset; interval: Motion.fast + Motion.width; onTriggered: root._paging = false }

    property int  _prevPageKey: 1
    property int  _pageDir:        1
    property real _pageShift:      0
    transform: Translate { x: root._pageShift }

    onPageKeyChanged: {
        const dir = pageKey >= _prevPageKey ? 1 : -1
        _prevPageKey = pageKey
        if (!_initialized || !monitorReady) {
            root.opacity = 1
            return
        }
        _pageDir = dir
        _paging = true
        _pagingReset.restart()
        if (ShellSettings.workspaceShift) _groupFadeAnim.restart()
        else root.opacity = 1
    }

    SequentialAnimation {
        id: _groupFadeAnim
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: Motion.ms(85);  easing.type: Easing.InCubic }
        ScriptAction    { script: root._pageShift = root._pageDir * 10 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity";    to: 1; duration: Motion.ms(150); easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "_pageShift"; to: 0; duration: Motion.ms(165); easing.type: Easing.OutQuart }
        }
    }

    function activate(id: int): void {
        if (!monitorReady || id < 1 || id === activeId || root._knownOnOtherMonitor(id)) return
        Compositor.focusWorkspace(id, root.monitorName)
    }

    function _scrollTarget(delta: int): int {
        let target = root.activeId
        const direction = delta > 0 ? -1 : 1
        const steps = Math.abs(delta)
        for (let step = 0; step < steps; step++) {
            let candidate = target + direction
            while (candidate > 0 && root._knownOnOtherMonitor(candidate))
                candidate += direction
            if (candidate < 1) break
            target = candidate
        }
        return target
    }

    function _focusWsIndex(index: int): void {
        if (_wsRepeater.count <= 0) return
        const i = Math.max(0, Math.min(_wsRepeater.count - 1, index))
        const item = _wsRepeater.itemAt(i)
        if (item) item.forceActiveFocus()
    }

    function openAnchorMenu(): void {
        const pt = root.mapToItem(null, marker.centerX, 0)
        MenuState.toggleAt(pt.x, root.screen)
    }

    function openQuickActions(): void {
        const pt = root.mapToItem(null, marker.centerX, 0)
        QuickActionsState.toggleAt(pt.x, root.screen, ShellSettings.barPosition === "bottom")
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.monitorReady && ShellSettings.wsScrollSwitch
        onWheel: (event) => {
            event.accepted = true
            const n = Scroll.processControlWheel(event, "workspaces")
            if (n !== 0) root.activate(root._scrollTarget(n))
        }
    }

    property int _hoveredWsId: 0

    // One listener routes pulses to the matching button. Previously every
    // visible workspace kept its own listener and renderer alive while idle.
    Connections {
        target: Notifications
        enabled: root.barActive && ShellSettings.wsNotifPulse
            && !ShellSettings.reduceMotion && !Idle.isIdle
        function onSourcePulse(wsId, critical) {
            const index = root.visibleIds.indexOf(wsId)
            if (index < 0) return
            const button = _wsRepeater.itemAt(index)
            if (button) button.playNotificationPulse(critical)
        }
    }

    WorkspaceMarker {
        id: marker
        style: ShellSettings.wsActiveMarker
        rowHeight: root.btnH
        cellWidth: root._btnW(root.activeId)
        targetX: root.activeIndex >= 0 ? root._markerX(marker.markerWidth) : 0
        shown: root.monitorReady && root.activeIndex >= 0
        inSpecial: root.inSpecial
        urgent: root.urgent(root.activeId)
        menuTargets: root._menuTargetsThisBar
        barActive: root.barActive
        paging: root._paging
        monitorReady: root.monitorReady
        shiftEnabled: ShellSettings.workspaceShift
        hovered: root._hoveredWsId === root.activeId && ShellSettings.barHoverHighlight
    }

    Row {
        id: wsRow
        spacing: root.gap

        Repeater {
            id: _wsRepeater
            model: root.visibleIds

            WorkspaceButton {
                id: ws
                required property int modelData

                wsId:         modelData
                siblingCount: _wsRepeater.count
                monitorReady: root.monitorReady
                active:       root.monitorReady && root.activeId === wsId
                occupied:     root.occupied(wsId)
                urgent:       root.urgent(wsId)
                apps:         root.appsFor(wsId)
                compact:      root.compact
                iconSize:     root._iconSz
                cellWidth:    root._btnW(wsId)
                rowHeight:    root.btnH
                barActive:    root.barActive
                initialized:  root._initialized
                paging:       root._paging
                markerCovers: root.markerCovers

                onActivateRequested:      root.activate(wsId)
                onAnchorMenuRequested:     root.openAnchorMenu()
                onQuickActionsRequested:   root.openQuickActions()
                onMarkerPulseRequested:    marker.pulse()
                onFocusSiblingRequested:   i => root._focusWsIndex(i)
                onHoverReported:           (id, on) => {
                    if (on) root._hoveredWsId = id
                    else if (root._hoveredWsId === id) root._hoveredWsId = 0
                }
            }
        }
    }

    WorkspaceUrgentTick {
        x: wsRow.implicitWidth + 2
        liveId: root.urgentOffPage
        rowHeight: root.btnH
        barActive: root.barActive
        onJumpRequested: id => root.activate(id)
    }
}
