pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../config"
import "../../../services"
import "workspaces"

Item {
    id: root

    property bool barActive: true
    property bool compact: ShellSettings.barCompact

    required property ShellScreen screen

    readonly property int minVisible: ShellSettings.wsMinVisible
    readonly property int btnH:       Metrics.barRowHeight
    readonly property int btnW:       btnH + 2
    readonly property int _iconSz:    Math.round(ShellSettings.barIconSize * ShellSettings.uiScale) + 2
    readonly property int gap:        3
    // updated imperatively because mapToItem() does not expose ancestor geometry dependencies to the QML binding engine
    property real menuAnchorX: 0

    // a keybind opens with no trigger widget, so the states' fallback x has to stay fresh
    readonly property bool _anchorFallbackBar: !!root.screen && root.screen.name === Monitors.overlayBarName

    function _syncMenuAnchor(): void {
        const pt = root.mapToItem(null, marker.centerX, 0)
        if (!isFinite(pt.x)) return
        root.menuAnchorX = pt.x
        root._publishFallbackAnchor()
    }
    function _publishFallbackAnchor(): void {
        if (!root._anchorFallbackBar) return
        MenuState.anchorX = root.menuAnchorX
        QuickActionsState.anchorX = root.menuAnchorX
    }
    on_AnchorFallbackBarChanged: root._syncMenuAnchor()

    readonly property bool _menuTargetsThisBar: {
        const self = root.screen
        if (!self) return false
        const target = MenuState.triggerScreen
        return target ? target.name === self.name
                      : Monitors.activeName === self.name
    }
    readonly property bool _quickActionsTargetsThisBar: {
        const self = root.screen
        if (!self) return false
        const target = QuickActionsState.triggerScreen
        return target ? target.name === self.name
                      : Monitors.activeName === self.name
    }

    readonly property int effectiveWsCount: Math.max(1, minVisible)
    property int _lastNormalActiveId: 1
    property bool _initialized: false


    // the cells ease their own widths; a Behavior on their sum restarts every frame and stalls until they settle
    property real _tickRoom: urgentOffPage > 0 ? 12 : 0
    MotionBehavior on _tickRoom {
        gate: root.barActive
        NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic }
    }
    implicitWidth:  wsRow.implicitWidth + _tickRoom
    implicitHeight: btnH

    readonly property string monitorName: Compositor.monitorName(root.screen)
    readonly property bool monitorReady: monitorName.length > 0 && Compositor.activeWorkspaceId(monitorName) > 0
    // a named hyprland workspace has an id below -1337; only -1 means no data yet
    readonly property bool monitorLive: monitorName.length > 0 && rawActiveId !== -1
    readonly property bool show: true
    readonly property int  rawActiveId:  Compositor.activeWorkspaceId(root.monitorName)
    readonly property int  activeId:     rawActiveId > 0 ? rawActiveId : _lastNormalActiveId
    property int _previousActiveId: 0
    property int _handoffFromId: 0
    property int _handoffToId: 0

    readonly property bool inSpecial: Compositor.hasSpecialWorkspaces && Compositor.specialOutputs.indexOf(root.monitorName) >= 0

    WorkspaceSlotModel {
        id: slotModel
        monitorName: root.monitorName
        activeId: root.activeId
        effectiveWsCount: root.effectiveWsCount
        perOutputWorkspaceIds: Compositor.perOutputWorkspaceIds
        workspaces: Compositor.workspaces
    }

    WorkspaceAppModel {
        id: appModel
        monitorName: root.monitorName
        visibleIdsKey: slotModel.visibleIdsKey
        visibleIds: slotModel.visibleIds
        workspaceToplevels: Compositor.workspaceToplevels
    }

    readonly property var _workspaceIndex: slotModel.workspaceIndex
    readonly property int _monitorAnchorId: slotModel.monitorAnchorId
    readonly property var _wsMap: slotModel.workspaceMap
    readonly property int _idCap: slotModel.idCap
    readonly property var visibleIds: slotModel.visibleIds
    readonly property int slotCount: slotModel.slotCount

    function _knownOnOtherMonitor(id: int): bool {
        return slotModel.knownOnOtherMonitor(id)
    }
    function _visibleIndex(wsId: int): int { return slotModel.visibleIndex(wsId) }

    function wsObjFor(id: int): var { return root._wsMap[id] ?? null }
    function appsFor(id: int): var { return appModel.appsFor(id) }
    function occupied(id: int): bool {
        const ws = root.wsObjFor(id)
        return (ws !== null && ws.occupied) || root.appsFor(id).length > 0
    }
    function urgent(id: int): bool {
        const ws = root.wsObjFor(id)
        return ws !== null && ws.urgent
    }

    property int urgentOffPage: 0

    function _syncUrgentOffPage(): void {
        let next = 0
        const vals = root._workspaceIndex.own
        for (let i = 0; i < vals.length; i++) {
            const ws = vals[i]
            if (ws.urgent && ws.wsId > 0
                    && root._visibleIndex(ws.wsId) < 0) {
                next = ws.wsId
                break
            }
        }
        if (root.urgentOffPage !== next) root.urgentOffPage = next
    }

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
                root._clearWorkspaceHandoffs()
                root._settleGroupMotion()
            }
        }
        function onReduceMotionChanged() {
            if (ShellSettings.reduceMotion) {
                root._clearWorkspaceHandoffs()
                root._settleGroupMotion()
            }
        }
    }
    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (Idle.isIdle) {
                root._clearWorkspaceHandoffs()
                root._settleGroupMotion()
            }
        }
    }

    readonly property bool markerCovers: ShellSettings.wsActiveMarker !== "bar"

    function _btnW(wsId: int): int {
        if (wsId < 0) return 0
        if (ShellSettings.wsShowAppIcons && !(wsId === activeId && root.markerCovers)) {
            const apps = root.appsFor(wsId)
            if (apps && apps.length > 0)
                return (root.compact ? 1 : apps.length) * _iconSz
                    + (root.compact ? 0 : (apps.length - 1) * 4) + 10
        }
        return btnW
    }
    function _cellCenterX(wsId: int): real {
        let acc = 0
        const ids = visibleIds
        for (let i = 0; i < ids.length; i++) {
            if (ids[i] === wsId) return acc + _btnW(ids[i]) / 2
            acc += _btnW(ids[i]) + gap
        }
        return 0
    }
    function _markerX(markerW: real): real {
        return root._cellCenterX(root.activeId) - markerW / 2
    }

    readonly property int activeIndex: root._visibleIndex(root.activeId)
    readonly property int pageKey: visibleIds.length > 0
        ? visibleIds[0] : _monitorAnchorId

    onVisibleIdsChanged: root._syncUrgentOffPage()
    onMonitorNameChanged: root._syncUrgentOffPage()
    Connections {
        target: Compositor
        function onWorkspacesChanged() { root._syncUrgentOffPage() }
    }

    // reordering bar widgets rebuilds this instance under the open menu; every live copy
    // offers itself each time the anchor goes vacant, so a rebuild that outlives its
    // replacement still ends up held by whichever one survives
    function _reclaimPopupAnchors(): void {
        if (root._menuTargetsThisBar) MenuState.adoptAnchor(root)
        if (root._quickActionsTargetsThisBar) QuickActionsState.adoptAnchor(root)
    }
    Connections {
        target: MenuState
        function onAnchorSourceChanged() { root._reclaimPopupAnchors() }
        // mapToItem sees no ancestor geometry, so the cached x is a stale layout pass by now.
        // Measured even when the anchor is already held: opening closes the sibling popups,
        // and a sibling's vacated anchor gets this widget adopted before this handler runs,
        // so a held anchor can still carry an x from before the bar's startup morph settled
        function onOpenChanged() {
            if (MenuState.open) root._syncMenuAnchor()
        }
    }
    Connections {
        target: QuickActionsState
        function onAnchorSourceChanged() { root._reclaimPopupAnchors() }
        function onOpenChanged() {
            if (QuickActionsState.open) root._syncMenuAnchor()
        }
    }

    Component.onCompleted: {
        _lastNormalActiveId = activeId
        _previousActiveId = activeId
        _prevPageKey = pageKey
        _initialized = monitorReady
        root._syncUrgentOffPage()
        root._reclaimPopupAnchors()
    }
    Component.onDestruction: MenuState.cancelWarm(root)

    onRawActiveIdChanged: {
        if (rawActiveId > 0) _lastNormalActiveId = rawActiveId
    }

    // one input event can emit several compositor updates; coalesce to one hand-off
    onActiveIdChanged: {
        const previous = root._previousActiveId
        root._previousActiveId = root.activeId
        if (previous < 1 || previous === root.activeId) return
        if (!_handoffDispatch.running) root._handoffFromId = previous
        root._handoffToId = root.activeId
        _handoffDispatch.restart()
    }

    function _intermediateIndexes(fromIndex: int, toIndex: int): var {
        const out = []
        if (fromIndex < 0 || toIndex < 0 || fromIndex === toIndex) return out
        const direction = toIndex > fromIndex ? 1 : -1
        for (let i = fromIndex + direction; i !== toIndex; i += direction)
            out.push(i)
        return out
    }

    // app icons make cells different widths; an index fraction fades a wide cell before the marker reaches it
    function _handoffDelayAt(fromX: real, toX: real, crossedX: real): int {
        const span = toX - fromX
        if (Math.abs(span) < 0.5) return 0
        const progress = Math.min(1, Math.max(0, (crossedX - fromX) / span))
        // invert the marker's OutQuart travel; a fixed stagger drifts behind on long jumps
        const crossingMs = marker.travelDuration
            * (1 - Math.pow(1 - progress, 0.25))
        return Math.max(0, Math.round(crossingMs - 30))
    }

    function _playWorkspaceHandoff(fromId: int, toId: int): void {
        if (!root._initialized || !root.monitorReady || root._paging
                || !ShellSettings.workspaceShift || ShellSettings.reduceMotion
                || Idle.isIdle) return
        const fromIndex = root._visibleIndex(fromId)
        const toIndex = root._visibleIndex(toId)
        const crossed = root._intermediateIndexes(fromIndex, toIndex)
        const fromX = root._cellCenterX(fromId)
        const toX = root._cellCenterX(toId)
        for (let i = 0; i < crossed.length; i++) {
            const button = _wsRepeater.itemAt(crossed[i])
            if (!button) continue
            button.playMarkerPass(root._handoffDelayAt(
                fromX, toX, root._cellCenterX(root.visibleIds[crossed[i]])))
        }
    }

    function _clearWorkspaceHandoffs(): void {
        _handoffDispatch.stop()
        for (let i = 0; i < _wsRepeater.count; i++) {
            const button = _wsRepeater.itemAt(i)
            if (button) button.clearMarkerPass()
        }
    }

    Timer {
        id: _handoffDispatch
        interval: 0
        onTriggered: root._playWorkspaceHandoff(root._handoffFromId, root._handoffToId)
    }

    onMonitorReadyChanged: {
        if (!monitorReady) {
            root._clearWorkspaceHandoffs()
            return
        }
        _lastNormalActiveId = activeId
        _previousActiveId = activeId
        root._clearWorkspaceHandoffs()
        _initialized = true
    }
    onBarActiveChanged: if (!root.barActive) {
        root._clearWorkspaceHandoffs()
        root._settleGroupMotion()
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
        if (ShellSettings.workspaceShift && root.barActive
                && !ShellSettings.reduceMotion && !Idle.isIdle) {
            _groupFadeAnim.restart()
        } else {
            root._settleGroupMotion()
        }
    }

    // reflow only: the marker slide and the page shift are animations, and following them retargets an open popup's x every frame
    onXChanged: root._syncMenuAnchor()
    onYChanged: root._syncMenuAnchor()
    onImplicitWidthChanged: root._syncMenuAnchor()

    SequentialAnimation {
        id: _groupFadeAnim
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: Motion.ms(85);  easing.type: Easing.InCubic }
        ScriptAction    { script: root._pageShift = root._pageDir * 10 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity";    to: 1; duration: Motion.ms(150); easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "_pageShift"; to: 0; duration: Motion.ms(165); easing.type: Easing.OutQuart }
        }
    }

    function _settleGroupMotion(): void {
        _groupFadeAnim.stop()
        root.opacity = 1
        root._pageShift = 0
    }

    function activate(id: int): void {
        if (!monitorLive) return
        if (id < 1 || id === rawActiveId || root._knownOnOtherMonitor(id)) return
        Compositor.focusWorkspace(id, root.monitorName)
    }

    function moveWindowTo(id: int): void {
        if (!Compositor.activeToplevel) return
        if (id > 0) Compositor.moveActiveToWorkspace(id, root.monitorName)
    }

    function _scrollTarget(delta: int): int {
        let target = root.activeId
        const direction = delta > 0 ? -1 : 1
        const steps = Math.abs(delta)
        const cap = root._idCap
        for (let step = 0; step < steps; step++) {
            let candidate = target + direction
            while (candidate > 0 && root._knownOnOtherMonitor(candidate))
                candidate += direction
            if (candidate < 1) break
            if (cap > 0 && candidate > cap) break
            target = candidate
        }
        return target
    }

    function openAnchorMenu(): void {
        root._syncMenuAnchor()
        MenuState.toggleAt(root.menuAnchorX, root.screen, root)
    }

    function openQuickActions(): void {
        root._syncMenuAnchor()
        QuickActionsState.toggleAt(root.menuAnchorX, root.screen,
            Metrics.barAtBottom, root)
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.monitorLive && ShellSettings.wsScrollSwitch
        onWheel: (event) => {
            event.accepted = true
            const n = Scroll.processControlWheel(event, "workspaces")
            if (n !== 0) root.activate(root._scrollTarget(n))
        }
    }

    property int _hoveredWsId: 0
    readonly property bool _menuWarmIntent: root.barActive
        && root.monitorReady
        && !MenuState.open
        && root._hoveredWsId === root.activeId

    function _syncMenuWarmIntent(): void {
        if (root._menuWarmIntent) {
            _menuWarmRelease.stop()
            if (MenuState.warmSource !== root) _menuWarmDelay.restart()
        } else {
            _menuWarmDelay.stop()
            if (MenuState.warmSource === root) _menuWarmRelease.restart()
        }
    }

    on_MenuWarmIntentChanged: root._syncMenuWarmIntent()

    Timer {
        id: _menuWarmDelay
        // Ignore quick pointer sweeps across the bar. A deliberate hover gets
        // enough time to prepare the menu before the following click.
        interval: 110
        onTriggered: if (root._menuWarmIntent) {
            MenuState.requestWarm(root, root.screen)
            _menuWarmExpiry.restart()
        }
    }

    Timer {
        id: _menuWarmRelease
        // Keep the prepared surface across the short gap between leaving the
        // marker and clicking, then return its memory if no open followed.
        interval: 900
        onTriggered: MenuState.cancelWarm(root)
    }

    Timer {
        id: _menuWarmExpiry
        // A parked pointer is not permanent intent. Bound speculative memory
        // even if no hover edge arrives to start the shorter release timer.
        interval: 2500
        onTriggered: MenuState.cancelWarm(root)
    }

    // one listener routes pulses to the matching button. Previously every visible workspace kept its own listener and renderer alive while idle
    Connections {
        target: Notifications
        enabled: root.barActive && ShellSettings.wsNotifPulse
            && !ShellSettings.reduceMotion && !Idle.isIdle
        function onSourcePulse(wsId, critical) {
            const index = root._visibleIndex(wsId)
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
            model: root.slotCount

            WorkspaceButton {
                id: ws
                required property int index

                wsId:         root.visibleIds[index] ?? -1
                monitorReady: root.monitorLive
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
                onMoveWindowRequested:     root.moveWindowTo(wsId)
                onAnchorMenuRequested:     root.openAnchorMenu()
                onQuickActionsRequested:   root.openQuickActions()
                onMarkerPulseRequested:    marker.pulse()
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
