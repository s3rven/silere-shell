pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../services"
import "../common"

PanelWindow {
    id: win

    required property ShellScreen targetScreen

    readonly property string _output: Compositor.monitorName(win.screen)
    property bool _ignoreOutsideTap: false

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
    WlrLayershell.keyboardFocus: MenuState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: MenuState.open || panel.opacity > 0.001

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
                panel.closePowerAndRestoreFocus()
            } else if (panel.activeTab === 0 && homeLoader.item && homeLoader.item.dismissInline()) {
            } else {
                MenuState.close()
            }
        }
    }

    // Ctrl (not bare Tab) so it can't hijack the wifi password field
    Shortcut {
        sequences: ["Ctrl+Tab", "Ctrl+PgDown"]
        context:  Qt.ApplicationShortcut
        enabled:  MenuState.open && !panel.powerOpen
        onActivated: panel._cycleTab(1)
    }
    Shortcut {
        sequences: ["Ctrl+Shift+Tab", "Ctrl+PgUp"]
        context:  Qt.ApplicationShortcut
        enabled:  MenuState.open && !panel.powerOpen
        onActivated: panel._cycleTab(-1)
    }

    Connections {
        target: ShellSettings
        function onBarPositionChanged() {
            if (!MenuState.open) return
            win._ignoreOutsideTap = true
            _outsideTapGuard.restart()
        }
    }

    Timer {
        id: _outsideTapGuard
        interval: 250
        repeat: false
        onTriggered: win._ignoreOutsideTap = false
    }

    Item { id: _fillArea; anchors.fill: parent }
    mask: Region { item: MenuState.open ? _fillArea : null }

    TapHandler {
        id: _dismiss
        enabled: MenuState.open && panel.scaleAmt > 0.95
        onTapped: {
            if (win._ignoreOutsideTap) return
            const p = _dismiss.point.position
            if (p.x < panel.x || p.x > panel.x + panel.width ||
                p.y < panel.y || p.y > panel.y + panel.height) {
                MenuState.close()
            }
        }
    }

    Loader {
        active: (MenuState.open || panel.opacity > 0.001)
            && ShellSettings.barFloating && ShellSettings.barShadow
        anchors.fill: panel
        opacity: panel.opacity
        z: -1
        sourceComponent: FloatingShadow {
            radius: panel.radius
            atBottom: panel.barBottom
        }
    }

    FloatingPopupCard {
        id: panel

        win: win
        open: MenuState.open
        anchorX: MenuState.anchorX
        barBottom: ShellSettings.barPosition === "bottom"
        targetWidth: placementW
        animateScale: false
        animatePlacement: false
        clip: true

        readonly property int _compactW: 398
        readonly property int _powerW: 566
        readonly property int _settingsW: 630
        readonly property bool _settingsNavVisible:
            activeTab === 1 && settingsNavOpen && !powerOpen
        readonly property bool _railExpanded: _settingsNavVisible || powerOpen
        readonly property int _targetPanelW: activeTab === 1 ? _settingsW
            : powerOpen ? _powerW : _compactW
        readonly property int _availablePanelW: win.width > 0
            ? Math.max(1, Math.floor(win.width - _minX * 2))
            : _settingsW
        readonly property int panelW: Math.max(1,
            Math.min(_targetPanelW, _availablePanelW))
        readonly property int placementW: Math.max(1,
            Math.min(_settingsW, _availablePanelW))
        readonly property int railCollapsedW: 44
        readonly property int _navMinW: powerOpen ? 112 : 118
        readonly property int _navMaxW: activeTab === 1 ? 176 : 160
        readonly property int navW: {
            const available = panelW - railCollapsedW
            const desired = Math.max(_navMinW, Math.round(panelW * 0.28))
            const detailSafe = Math.max(_navMinW, available - 224)
            const sidebarFit = Math.max(0, available - 96)
            return Math.max(0, Math.min(_navMaxW, desired, detailSafe, sidebarFit))
        }
        readonly property int railExpandedW: railCollapsedW + navW
        readonly property int railW: _railExpanded ? railExpandedW : railCollapsedW
        readonly property int _railMotionMs: _railExpanded
            ? Motion.ms(165) : Motion.ms(115)
        readonly property int _railMotionEasing: _railExpanded
            ? Easing.OutQuint : Easing.InOutCubic
        readonly property int _panelWidthMotionMs: activeTab === 1
            ? Motion.ms(180) : Motion.ms(145)
        readonly property int contentW: panelW - railW
        readonly property int contentPad: activeTab === 1
            ? Math.max(12, Math.min(20,
                Math.round(12 + (panelW - 398) * 8 / 232)))
            : _railExpanded && panelW >= 460 ? 18 : 12
        readonly property int innerW: Math.max(1, contentW - contentPad * 2)
        readonly property int idealMinH: 360
        readonly property int minRailFitH: 252
        readonly property int pageTopInset: 12
        readonly property int pageBottomInset: 12
        readonly property int _availablePanelH: win.height > 0
            ? Math.max(1, Math.floor(win.height - _edgeY - _minX))
            : contentPane.targetH
        readonly property int recentViewportH: Math.max(1,
            Math.min(idealMinH - pageTopInset - pageBottomInset,
                _availablePanelH - pageTopInset - pageBottomInset))
        readonly property int targetPanelH: Math.max(1,
            Math.min(contentPane.targetH, _availablePanelH))

        readonly property int activeTab: MenuState.activeTab
        readonly property var _focusWindow: panel.Window.window

        property bool powerOpen: false
        property bool settingsNavOpen: true
        property bool _loadedDeferred: false
        property bool _geometryReady:  false
        property bool _homeRetained:    false
        property bool _settingsRetained: false
        property bool _recentRetained:  false
        // kept alive once incubated so later reveals are presentation-only
        property bool _settingsNavRetained: false

        Component.onCompleted: {
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

            if (!_loadedDeferred) {
                _settingsUnload.stop()
                _recentUnload.stop()
                _settingsRetained = false
                _recentRetained = false
                return
            }

            if (activeTab === 1) {
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

        function _settlePageVisuals(): void {
            if (homeLoader.item) homeLoader.item.settleVisual(activeTab === 0)
            if (settingsLoader.item) settingsLoader.item.settleVisual(activeTab === 1)
            if (recentLoader.item) recentLoader.item.settleVisual(activeTab === 2)
        }

        onCloseFinished: {
            if (open) return
            _settlePageVisuals()
            if (powerOpen) _railPower.forceActiveFocus()
            powerOpen = false
        }

        function _ownsItem(item, ancestor): bool {
            let current = item
            while (current) {
                if (current === ancestor) return true
                current = current.parent
            }
            return false
        }

        function switchTab(idx: int): void {
            const tab = Math.max(0, Math.min(2, idx))
            if (tab === 1) {
                _settingsNavRetained = true
                if (activeTab !== 1) settingsNavOpen = true
            }
            const focusedItem = _focusWindow ? _focusWindow.activeFocusItem : null
            const focusNeedsReset = focusedItem && (
                _ownsItem(focusedItem, tabContent)
                || _ownsItem(focusedItem, _settingsNavLoader.item)
                || _ownsItem(focusedItem, _powerRailLoader.item))
            // move focus first: the tab change disables the page controls holding it
            if (focusNeedsReset) panel.forceActiveFocus()
            if (powerOpen) powerOpen = false
            if (tab !== MenuState.activeTab) MenuState.activeTab = tab
            contentFlick.contentY = 0
        }

        function toggleSettingsNav(): void {
            if (activeTab !== 1) {
                settingsNavOpen = true
                switchTab(1)
                return
            }
            const focusedItem = _focusWindow ? _focusWindow.activeFocusItem : null
            if (settingsNavOpen && _ownsItem(focusedItem, _settingsNavLoader.item))
                _railSettings.forceActiveFocus()
            settingsNavOpen = !settingsNavOpen
        }

        function closePowerAndRestoreFocus(): void {
            if (!powerOpen) return
            // PowerRailContent drops out of tab focus when inactive; hand focus
            // over first or Qt rejects the activeFocusOnTab change
            _railPower.forceActiveFocus()
            powerOpen = false
            _powerFocusRestore.restart()
        }

        function _revealFocusedControl(): void {
            if (powerOpen || activeTab === 2 || !MenuState.open) return
            const item = _focusWindow ? _focusWindow.activeFocusItem : null
            if (!item || !_ownsItem(item, tabContent)) return

            const p = item.mapToItem(contentFlick.contentItem, 0, 0)
            const margin = 12
            const top = p.y
            const bottom = top + Math.max(1, Number(item.height) || 1)
            const maxY = Math.max(0, contentFlick.contentHeight - contentFlick.height)
            let target = contentFlick.contentY
            if (top - margin < target) target = top - margin
            else if (bottom + margin > target + contentFlick.height)
                target = bottom + margin - contentFlick.height
            contentFlick.contentY = Math.max(0, Math.min(maxY, target))
        }

        readonly property var _tabOrder: [0, 2, 1]
        function _cycleTab(dir: int): void {
            const i = Math.max(0, _tabOrder.indexOf(activeTab))
            switchTab(_tabOrder[(i + dir + _tabOrder.length) % _tabOrder.length])
        }

        Connections {
            target: MenuState
            function onTabRequested(index) {
                if (index !== 0) panel._loadedDeferred = true
                panel.switchTab(index)
            }
            function onActiveTabChanged() {
                contentFlick.contentY = 0
                panel._syncPageRetention()
                if (!MenuState.open) panel._settlePageVisuals()
            }
            function onOpenChanged() {
                if (MenuState.open) {
                    contentFlick.contentY = 0
                    contentFlick.syncScrollAffordance()
                    panel.forceActiveFocus()
                } else {
                    _scrollSettle.stop()
                    _sectionScrollReset.stop()
                    _outsideTapGuard.stop()
                    win._ignoreOutsideTap = false
                }
            }
            function onSettingsSectionChanged() {
                if (MenuState.open && panel.activeTab === 1)
                    _sectionScrollReset.restart()
            }
        }

        Timer {
            id: _sectionScrollReset
            interval: Motion.pageOut
            onTriggered: contentFlick.contentY = 0
        }

        Timer {
            id: _homeUnload
            interval: Math.max(Motion.pageOut, Motion.ms(100)) + 30
            onTriggered: if (panel.activeTab !== 0) panel._homeRetained = false
        }

        Timer {
            id: _settingsUnload
            // warm window: cheap Home/Settings comparisons without a session-long retain
            interval: 8000
            onTriggered: if (panel.activeTab !== 1) panel._settingsRetained = false
        }

        Timer {
            id: _recentUnload
            interval: Math.max(Motion.pageOut, Motion.ms(100)) + 30
            onTriggered: if (panel.activeTab !== 2) panel._recentRetained = false
        }

        Timer {
            id: _settingsNavPrewarm
            // incubate after the entrance settles; switchTab() skips this delay
            interval: Motion.popIn + Motion.ms(70)
            onTriggered: panel._settingsNavRetained = true
        }

        Timer {
            id: _focusReveal
            interval: 0
            onTriggered: panel._revealFocusedControl()
        }

        Timer {
            id: _powerFocusRestore
            interval: 0
            onTriggered: if (MenuState.open && !panel.powerOpen) _railPower.forceActiveFocus()
        }

        Connections {
            target: panel._focusWindow
            function onActiveFocusItemChanged() {
                if (MenuState.open) _focusReveal.restart()
            }
        }

        width:  panelW
        height: targetPanelH

        Behavior on width {
            enabled: panel._geometryReady && panel.open
                && !ShellSettings.reduceMotion
            NumberAnimation {
                duration: panel._panelWidthMotionMs
                easing.type: Easing.OutQuint
            }
        }
        Behavior on height {
            enabled: panel._geometryReady && panel.open
                && !ShellSettings.reduceMotion
            SmoothedAnimation {
                velocity: Motion.panelVelocity
                maximumEasingTime: Motion.panelHeight
                reversingMode: SmoothedAnimation.Sync
            }
        }

        onStateChanged: {
            if (state === "visible") {
                if (!_loadedDeferred) {
                    Qt.callLater(function() { _loadedDeferred = true })
                }
                if (!_settingsNavRetained) _settingsNavPrewarm.restart()
            } else {
                _settingsNavPrewarm.stop()
            }
        }

        Item {
            id: rail
            x: 0; y: 0
            width: panel.railW
            height: panel.height
            clip: false
            z: 6

            Behavior on width {
                enabled: panel._geometryReady && panel.open
                    && !ShellSettings.reduceMotion
                NumberAnimation {
                    duration: panel._railMotionMs
                    easing.type: panel._railMotionEasing
                }
            }

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

                Hairline {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    vertical: true
                    color: Theme.menuDivider
                }

                Rectangle {
                    x: panel.railCollapsedW
                    width: Math.max(0, parent.width - x)
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    color: Theme.mix(Theme.menuPane, Theme.menuControl, 0.14)
                    visible: panel._railExpanded
                }

                Item {
                    id: _settingsRailSurface
                    x: panel.railCollapsedW
                    width: panel.navW
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    property real _slide: panel._settingsNavVisible
                        ? 0 : -Motion.pageOffset
                    opacity: panel._settingsNavVisible ? 1 : 0
                    visible: opacity > 0.001
                    enabled: panel._settingsNavVisible
                    transform: Translate { x: _settingsRailSurface._slide }
                    Behavior on opacity {
                        enabled: !ShellSettings.reduceMotion
                        NumberAnimation {
                            duration: panel._settingsNavVisible
                                ? Motion.ms(130) : Motion.ms(90)
                            easing.type: panel._settingsNavVisible
                                ? Easing.OutCubic : Easing.InCubic
                        }
                    }
                    Behavior on _slide {
                        enabled: !ShellSettings.reduceMotion
                        NumberAnimation {
                            duration: panel._railMotionMs
                            easing.type: panel._railMotionEasing
                        }
                    }

                    Loader {
                        id: _settingsNavLoader
                        anchors.fill: parent
                        active: panel._settingsNavRetained
                            || panel.activeTab === 1
                        // prewarm incubates across frames; a direct reveal must finish now
                        asynchronous: !panel._settingsNavVisible
                        sourceComponent: Component {
                            SettingsNav {
                                powerOpen: panel.powerOpen
                                onCurrentPageRetapped: contentFlick.contentY = 0
                            }
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

                    Behavior on height {
                        enabled: !ShellSettings.reduceMotion
                        NumberAnimation {
                            duration: Motion.panelHeight
                            easing.type: panel.powerOpen ? Easing.OutQuart : Easing.InCubic
                        }
                    }
                    Behavior on opacity {
                        enabled: !ShellSettings.reduceMotion
                        NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
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

            Column {
                id: _railNav
                width: panel.railCollapsedW
                x: 0
                y: 10
                spacing: 6

                RailNavItem {
                    id: _railHome
                    labels: _railLabels
                    railW: panel.railCollapsedW
                    glyph: "󰋜"
                    label: "Home"
                    active: panel.activeTab === 0
                    KeyNavigation.up: _railPower
                    KeyNavigation.down: _railRecent
                    onTapped: panel.switchTab(0)
                }

                RailNavItem {
                    id: _railRecent
                    labels: _railLabels
                    railW: panel.railCollapsedW
                    glyph: "󰋚"
                    label: "Notifications"
                    active: panel.activeTab === 2
                    KeyNavigation.up: _railHome
                    KeyNavigation.down: _railSettings
                    onTapped: panel.switchTab(2)

                    Rectangle {
                        readonly property bool _show: Notifications.hasHistory && !_railRecent.active
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.horizontalCenterOffset: 8
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -8
                        width: Math.max(height, _railBadgeCount.implicitWidth + 7)
                        height: 14; radius: height / 2
                        color: Theme.accent; antialiasing: true
                        border.width: 2
                        border.color: Theme.menuPane
                        opacity: _show ? 1.0 : 0.0
                        scale:   _show ? 1.0 : 0.5
                        visible: opacity > 0.01
                        transformOrigin: Item.Center
                        Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast } }
                        Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic } }
                        Text {
                            id: _railBadgeCount
                            anchors.fill: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: Notifications.historyCount > 99 ? "99+" : Notifications.historyCount
                            color: Theme.background
                            font.family: Settings.font; font.pixelSize: Settings.fontSize - 4
                            font.weight: Font.Bold
                            renderType: Text.NativeRendering
                        }
                    }
                }

                RailNavItem {
                    id: _railSettings
                    labels: _railLabels
                    railW: panel.railCollapsedW
                    glyph: panel.activeTab === 1 ? "󰍜" : "󰒓"
                    label: "Settings"
                    accessibleDescription: panel.activeTab === 1
                        ? (panel.settingsNavOpen ? "Collapse the settings sidebar"
                            : "Expand the settings sidebar")
                        : "Open Settings"
                    active: panel.activeTab === 1
                    KeyNavigation.up: _railRecent
                    KeyNavigation.down: _railPower
                    onTapped: panel.toggleSettingsNav()
                }
            }

            Item {
                id: _railPowerSlot
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                anchors.left: parent.left
                width: panel.railCollapsedW
                height: 1 + 10 + 34
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
                    anchors.topMargin: 10
                    anchors.horizontalCenter: parent.horizontalCenter
                    railW: panel.railCollapsedW
                    glyph: "󰐥"
                    label: "Power"
                    accentColor: Theme.error
                    active: panel.powerOpen
                    KeyNavigation.up: _railSettings
                    KeyNavigation.down: _railHome
                    onTapped: {
                        if (panel.powerOpen) panel.closePowerAndRestoreFocus()
                        else {
                            _railPower.forceActiveFocus()
                            panel.powerOpen = true
                        }
                    }
                }
            }
        }

        Item {
            id: contentPane
            x: panel.railW
            y: 0
            width: panel.contentW
            clip: true

            Behavior on x {
                enabled: panel._geometryReady && panel.open
                    && !ShellSettings.reduceMotion
                NumberAnimation {
                    duration: panel._railMotionMs
                    easing.type: panel._railMotionEasing
                }
            }

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
                    ? (_settingsNavLoader.item?.implicitHeight ?? 0) + 16 : 0
                return 4 * Math.ceil(Math.max(panel.minRailFitH,
                    panel.idealMinH, contentH, navH) / 4)
            }

            height: panel.height

            TapHandler {
                enabled: panel.powerOpen
                onTapped: panel.closePowerAndRestoreFocus()
            }

            Flickable {
                id: contentFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: tabContent.y + tabContent.height
                    + panel.pageBottomInset
                clip: true
                boundsMovement: Flickable.StopAtBounds
                flickDeceleration: 1800
                maximumFlickVelocity: 2200
                readonly property bool _overflows: contentHeight > height + 1
                // scrolling reacts at once; the edge fades wait out the resize so a
                // page swap can't flash them (see MenuScrollThumb)
                property bool needsScroll: false
                function syncScrollAffordance(): void {
                    if (!contentFlick._overflows) {
                        _scrollSettle.stop()
                        contentFlick.needsScroll = false
                    } else if (panel.open) {
                        _scrollSettle.restart()
                    }
                }
                on_OverflowsChanged: syncScrollAffordance()
                Timer {
                    id: _scrollSettle
                    interval: Motion.panelHeight
                    onTriggered: contentFlick.needsScroll = contentFlick._overflows
                }
                Component.onCompleted: syncScrollAffordance()
                interactive: !panel.powerOpen && panel.activeTab !== 2 && _overflows

                function clampToContent(): void {
                    const maxY = Math.max(0, contentHeight - height)
                    if (contentY > maxY) contentY = maxY
                    else if (contentY < 0) contentY = 0
                }

                onContentHeightChanged: clampToContent()
                onHeightChanged: clampToContent()

                Item {
                    id: tabContent
                    x: panel.contentPad
                    y: panel.pageTopInset
                    width: panel.innerW
                    readonly property bool _pagePending:
                        panel.activeTab === 1 ? settingsLoader.status !== Loader.Ready
                      : panel.activeTab === 2 ? recentLoader.status !== Loader.Ready
                      : false
                    readonly property bool _pageError:
                        panel.activeTab === 1 ? settingsLoader.status === Loader.Error
                      : panel.activeTab === 2 ? recentLoader.status === Loader.Error
                      : false
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
                        opacity: tabContent._pagePending ? 1 : 0
                        visible: opacity > 0.001
                        enabled: false
                        z: 5

                        Behavior on opacity {
                            enabled: !ShellSettings.reduceMotion
                            NumberAnimation { duration: Motion.pageOut; easing.type: Easing.InCubic }
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

                                Text {
                                    anchors.centerIn: parent
                                    text: tabContent._pageError ? "󰅙" : "󰔟"
                                    color: tabContent._pageError
                                        ? Theme.withAlpha(Theme.error, 0.82)
                                        : Theme.withAlpha(Theme.accent, 0.76)
                                    font.family: Settings.font
                                    font.pixelSize: Settings.iconSize + 5
                                    renderType: Text.NativeRendering
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.max(1, _pagePlaceholder.width - 24)
                                horizontalAlignment: Text.AlignHCenter
                                text: tabContent._pageError
                                    ? "Couldn’t load this page"
                                    : panel.activeTab === 1 ? "Loading settings…" : "Loading notifications…"
                                color: Theme.withAlpha(Theme.text, 0.76)
                                font.family: Settings.font
                                font.pixelSize: Settings.fontSize
                                font.weight: Font.Medium
                                renderType: Text.NativeRendering
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.max(1, _pagePlaceholder.width - 24)
                                horizontalAlignment: Text.AlignHCenter
                                visible: tabContent._pageError
                                text: "The menu is still usable; check the shell log for details"
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                color: Theme.withAlpha(Theme.subtext, 0.54)
                                font.family: Settings.font
                                font.pixelSize: Math.max(8, Settings.fontSize - 2)
                                renderType: Text.NativeRendering
                            }
                        }
                    }

                    Loader {
                        id: homeLoader
                        width: parent.width
                        active: panel._homeRetained
                        asynchronous: false
                        sourceComponent: Component {
                            HomePage {
                                width: parent.width
                                active: panel.activeTab === 0 && MenuState.open
                                powerOpen: panel.powerOpen
                            }
                        }
                    }

                    Loader {
                        id: settingsLoader
                        width: parent.width
                        active: panel._loadedDeferred && panel._settingsRetained
                        asynchronous: true
                        sourceComponent: Component {
                            SettingsPage {
                                width: parent.width
                                active: panel.activeTab === 1 && MenuState.open
                                powerOpen: panel.powerOpen
                            }
                        }
                    }

                    Loader {
                        id: recentLoader
                        width: parent.width
                        active: panel._loadedDeferred && panel._recentRetained
                        asynchronous: true
                        sourceComponent: Component {
                            RecentPage {
                                width: parent.width
                                viewportHeight: panel.recentViewportH
                                active: panel.activeTab === 2 && MenuState.open
                                powerOpen: panel.powerOpen
                            }
                        }
                    }
                }
            }

            ListEdgeFade {
                anchors.fill: contentFlick
                list: contentFlick
                fadeColor: Theme.menuPane
                visible: panel.activeTab !== 2 && contentFlick.needsScroll
                z: 4
            }

            MenuScrollThumb {
                list: contentFlick
                shown: !panel.powerOpen && panel.activeTab !== 2
                z: 5
            }
        }

        OutlineBorder {
            radius: panel.radius
            outlineColor: Theme.outline
            z: 20
        }
    }

}
