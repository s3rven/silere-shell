pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../services"
import "../common"
import "controls"
import "settings"

PanelWindow {
    id: win

    required property ShellScreen targetScreen
    readonly property var popupCard: panel

    readonly property string _output: Compositor.monitorName(win.screen)

    Connections {
        target: Compositor
        function onWorkspaceActivated(output) {
            if (output === win._output && MenuState.open) MenuState.close()
        }
    }

    screen:        targetScreen
    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "silere-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // full screen only to catch the closing click: the compositor recomposites every pixel of a surface Qt redraws, so the panel animates in its own narrow window
    visible: MenuState.open || cardWin.visible
    // layer surfaces stack in map order: mapped after the panel, this window would cover it and take its clicks
    property bool _cardMayMap: false
    onVisibleChanged: {
        if (visible) Qt.callLater(() => win._cardMayMap = win.visible)
        else win._cardMayMap = false
    }

    anchors {
        top:    true
        left:   true
        right:  true
        bottom: true
    }

    Shortcut {
        sequence: "Escape"
        context:  Qt.ApplicationShortcut
        enabled:  MenuState.open
        onActivated: {
            if (panel.powerOpen) {
                panel.powerOpen = false
            } else if (panel.activeTab === 0 && homeLoader.item && homeLoader.item.dismissInline()) {
            } else if (panel.activeTab === 1 && settingsLoader.item && settingsLoader.item.dismissInline()) {
            } else if (panel.activeTab === 2 && recentLoader.item && recentLoader.item.dismissInline()) {
            } else {
                MenuState.close()
            }
        }
    }

    OutsideTapGuard {
        id: _tapGuard
        open: MenuState.open
    }

    Item { id: _fillArea; anchors.fill: parent }
    mask: Region { item: MenuState.open ? _fillArea : null }
    // an empty region, not none: the silere-menu layer rule would otherwise blur the whole screen behind this window
    BackgroundEffect.blurRegion: Region { item: null }

    function _outsideCard(p: point): bool {
        return p.x < panel.x || p.x > panel.x + panel.width ||
            p.y < panel.y || p.y > panel.y + panel.height
    }

    function _closeIfOutside(p: point): void {
        if (!_tapGuard.ignoring && _outsideCard(p)) MenuState.close()
    }

    TapHandler {
        id: _dismiss
        enabled: MenuState.open
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onTapped: win._closeIfOutside(_dismiss.point.position)
    }

    PanelWindow {
        id: cardWin

        // room for the shadow; snapped so a moving anchor rarely reconfigures the surface
        readonly property int _slack: 48
        readonly property real _screenW: win.screen ? win.screen.width : 0
        readonly property int _left: Math.max(0,
            64 * Math.floor((panel.placementSpan.x - _slack) / 64))
        readonly property int _right: Math.min(Math.ceil(_screenW),
            64 * Math.ceil((panel.placementSpan.y + panel.targetWidth + _slack) / 64))

        screen:        win.screen
        color:         "transparent"
        exclusiveZone: -1
        WlrLayershell.namespace: "silere-menu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: MenuState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        visible: (MenuState.open || panel.opacity > 0.001) && win._cardMayMap

        anchors { top: true; bottom: true; left: true }
        margins.left: cardWin._left
        implicitWidth: Math.max(1, cardWin._right - cardWin._left)

        // the panel alone: anywhere else in the strip has to fall through to the closing window below
        mask: Region {
            item: MenuState.open ? panel : null
            Region { item: _stage; intersection: Intersection.Intersect }
        }
        BackgroundEffect.blurRegion: Region {
            item: panel.blurItem
            radius: Math.round(panel.radius)
            // a region rebuilds only when one of its own items moves, and the stage carries every panel x shift
            Region { item: _stage; intersection: Intersection.Intersect }
        }

        // screen coordinates: the panel places itself as it did in a full-screen window
        Item {
            id: _stage
            x: -cardWin._left
            width: cardWin._screenW
            height: parent.height

            // hyprland hands every click to the exclusive-focus surface, so one outside the panel lands here, not on the window below; a MouseArea because pointer handlers drop points outside their window, oversized because a click on another monitor arrives offset by the layout
            MouseArea {
                id: _outsideCatch
                anchors.fill: parent
                anchors.margins: -16384
                enabled: MenuState.open
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: mouse => mouse.accepted = win._outsideCard(_outsideCatch.mapToItem(_stage, mouse.x, mouse.y))
                onClicked: mouse => win._closeIfOutside(_outsideCatch.mapToItem(_stage, mouse.x, mouse.y))
            }

            PopupShadow { card: panel }

            FloatingPopupCard {
                id: panel

                win: win
                open: MenuState.open
                anchorX: MenuState.effectiveAnchorX
                // glass makes the rail and pane tints over this, so the blur reads through; opaque, they cover every pixel and a translucent fill would only buy a blur pass nothing shows
                color: Theme.glass ? Theme.popup : Theme.background
                barBottom: Metrics.barAtBottom
                targetWidth: placementW
                animateScale: true
                scaleUniform: false
                animatePlacement: false
                clip: true

                // the rail cap and the detail pane are both px while a category label scales with
                // uiScale, so each end takes the same growth: the pane keeps its width and the
                // longest label, 13 characters, stops eliding at the top of the type range
                readonly property int _typeGain: Metrics.snap4(
                    13 * 0.6 * Math.max(0, Settings.fontSize - Settings.fontSizeBase))

                // every panel width stays on the 4px grid, or the outline's right edge lands on a half output px at fractional scale and rasterizes wider than its left
                readonly property int _compactW: 400
                readonly property int _powerW: 568
                readonly property int _settingsW: 632 + _typeGain
                readonly property int _recentBaseW: 492 + _typeGain
                readonly property int _recentW: _recentBaseW + _navMaxW + 12
                readonly property bool _settingsNavVisible:
                    activeTab === 1 && !powerOpen
                // one app cannot be filtered against anything, so the drawer stays out of its way
                readonly property bool _recentNavVisible:
                    activeTab === 2 && !powerOpen && Notifications.historyApps.length > 1
                readonly property bool _railExpanded:
                    _settingsNavVisible || _recentNavVisible || powerOpen
                readonly property int _targetPanelW: activeTab === 1 ? _settingsW
                    : powerOpen ? _powerW
                    : activeTab === 2 ? (_recentNavVisible ? _recentW : _recentBaseW)
                    : _compactW
                // x is clamped once, against the widest page, so switching tabs never moves the card
                readonly property int _widestW: Math.max(_settingsW, _recentW)
                readonly property int _availablePanelW: winW > 0
                    ? Math.max(4, Metrics.snap4Down(winW - _minX * 2))
                    : _widestW
                readonly property int panelW: Math.max(1,
                    Math.min(_targetPanelW, _availablePanelW))
                readonly property int placementW: Math.max(1,
                    Math.min(_widestW, _availablePanelW))
                readonly property int railCollapsedW: 44
                readonly property int _navMinW: 112
                readonly property int _navMaxW: 160 + _typeGain
                readonly property int navW: {
                    const available = panelW - railCollapsedW
                    const desired = Math.max(_navMinW, Metrics.snap4(panelW * 0.28))
                    const detailSafe = Math.max(_navMinW, available - 224)
                    const sidebarFit = Math.max(0, available - 96)
                    return Math.max(0, Math.min(_navMaxW, desired, detailSafe, sidebarFit))
                }
                readonly property int railExpandedW: railCollapsedW + navW
                // animated here, not on the rail Item: the content pane derives its x and width from this, and easing only the rail leaves the content snapping ahead of it
                property int railW: _railExpanded ? railExpandedW : railCollapsedW
                MotionBehavior on railW {
                    id: _railMotion
                    gate: panel._geometryReady && panel.open
                    NumberAnimation {
                        duration: _railMotion.targetValue > panel.railCollapsedW
                            ? Motion.panelResize : Motion.panelCollapse
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: _railMotion.targetValue > panel.railCollapsedW
                            ? Motion.emphasizedDecel : Motion.emphasizedAccel
                    }
                }
                // live width, not the target: the page reflows ahead of the outer edge otherwise
                readonly property int contentW: Math.max(1, Math.round(width - railW))
                readonly property int contentPad: activeTab === 1
                    ? Math.max(12, Math.min(20,
                        Metrics.snap4(12 + (width - _compactW) * 8 / (_settingsW - _compactW))))
                    : _railExpanded && width >= 460 ? 18 : 12
                readonly property int innerW: Math.max(1, contentW - contentPad * 2)
                readonly property int idealMinH: activeTab === 2 ? 440 : 360
                readonly property int minRailFitH: 252
                readonly property int pageTopInset: 12
                readonly property int pageBottomInset: 12
                // snapped like the content height it clamps: a floor() here puts the bottom edge on a
                // different output-pixel phase from the top whenever the screen is the limit
                readonly property int _availablePanelH: winH > 0
                    ? Math.max(4, Metrics.snap4Down(winH - _edgeY - _minX))
                    : contentPane.targetH
                readonly property int recentViewportH: Metrics.historyViewportFor(
                    panel._availablePanelH - panel.pageTopInset - panel.pageBottomInset,
                    recentLoader.item ? recentLoader.item.wantedHeight : 0)
                readonly property int _resolvedPanelH: Math.max(1,
                    Math.min(contentPane.targetH, _availablePanelH))
                // a lazy page reports its placeholder height first; holding the edge gives a tab switch one destination instead of shrinking then growing
                readonly property int targetPanelH: _tabHeightHeld
                    ? Math.max(1, Math.min(_tabHeldH, _availablePanelH))
                    : _resolvedPanelH

                readonly property int activeTab: MenuState.activeTab

                property bool powerOpen: false
                property bool _loadedDeferred: false
                property bool _geometryReady:  false
                property bool _outerHeightMotion: false
                property bool _tabHeightHeld: false
                property int  _tabHeldH: idealMinH
                property bool _homeRetained:    false
                property bool _settingsRetained: false
                property bool _recentRetained:  false
                property bool _settingsNavRetained: false

                Component.onCompleted: {
                    panel._shownH = panel.targetPanelH
                    if (activeTab !== 0) _loadedDeferred = true
                    if (activeTab === 1) _settingsNavRetained = true
                    panel._syncPageRetention()
                    Qt.callLater(function() { panel._geometryReady = true })
                }

                function _syncPageRetention(): void {
                    if (activeTab === 0) {
                        _homeUnload.stop()
                        _homeRetained = true
                    } else if (_homeRetained) {
                        _homeUnload.restart()
                    }

                    if (activeTab === 1)
                        _settingsNavRetained = true

                    if (!_loadedDeferred) {
                        _settingsUnload.stop()
                        _recentUnload.stop()
                        _settingsRetained = false
                        _recentRetained = false
                        return
                    }

                    if (activeTab === 1) {
                        _settingsWarmUnload.stop()
                        _settingsUnload.stop()
                        _settingsRetained = true
                    } else if (_settingsRetained) {
                        _settingsUnload.restart()
                    }

                    if (activeTab === 2) {
                        _recentUnload.stop()
                        _recentRetained = true
                    } else if (_recentRetained) {
                        _recentUnload.restart()
                    }
                }

                on_LoadedDeferredChanged: _syncPageRetention()

                // settings costs ~60ms to build and it lands on the tap that starts the widen
                function warmSettings(): void {
                    if (!MenuState.open || panel.activeTab === 1
                            || panel._settingsRetained) return
                    panel._loadedDeferred = true
                    panel._settingsRetained = true
                    panel._settingsNavRetained = true
                    _settingsWarmUnload.restart()
                }

                function _settlePageVisuals(): void {
                    if (homeLoader.item) homeLoader.item.settleVisual(activeTab === 0)
                    if (settingsLoader.item) settingsLoader.item.settleVisual(activeTab === 1)
                    if (recentLoader.item) recentLoader.item.settleVisual(activeTab === 2)
                }

                onCloseFinished: {
                    if (open) return
                    _settlePageVisuals()
                    powerOpen = false
                }

                function switchTab(idx: int): void {
                    const tab = Math.max(0, Math.min(2, idx))
                    if (powerOpen) powerOpen = false
                    if (tab !== activeTab) panel._beginTabHeightHold()
                    MenuState.selectTab(tab)
                    contentFlick.contentY = 0
                }

                function _beginTabHeightHold(): void {
                    if (!panel.open || ShellSettings.reduceMotion) return
                    panel._tabHeldH = Math.max(4, Metrics.snap4Up(panel.height))
                    panel._tabHeightHeld = true
                }

                function _activePageSettled(): bool {
                    if (panel.activeTab === 1) {
                        if (settingsLoader.status === Loader.Error) return true
                        return settingsLoader.status === Loader.Ready
                            && settingsLoader.item?.contentReady === true
                    }
                    if (panel.activeTab === 2) {
                        if (recentLoader.status === Loader.Error) return true
                        return recentLoader.status === Loader.Ready
                            && recentLoader.item?.contentReady === true
                    }
                    return homeLoader.status === Loader.Ready || homeLoader.status === Loader.Error
                }

                function _scheduleTabHeightRelease(): void {
                    if (panel._tabHeightHeld && panel._activePageSettled())
                        _tabHeightRelease.restart()
                }

                function _armOuterHeightMotion(): void {
                    if (!panel.open || ShellSettings.reduceMotion) return
                    panel._outerHeightMotion = true
                    _outerHeightMotionHold.restart()
                }

                Connections {
                    target: MenuState
                    function onTabRequested(index) {
                        if (index !== 0) panel._loadedDeferred = true
                        panel.switchTab(index)
                    }
                    function onTabChanging() {
                        if (!panel._tabHeightHeld) panel._beginTabHeightHold()
                    }
                    function onActiveTabChanged() {
                        contentFlick.contentY = 0
                        if (panel.activeTab !== 0) panel._loadedDeferred = true
                        panel._syncPageRetention()
                        panel._scheduleTabHeightRelease()
                        if (!MenuState.open) panel._settlePageVisuals()
                    }
                    function onSettingsSectionChanged() {
                        if (MenuState.settingsActive) panel._armOuterHeightMotion()
                    }
                    function onOpenChanged() {
                        if (MenuState.open) {
                            _closedUnload.stop()
                            panel._syncPageRetention()
                            // closeFinished is canceled when a close animation reverses; transient drawer state must not depend on that callback
                            panel.powerOpen = false
                            panel._outerHeightMotion = false
                            panel._tabHeightHeld = false
                            _tabHeightRelease.stop()
                            _outerHeightMotionHold.stop()
                            contentFlick.contentY = 0
                        } else {
                            _settingsWarmDelay.stop()
                            _closedUnload.restart()
                        }
                    }
                }

                Timer {
                    id: _homeUnload
                    interval: Math.max(Motion.pageOut, Motion.ms(100)) + 30
                    onTriggered: if (panel.activeTab !== 0) panel._homeRetained = false
                }

                Timer {
                    id: _settingsUnload
                    // keep Settings warm briefly for quick comparisons, then release both the page and its category delegates together
                    interval: 8000
                    onTriggered: {
                        if (panel.activeTab === 1) return
                        panel._settingsRetained = false
                        panel._settingsNavRetained = false
                    }
                }

                Timer {
                    id: _settingsWarmUnload
                    // a hover preload is speculative: long enough for a pause before the click, not the eight seconds a visited page keeps
                    interval: 2500
                    onTriggered: {
                        if (panel.activeTab === 1) return
                        _settingsUnload.stop()
                        panel._settingsRetained = false
                        panel._settingsNavRetained = false
                    }
                }

                Timer {
                    id: _recentUnload
                    interval: Math.max(Motion.pageOut, Motion.ms(100)) + 30
                    onTriggered: if (panel.activeTab !== 2) panel._recentRetained = false
                }

                Timer {
                    id: _closedUnload
                    interval: Math.max(Motion.pageOut, Motion.ms(100)) + 120
                    onTriggered: {
                        if (MenuState.open) return
                        _settingsWarmDelay.stop()
                        _settingsWarmUnload.stop()
                        _settingsUnload.stop()
                        _recentUnload.stop()
                        panel._settingsRetained = false
                        panel._recentRetained = false
                        panel._settingsNavRetained = false
                    }
                }

                Timer {
                    id: _outerHeightMotionHold
                    interval: Motion.pageOut + Motion.panelResize + Motion.ms(60)
                    onTriggered: panel._outerHeightMotion = false
                }

                Timer {
                    id: _tabHeightRelease
                    interval: 0
                    onTriggered: {
                        if (!panel._tabHeightHeld || !panel._activePageSettled()) return
                        panel._armOuterHeightMotion()
                        panel._tabHeightHeld = false
                    }
                }

                Connections {
                    target: ShellSettings
                    function onReduceMotionChanged() {
                        if (!ShellSettings.reduceMotion) return
                        _tabHeightRelease.stop()
                        panel._tabHeightHeld = false
                        panel._outerHeightMotion = false
                    }
                }

                width:  panelW
                height: _shownH

                // must match railW's curve, or the panel's outer edge and the rail's inner edge disagree mid-motion
                MotionBehavior on width {
                    id: _widthMotion
                    gate: panel._geometryReady && panel.open
                    NumberAnimation {
                        duration: _widthMotion.targetValue >= panel.width
                            ? Motion.panelResize : Motion.panelCollapse
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: _widthMotion.targetValue >= panel.width
                            ? Motion.emphasizedDecel : Motion.emphasizedAccel
                    }
                }
                // home sections animate their own height, so the panel follows it live instead of easing twice; tab swaps still animate here
                readonly property bool _heightGlides: panel._geometryReady && panel.open
                    && (panel._transitionReady || panel._outerHeightMotion)
                    && (panel.activeTab !== 0 || panel._outerHeightMotion)
                    && panel._shownH <= panel._availablePanelH + 1
                    && !ShellSettings.reduceMotion && !Idle.isIdle
                // a page reflowing at the live width moves the target 4 px at a time; restarting the ease on every step stalled the edge, so a run keeps its clock and small steps only move its end
                property real _shownH: 0
                property real _heightFrom: 0
                property real _heightTo: 0
                property real _heightEase: 1
                property bool _heightGrows: true

                function _placeHeight(): void {
                    panel._shownH = panel._heightFrom + (panel.targetPanelH - panel._heightFrom) * panel._heightEase
                }

                onTargetPanelHChanged: {
                    const to = panel.targetPanelH
                    if (!panel._heightGlides) {
                        _heightRun.stop()
                        panel._shownH = to
                        return
                    }
                    // re-based so the edge stays put and the run still lands on time; late in a run that would whip, so a fresh nudge takes over
                    const e = panel._heightEase
                    if (_heightRun.running && Math.abs(to - panel._heightTo) <= 16 && e < 0.75) {
                        panel._heightFrom = (panel._shownH - to * e) / (1 - e)
                        panel._heightTo = to
                        return
                    }
                    _heightRun.stop()
                    panel._heightFrom = panel._shownH
                    panel._heightTo = to
                    // a nudge eases out like a growth: easing in from rest reads as a pause before a few px
                    panel._heightGrows = to >= panel._shownH || Math.abs(to - panel._shownH) <= 16
                    panel._heightEase = 0
                    _heightRun.start()
                }
                on_HeightEaseChanged: if (_heightRun.running) panel._placeHeight()
                on_HeightGlidesChanged: {
                    if (panel._heightGlides || !_heightRun.running) return
                    _heightRun.stop()
                    panel._shownH = panel.targetPanelH
                }

                NumberAnimation {
                    id: _heightRun
                    target: panel
                    property: "_heightEase"
                    from: 0
                    to: 1
                    duration: panel._heightGrows ? Motion.panelResize : Motion.panelCollapse
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: panel._heightGrows ? Motion.emphasizedDecel : Motion.emphasizedAccel
                    onFinished: panel._shownH = panel.targetPanelH
                }

                onFullyShownChanged: {
                    if (fullyShown && !panel._loadedDeferred) {
                        Qt.callLater(function() {
                            if (panel && panel.fullyShown)
                                panel._loadedDeferred = true
                        })
                    }
                }

                Item {
                    id: rail
                    x: 0; y: 0
                    width: panel.railW
                    height: panel.height
                    clip: false
                    z: 6

                    Item {
                        anchors.fill: parent
                        clip: true

                        Rectangle {
                            x: 0; y: 0
                            width: parent.width + panel.radius
                            height: parent.height
                            radius: panel.radius
                            antialiasing: true
                            color: Theme.menuPane
                        }

                        Rectangle {
                            x: panel.railCollapsedW
                            width: Math.max(0, parent.width - x)
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            color: Theme.blend(Theme.menuPane, Theme.menuControl, 0.14)
                            visible: parent.width > panel.railCollapsedW + 0.5
                        }

                        RailDrawer {
                            id: _settingsDrawer
                            x: panel.railCollapsedW
                            width: panel.navW
                            revealedWidth: Math.max(0, panel.railW - panel.railCollapsedW)
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            shown: panel._settingsNavVisible
                            retained: panel._settingsNavRetained
                                || (MenuState.open && panel.activeTab === 1)
                            content: Component {
                                SettingsNav {
                                    powerOpen: panel.powerOpen
                                    onCurrentPageRetapped: contentFlick.contentY = 0
                                    onGroupToggled: panel._armOuterHeightMotion()
                                }
                            }
                        }

                        RailDrawer {
                            x: panel.railCollapsedW
                            width: panel.navW
                            revealedWidth: Math.max(0, panel.railW - panel.railCollapsedW)
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            shown: panel._recentNavVisible
                            retained: panel._recentRetained
                                || (MenuState.open && panel.activeTab === 2)
                            content: Component {
                                RecentNav {
                                    onFilterPicked: contentFlick.contentY = 0
                                }
                            }
                        }

                        Item {
                            id: _powerRailSurface
                            x: panel.railCollapsedW
                            width: panel.navW
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 10
                            height: panel.powerOpen
                                ? (_powerRailLoader.item?.implicitHeight ?? 0) : 0
                            clip: true
                            opacity: panel.powerOpen ? 1 : 0
                            visible: height > 0.5 || opacity > 0.001
                            enabled: panel.powerOpen

                            MotionBehavior on height {
                                id: _powerRailHeight
                                NumberAnimation {
                                    duration: _powerRailHeight.targetValue > 0 ? Motion.panelResize : Motion.panelCollapse
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: _powerRailHeight.targetValue > 0
                                        ? Motion.emphasizedDecel : Motion.emphasizedAccel
                                }
                            }
                            MotionBehavior on opacity {
                                id: _powerRailFade
                                NumberAnimation {
                                    duration: Motion.fast
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: _powerRailFade.targetValue > 0.5
                                        ? Motion.standardDecel : Motion.standardAccel
                                }
                            }

                            Loader {
                                id: _powerRailLoader
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 9
                                anchors.rightMargin: 9
                                anchors.bottom: parent.bottom
                                height: item ? item.implicitHeight : 0
                                active: panel.powerOpen || _powerRailSurface.height > 0.5
                                sourceComponent: Component {
                                    PowerRailContent { active: panel.powerOpen }
                                }
                            }
                        }

                    }

                    RailLabelGroup { id: _railLabels }

                    Timer {
                        id: _settingsWarmDelay
                        // ignore incidental sweeps down the icon rail; this is input intent detection, not visual motion, so reduce-motion does not collapse the delay to zero
                        interval: 90
                        onTriggered: if (_railSettings.hovered) panel.warmSettings()
                    }

                    Rectangle {
                        id: _railSelection
                        // strip order is Home, Notifications, Settings; tabs are numbered 0, 2, 1
                        readonly property int _slotIndex: panel.activeTab === 2 ? 1
                            : panel.activeTab === 1 ? 2 : 0
                        readonly property real _slot: _slotGlide.value
                        SpringGlide { id: _slotGlide; target: _railSelection._slotIndex }
                        x: _railNav.x + (panel.railCollapsedW - width) / 2
                        y: _railNav.y + (_railHome.height - height) / 2
                            + _slot * (_railHome.height + _railNav.spacing)
                        // 30px is 37.5 device px at 1.25; whole pixels at a snapped position keep its outline even
                        readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                        width: Metrics.devicePx(30, _dpr); height: width; radius: 9
                        antialiasing: true
                        color: Theme.menuControl
                        transform: PixelSnap { item: _railSelection; dpr: _railSelection._dpr }
                        OutlineBorder {
                            radius: _railSelection.radius
                            outlineColor: Theme.menuControlLine
                        }
                    }

                    Column {
                        id: _railNav
                        width: panel.railCollapsedW
                        x: 0
                        y: 10
                        spacing: 6

                        RailNavItem {
                            id: _railHome
                            labels: _railLabels
                            glidingSelection: true
                            railW: panel.railCollapsedW
                            glyph: "󰋜"
                            label: "Home"
                            labelPillEnabled: !panel._railExpanded
                                || panel.navW < panel._navMinW
                            active: panel.activeTab === 0
                            onTapped: panel.switchTab(0)
                        }

                        RailNavItem {
                            id: _railRecent
                            labels: _railLabels
                            glidingSelection: true
                            railW: panel.railCollapsedW
                            glyph: "󰋚"
                            label: "Notifications"
                            labelPillEnabled: !panel._railExpanded
                                || panel.navW < panel._navMinW
                            active: panel.activeTab === 2
                            onTapped: panel.switchTab(2)

                            Rectangle {
                                id: _railBadge
                                readonly property bool _show: Notifications.hasHistory && !_railRecent.active
                                readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.horizontalCenterOffset: 8
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: -8
                                // whole device pixels at a snapped position, like the rail selection beside it
                                width: Metrics.devicePx(Math.max(height, _railBadgeCount.implicitWidth + 7), _dpr)
                                height: Metrics.devicePx(14, _dpr); radius: height / 2
                                transform: PixelSnap { item: _railBadge; dpr: _railBadge._dpr }
                                color: Theme.accent; antialiasing: true
                                opacity: _show ? 1.0 : 0.0
                                scale:   _show ? 1.0 : 0.5
                                visible: opacity > 0.01
                                transformOrigin: Item.Center
                                MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }
                                MotionBehavior on scale   {NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic } }
                                OutlineBorder {
                                    radius: parent.radius
                                    outlineWidth: 2
                                    outlineColor: Theme.menuPane
                                }
                                ShellText {
                                    id: _railBadgeCount
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: Notifications.historyCount > 99 ? "99+" : Notifications.historyCount
                                    color: Theme.background
                                    font.pixelSize: Settings.fontTiny
                                    font.weight: Font.Bold
                                }
                            }
                        }

                        RailNavItem {
                            id: _railSettings
                            labels: _railLabels
                            glidingSelection: true
                            railW: panel.railCollapsedW
                            glyph: "󰒓"
                            label: "Settings"
                            labelPillEnabled: !panel._railExpanded
                                || panel.navW < panel._navMinW
                            active: panel.activeTab === 1
                            onTapped: panel.switchTab(1)
                            onHoveredChanged: {
                                if (hovered) _settingsWarmDelay.restart()
                                else _settingsWarmDelay.stop()
                            }
                        }
                    }

                    Item {
                        id: _railPowerSlot
                        readonly property int gap: 10
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 10
                        anchors.left: parent.left
                        width: panel.railCollapsedW
                        // derived, not summed: RailNavItem is rowHeightFor(34), which grows with the
                        // font, so a hardcoded total drops the icon below its own inset at larger type
                        height: _railDivider.height + _railPowerSlot.gap + _railPower.height
                        z: 9

                        Hairline {
                            id: _railDivider
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 18
                            color: Theme.menuDivider
                        }

                        RailNavItem {
                            id: _railPower
                            labels: _railLabels
                            anchors.top: _railDivider.bottom
                            anchors.topMargin: _railPowerSlot.gap
                            anchors.horizontalCenter: parent.horizontalCenter
                            railW: panel.railCollapsedW
                            glyph: "󰐥"
                            label: "Power"
                            labelPillEnabled: !panel._railExpanded
                                || panel.navW < panel._navMinW
                            accentColor: Theme.error
                            active: panel.powerOpen
                            onTapped: panel.powerOpen = !panel.powerOpen
                        }
                    }
                }

                Item {
                    id: contentPane
                    // no MotionBehavior here: x tracks panel.railW, which is already animated at the source —
                    // a second Behavior on top double-eases and lags the pane behind the rail it's supposed to hug
                    x: panel.railW
                    y: 0
                    width: panel.contentW
                    clip: true

                    Rectangle {
                        x: -panel.radius
                        y: 0
                        width: parent.width + panel.radius
                        height: parent.height
                        radius: panel.radius
                        antialiasing: true
                        color: Theme.menuPane
                    }

                    readonly property int targetH: {
                        const contentH = tabContent.y + tabContent.height
                            + panel.pageBottomInset
                        const navH = panel.activeTab === 1
                            ? (_settingsDrawer.item?.implicitHeight ?? 0) + 16 : 0
                        return 4 * Math.ceil(Math.max(panel.minRailFitH,
                            panel.idealMinH, contentH, navH) / 4)
                    }

                    height: panel.height

                    TapHandler {
                        enabled: panel.powerOpen
                        onTapped: panel.powerOpen = false
                    }

                    ShellFlickable {
                        id: contentFlick
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: tabContent.y + tabContent.height
                            + panel.pageBottomInset
                        interactive: !panel.powerOpen && panel.activeTab !== 2
                            && _contentSettle.overflows

                        function clampToContent(): void {
                            const maxY = Math.max(0, contentHeight - height)
                            if (contentY > maxY) contentY = maxY
                            else if (contentY < 0) contentY = 0
                        }

                        function revealSettingsSelect(): void {
                            const row = MenuState._settingsSelectOwner
                            if (!row || !panel.open || panel.activeTab !== 1) return
                            // a list taller than the viewport keeps its header in view, not its end
                            const top = row.mapToItem(contentFlick.contentItem, 0, 0).y
                            const bottom = top + row.height
                            const margin = 8
                            let target = contentY
                            if (row.height + margin * 2 > height)
                                target = top - margin
                            else if (top - margin < target)
                                target = top - margin
                            else if (bottom + margin > target + height)
                                target = bottom + margin - height
                            contentY = Math.max(0,
                                Math.min(Math.max(0, contentHeight - height), target))
                        }

                        Timer {
                            id: _selectReveal
                            interval: Motion.medium + 24
                            onTriggered: contentFlick.revealSettingsSelect()
                        }

                        Connections {
                            target: MenuState
                            function onSettingsSelectClaimed() {
                                if (panel.open && panel.activeTab === 1) {
                                    panel._armOuterHeightMotion()
                                    _selectReveal.restart()
                                }
                            }
                            function onSettingsSelectOpenChanged() {
                                if (!MenuState.settingsSelectOpen) {
                                    _selectReveal.stop()
                                    if (panel.activeTab === 1) panel._armOuterHeightMotion()
                                }
                            }
                        }

                        onContentHeightChanged: clampToContent()
                        onHeightChanged: {
                            clampToContent()
                            if (MenuState.settingsSelectOpen && panel.activeTab === 1)
                                _selectReveal.restart()
                        }

                        Item {
                            id: tabContent
                            x: panel.contentPad
                            y: panel.pageTopInset
                            width: panel.innerW
                            readonly property bool _pagePending:
                                panel.activeTab === 1
                                    ? settingsLoader.status !== Loader.Ready
                                        || settingsLoader.item?.contentReady !== true
                              : panel.activeTab === 2 ? recentLoader.status !== Loader.Ready
                              : false
                            readonly property bool _pageError:
                                panel.activeTab === 1
                                    ? settingsLoader.status === Loader.Error
                                        || settingsLoader.item?.contentError === true
                              : panel.activeTab === 2 ? recentLoader.status === Loader.Error
                              : false
                            // a build shorter than this reads as a flicker, not as feedback
                            property bool _pageSlow: false
                            on_PagePendingChanged: {
                                if (tabContent._pagePending) {
                                    _pageSlowDefer.restart()
                                } else {
                                    _pageSlowDefer.stop()
                                    tabContent._pageSlow = false
                                }
                            }
                            Timer {
                                id: _pageSlowDefer
                                interval: 220
                                onTriggered: tabContent._pageSlow = tabContent._pagePending
                            }
                            height: panel.activeTab === 0 ? (homeLoader.item?.implicitHeight ?? 0)
                                  : panel.activeTab === 1 ? (settingsLoader.item?.implicitHeight
                                        ?? _pagePlaceholder.implicitHeight)
                                  : (recentLoader.item?.implicitHeight ?? _pagePlaceholder.implicitHeight)
                            clip: false

                            Item {
                                id: _pagePlaceholder
                                width: parent.width
                                height: implicitHeight
                                implicitHeight: Math.max(1, panel.idealMinH
                                    - panel.pageTopInset - panel.pageBottomInset)
                                readonly property bool _shown:
                                    tabContent._pageSlow || tabContent._pageError
                                opacity: _pagePlaceholder._shown ? 1 : 0
                                visible: opacity > 0.001
                                enabled: false
                                z: 5

                                MotionBehavior on opacity {
                                    id: _placeholderFade
                                    NumberAnimation {
                                        duration: Motion.pageOut
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: _placeholderFade.targetValue > 0.5
                                            ? Motion.standardDecel : Motion.standardAccel
                                    }
                                }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 8

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 40
                                        height: 40
                                        radius: 20
                                        antialiasing: true
                                        color: tabContent._pageError
                                            ? Theme.withAlpha(Theme.error, 0.10)
                                            : Theme.withAlpha(Theme.accent, 0.08)

                                        OutlineBorder {
                                            radius: 20
                                            outlineColor: tabContent._pageError
                                                ? Theme.withAlpha(Theme.error, 0.34)
                                                : Theme.withAlpha(Theme.accent, 0.20)
                                        }

                                        ShellText {
                                            anchors.centerIn: parent
                                            text: tabContent._pageError ? "󰅙" : "󰔟"
                                            color: tabContent._pageError
                                                ? Theme.withAlpha(Theme.error, 0.82)
                                                : Theme.withAlpha(Theme.accent, 0.76)
                                            font.pixelSize: Settings.iconSize + 5
                                        }
                                    }

                                    ShellText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Math.max(1, _pagePlaceholder.width - 24)
                                        horizontalAlignment: Text.AlignHCenter
                                        text: tabContent._pageError
                                            ? "Couldn’t load this page"
                                            : panel.activeTab === 1 ? "Loading settings…" : "Loading notifications…"
                                        color: Theme.withAlpha(Theme.text, 0.76)
                                        font.pixelSize: Settings.fontSize
                                        font.weight: Font.Medium
                                    }

                                    ShellText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Math.max(1, _pagePlaceholder.width - 24)
                                        horizontalAlignment: Text.AlignHCenter
                                        visible: tabContent._pageError
                                        text: "The menu is still usable; check the shell log for details"
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        color: Theme.withAlpha(Theme.subtext, 0.54)
                                        font.pixelSize: Settings.fontCaption
                                    }
                                }
                            }

                            Loader {
                                id: homeLoader
                                width: parent.width
                                active: panel._homeRetained
                                asynchronous: false
                                onStatusChanged: panel._scheduleTabHeightRelease()
                                sourceComponent: Component {
                                    HomePage {
                                        width: parent.width
                                        active: panel.activeTab === 0 && MenuState.open
                                        powerOpen: panel.powerOpen
                                        animateOnCreate: panel.fullyShown
                                    }
                                }
                            }

                            Loader {
                                id: settingsLoader
                                width: parent.width
                                active: panel._loadedDeferred && panel._settingsRetained
                                asynchronous: true
                                onStatusChanged: panel._scheduleTabHeightRelease()
                                sourceComponent: Component {
                                    SettingsPage {
                                        width: parent.width
                                        active: panel.activeTab === 1 && MenuState.open
                                        powerOpen: panel.powerOpen
                                        animateOnCreate: panel.fullyShown
                                        scroller: contentFlick
                                        onContentReadyChanged: panel._scheduleTabHeightRelease()
                                        onSectionSwapped: contentFlick.contentY = 0
                                    }
                                }
                            }

                            Loader {
                                id: recentLoader
                                width: parent.width
                                active: panel._loadedDeferred && panel._recentRetained
                                asynchronous: true
                                onStatusChanged: panel._scheduleTabHeightRelease()
                                sourceComponent: Component {
                                    RecentPage {
                                        width: parent.width
                                        viewportHeight: panel.recentViewportH
                                        thumbOutset: panel.contentPad
                                        onContentReadyChanged: panel._scheduleTabHeightRelease()
                                        active: panel.activeTab === 2 && MenuState.open
                                        powerOpen: panel.powerOpen
                                        animateOnCreate: panel.fullyShown
                                    }
                                }
                            }
                        }
                    }

                    ScrollSettle {
                        id: _contentSettle
                        list: contentFlick
                        armed: panel.open
                        contextKey: panel.activeTab === 1
                            ? "settings:" + MenuState.settingsSection
                            : "tab:" + panel.activeTab
                    }

                    ListEdgeLines {
                        anchors.fill: contentFlick
                        list: contentFlick
                        visible: panel.activeTab !== 2 && _contentSettle.ready
                        z: 4
                    }

                    MenuScrollThumb {
                        list: contentFlick
                        shown: panel.open && !panel.powerOpen && panel.activeTab !== 2
                        z: 5
                    }
                }

                OutlineBorder {
                    radius: panel.radius
                    outlineColor: Theme.withAlpha(Theme.outline,
                        Math.min(1, Theme.outline.a * 1.35))
                    z: 20
                }
            }
        }
    }
}
