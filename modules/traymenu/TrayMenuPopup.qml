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

    // holds the last handle through the close fade so rows don't collapse early
    property var _activeMenu: null
    property bool _rootOpenedSent: false

    function _menuRoot() {
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
        if (win._activeMenu === handle) return
        win._sendRootClosed()
        win._activeMenu = handle
        win._sendRootOpened()
    }

    onVisibleChanged: if (!visible) win._setActiveMenu(null)
    // lazy-loaded after openAt() already set the handle, so the change signal
    // fired before this popup existed; seed from the current state on creation
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

    TapHandler {
        id: _dismiss
        enabled: TrayMenuState.open && card.scaleAmt > 0.95
        onTapped: {
            if (win._ignoreOutsideTap) return
            const p = _dismiss.point.position
            if (p.x < card.x || p.x > card.x + card.width ||
                p.y < card.y || p.y > card.y + card.height)
                TrayMenuState.close()
        }
    }

    // recurses into itself for submenu flyouts, any nesting depth
    Component {
        id: _rowDelegate

        Item {
            id: _entry
            required property var modelData

            readonly property bool sep:       modelData?.isSeparator ?? false
            readonly property bool on:        (modelData?.enabled ?? true) && !sep
            readonly property bool sub:       modelData?.hasChildren ?? false
            readonly property int  btnType:   modelData?.buttonType ?? 0
            readonly property bool checkable: btnType !== 0
            readonly property bool checked:   (modelData?.checkState ?? Qt.Unchecked) === Qt.Checked
            readonly property string iconSrc: modelData?.icon ?? ""
            // duck-type marker so focus movement can skip the Repeater and separators
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
            function _focusFirstSub(): void {
                const subs = _subCol.children
                for (let k = 0; k < subs.length; k++) {
                    const c = subs[k]
                    if (c && c.isMenuRow === true && c.on) { c.forceActiveFocus(); return }
                }
            }
            function _activate(): void {
                if (!_entry.on) return
                if (_entry.sub) {
                    _flyout.visible = !_flyout.visible
                    if (_flyout.visible) Qt.callLater(_entry._focusFirstSub)
                } else {
                    win._emitMenuSignal(_entry.modelData, "triggered", "sendTriggered")
                    TrayMenuState.close()
                }
            }

            activeFocusOnTab: _entry.on
            Accessible.role: Accessible.MenuItem
            Accessible.name: _entry.modelData?.text ?? ""
            Keys.onUpPressed:     e => { _entry._moveFocus(-1); e.accepted = true }
            Keys.onDownPressed:   e => { _entry._moveFocus(1);  e.accepted = true }
            Keys.onSpacePressed:  e => { if (!e.isAutoRepeat) _entry._activate(); e.accepted = true }
            Keys.onReturnPressed: e => { if (!e.isAutoRepeat) _entry._activate(); e.accepted = true }
            Keys.onEnterPressed:  e => { if (!e.isAutoRepeat) _entry._activate(); e.accepted = true }
            Keys.onRightPressed:  e => {
                if (_entry.sub) {
                    if (!_flyout.visible) _flyout.visible = true
                    Qt.callLater(_entry._focusFirstSub)
                    e.accepted = true
                } else {
                    e.accepted = false
                }
            }
            Keys.onLeftPressed: e => {
                if (_entry.sub && _flyout.visible) { _flyout.visible = false; e.accepted = true }
                else e.accepted = false
            }

            QsMenuOpener {
                id: _subOpener
                menu: _entry.sub ? _entry.modelData : null
            }

            Rectangle {
                visible: _entry.sep
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Theme.menuDivider
            }

            Rectangle {
                visible: !_entry.sep
                anchors.fill: parent
                radius: Theme.radiusControl
                antialiasing: true
                color: (_entry.on && (_rowHover.hovered || _flyout.visible || _entry.activeFocus))
                    ? Theme.withAlpha(Theme.menuHover, 0.12) : "transparent"
                Behavior on color { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.fast } }
            }

            HoverHandler {
                id: _rowHover
                enabled: _entry.on
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: if (hovered && _entry.sub) _flyout.visible = true
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
                onTapped: _flyout.visible = !_flyout.visible
            }

            Item {
                visible: !_entry.sep
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                opacity: _entry.on ? 1.0 : 0.4

                // Check / radio marker, or icon, share the leading slot.
                Item {
                    id: _mark
                    visible: _entry.checkable
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? Settings.fontSize : 0
                    height: Settings.fontSize

                    Text {
                        anchors.centerIn: parent
                        visible: _entry.btnType === 1 && _entry.checked
                        text: "󰄬"
                        color: Theme.accent
                        font.family: Settings.font; font.pixelSize: Settings.fontSize
                        renderType: Text.NativeRendering
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

                Text {
                    anchors.left: _entry.checkable ? _mark.right : _icon.visible ? _icon.right : parent.left
                    anchors.leftMargin: (_entry.checkable || _icon.visible) ? 8 : 0
                    anchors.right: _arrow.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: _entry.modelData?.text ?? ""
                    textFormat: Text.PlainText
                    color: Theme.text
                    font.family: Settings.font; font.pixelSize: Settings.fontSize
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                }

                Text {
                    id: _arrow
                    visible: _entry.sub
                    width: visible ? implicitWidth : 0
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰅂"
                    color: Theme.withAlpha(Theme.subtext, 0.7)
                    font.family: Settings.font; font.pixelSize: Settings.fontSize
                    renderType: Text.NativeRendering
                }
            }

            // flips to the left edge when it would run off-screen
            Rectangle {
                id: _flyout
                visible: false
                z: 10
                readonly property real _w: win.menuWidth + pad * 2
                readonly property int  pad: 6
                readonly property point _origin: _entry.mapToItem(null, 0, 0)
                readonly property bool  _flip: _origin.x + _entry.width + 4 + _w > win.width
                readonly property real _panelH: Math.min(_subCol.implicitHeight + pad * 2, Math.max(48, win.height - 8))
                readonly property real _targetY: Math.max(4 - _origin.y, Math.min(-pad, win.height - 4 - _origin.y - _panelH))
                x: _flip ? -(_w + 4) : (_entry.width + 4)
                y: _targetY
                width:  _w
                height: _panelH
                radius: Math.min(win._cardRadius, height / 2)
                antialiasing: true
                color: Theme.popup
                border.width: 1
                border.color: Theme.outline

                // apps populate submenu children lazily, only after the opened signal.
                onVisibleChanged: {
                    if (!_entry.sub) return
                    if (visible) win._emitMenuSignal(_entry.modelData, "opened", "sendOpened")
                    else win._emitMenuSignal(_entry.modelData, "closed", "sendClosed")
                }
                Component.onDestruction: if (_entry.sub && _flyout.visible) win._emitMenuSignal(_entry.modelData, "closed", "sendClosed")

                HoverHandler { id: _flyHover }

                Timer {
                    id: _flyClose
                    interval: 180
                    onTriggered: if (!_rowHover.hovered && !_flyHover.hovered) _flyout.visible = false
                }
                Connections {
                    target: _flyHover
                    function onHoveredChanged() { if (!_flyHover.hovered) _flyClose.restart() }
                }
                Connections {
                    target: _rowHover
                    function onHoveredChanged() { if (!_rowHover.hovered && _flyout.visible) _flyClose.restart() }
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
                            model: _subOpener.children
                            delegate: _rowDelegate
                        }
                    }
                }

                ListEdgeFade {
                    anchors.fill: _subScroll
                    visible: _subScroll.interactive
                    list: _subScroll
                }
            }
        }
    }

    // Floating drop shadow, same elevation cue as the bar/OSD/notification cards.
    Loader {
        active: TrayMenuState.open && ShellSettings.barFloating && ShellSettings.barShadow
        anchors.fill: card
        opacity: card.opacity
        z: -1
        sourceComponent: FloatingShadow {
            radius: card.radius
            atBottom: card.barBottom
        }
    }

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

        // card holds focus on open (paints nothing) so a mouse-open shows no highlight; Down/Tab enters the first usable row
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
                }
            }
        }

        ListEdgeFade {
            anchors.fill: _scroll
            visible: _scroll.interactive
            list: _scroll
        }
    }
}
