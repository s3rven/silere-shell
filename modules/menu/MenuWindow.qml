pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"
import "controls"
// loaded from a file, not named below; Quickshell only scans a directory it sees imported
import "settings" // qmllint disable unused-imports

FittedPopupWindow {
    id: win

    targetScreen: MenuState.surfaceScreen
    open: MenuState.open
    layerNamespace: "silere-menu"
    popupCard: panel
    onDismissed: MenuState.close()
    onEscapePressed: {
        if (panel.dismissNav()) {
        } else if (panel.powerOpen) {
            panel.powerOpen = false
        } else if (panel.activeTab === 0 && homeLoader.item && homeLoader.item.dismissInline()) {
        } else if (panel.activeTab === 1 && settingsLoader.item && settingsLoader.item.dismissInline()) {
        } else if (panel.activeTab === 2 && recentLoader.item && recentLoader.item.dismissInline()) {
        } else if (panel.activeTab === MenuState.mediaTab && mediaLoader.item && mediaLoader.item.dismissInline()) {
        } else {
            MenuState.close()
        }
    }

    PopupShadow { card: panel }

    Shortcut {
        sequence: "Ctrl+Tab"
        context: Qt.ApplicationShortcut
        enabled: MenuState.open
        onActivated: panel.switchTab(MenuState.adjacentTab(panel.activeTab, Media.menuShown, 1))
    }
    Shortcut {
        sequences: ["Ctrl+Shift+Tab", "Ctrl+Backtab"]
        context: Qt.ApplicationShortcut
        enabled: MenuState.open
        onActivated: panel.switchTab(MenuState.adjacentTab(panel.activeTab, Media.menuShown, -1))
    }

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
        readonly property int _typeGain: Metrics.menuTypeGain

        // every panel width stays on the 4px grid, or the outline's right edge lands on a half output px at fractional scale and rasterizes wider than its left
        readonly property int _compactW: 400 + Metrics.menuContentGrowth
        // the home pane at its own width beside the power column (400 - 44 - 2 * 12 = 576 - 204 - 2 * 20): at 572 Home
        // reflowed 4 px narrower as the drawer opened, and every right-aligned value stepped back before the glide
        readonly property int _powerW: 576 + _typeGain + Metrics.menuContentGrowth
        readonly property int _settingsW: 672 + _typeGain + Metrics.menuContentGrowth
        readonly property int _recentBaseW: 492 + _typeGain + Metrics.menuContentGrowth
        readonly property int _recentW: _recentBaseW + _navMaxW + 16
        readonly property bool _settingsNavVisible:
            activeTab === 1 && !powerOpen && (!_compactSettingsNav || _settingsNavOverlay)
        // one app cannot be filtered against anything, so the drawer stays out of its way
        readonly property bool _recentHasAppFilters: activeTab === 2 && Notifications.historyApps.length > 1
        readonly property bool _recentNavDocked:
            activeTab === 2 && !powerOpen && _recentHasAppFilters && !_compactRecentNav
        readonly property bool _recentNavVisible: _recentNavDocked || _recentNavOverlay
        readonly property bool _railExpanded:
            (_settingsNavVisible && !_compactSettingsNav) || _recentNavDocked || powerOpen
        readonly property int _targetPanelW: activeTab === 1 ? _settingsW
            : powerOpen ? _powerW
            : activeTab === 2 ? (_recentNavDocked ? _recentW : _recentBaseW)
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
        readonly property int navW: panel._navWidthFor(panelW, powerOpen)
        function _navWidthFor(width: int, forPower: bool): int {
            const available = width - railCollapsedW
            // the power panel is the home pane plus a nav column, so a share of it undercuts the column above 100% type
            const desired = Math.max(_navMinW, forPower ? _navMaxW : Metrics.snap4(width * 0.28))
            const detailSafe = Math.max(_navMinW, available - 224)
            const sidebarFit = Math.max(0, available - 96)
            return Math.max(0, Math.min(_navMaxW, desired, detailSafe, sidebarFit))
        }
        readonly property int railExpandedW: railCollapsedW + navW
        // width, rail and padding use the same response. Retargeting a quick tab reversal preserves velocity instead of restarting three eases
        readonly property bool _horizontalMotion: panel._geometryReady && (panel.open || panel._closing)
        readonly property real railW: _railGlide.value
        SmoothGlide {
            id: _railGlide
            holdsSnaps: true
            target: panel._railExpanded ? panel.railExpandedW : panel.railCollapsedW
            gate: panel._horizontalMotion
        }
        // live width, not the target: the page reflows ahead of the outer edge otherwise
        readonly property real contentW: Math.max(1, width - railW)
        readonly property real _targetContentPad: activeTab === 1
            ? Metrics.snap4(Math.max(12, Math.min(20,
                12 + (panelW - _compactW) * 8 / (_settingsW - _compactW))))
            // 4px steps: an 18px pad starts the pane half a device pixel off at 1.25 and softens every outline in it
            : _railExpanded && panelW >= 460 ? 20 : 12
        readonly property real contentPad: _paddingGlide.value
        SmoothGlide {
            id: _paddingGlide
            holdsSnaps: true
            target: panel._targetContentPad
            gate: panel._horizontalMotion
        }
        readonly property real innerW: Math.max(1, contentW - contentPad * 2)
        readonly property real pageLayoutW: Math.max(1, panelW
            - (_railExpanded ? railExpandedW : railCollapsedW) - _targetContentPad * 2)
        // below the narrow layout-fit width, give the controls the sidebar's space and put sections in a drawer
        readonly property bool _compactSettingsNav: activeTab === 1
            && panelW - railExpandedW - _targetContentPad * 2 < 332
        // compute the docked width with filters present, so the first arrival from another app cannot change modes
        readonly property int _recentDockedW: Math.min(_recentW, _availablePanelW)
        readonly property bool _compactRecentNav: activeTab === 2 && _recentDockedW - railCollapsedW
            - panel._navWidthFor(_recentDockedW, false) - (_recentDockedW >= 460 ? 40 : 24) < 332
        readonly property bool _canOpenNav: _compactSettingsNav || (_compactRecentNav && _recentHasAppFilters)
        property bool _navOpen: false
        readonly property bool _navOverlay: _canOpenNav && _navOpen && open && !powerOpen
        readonly property bool _settingsNavOverlay: _navOverlay && _compactSettingsNav
        readonly property bool _recentNavOverlay: _navOverlay && _compactRecentNav
        readonly property int _navOverlayW: Math.max(0, Math.min(_navMaxW, panelW - railCollapsedW))
        on_CanOpenNavChanged: if (!_canOpenNav && _navOpen) {
            _navOpen = false
            if (_compactRecentNav) Qt.callLater(panel._focusNavButton)
        }
        onPowerOpenChanged: if (powerOpen) _navOpen = false
        // reveal when nearly all of the incoming layout fits. Width and rail can keep settling behind it without clipping the first visible frame
        readonly property bool pageViewportReady: innerW >= pageLayoutW - 12
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
        readonly property real targetPanelH: _tabHeightHeld
            ? Math.max(1, Math.min(_tabHeldH, _availablePanelH))
            : _resolvedPanelH

        readonly property int activeTab: MenuState.activeTab

        property bool powerOpen: false
        property bool _loadedDeferred: false
        property bool _geometryReady:  false
        property bool _outerHeightMotion: false
        property bool _tabHeightHeld: false
        property real _tabHeldH: idealMinH
        property bool _homeRetained:    false
        property bool _settingsRetained: false
        property bool _recentRetained:  false
        property bool _mediaRetained:   false
        property bool _settingsNavRetained: false
        // the nav floors the settings panel and is unloaded with the page, so it stands in at its closing height too
        readonly property real _settingsNavH: _compactSettingsNav ? 0 : rail.settingsNavHeight > 0 ? rail.settingsNavHeight
            : MenuState.settingsClosedSection === MenuState.settingsSection ? MenuState.settingsNavClosedHeight : 0

        Component.onCompleted: {
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
                _recentWarmUnload.stop()
                _recentUnload.stop()
                _recentRetained = true
            } else if (_recentRetained) {
                _recentUnload.restart()
            }

            if (activeTab === MenuState.mediaTab) {
                _mediaUnload.stop()
                _mediaRetained = true
            } else if (_mediaRetained) {
                _mediaUnload.restart()
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

        // the history page and its app drawer rebuild otherwise on the tap, so the drawer arrived after the panel widened
        function warmRecent(): void {
            if (!MenuState.open || panel.activeTab === 2 || panel._recentRetained) return
            panel._loadedDeferred = true
            panel._recentRetained = true
            _recentWarmUnload.restart()
        }

        function _settlePageVisuals(): void {
            if (homeLoader.item) homeLoader.item.settleVisual(activeTab === 0)
            if (settingsLoader.item) settingsLoader.item.settleVisual(activeTab === 1)
            if (recentLoader.item) recentLoader.item.settleVisual(activeTab === 2)
            if (mediaLoader.item) mediaLoader.item.settleVisual(activeTab === MenuState.mediaTab)
        }

        onCloseFinished: {
            if (open) return
            _settlePageVisuals()
            powerOpen = false
        }

        function switchTab(idx: int): void {
            const tab = Math.max(0, Math.min(MenuState.mediaTab, idx))
            const sameTab = tab === activeTab
            if (sameTab && panel.dismissNav()) return
            if (powerOpen) powerOpen = false
            if (tab !== activeTab) panel._beginTabHeightHold()
            MenuState.selectTab(tab)
            if (sameTab) contentFlick.scrollToTop()
        }

        function openNav(): void {
            if (!panel.open || panel.powerOpen || !panel._canOpenNav) return
            if (panel._compactSettingsNav) MenuState.closeSettingsSelect()
            contentFlick.cancelFlick()
            panel._navOpen = true
        }

        function dismissNav(): bool {
            if (!panel._navOverlay) return false
            panel._navOpen = false
            Qt.callLater(panel._focusNavButton)
            return true
        }

        function _focusNavButton(): void {
            if (!panel.open || panel._navOverlay || panel.powerOpen) return
            if (panel._compactSettingsNav) settingsLoader.item?.focusSectionsButton()
            if (panel._compactRecentNav) recentLoader.item?.focusAppsButton()
        }

        // a card still fading out is on screen, so a tab picked then is a switch like any other
        function _beginTabHeightHold(): void {
            if (!(panel.open || panel._closing) || ShellSettings.reduceMotion) return
            panel._tabHeldH = Math.max(4, panel.height)
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
            if (panel.activeTab === MenuState.mediaTab)
                return mediaLoader.status === Loader.Ready || mediaLoader.status === Loader.Error
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
                // snapshot before activeTab changes its dependent geometry
                homeLoader.holdLayout()
                settingsLoader.holdLayout()
                recentLoader.holdLayout()
                mediaLoader.holdLayout()
                rail.holdDrawerLayouts()
            }
            function onActiveTabChanged() {
                panel._navOpen = false
                contentFlick.scrollToTop()
                if (panel.activeTab !== 0) panel._loadedDeferred = true
                panel._syncPageRetention()
                panel._scheduleTabHeightRelease()
                if (!MenuState.open) panel._settlePageVisuals()
            }
            function onSettingsSectionChanged() {
                if (MenuState.settingsActive) panel._armOuterHeightMotion()
            }
            function onOpenChanged() {
                panel._navOpen = false
                if (MenuState.open) {
                    _closedUnload.stop()
                    panel._syncPageRetention()
                    // closeFinished is canceled when a close animation reverses; transient drawer state must not depend on that callback
                    panel.powerOpen = false
                    if (panel.activeTab === MenuState.mediaTab && !Media.menuShown)
                        MenuState.selectTab(MenuState.homeTab)
                    // a reopen during the fade reverses it: keep the switch a tab picked meanwhile started
                    if (panel.opacity <= 0.001) {
                        panel._outerHeightMotion = false
                        panel._tabHeightHeld = false
                        _tabHeightRelease.stop()
                        _outerHeightMotionHold.stop()
                        contentFlick.scrollToTop()
                    }
                } else {
                    rail.stopWarmDelays()
                    if (settingsLoader.item?.contentReady === true) {
                        MenuState.settingsClosedHeight = settingsLoader.item.implicitHeight
                        MenuState.settingsClosedSection = MenuState.settingsSection
                        MenuState.settingsNavClosedHeight = rail.settingsNavHeight
                    }
                    if (recentLoader.item?.contentReady === true)
                        MenuState.recentClosedHeight = recentLoader.item.implicitHeight
                    _closedUnload.restart()
                }
            }
        }

        Timer {
            id: _homeUnload
            // a return within seconds skips the ~8 ms rebuild that lands on the switch's first frame
            interval: 8000
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
            // like Settings: a return within seconds finds the page and its app drawer built
            interval: 8000
            onTriggered: if (panel.activeTab !== 2) panel._recentRetained = false
        }

        Timer {
            id: _recentWarmUnload
            interval: 2500
            onTriggered: {
                if (panel.activeTab === 2) return
                _recentUnload.stop()
                panel._recentRetained = false
            }
        }

        Timer {
            id: _mediaUnload
            // a hidden page keeps its decoded cover, so a return within seconds lands with the art already there
            interval: 8000
            onTriggered: if (panel.activeTab !== MenuState.mediaTab) panel._mediaRetained = false
        }

        Timer {
            id: _closedUnload
            interval: Math.max(Motion.pageOut, Motion.ms(100)) + 120
            onTriggered: {
                if (MenuState.open) return
                rail.stopWarmDelays()
                _settingsWarmUnload.stop()
                _recentWarmUnload.stop()
                _settingsUnload.stop()
                _recentUnload.stop()
                _mediaUnload.stop()
                panel._settingsRetained = false
                panel._recentRetained = false
                panel._mediaRetained = false
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
            target: Media
            function onMenuShownChanged() {
                if (MenuState.open && !Media.menuShown && panel.activeTab === MenuState.mediaTab)
                    panel.switchTab(MenuState.homeTab)
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

        width: Math.max(1, Math.min(_widthGlide.value, _availablePanelW))
        height: _shownH

        SmoothGlide {
            id: _widthGlide
            holdsSnaps: true
            target: panel.panelW
            gate: panel._horizontalMotion
        }
        // home sections animate their own height, so the panel follows it live instead of easing twice; tab swaps still animate here
        readonly property bool _heightGlides: panel._geometryReady && (panel.open || panel._closing)
            && (panel._transitionReady || panel._outerHeightMotion)
            && (panel.activeTab !== 0 || panel._outerHeightMotion)
            && !ShellSettings.reduceMotion && !Idle.isIdle
        // reflow can change the destination every frame. Keep velocity across those updates, and drive geometry once rather than easing each nudge
        readonly property real _shownH: Math.max(1,
            Math.min(_heightGlide.value, panel._availablePanelH))
        SmoothGlide {
            id: _heightGlide
            holdsSnaps: true
            target: panel.targetPanelH
            gate: panel._heightGlides
        }

        onFullyShownChanged: {
            if (fullyShown && !panel._loadedDeferred) {
                Qt.callLater(function() {
                    if (panel && panel.fullyShown)
                        panel._loadedDeferred = true
                })
            }
        }

        MenuRail {
            id: rail
            menu: panel
            z: 6
            onScrollToTopRequested: contentFlick.scrollToTop()
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.withAlpha(Theme.background, 0.56)
            z: 5
            opacity: panel._navOverlay ? 1 : 0
            visible: opacity > 0.001
            MotionBehavior on opacity { NumberAnimation { duration: Motion.fast } }
            TapHandler {
                enabled: panel._navOverlay
                onTapped: panel.dismissNav()
            }
        }

        Item {
            id: contentPane
            // no MotionBehavior here: x tracks panel.railW, which is already animated at the source —
            // a second Behavior on top double-eases and lags the pane behind the rail it's supposed to hug
            x: panel.railW
            y: 0
            width: panel.contentW
            enabled: !panel._navOverlay
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

            // settings stops at the nav's height, as history stops at its viewport: a long page
            // scrolls inside it instead of stretching the panel to the screen edge
            readonly property int _settingsMaxH: Math.max(panel._settingsNavH + 16,
                Metrics.rowHeightFor(640))
            readonly property real _fitH: {
                const contentH = panel.pageTopInset + tabContent.height
                    + panel.pageBottomInset
                const navH = panel.activeTab === 1
                    ? panel._settingsNavH + 16 : 0
                return Math.max(panel.minRailFitH, panel.idealMinH, navH,
                    panel.activeTab === 1 ? Math.min(contentH, _settingsMaxH) : contentH)
            }
            readonly property int targetH: 4 * Math.ceil(_fitH / 4)
            // over a bottom bar the panel grows upward on the 4 px grid while a fold grows smoothly: the grid's
            // remainder goes above the page, or every row below the fold trembles against the fixed edge.
            // A panel at the screen's limit scrolls instead, and ScrollHold keeps those rows
            readonly property real gridSlack: Metrics.barAtBottom && targetH <= panel._availablePanelH
                ? targetH - _fitH : 0

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
                // settings pins its header over the top of the viewport, so a revealed row has to land below it
                readonly property real revealTopInset: panel.activeTab === 1 && settingsLoader.item
                    ? panel.pageTopInset + (settingsLoader.item.pinnedHeight ?? 0) : 0
                // delayed reveals belong to the page that requested them
                readonly property string _settingsRevealSection: MenuState.settingsActive && !panel.powerOpen
                    ? MenuState.settingsSection : ""
                readonly property bool _homeRevealActive: MenuState.homeActive && !panel.powerOpen

                on_SettingsRevealSectionChanged: {
                    _toggleReveal.stop()
                    _toggleReveal.row = null
                    _selectReveal.stop()
                }
                on_HomeRevealActiveChanged: if (!_homeRevealActive) {
                    _homeReveal.stop()
                    _homeReveal.control = null
                    _homeReveal.choices = null
                }

                function clampToContent(): void {
                    const maxY = Math.max(0, contentHeight - height)
                    if (contentY > maxY) contentY = maxY
                    else if (contentY < 0) contentY = 0
                }

                function revealControl(row, choices): void {
                    if (!row) return
                    contentFlick.cancelFlick()
                    // a list taller than the viewport keeps its header in view, not its end
                    const rowTop = row.mapToItem(contentFlick.contentItem, 0, 0).y
                    const choicesTop = choices && choices.height > 0
                        ? choices.mapToItem(contentFlick.contentItem, 0, 0).y : rowTop
                    const top = Math.min(rowTop, choicesTop)
                    const bottom = Math.max(rowTop + row.height, choicesTop + (choices ? choices.height : 0))
                    const margin = 8
                    const inset = contentFlick.revealTopInset
                    let target = contentY
                    if (bottom - top + margin * 2 > height - inset)
                        target = rowTop - margin - inset
                    else if (top - margin < target + inset)
                        target = top - margin - inset
                    else if (bottom + margin > target + height)
                        target = bottom + margin - height
                    contentY = Math.max(0,
                        Math.min(Math.max(0, contentHeight - height), target))
                }

                // the rows a switch opens sit right under it, in the same card
                function sectionAfter(row): var {
                    const siblings = row && row.parent ? row.parent.children : []
                    for (let i = 0; i + 1 < siblings.length; i++)
                        if (siblings[i] === row)
                            return siblings[i + 1].isRadiusGroup && siblings[i + 1].expanded ? siblings[i + 1] : null
                    return null
                }

                readonly property Timer _toggleRevealTimer: Timer {
                    id: _toggleReveal
                    property Item row: null
                    interval: Motion.medium + 24
                    onTriggered: {
                        const flipped = row
                        row = null
                        if (flipped && flipped.enabled && flipped.visible && contentFlick._settingsRevealSection)
                            contentFlick.revealControl(flipped, contentFlick.sectionAfter(flipped))
                    }
                }

                Timer {
                    id: _selectReveal
                    interval: Motion.medium + 24
                    onTriggered: if (contentFlick._settingsRevealSection)
                        contentFlick.revealControl(MenuState.settingsSelectOwner, null)
                }

                Timer {
                    id: _homeReveal
                    property Item control: null
                    property Item choices: null
                    interval: Math.max(Motion.medium, Motion.panelResize) + 24
                    onTriggered: {
                        const row = control
                        const extra = choices
                        control = null
                        choices = null
                        if (contentFlick._homeRevealActive) contentFlick.revealControl(row, extra)
                    }
                }

                Connections {
                    target: MenuState
                    function onSettingsRevealRequested(row) {
                        if (!contentFlick._settingsRevealSection) return
                        _toggleReveal.row = row
                        _toggleReveal.restart()
                    }
                    function onSettingsSelectClaimed() {
                        if (contentFlick._settingsRevealSection) {
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
                    if (MenuState.settingsSelectOpen && contentFlick._settingsRevealSection)
                        _selectReveal.restart()
                }

                Item {
                    id: tabContent
                    x: panel.contentPad
                    y: panel.pageTopInset + contentPane.gridSlack
                    width: panel.innerW
                    readonly property bool _pagePending:
                        panel.activeTab === 1
                            ? settingsLoader.status !== Loader.Ready
                                || settingsLoader.item?.contentReady !== true
                      : panel.activeTab === 2 ? recentLoader.status !== Loader.Ready
                      : false
                    readonly property bool _pageError:
                        panel.activeTab === 1 ? settingsLoader.failed
                      : panel.activeTab === 2 ? recentLoader.failed
                      : panel.activeTab === MenuState.mediaTab ? mediaLoader.failed
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
                          : panel.activeTab === MenuState.mediaTab ? (mediaLoader.item?.implicitHeight ?? 0)
                          : panel.activeTab === 1 ? (settingsLoader.item?.implicitHeight
                                ?? _pagePlaceholder.implicitHeight)
                          : (recentLoader.item?.implicitHeight ?? _pagePlaceholder.implicitHeight)
                    clip: false

                    Item {
                        id: _pagePlaceholder
                        width: parent.width
                        height: implicitHeight
                        implicitHeight: Math.max(1,
                            panel.activeTab === 1 && MenuState.settingsClosedSection === MenuState.settingsSection
                                && MenuState.settingsClosedHeight > 0 ? MenuState.settingsClosedHeight
                            : panel.activeTab === 2 && MenuState.recentClosedHeight > 0 ? MenuState.recentClosedHeight
                            : panel.idealMinH - panel.pageTopInset - panel.pageBottomInset)
                        readonly property bool _shown:
                            tabContent._pageSlow || tabContent._pageError
                        opacity: _pagePlaceholder._shown ? 1 : 0
                        visible: opacity > 0.001
                        enabled: tabContent._pageError
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
                                        : Theme.withAlpha(Theme.accentInk, 0.76)
                                    font.pixelSize: Settings.iconSize + 5
                                }
                            }

                            ShellText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.max(1, _pagePlaceholder.width - 24)
                                horizontalAlignment: Text.AlignHCenter
                                text: tabContent._pageError
                                    ? "Could not load this page"
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
                                text: "Reloading Silere usually brings it back; silere log has the details"
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                color: Theme.menuTextQuiet
                                font.pixelSize: Settings.fontCaption
                            }

                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: tabContent._pageError
                                width: _reloadButton.width
                                height: _reloadButton.height + 8

                                ActionButton {
                                    id: _reloadButton
                                    anchors.bottom: parent.bottom
                                    glyph: "󰑐"
                                    label: "Reload"
                                    accessibleName: "Reload Silere"
                                    onTriggered: MenuState.reloadShell()
                                }
                            }
                        }
                    }

                    PageLoader {
                        id: homeLoader
                        layoutWidth: panel.pageLayoutW
                        shown: panel.activeTab === 0 && MenuState.open
                        scrollOffset: contentFlick.contentY
                        active: panel._homeRetained
                        asynchronous: panel.fullyShown
                        onStatusChanged: panel._scheduleTabHeightRelease()
                        sourceComponent: Component {
                            HomePage {
                                width: parent.width
                                active: panel.activeTab === 0 && MenuState.open
                                powerOpen: panel.powerOpen
                                animateOnCreate: panel.fullyShown
                                viewportReady: panel.pageViewportReady
                                onControlRequested: (control, choices) => {
                                    if (!contentFlick._homeRevealActive) return
                                    _homeReveal.control = control
                                    _homeReveal.choices = choices
                                    _homeReveal.restart()
                                }
                            }
                        }
                    }

                    PageLoader {
                        id: settingsLoader
                        layoutWidth: panel.pageLayoutW
                        shown: panel.activeTab === 1 && MenuState.open
                        scrollOffset: contentFlick.contentY
                        active: panel._loadedDeferred && panel._settingsRetained
                        asynchronous: true
                        onStatusChanged: panel._scheduleTabHeightRelease()
                        source: "settings/SettingsPage.qml"
                        pageActive: panel.activeTab === 1 && MenuState.open
                        powerOpen: panel.powerOpen
                        animateOnCreate: panel.fullyShown
                        viewportReady: panel.pageViewportReady
                        scroller: contentFlick
                        compactNavigation: panel._compactSettingsNav
                        Connections {
                            target: settingsLoader.item
                            function onContentReadyChanged() { panel._scheduleTabHeightRelease() }
                            function onSectionSwapped() { contentFlick.scrollToTop() }
                            function onSectionsRequested() { panel.openNav() }
                        }
                    }

                    PageLoader {
                        id: recentLoader
                        layoutWidth: panel.pageLayoutW
                        shown: panel.activeTab === 2 && MenuState.open
                        scrollOffset: contentFlick.contentY
                        active: panel._loadedDeferred && panel._recentRetained
                        asynchronous: true
                        onStatusChanged: panel._scheduleTabHeightRelease()
                        source: "RecentPage.qml"
                        pageActive: panel.activeTab === 2 && MenuState.open
                        powerOpen: panel.powerOpen
                        animateOnCreate: panel.fullyShown
                        viewportReady: panel.pageViewportReady
                        viewportHeight: panel.recentViewportH
                        thumbOutset: Math.round(panel.contentPad)
                        compactNavigation: panel._compactRecentNav
                        Connections {
                            target: recentLoader.item
                            function onContentReadyChanged() { panel._scheduleTabHeightRelease() }
                            function onAppsRequested() { panel.openNav() }
                        }
                    }

                    PageLoader {
                        id: mediaLoader
                        layoutWidth: panel.pageLayoutW
                        shown: panel.activeTab === MenuState.mediaTab && MenuState.open
                        scrollOffset: contentFlick.contentY
                        active: panel._mediaRetained
                        asynchronous: panel.fullyShown
                        onStatusChanged: panel._scheduleTabHeightRelease()
                        source: "MediaPage.qml"
                        pageActive: panel.activeTab === MenuState.mediaTab && MenuState.open
                        powerOpen: panel.powerOpen
                        animateOnCreate: panel.fullyShown
                        viewportReady: panel.pageViewportReady
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
                // the top line marks where scrolled rows are cut, which is under the settings header when it is pinned
                anchors.topMargin: Math.max(0, contentFlick.revealTopInset - 1)
                list: contentFlick
                // faded, not switched: the lines left on the first frame of a close or a page change
                opacity: panel.activeTab !== 2 && _contentSettle.ready ? 1 : 0
                visible: opacity > 0
                MotionBehavior on opacity { NumberAnimation { duration: Motion.fast } }
                z: 4
            }

            MenuScrollThumb {
                list: contentFlick
                contextKey: _contentSettle.contextKey
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
