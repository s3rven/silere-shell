pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland._WlrLayerShell
import Quickshell.Hyprland
import "../../config"
import "../../services"
import "../common"

PanelWindow {
    id: win

    required property ShellScreen targetScreen

    readonly property HyprlandMonitor _monitor: Hyprland.monitorFor(win.screen)
    property bool _ignoreOutsideTap: false

    Connections {
        target: win._monitor
        function onActiveWorkspaceChanged() {
            if (MenuState.open) MenuState.close()
        }
    }

    screen:        targetScreen
    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "silere-menu"
    WlrLayershell.keyboardFocus: MenuState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Unmap the full-screen surface while the menu is closed so it isn't holding a
    // screen-sized GPU buffer at rest, stays mapped through the close animation.
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
                panel.powerOpen = false
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
            if (!MenuState.open) {
                panel.edgeOffset = panel._closedOffset
                panel._place()
                return
            }
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

    function commandAvailable(command): bool {
        if (!command || command.length === 0) return false
        const tool = String(command[0])
        if (tool === "hyprlock")  return SystemTools.hasHyprlock
        if (tool === "systemctl") return SystemTools.hasSystemctl
        return true
    }

    function _shq(s): string {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    // execDetached can't report failures; wrap so a non-zero exit (auth/inhibitor) notifies.
    function runPower(command, failTitle): void {
        if (!command || command.length === 0) return
        if (!SystemTools.hasNotifySend) { Quickshell.execDetached(command); return }
        const note = "notify-send --urgency=critical --app-name=silere-shell " +
            _shq(failTitle) + " " + _shq("It may require authorization or be blocked by a running task.")
        const argv = ["bash", "-c", '"$@" || ' + note, "bash"]
        for (let i = 0; i < command.length; i++) argv.push(String(command[i]))
        Quickshell.execDetached(argv)
    }

    Item { id: _fillArea; anchors.fill: parent }
    mask: Region { item: MenuState.open ? _fillArea : null }

    TapHandler {
        id: _dismiss
        enabled: MenuState.open && panel.menuScale > 0.95
        onTapped: {
            if (win._ignoreOutsideTap) return
            const p = _dismiss.point.position
            if (p.x < panel.x || p.x > panel.x + panel.width ||
                p.y < panel.y || p.y > panel.y + panel.height) {
                MenuState.close()
            }
        }
    }

    Rectangle {
        id: panel

        // Home/Notifications read best compact; Settings needs room for the tree-nav
        // plus the 4-chip option rows.
        readonly property int _compactW:  398
        // Expanded settings width is the collapsed icon rail plus category nav
        // and a content column wide enough for dense settings rows.
        readonly property int _settingsW: 566
        readonly property int _targetPanelW: activeTab === 1 ? _settingsW : _compactW
        readonly property int panelW: Math.max(320, Math.min(_targetPanelW,
            win.width > 0 ? win.width - panelMinX * 2 : _targetPanelW))
        // Rail expands when Settings is active: the icon strip stays fixed and the
        // category nav rides on beside it, so they read as one growing surface.
        readonly property int railCollapsedW: 44
        readonly property int navW: 168
        readonly property int railExpandedW: railCollapsedW + navW
        readonly property int railW: activeTab === 1 ? railExpandedW : railCollapsedW
        readonly property int contentW: panelW - railW
        readonly property int contentPad: activeTab === 1 ? 18 : 12
        readonly property int innerW: contentW - contentPad * 2
        // Shared height floor so every tab opens at the same size; taller
        // content grows above it and the panel animates the change.
        readonly property int idealMinH: 360
        // min height so rail icons never overlap the power slot
        readonly property int minRailFitH: 252
        readonly property int heightAnimDuration: Motion.medium
        readonly property int _availablePanelH: win.height > 0
            ? Math.max(minRailFitH, win.height - _edgeY - panelMinX)
            : contentPane.targetH
        readonly property int targetPanelH: Math.min(contentPane.targetH, _availablePanelH)

        property int activeTab: 0
        onActiveTabChanged: MenuState.activeTab = activeTab

        readonly property bool _barBottom: ShellSettings.barPosition === "bottom"

        // Visible bar edge in window coords (mirrors Bar.qml's surfaceInset),
        // plus a detach gap so the panel floats clear of the bar.
        readonly property int _barInset: ShellSettings.barFloating ? 4 : 0
        readonly property int _edgeY: _barInset + ShellSettings.barHeight + 8
        readonly property real panelMinX: radius + 4
        readonly property real panelMaxX: Math.max(panelMinX, win.width - panelW - panelMinX)

        // Detached popup: starts just behind the bar-side edge, then settles into
        // place via scale/offset — height is fixed up front, not animated.
        property real menuScale: Motion.popScaleFrom
        property real edgeOffset: _closedOffset
        readonly property real _closedOffset: _barBottom ? 8 : -8
        readonly property real _originX: Math.max(0, Math.min(panelW, MenuState.anchorX - x))

        property bool powerOpen: false
        property bool _loaded:         false
        property bool _loadedDeferred: false
        property bool _recentLoaded:   false
        property bool _placementSettled: false

        function switchTab(idx: int): void {
            if (powerOpen) powerOpen = false
            if (idx === 2) _recentLoaded = true
            if (idx === activeTab) return
            activeTab = idx
            contentFlick.contentY = 0
        }

        // Cycle the rail in its visual order (Now, Recent, Settings) for Ctrl+Tab.
        readonly property var _tabOrder: [0, 2, 1]
        function _cycleTab(dir: int): void {
            const i = Math.max(0, _tabOrder.indexOf(activeTab))
            switchTab(_tabOrder[(i + dir + _tabOrder.length) % _tabOrder.length])
        }

        function _clampedPanelX(px: real): real {
            return Math.max(panelMinX, Math.min(px, panelMaxX))
        }

        // x is stateful, not a live clamp binding: it re-clamps only when the
        // constraints are actually violated, so the panel holds still while
        // settings resize the screen-side margins underneath it.
        //
        // Trigger-proportional placement: the trigger keeps the same relative
        // position inside the panel as it has across the screen (centre click
        // → centred panel, edge click → panel hugs that side). A plain
        // centre-then-clamp saturates near the edges, pinning every open from
        // the workspaces diamond on a custom-width bar to one spot.
        function _place(): void {
            const t = Math.max(0, Math.min(win.width, MenuState.anchorX))
            x = Math.round(_clampedPanelX(t - panelW * t / Math.max(1, win.width)))
        }
        function _reclamp(): void {
            const nx = Math.round(_clampedPanelX(x))
            if (Math.abs(nx - x) > 0.5) x = nx
        }
        onPanelMinXChanged: _reclamp()
        onPanelMaxXChanged: _reclamp()
        onPanelWChanged: if (MenuState.open) _reclamp()
        Component.onCompleted: _place()

        // Pages (e.g. the DND tile's missed-count badge) can ask to jump tabs.
        Connections {
            target: MenuState
            function onTabRequested(index) {
                if (index !== 0) panel._loadedDeferred = true
                panel.switchTab(index)
            }
            function onAnchorXChanged() { panel._place() }
            function onOpenChanged() {
                if (MenuState.open) {
                    panel._placementSettled = false
                    panel._place()
                    _placementSettle.restart()
                    contentFlick.contentY = 0
                    // Deterministic Tab start, no ring: the panel paints nothing
                    // on focus, and this clears any stale child focus from the
                    // previous open.
                    panel.forceActiveFocus()
                } else {
                    _placementSettle.stop()
                    panel._placementSettled = false
                    _outsideTapGuard.stop()
                    win._ignoreOutsideTap = false
                }
            }
        }

        // The window unmaps while closed and its width reads garbage (100/0/
        // stale) until the compositor configures it — the open-time _place()
        // computes against that and pins the panel far left. x is stateful, so
        // it can't self-heal: re-place when the real width lands.
        Connections {
            target: win
            function onWidthChanged() {
                if (!MenuState.open) return
                const t = Math.max(0, Math.min(win.width, MenuState.anchorX))
                const nx = Math.round(panel._clampedPanelX(t - panel.panelW * t / Math.max(1, win.width)))
                if (Math.abs(nx - panel.x) > 0.5) panel._place()
            }
        }

        y: Math.round((_barBottom ? (win.height - _edgeY - height) : _edgeY) + edgeOffset)

        width:  panelW
        height: targetPanelH
        radius: Theme.radiusPanel
        clip: false
        antialiasing: true

        Behavior on height {
            enabled: panel.state === "visible" && !ShellSettings.reduceMotion
            NumberAnimation { duration: panel.heightAnimDuration; easing.type: Easing.OutCubic }
        }

        // Width and x share the height duration; mismatched clocks read as jitter.
        Behavior on width {
            enabled: panel.state === "visible" && !ShellSettings.reduceMotion
            NumberAnimation { duration: panel.heightAnimDuration; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            enabled: !ShellSettings.reduceMotion && panel.state === "visible" && panel._placementSettled
            NumberAnimation { duration: panel.heightAnimDuration; easing.type: Easing.OutCubic }
        }

        Behavior on edgeOffset {
            enabled: panel.state === "visible" && !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
        }

        // Same material as the bar so the shell reads as one family, but a
        // free-standing rounded panel rather than a fused extension of it.
        color: Theme.popup
        border.width: 0

        transform: Scale {
            origin.x: panel._originX
            origin.y: panel._barBottom ? panel.height : 0
            xScale:   panel.menuScale
            yScale:   panel.menuScale
        }

        state: MenuState.open ? "visible" : "hidden"
        // Layer only while the scale animates so NativeRendering text doesn't
        // shimmer; a hidden menu holds no FBO.
        layer.enabled: !ShellSettings.reduceMotion && opacity > 0.001 && menuScale < 0.999

        states: [
            State {
                name: "hidden"
                PropertyChanges { target: panel; menuScale: Motion.popScaleFrom; edgeOffset: panel._closedOffset; opacity: 0 }
            },
            State {
                name: "visible"
                PropertyChanges { target: panel; menuScale: 1.0; edgeOffset: 0; opacity: 1 }
            }
        ]

        transitions: [
            Transition {
                from: "*"; to: "visible"
                ParallelAnimation {
                    NumberAnimation {
                        target: panel; property: "menuScale"
                        to: 1.0; duration: Motion.popIn
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: panel; property: "edgeOffset"
                        to: 0; duration: Motion.popIn
                        easing.type: Easing.OutQuart
                    }
                    NumberAnimation {
                        target: panel; property: "opacity"
                        to: 1.0; duration: Motion.popInFade; easing.type: Easing.OutCubic
                    }
                }
            },
            Transition {
                from: "visible"; to: "hidden"
                ParallelAnimation {
                    NumberAnimation {
                        target: panel; property: "menuScale"
                        to: Motion.popScaleFrom; duration: Motion.popOut
                        easing.type: Easing.InCubic
                    }
                    NumberAnimation {
                        target: panel; property: "edgeOffset"
                        to: panel._closedOffset; duration: Motion.popOut
                        easing.type: Easing.InCubic
                    }
                    NumberAnimation {
                        target: panel; property: "opacity"
                        to: 0.0; duration: Motion.popOutFade; easing.type: Easing.InCubic
                    }
                }
            }
        ]

        onStateChanged: {
            if (state === "hidden") {
                powerOpen = false
                _placementSettled = false
                _idleUnload.restart()
            } else {
                _idleUnload.stop()
                if (!_loaded) {
                    _loaded = true
                    Qt.callLater(function() { _loadedDeferred = true })
                }
            }
        }

        // Free the page tree once the menu's been closed a while. Reopening
        // rebuilds it from cached bytecode, so quick reopens stay instant while
        // a genuinely idle menu stops holding ~50-100 MB.
        Timer {
            id: _idleUnload
            interval: 45000
            onTriggered: if (panel.state === "hidden") {
                panel._loadedDeferred = false
                panel._loaded = false
                panel._recentLoaded = false
            }
        }

        Timer {
            id: _placementSettle
            interval: Motion.popSettle
            repeat: false
            onTriggered: panel._placementSettled = true
        }

        // ── Left rail ──────────────────────────────────────────────────────────
        Item {
            id: rail
            x: 0; y: 0
            width: panel.railW
            height: panel.height
            clip: false  // allow hover pills to overflow into content area
            z: 6         // render above the content pane so pills aren't hidden

            // Expand/collapse in step with the panel's width clock.
            Behavior on width {
                enabled: panel.state === "visible" && !ShellSettings.reduceMotion
                NumberAnimation { duration: panel.heightAnimDuration; easing.type: Easing.OutCubic }
            }

            // Background + divider live in a clipped sub-layer so the rounded
            // background (drawn wider than the rail) can't bleed past the rail's
            // right edge into the content pane. The icons/pills stay unclipped.
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

                // Divider between the icon strip and the categories — only while expanded.
                Rectangle {
                    x: panel.railCollapsedW
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    color: Theme.menuDivider
                    opacity: panel.activeTab === 1 ? 1 : 0
                    visible: opacity > 0.001
                    Behavior on opacity {
                        enabled: !ShellSettings.reduceMotion
                        NumberAnimation { duration: Motion.medium }
                    }
                }

                // Settings categories. Living in the clipped surface means the
                // growing rail reveals them left-to-right and they can't paint
                // past the rail edge mid-animation.
                Item {
                    x: panel.railCollapsedW
                    width: panel.navW
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    opacity: panel.activeTab === 1 ? 1 : 0
                    visible: opacity > 0.001
                    enabled: panel.activeTab === 1 && !panel.powerOpen
                    Behavior on opacity {
                        enabled: !ShellSettings.reduceMotion
                        NumberAnimation { duration: Motion.fast }
                    }

                    SettingsNav {
                        id: _settingsNav
                        anchors.fill: parent
                        powerOpen: panel.powerOpen
                    }
                }
            }

            // Top group: nav icons. Rail order is visual only; tab index stays
            // bound to the page (0 Home / 1 Settings / 2 Notifications) so loaders and
            // jump-to-tab keep working regardless of where an item sits here.
            Column {
                id: _railNav
                width: panel.railCollapsedW
                x: 0
                y: 10
                spacing: 6

                RailNavItem {
                    railW: panel.railCollapsedW
                    glyph: "󰋜"
                    label: "Home"
                    active: panel.activeTab === 0
                    onTapped: panel.switchTab(0)
                }

                RailNavItem {
                    id: _railRecent
                    railW: panel.railCollapsedW
                    glyph: "󰋚"
                    label: "Notifications"
                    active: panel.activeTab === 2
                    onTapped: panel.switchTab(2)

                    // Count badge rides the icon's top-right corner. Anchored to the
                    // item centre (where the icon sits) so it stays glued to the glyph
                    // regardless of rail width; a rail-coloured ring lifts it off the icon.
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
                    railW: panel.railCollapsedW
                    glyph: "󰒓"
                    label: "Settings"
                    active: panel.activeTab === 1
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

                Rectangle {
                    id: _railDivider
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 18
                    height: 1
                    color: Theme.menuDivider
                }

                RailNavItem {
                    anchors.top: _railDivider.bottom
                    anchors.topMargin: 10
                    anchors.horizontalCenter: parent.horizontalCenter
                    railW: panel.railCollapsedW
                    glyph: "󰐥"
                    label: "Power"
                    accentColor: Theme.error
                    active: panel.powerOpen
                    onTapped: panel.powerOpen = !panel.powerOpen
                }
            }
        }

        // ── Content pane (right of rail) ───────────────────────────────────────
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

            // Slide in step with the expanding rail so the rail's right edge and
            // the content's left edge stay flush.
            Behavior on x {
                enabled: panel.state === "visible" && !ShellSettings.reduceMotion
                NumberAnimation { duration: panel.heightAnimDuration; easing.type: Easing.OutCubic }
            }

            // snapped to 4 so a bottom-bar panel's y stays on the divider grid.
            // The rail-borne settings nav can be taller than the detail pane, so it
            // sets the floor too (the old single-page layout did this implicitly).
            readonly property int targetH: {
                const contentH = tabContent.y + tabContent.height + 12
                const navH = panel.activeTab === 1 ? _settingsNav.implicitHeight + 16 : 0
                return 4 * Math.ceil(Math.max(panel.minRailFitH, panel.idealMinH, contentH, navH) / 4)
            }
            height: panel.height

            TapHandler {
                id: _powerDismiss
                enabled: panel.powerOpen
                onTapped: {
                    const p = _powerDismiss.point.position
                    if (p.x < powerStrip.x || p.x > powerStrip.x + powerStrip.width ||
                        p.y < powerStrip.y || p.y > powerStrip.y + powerStrip.height) {
                        panel.powerOpen = false
                    }
                }
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
                // Notifications owns the only scroll surface on its tab; the
                // other pages continue to use this outer content scroller.
                interactive: !panel.powerOpen && panel.activeTab !== 2 && contentHeight > height + 1

                Item {
                    id: tabContent
                    x: panel.contentPad
                    y: 12   // 4px multiple, keeps card dividers on the grid
                    width: panel.innerW
                    height: panel.activeTab === 0 ? (homeLoader.item?.implicitHeight     ?? 0)
                          : panel.activeTab === 1 ? (settingsLoader.item?.implicitHeight ?? 0)
                          :                          (recentLoader.item?.implicitHeight  ?? 0)
                    clip: false

                    Loader {
                        id: homeLoader
                        width: parent.width
                        active: panel._loaded
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
                        // Preload so switching in doesn't async-reload mid-animation;
                        // unloads with the menu via _loadedDeferred.
                        active: panel._loadedDeferred
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
                        // Build the archive only after it is first opened. It then
                        // stays cached until the menu's normal idle unload.
                        active: panel._loadedDeferred && (panel._recentLoaded || panel.activeTab === 2)
                        asynchronous: true
                        sourceComponent: Component {
                            RecentPage {
                                width: parent.width
                                viewportHeight: Math.max(220,
                                    Math.min(panel.idealMinH, panel._availablePanelH) - tabContent.y - 16)
                                active: panel.activeTab === 2 && MenuState.open
                                powerOpen: panel.powerOpen
                            }
                        }
                    }
                }
            }

            // Overflow cue for the shared Home/Settings scroller — without it,
            // content taller than the clamped panel (media + sun arc) is clipped
            // with no hint there's more. Notifications owns its own fade.
            ListEdgeFade {
                anchors.fill: contentFlick
                list: contentFlick
                visible: panel.activeTab !== 2 && contentFlick.contentHeight > contentFlick.height + 1
                z: 4
            }

            // Dims the content so the power options read as a focused layer.
            Rectangle {
                anchors.fill: parent
                color: Theme.background
                opacity: panel.powerOpen ? 0.4 : 0.0
                visible: opacity > 0.001
                z: 4
                Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            }

            // ── Power menu ──────────────────────────────────────────────
            Item {
                id: powerStrip
                readonly property int _pad:  8
                readonly property int _gap:  8
                readonly property int _tileH: 56
                readonly property int _tileW: _tileH
                readonly property int _rowW: _tileW * 4 + _gap * 3
                // recessed a step below menuPane; theme-derived so matugen/black tones follow
                readonly property color _surface: Theme.mix(Theme.background, Theme.text, 0.010)
                readonly property color _surfaceLine: Theme.menuCardBorder
                width: _rowW + _pad * 2
                x: Math.round((parent.width - width) / 2)
                height: _pad * 2 + _tileH
                y: panel.powerOpen
                    ? contentPane.height - height - 12
                    : contentPane.height - height - 4
                opacity: panel.powerOpen ? 1.0 : 0.0
                visible: opacity > 0.001
                z: 5

                Behavior on y       { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    radius: 16
                    antialiasing: true
                    color: powerStrip._surface
                    border.width: 1
                    border.color: powerStrip._surfaceLine

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 1
                        height: Math.round(parent.height * 0.45)
                        radius: parent.radius - 1
                        antialiasing: true
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Theme.withAlpha(Theme.text, 0.028) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }

                    Row {
                        id: _powerRow
                        x: Math.round((parent.width - powerStrip._rowW) / 2)
                        y: powerStrip._pad
                        width: powerStrip._rowW
                        height: powerStrip._tileH
                        spacing: powerStrip._gap

                        PowerAction {
                            id: _powLock
                            width: powerStrip._tileW
                            height: powerStrip._tileH
                            label: "Lock"
                            enabled: win.commandAvailable(Settings.lockCommand)
                            glyph: "󰍁"
                            glyphOffsetY: 1
                            KeyNavigation.right: _powSusp
                            onTriggered: { MenuState.close(); Quickshell.execDetached(Settings.lockCommand) }
                        }

                        PowerAction {
                            id: _powSusp
                            width: powerStrip._tileW
                            height: powerStrip._tileH
                            label: "Sleep"
                            enabled: win.commandAvailable(Settings.suspendCommand)
                            glyph: "󰒲"
                            glyphOffsetX: -1
                            glyphOffsetY: 1
                            KeyNavigation.left: _powLock
                            KeyNavigation.right: _powReb
                            onTriggered: { MenuState.close(); win.runPower(Settings.suspendCommand, "Suspend failed") }
                        }

                        PowerAction {
                            id: _powReb
                            width: powerStrip._tileW
                            height: powerStrip._tileH
                            label: "Reboot"
                            enabled: win.commandAvailable(Settings.rebootCommand)
                            glyph: "󰑐"
                            glyphOffsetY: 1
                            confirm: true
                            KeyNavigation.left: _powSusp
                            KeyNavigation.right: _powOff
                            onArmedChanged: if (armed) _powOff.disarm()
                            onTriggered: { MenuState.close(); win.runPower(Settings.rebootCommand, "Reboot failed") }
                        }

                        PowerAction {
                            id: _powOff
                            width: powerStrip._tileW
                            height: powerStrip._tileH
                            label: "Power off"
                            enabled: win.commandAvailable(Settings.poweroffCommand)
                            glyph: "󰐥"
                            glyphOffsetY: 1
                            confirm: true
                            KeyNavigation.left: _powReb
                            onArmedChanged: if (armed) _powReb.disarm()
                            onTriggered: { MenuState.close(); win.runPower(Settings.poweroffCommand, "Shut down failed") }
                        }
                    }

                    Connections {
                        target: panel
                        function onPowerOpenChanged() {
                            if (panel.powerOpen) {
                                Qt.callLater(function() { powerStrip.forceActiveFocus() })
                            } else {
                                _powReb.disarm()
                                _powOff.disarm()
                            }
                        }
                    }
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
