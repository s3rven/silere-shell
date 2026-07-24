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

    // unmap the full-screen surface while closed so it isn't holding a screen-sized GPU buffer; stays mapped through the close animation
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
                // open wifi/bt picker folded away; menu stays
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

    // shadow matches the other bar-edge popups; outside the card so the scale transform doesn't distort it
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
        // Place every tab inside the widest responsive envelope from the
        // start. The card may resize, but its left rail stays under the mouse.
        targetWidth: placementW
        animateScale: false
        animatePlacement: false
        border.width: 0
        // Keep async page content inside the destination surface.
        clip: true

        // Home/Notifications read best compact; Settings needs room for the
        // category nav and detail column.
        readonly property int _compactW: 398
        readonly property int _powerW: 566
        readonly property int _settingsW: 630
        readonly property bool _railExpanded: activeTab === 1 || powerOpen
        readonly property int _targetPanelW: activeTab === 1 ? _settingsW
            : powerOpen ? _powerW : _compactW
        readonly property int _availablePanelW: win.width > 0
            ? Math.max(1, Math.floor(win.width - _minX * 2))
            : _settingsW
        // Never force the popup beyond the output. Controls below already
        // reflow; letting the surface shrink keeps both edges reachable.
        readonly property int panelW: Math.max(1,
            Math.min(_targetPanelW, _availablePanelW))
        readonly property int placementW: Math.max(1,
            Math.min(_settingsW, _availablePanelW))
        // rail expands for Settings: icon strip stays fixed, category nav rides on beside it as one growing surface
        readonly property int railCollapsedW: 44
        readonly property int _navMinW: powerOpen ? 112 : 118
        readonly property int _navMaxW: activeTab === 1 ? 176 : 160
        // Preserve a useful detail pane on narrow outputs. The category labels
        // elide cleanly, while settings controls need at least twice this space.
        readonly property int navW: {
            const available = panelW - railCollapsedW
            const desired = Math.max(_navMinW, Math.round(panelW * 0.28))
            // Prefer a readable nav, but never let it consume the last 96px of
            // the detail pane on exceptionally narrow outputs.
            const detailSafe = Math.max(_navMinW, available - 224)
            const sidebarFit = Math.max(0, available - 96)
            return Math.max(0, Math.min(_navMaxW, desired, detailSafe, sidebarFit))
        }
        readonly property int railExpandedW: railCollapsedW + navW
        readonly property int railW: _railExpanded ? railExpandedW : railCollapsedW
        readonly property int contentW: panelW - railW
        readonly property int contentPad: activeTab === 1
            ? Math.max(12, Math.min(20,
                Math.round(12 + (panelW - 398) * 8 / 232)))
            : _railExpanded && panelW >= 460 ? 18 : 12
        readonly property int innerW: Math.max(1, contentW - contentPad * 2)
        // shared height floor so every tab opens at the same size; taller content grows above it
        readonly property int idealMinH: 360
        // min height so rail icons never overlap the power slot
        readonly property int minRailFitH: 252
        readonly property int _availablePanelH: win.height > 0
            ? Math.max(1, Math.floor(win.height - _edgeY - _minX))
            : contentPane.targetH
        readonly property int targetPanelH: Math.max(1,
            Math.min(contentPane.targetH, _availablePanelH))

        readonly property int activeTab: MenuState.activeTab
        readonly property var _focusWindow: panel.Window.window

        property bool powerOpen: false
        property bool _homeLoaded:     false
        property bool _loadedDeferred: false
        property bool _settingsLoaded: false
        property bool _recentLoaded:   false

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
            const focusedItem = _focusWindow ? _focusWindow.activeFocusItem : null
            const focusNeedsReset = focusedItem && (
                _ownsItem(focusedItem, tabContent)
                || _ownsItem(focusedItem, _settingsNavLoader.item)
                || _ownsItem(focusedItem, _powerRailLoader.item))
            if (powerOpen) powerOpen = false
            if (tab === 0) _homeLoaded = true
            if (tab === 1) _settingsLoaded = true
            if (tab === 2) _recentLoaded = true
            if (tab !== MenuState.activeTab) MenuState.activeTab = tab
            contentFlick.contentY = 0
            // panel is a ring-free Tab origin; otherwise focus strands in the disabled page
            if (focusNeedsReset) panel.forceActiveFocus()
        }

        function closePowerAndRestoreFocus(): void {
            if (!powerOpen) return
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

        // Cycle the rail in its visual order (Now, Recent, Settings) for Ctrl+Tab.
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
                if (MenuState.activeTab === 0) panel._homeLoaded = true
                if (MenuState.activeTab === 1) panel._settingsLoaded = true
                if (MenuState.activeTab === 2) panel._recentLoaded = true
                contentFlick.contentY = 0
            }
            function onOpenChanged() {
                if (MenuState.open) {
                    contentFlick.contentY = 0
                    // deterministic Tab start: panel paints no focus ring, and this clears stale child focus from the previous open
                    panel.forceActiveFocus()
                } else {
                    _outsideTapGuard.stop()
                    win._ignoreOutsideTap = false
                }
            }
            function onSettingsSectionChanged() { _sectionScrollReset.restart() }
        }

        // a new section starts at its top; the delay lands the jump inside the
        // detail swap's opacity-0 gap so it is never seen
        Timer {
            id: _sectionScrollReset
            interval: ShellSettings.reduceMotion ? 0 : Motion.ms(60)
            onTriggered: contentFlick.contentY = 0
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

        onStateChanged: {
            if (state === "hidden") {
                powerOpen = false
            } else {
                if (activeTab === 1) _settingsLoaded = true
                if (activeTab === 2) _recentLoaded = true
                if (activeTab === 0) _homeLoaded = true
                if (!_loadedDeferred) {
                    Qt.callLater(function() { _loadedDeferred = true })
                }
            }
        }

        Item {
            id: rail
            x: 0; y: 0
            width: panel.railW
            height: panel.height
            clip: false  // allow hover pills to overflow into content area
            z: 6         // render above the content pane so pills aren't hidden

            // background + divider live in a clipped sub-layer so the over-wide rounded background can't bleed past the rail edge; icons/pills stay unclipped
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
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    color: Theme.menuDivider
                }

                Rectangle {
                    x: panel.railCollapsedW
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    color: Theme.menuDivider
                    opacity: panel._railExpanded ? 1 : 0
                    visible: opacity > 0.001
                    Behavior on opacity {
                        enabled: !ShellSettings.reduceMotion
                        NumberAnimation { duration: Motion.medium }
                    }
                }

                // settings categories in the clipped surface: the growing rail reveals them left-to-right, can't paint past the rail edge mid-animation
                Item {
                    x: panel.railCollapsedW
                    width: panel.navW
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    opacity: panel.activeTab === 1 && !panel.powerOpen ? 1 : 0
                    visible: opacity > 0.001
                    enabled: panel.activeTab === 1 && !panel.powerOpen
                    Behavior on opacity {
                        enabled: !ShellSettings.reduceMotion
                        NumberAnimation { duration: Motion.fast }
                    }

                    Loader {
                        id: _settingsNavLoader
                        anchors.fill: parent
                        active: panel._settingsLoaded || panel.activeTab === 1
                        sourceComponent: Component {
                            SettingsNav {
                                powerOpen: panel.powerOpen
                                onCurrentPageRetapped: contentFlick.contentY = 0
                            }
                        }
                    }
                }

                // Same expanded rail surface as Settings, clipped from the bottom so it reveals upward from the power slot.
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
                        NumberAnimation { duration: Motion.ms(170); easing.type: Easing.OutCubic }
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

            // nav icons. rail order is visual only; tab index stays page-bound (0 Home / 1 Settings / 2 Notifications) so loaders and jump-to-tab keep working
            Column {
                id: _railNav
                width: panel.railCollapsedW
                x: 0
                y: 10
                spacing: 6

                RailNavItem {
                    id: _railHome
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
                    railW: panel.railCollapsedW
                    glyph: "󰋚"
                    label: "Notifications"
                    active: panel.activeTab === 2
                    KeyNavigation.up: _railHome
                    KeyNavigation.down: _railSettings
                    onTapped: panel.switchTab(2)

                    // count badge on the icon's top-right, anchored to item centre so it stays glued regardless of rail width; rail-coloured ring lifts it off
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
                    railW: panel.railCollapsedW
                    glyph: "󰒓"
                    label: "Settings"
                    active: panel.activeTab === 1
                    KeyNavigation.up: _railRecent
                    KeyNavigation.down: _railPower
                    onTapped: panel.switchTab(1)
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

                Rectangle {
                    id: _railDivider
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 18
                    height: 1
                    color: Theme.menuDivider
                }

                RailNavItem {
                    id: _railPower
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
                        else panel.powerOpen = true
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

            Rectangle {
                x: -panel.radius
                y: 0
                width: parent.width + panel.radius
                height: parent.height
                radius: panel.radius
                antialiasing: true
                color: Theme.menuPane
            }

            // Snap the destination to the divider grid. Content and the nav
            // determine the compact height; the viewport handles overflow.
            readonly property int targetH: {
                const contentH = tabContent.y + tabContent.height + 12
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
                contentHeight: tabContent.y + tabContent.height + 12
                clip: true
                boundsMovement: Flickable.StopAtBounds
                flickDeceleration: 1800
                maximumFlickVelocity: 2200
                // Notifications owns the only scroll surface on its tab; other pages use this outer scroller
                interactive: !panel.powerOpen && panel.activeTab !== 2 && contentHeight > height + 1

                function clampToContent(): void {
                    const maxY = Math.max(0, contentHeight - height)
                    if (contentY > maxY) contentY = maxY
                    else if (contentY < 0) contentY = 0
                }

                // content can shrink while the viewport grows; both bounds move
                onContentHeightChanged: clampToContent()
                onHeightChanged: clampToContent()

                Item {
                    id: tabContent
                    x: panel.contentPad
                    y: 12   // 4px multiple, keeps card dividers on the grid
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
                        implicitHeight: Math.max(220, panel.idealMinH - tabContent.y - 16)
                        visible: tabContent._pagePending
                        enabled: false
                        z: 5

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
                                border.width: 1
                                border.color: tabContent._pageError
                                    ? Theme.withAlpha(Theme.error, 0.34)
                                    : Theme.withAlpha(Theme.accent, 0.20)

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
                        active: panel._homeLoaded
                        // sync: the landing tab must be up with the open animation
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
                        // build Settings only when the tab's first used — it's the largest subtree, preloading on every Home open costs memory + startup
                        active: panel._loadedDeferred && (panel._settingsLoaded || panel.activeTab === 1)
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
                        // build the archive only after first open; then cached until the menu's idle unload
                        active: panel._loadedDeferred && (panel._recentLoaded || panel.activeTab === 2)
                        asynchronous: true
                        sourceComponent: Component {
                            RecentPage {
                                width: parent.width
                                viewportHeight: Math.max(220,
                                    Math.min(panel.idealMinH,
                                        panel._availablePanelH)
                                        - tabContent.y - 16)
                                active: panel.activeTab === 2 && MenuState.open
                                powerOpen: panel.powerOpen
                            }
                        }
                    }
                }
            }

            // overflow cue for the shared Home/Settings scroller; without it, over-tall content (media + sun arc) clips with no hint. Notifications owns its own fade
            ListEdgeFade {
                anchors.fill: contentFlick
                list: contentFlick
                fadeColor: Theme.menuPane
                visible: panel.activeTab !== 2 && contentFlick.contentHeight > contentFlick.height + 1
                z: 4
            }

            // Quiet position cue for long Home/Settings pages. The edge fade
            // says more content exists; this shows where the user is in it.
            Rectangle {
                id: _contentScrollThumb
                readonly property real _trackH: Math.max(1, contentPane.height - 16)
                readonly property real _overflow: Math.max(1,
                    contentFlick.contentHeight - contentFlick.height)

                anchors.right: parent.right
                anchors.rightMargin: 3
                y: 8 + Math.max(0, _trackH - height)
                    * (contentFlick.contentY / _overflow)
                width: 2
                height: Math.min(_trackH, Math.max(22, _trackH * Math.min(1,
                    contentFlick.height / Math.max(1, contentFlick.contentHeight))))
                radius: 1
                antialiasing: true
                color: Theme.accent
                opacity: visible ? (contentFlick.moving ? 0.62 : 0.26) : 0
                visible: !panel.powerOpen && panel.activeTab !== 2
                    && contentFlick.contentHeight > contentFlick.height + 1
                z: 5

                Behavior on opacity {
                    enabled: !ShellSettings.reduceMotion
                    NumberAnimation { duration: Motion.fast }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: panel.radius
            antialiasing: true
            color: "transparent"
            border.width: 1
            border.color: Theme.outline
            z: 20
        }
    }

}
