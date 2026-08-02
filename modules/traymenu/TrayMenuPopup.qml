pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import "../../config"
import "../../services"
import "../common"

PanelWindow {
    id: win

    required property ShellScreen targetScreen

    readonly property string _output: Compositor.monitorName(win.screen)
    readonly property int menuWidth: 220
    readonly property real _cardRadius: Theme.radiusPanel
    property bool _ignoreOutsideTap: false

    property var _activeMenu: null
    property bool _rootOpenedSent: false

    function _menuRoot(): var {
        return win._activeMenu?.menu ?? win._activeMenu
    }
    function _emitMenuSignal(entry, signalName: string, fallbackName: string): bool {
        if (entry === null || entry === undefined) return false

        const fn = entry[signalName]
        if (typeof fn === "function") {
            fn()
            return true
        }

        const fallback = entry[fallbackName]
        if (typeof fallback === "function") {
            fallback()
            return true
        }

        console.warn("silere-shell: tray menu entry has no", signalName, "signal")
        return false
    }
    function _sendRootOpened(): void {
        if (_rootOpenedSent || !TrayMenuState.open) return
        if (_emitMenuSignal(_menuRoot(), "opened", "sendOpened"))
            _rootOpenedSent = true
    }
    function _sendRootClosed(): void {
        if (!_rootOpenedSent) return
        _emitMenuSignal(_menuRoot(), "closed", "sendClosed")
        _rootOpenedSent = false
    }
    function _setActiveMenu(handle): void {
        if (win._activeMenu === handle) {
            // a quick close/reopen reuses the handle: same object identity, but the previous close already cleared the sent flag
            if (handle !== null) win._sendRootOpened()
            return
        }
        win._sendRootClosed()
        win._activeMenu = handle
        win._sendRootOpened()
    }
    function _closeFlyouts(): void {
        const kids = win.contentItem.children
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i]
            if (k && k.opened === true) k.opened = false
        }
    }

    onVisibleChanged: if (!visible) win._setActiveMenu(null)
    // openAt() set the handle before this popup existed, so seed from the current state on creation
    Component.onCompleted: if (TrayMenuState.menuHandle !== null) win._setActiveMenu(TrayMenuState.menuHandle)
    Connections {
        target: TrayMenuState
        function onMenuHandleChanged() {
            if (TrayMenuState.menuHandle !== null) win._setActiveMenu(TrayMenuState.menuHandle)
        }
    }

    Connections {
        target: Compositor
        function onWorkspaceActivated(output) {
            if (output === win._output && TrayMenuState.open) TrayMenuState.close()
        }
    }

    screen:        targetScreen
    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "silere-traymenu"
    WlrLayershell.keyboardFocus: TrayMenuState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: TrayMenuState.open || card.opacity > 0.001

    anchors { top: true; left: true; right: true; bottom: true }

    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: TrayMenuState.open; onActivated: TrayMenuState.close() }

    Connections {
        target: ShellSettings
        function onBarPositionChanged() {
            if (!TrayMenuState.open) return
            win._ignoreOutsideTap = true
            _outsideTapGuard.restart()
        }
    }

    Connections {
        target: TrayMenuState
        function onOpenChanged() {
            if (!TrayMenuState.open) {
                _outsideTapGuard.stop()
                win._ignoreOutsideTap = false
                win._closeFlyouts()
                win._sendRootClosed()
            } else {
                win._sendRootOpened()
            }
        }
    }

    Timer {
        id: _outsideTapGuard
        interval: 250
        repeat: false
        onTriggered: win._ignoreOutsideTap = false
    }

    QsMenuOpener {
        id: _opener
        menu: win._menuRoot()
    }

    Item { id: _fillArea; anchors.fill: parent }
    mask: Region { item: TrayMenuState.open ? _fillArea : null }

    // submenu flyouts sit outside the card, as siblings of it under contentItem
    function _overFlyout(p: point): bool {
        const kids = win.contentItem.children
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i]
            if (!k || k.opened !== true || !k.visible) continue
            if (p.x >= k.x && p.x <= k.x + k.width &&
                p.y >= k.y && p.y <= k.y + k.height) return true
        }
        return false
    }

    TapHandler {
        id: _dismiss
        enabled: TrayMenuState.open && card.scaleAmt > 0.95
        // a TapHandler keeps a passive grab, so this fires for taps on rows too
        onTapped: {
            if (win._ignoreOutsideTap) return
            const p = _dismiss.point.position
            if (win._overFlyout(p)) return
            if (p.x < card.x || p.x > card.x + card.width ||
                p.y < card.y || p.y > card.y + card.height)
                TrayMenuState.close()
        }
    }

    Component {
        id: _rowDelegate

        Item {
            id: _entry
            required property var modelData
            // submenu rows only: lets Left-arrow close the right flyout, reparented to the window root and no longer bubbling keys up
            property Item ownerFlyout: null
            property Flickable ownerScroll: null

            readonly property bool sep:       modelData?.isSeparator ?? false
            readonly property bool on:        (modelData?.enabled ?? true) && !sep
            readonly property bool sub:       modelData?.hasChildren ?? false
            readonly property int  btnType:   modelData?.buttonType ?? 0
            readonly property bool checkable: btnType !== 0
            readonly property bool checked:   (modelData?.checkState ?? Qt.Unchecked) === Qt.Checked
            readonly property string iconSrc: modelData?.icon ?? ""
            readonly property bool isMenuRow: !sep

            width: win.menuWidth
            height: sep ? 11 : 32

            function _moveFocus(dir: int): void {
                const sibs = _entry.parent ? _entry.parent.children : []
                let i = -1
                for (let k = 0; k < sibs.length; k++) if (sibs[k] === _entry) { i = k; break }
                if (i < 0) return
                for (let k = i + dir; k >= 0 && k < sibs.length; k += dir) {
                    const c = sibs[k]
                    if (c && c.isMenuRow === true && c.on) { c.forceActiveFocus(); return }
                }
            }
            function _revealInOwner(): void {
                const scroll = _entry.ownerScroll
                if (!scroll || scroll.height <= 0) return
                const pos = _entry.mapToItem(scroll.contentItem, 0, 0)
                const top = pos.y
                const bottom = top + _entry.height
                const maxY = Math.max(0, scroll.contentHeight - scroll.height)
                if (top < scroll.contentY) scroll.contentY = Math.max(0, top)
                else if (bottom > scroll.contentY + scroll.height)
                    scroll.contentY = Math.min(maxY, bottom - scroll.height)
            }
            function _focusFirstSub(): void {
                const subs = _subCol.children
                for (let k = 0; k < subs.length; k++) {
                    const c = subs[k]
                    if (c && c.isMenuRow === true && c.on) { c.forceActiveFocus(); return }
                }
            }
            function closeFlyout(): void {
                if (_flyout.opened) _flyout.opened = false
            }
            function _openFlyout(): void {
                if (!_entry.sub || _flyout.opened) return
                // one visible child branch per menu branch; closing the siblings releases their nested models
                const sibs = _entry.parent ? _entry.parent.children : []
                for (let k = 0; k < sibs.length; k++) {
                    const c = sibs[k]
                    if (c !== _entry && c && typeof c.closeFlyout === "function")
                        c.closeFlyout()
                }
                _flyout.opened = true
            }
            function _toggleFlyout(): void {
                if (_flyout.opened) _entry.closeFlyout()
                else _entry._openFlyout()
            }
            function _activate(): void {
                if (!_entry.on) return
                if (_entry.sub) {
                    _entry._toggleFlyout()
                    if (_flyout.opened) Qt.callLater(_entry._focusFirstSub)
                } else {
                    win._emitMenuSignal(_entry.modelData, "triggered", "sendTriggered")
                    TrayMenuState.close()
                }
            }

            activeFocusOnTab: _entry.on
            Accessible.role: _entry.sep ? Accessible.Separator : Accessible.MenuItem
            Accessible.name: _entry.modelData?.text ?? ""
            Accessible.focusable: _entry.on
            Accessible.checkable: _entry.checkable
            Accessible.checked: _entry.checked
            Accessible.onPressAction: _entry._activate()
            onActiveFocusChanged: if (activeFocus) _entry._revealInOwner()
            Keys.onUpPressed:     e => { _entry._moveFocus(-1); e.accepted = true }
            Keys.onDownPressed:   e => { _entry._moveFocus(1);  e.accepted = true }
            Keys.onSpacePressed:  e => { if (!e.isAutoRepeat) _entry._activate(); e.accepted = true }
            Keys.onReturnPressed: e => { if (!e.isAutoRepeat) _entry._activate(); e.accepted = true }
            Keys.onEnterPressed:  e => { if (!e.isAutoRepeat) _entry._activate(); e.accepted = true }
            Keys.onRightPressed:  e => {
                if (_entry.sub) {
                    _entry._openFlyout()
                    Qt.callLater(_entry._focusFirstSub)
                    e.accepted = true
                } else {
                    e.accepted = false
                }
            }
            Keys.onLeftPressed: e => {
                if (_entry.sub && _flyout.opened) { _entry.closeFlyout(); e.accepted = true }
                else if (_entry.ownerFlyout) { _entry.ownerFlyout.opened = false; e.accepted = true }
                else e.accepted = false
            }

            QsMenuOpener {
                id: _subOpener
                menu: _entry.sub ? _entry.modelData : null
            }

            Hairline {
                visible: _entry.sep
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.menuDivider
            }

            Rectangle {
                visible: !_entry.sep
                anchors.fill: parent
                radius: Theme.radiusControl
                antialiasing: true
                color: (_entry.on && (_rowHover.hovered || _flyout.opened || _entry.activeFocus))
                    ? Theme.withAlpha(Theme.menuHover, 0.12) : "transparent"
                ColorFade on color {}
            }

            HoverHandler {
                id: _rowHover
                enabled: _entry.on
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: if (hovered && _entry.sub) _entry._openFlyout()
            }
            TapHandler {
                enabled: _entry.on && !_entry.sub
                onTapped: {
                    win._emitMenuSignal(_entry.modelData, "triggered", "sendTriggered")
                    TrayMenuState.close()
                }
            }
            TapHandler {
                enabled: _entry.on && _entry.sub
                onTapped: _entry._toggleFlyout()
            }

            Item {
                visible: !_entry.sep
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                opacity: _entry.on ? 1.0 : 0.4

                Item {
                    id: _mark
                    visible: _entry.checkable
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? Settings.fontSize : 0
                    height: Settings.fontSize

                    ShellText {
                        anchors.centerIn: parent
                        visible: _entry.btnType === 1 && _entry.checked
                        text: "󰄬"
                        color: Theme.accent
                        font.family: Settings.font; font.pixelSize: Settings.fontSize
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        visible: _entry.btnType === 2
                        width: 8; height: 8; radius: 4
                        antialiasing: true
                        color: _entry.checked ? Theme.accent : "transparent"
                        border.width: _entry.checked ? 0 : 1
                        border.color: Theme.withAlpha(Theme.subtext, 0.5)
                    }
                }

                IconImage {
                    id: _icon
                    visible: !_entry.checkable && _entry.iconSrc !== "" && status === Image.Ready
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: Settings.fontSize + 4
                    source: _entry.iconSrc
                    asynchronous: true
                }

                ShellText {
                    anchors.left: _entry.checkable ? _mark.right : _icon.visible ? _icon.right : parent.left
                    anchors.leftMargin: (_entry.checkable || _icon.visible) ? 8 : 0
                    anchors.right: _arrow.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: _entry.modelData?.text ?? ""
                    color: Theme.text
                    font.family: Settings.font; font.pixelSize: Settings.fontSize
                    elide: Text.ElideRight
                }

                ShellText {
                    id: _arrow
                    visible: _entry.sub
                    width: visible ? implicitWidth : 0
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰅂"
                    color: Theme.withAlpha(Theme.subtext, 0.7)
                    font.family: Settings.font; font.pixelSize: Settings.fontSize
                }
            }

            Rectangle {
                id: _flyout
                // reparented to the window root: inside the clipped row Flickable the submenu would be scissored away
                parent: win.contentItem
                property bool opened: false
                property real _shift: opened ? 0 : (_flip ? 5 : -5)

                visible: opened || opacity > 0.001
                enabled: opened
                opacity: opened ? 1 : 0
                z: 10
                readonly property real _w: win.menuWidth + pad * 2
                readonly property int  pad: 6
                // mapToItem() captures no dependencies, so a binding freezes at the pre-layout position; re-snap off everything that moves the row
                property point _origin: Qt.point(0, 0)
                readonly property real _originTick: card.x + card.y + _entry.y
                    + (_entry.ownerScroll ? _entry.ownerScroll.contentY : 0)
                    + (_entry.ownerFlyout ? _entry.ownerFlyout.x + _entry.ownerFlyout.y : 0)
                on_OriginTickChanged: if (_flyout.visible) _flyout._syncOrigin()
                function _syncOrigin(): void {
                    _flyout._origin = _entry.mapToItem(null, 0, 0)
                }
                function _holdsFocus(): bool {
                    let it = _flyout.Window.activeFocusItem
                    if (!it || it === win.contentItem) return true
                    for (; it; it = it.parent) if (it === _flyout) return true
                    return false
                }
                readonly property bool  _flip: _origin.x + _entry.width + 4 + _w > win.width
                readonly property real _panelH: Math.min(_subCol.implicitHeight + pad * 2, Math.max(48, win.height - 8))
                readonly property real _targetY: Math.max(4 - _origin.y, Math.min(-pad, win.height - 4 - _origin.y - _panelH))
                x: _origin.x + (_flip ? -(_w + 4) : (_entry.width + 4))
                y: _origin.y + _targetY
                width:  _w
                height: _panelH
                radius: Math.min(win._cardRadius, height / 2)
                antialiasing: true
                color: Theme.popup
                transform: Translate { x: _flyout._shift }

                OutlineBorder {
                    radius: _flyout.radius
                    outlineColor: Theme.outline
                }

                MotionBehavior on opacity {
                    NumberAnimation {
                        duration: _flyout.opened ? Motion.medium : Motion.fast
                        easing.type: _flyout.opened ? Easing.OutCubic : Easing.InCubic
                    }
                }
                MotionBehavior on _shift {
                    NumberAnimation {
                        duration: _flyout.opened ? Motion.medium : Motion.fast
                        easing.type: _flyout.opened ? Easing.OutQuart : Easing.InCubic
                    }
                }

                onOpenedChanged: {
                    if (!_entry.sub) return
                    if (opened) {
                        _flyout._syncOrigin()
                        win._emitMenuSignal(_entry.modelData, "opened", "sendOpened")
                    } else {
                        win._emitMenuSignal(_entry.modelData, "closed", "sendClosed")
                        // disabling the flyout strands focus at the window root; reclaiming it unconditionally would steal it on every hover-out
                        if (_flyout._holdsFocus()) _entry.forceActiveFocus()
                    }
                }
                Component.onDestruction: if (_entry.sub && _flyout.opened) win._emitMenuSignal(_entry.modelData, "closed", "sendClosed")

                HoverHandler { id: _flyHover }

                Timer {
                    id: _flyClose
                    interval: 180
                    onTriggered: if (!_rowHover.hovered && !_flyHover.hovered) _entry.closeFlyout()
                }
                Connections {
                    target: _flyHover
                    function onHoveredChanged() { if (!_flyHover.hovered) _flyClose.restart() }
                }
                Connections {
                    target: _rowHover
                    function onHoveredChanged() { if (!_rowHover.hovered && _flyout.opened) _flyClose.restart() }
                }

                Flickable {
                    id: _subScroll
                    x: _flyout.pad; y: _flyout.pad
                    width: win.menuWidth
                    height: Math.max(0, _flyout.height - _flyout.pad * 2)
                    contentWidth: width
                    contentHeight: _subCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    flickDeceleration: 1800
                    maximumFlickVelocity: 2200
                    clip: true
                    interactive: contentHeight > height

                    Column {
                        id: _subCol
                        width: win.menuWidth
                        spacing: 1
                        Repeater {
                            // hold the delegates through the close fade, then release the nested branch while the flyout is hidden
                            model: _flyout.opened || _flyout.opacity > 0.001
                                ? _subOpener.children : []
                            delegate: _rowDelegate
                            onItemAdded: (index, item) => {
                                item.ownerFlyout = _flyout
                                item.ownerScroll = _subScroll
                            }
                        }
                    }
                }

                ListEdgeLines {
                    anchors.fill: _subScroll
                    visible: _subScroll.interactive
                    list: _subScroll
                }
            }
        }
    }

    PopupShadow { card: card }

    FloatingPopupCard {
        id: card
        win: win
        open: TrayMenuState.open
        anchorX: TrayMenuState.anchorX
        barBottom: TrayMenuState.barBottom

        readonly property int pad: 6
        readonly property real _maxContentH: Math.max(48, win.height - _edgeY - pad * 2 - 8)

        width:  win.menuWidth + pad * 2
        height: Math.min(_col.implicitHeight, _maxContentH) + pad * 2
        radius: Math.min(win._cardRadius, height / 2)

        function _focusFirstRow(): void {
            const sibs = _col.children
            for (let k = 0; k < sibs.length; k++) {
                const c = sibs[k]
                if (c && c.isMenuRow === true && c.on) { c.forceActiveFocus(); return }
            }
        }
        Keys.onDownPressed: e => { card._focusFirstRow(); e.accepted = true }
        Keys.onUpPressed:   e => { card._focusFirstRow(); e.accepted = true }
        Connections {
            target: TrayMenuState
            function onOpenChanged() { if (TrayMenuState.open) card.forceActiveFocus() }
        }
        Component.onCompleted: if (TrayMenuState.open) card.forceActiveFocus()

        Flickable {
            id: _scroll
            x: card.pad; y: card.pad
            width: win.menuWidth
            height: Math.max(0, card.height - card.pad * 2)
            contentWidth: width
            contentHeight: _col.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 1800
            maximumFlickVelocity: 2200
            clip: true
            interactive: contentHeight > height

            Column {
                id: _col
                width: win.menuWidth
                spacing: 1

                Repeater {
                    model: _opener.children
                    delegate: _rowDelegate
                    onItemAdded: (index, item) => item.ownerScroll = _scroll
                }
            }
        }

        ListEdgeLines {
            anchors.fill: _scroll
            visible: _scroll.interactive
            list: _scroll
        }
    }
}
