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
    readonly property int menuWidth: Metrics.snap4Up(220
        + Math.max(0, Settings.capHeight - Settings.capHeightBase) * 6)

    property var _activeMenu: null
    function _trigger(entry): void {
        if (entry === null || entry === undefined) return
        try {
            if (typeof entry.triggered === "function") entry.triggered()
            else if (typeof entry.sendTriggered === "function") entry.sendTriggered()
            else console.warn("silere-shell: tray menu entry has no triggered signal")
        } catch (error) {
            console.warn("silere-shell: tray menu signal failed:", String(error))
        }
    }
    function _activateEntry(entry): void {
        if (!TrayMenuState.open || !entry || !entry.on) return
        if (entry.sub) {
            entry._openFlyout()
            return
        }
        win._trigger(entry.modelData)
        TrayMenuState.close()
    }
    function _setActiveMenu(handle): void {
        if (win._activeMenu === handle) return
        win._closeFlyouts()
        _scroll.contentY = 0
        win._activeMenu = handle
    }
    function _closeFlyouts(): void {
        const kids = win.contentItem.children
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i]
            if (k && k.opened === true) k.opened = false
        }
    }
    function _closeFlyoutBranch(flyout): void {
        const kids = win.contentItem.children
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i]
            if (k && k.parentFlyout === flyout && k.opened === true)
                win._closeFlyoutBranch(k)
        }
        flyout.opened = false
    }

    onVisibleChanged: if (!visible) win._setActiveMenu(null)
    // the handle is set before this popup exists, so seed from the current state on creation
    Component.onCompleted: if (TrayMenuState.menuHandle !== null) win._setActiveMenu(TrayMenuState.menuHandle)
    Connections {
        target: TrayMenuState
        function onMenuHandleChanged() {
            if (TrayMenuState.menuHandle !== null) win._setActiveMenu(TrayMenuState.menuHandle)
        }
        function onOpenChanged() {
            if (TrayMenuState.open) win._setActiveMenu(TrayMenuState.menuHandle)
        }
    }

    Connections {
        target: Compositor
        function onWorkspaceActivated(output) {
            if (output === win._output && TrayMenuState.open) TrayMenuState.close()
        }
    }
    Connections {
        target: ShellSettings
        function onBarPositionChanged() { if (TrayMenuState.open) TrayMenuState.close() }
    }

    screen:        targetScreen
    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "silere-traymenu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: TrayMenuState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: TrayMenuState.open || card.opacity > 0.001

    anchors { top: true; left: true; right: true; bottom: true }

    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: TrayMenuState.open; onActivated: TrayMenuState.close() }

    OutsideTapGuard {
        id: _tapGuard
        open: TrayMenuState.open
    }

    Connections {
        target: TrayMenuState
        function onOpenChanged() {
            if (!TrayMenuState.open) {
                win._closeFlyouts()
            }
        }
    }

    QsMenuOpener {
        id: _opener
        menu: win._activeMenu
    }

    Item { id: _fillArea; anchors.fill: parent }
    mask: Region { item: TrayMenuState.open ? _fillArea : null }
    BackgroundEffect.blurRegion: Region { item: card.blurItem; radius: Math.round(card.radius) }

    // submenu flyouts sit outside the card, as siblings of it under contentItem
    function _overFlyout(p: point): bool {
        const kids = win.contentItem.children
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i]
            if (!k || k.opened !== true || !k.visible) continue
            const local = k.mapFromItem(win.contentItem, p.x, p.y)
            if (local.x >= 0 && local.x <= k.width &&
                local.y >= 0 && local.y <= k.height) return true
        }
        return false
    }

    TapHandler {
        id: _dismiss
        enabled: TrayMenuState.open
        // a TapHandler keeps a passive grab, so this fires for taps on rows too
        onTapped: {
            if (_tapGuard.ignoring) return
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
            // flyouts live at the window root so the scroll clip cannot cut them off
            property Item ownerFlyout: null
            property Flickable ownerScroll: null
            property int menuDepth: 0

            readonly property bool sep:       modelData?.isSeparator ?? false
            readonly property bool hasChildMenu: modelData?.hasChildren ?? false
            readonly property bool sub:       hasChildMenu
                && menuDepth < 8
            // a branch past the depth cap renders nothing, so its row must never send a leaf click
            readonly property bool on:        (modelData?.enabled ?? true) && !sep
                && (!hasChildMenu || sub)
            readonly property int  btnType:   modelData?.buttonType ?? 0
            readonly property bool checkable: btnType !== 0
            readonly property bool checked:   (modelData?.checkState ?? Qt.Unchecked) === Qt.Checked
            readonly property string label: SafeText.singleLineText(modelData?.text, 256)
            readonly property string iconSrc: IconResolver.trayIconSource(modelData?.icon)

            width: win.menuWidth
            height: sep ? 11 : Metrics.rowHeightFor(32)

            function closeFlyout(): void {
                if (_flyout.opened) win._closeFlyoutBranch(_flyout)
            }
            function _openFlyout(): void {
                if (!_entry.on || !_entry.sub || _flyout.opened) return
                // one visible child branch per menu branch; closing the siblings releases their nested models
                const sibs = _entry.parent ? _entry.parent.children : []
                for (let k = 0; k < sibs.length; k++) {
                    const c = sibs[k]
                    if (c !== _entry && c && typeof c.closeFlyout === "function")
                        c.closeFlyout()
                }
                _flyout.opened = true
            }
            QsMenuOpener {
                id: _subOpener
                menu: _entry.sub && (_flyout.opened || _flyout.opacity > 0.001)
                    ? _entry.modelData : null
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
                color: !_entry.on ? "transparent"
                    : _entryTap.pressed ? Theme.withAlpha(Theme.menuHover, 0.13)
                    : (_rowHover.hovered || _flyout.opened)
                        ? Theme.withAlpha(Theme.menuHover, 0.08) : "transparent"
                ColorFade on color {}
            }

            HoverHandler {
                id: _rowHover
                enabled: _entry.on
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: if (hovered && _entry.sub) _entry._openFlyout()
            }
            Accessible.role: _entry.sep ? Accessible.Separator
                : _entry.checkable ? Accessible.CheckBox : Accessible.MenuItem
            Accessible.name: _entry.label
            Accessible.checked: _entry.checked
            Accessible.focusable: _entry.on
            Accessible.onPressAction: win._activateEntry(_entry)

            TapHandler {
                id: _entryTap
                enabled: _entry.on
                // hover may already have opened it, so a tap never toggles it shut
                onTapped: win._activateEntry(_entry)
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
                        font.pixelSize: Settings.fontSize
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        visible: _entry.btnType === 2
                        width: 8; height: 8; radius: 4
                        antialiasing: true
                        color: _entry.checked ? Theme.accent : "transparent"
                        OutlineBorder {
                            radius: parent.radius
                            outlineColor: _entry.checked
                                ? "transparent" : Theme.withAlpha(Theme.subtext, 0.5)
                        }
                    }
                }

                IconImage {
                    id: _icon
                    visible: !_entry.checkable && _entry.iconSrc !== "" && status === Image.Ready
                    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                    transform: PixelSnap { item: _icon; dpr: _icon._dpr }
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
                    text: _entry.label
                    color: Theme.text
                    font.pixelSize: Settings.fontSize
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
                    font.pixelSize: Settings.fontSize
                }
            }

            Rectangle {
                id: _flyout
                // reparented to the window root: inside the clipped row Flickable the submenu would be scissored away
                parent: win.contentItem
                property bool opened: false
                readonly property Item parentFlyout: _entry.ownerFlyout
                readonly property bool hovered: _flyHover.hovered
                readonly property real _closedShift: _flip ? 5 : -5
                property real _shift: opened ? 0 : _closedShift

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
                readonly property bool  _flip: _origin.x + _entry.width + 4 + _w > card.winW - 4
                readonly property real _panelH: Metrics.snap4Up(
                    Math.min(_subCol.implicitHeight + pad * 2, Math.max(48, card.winH - 8)))
                readonly property real _targetY: Math.max(4 - _origin.y, Math.min(-pad, card.winH - 4 - _origin.y - _panelH))
                x: Metrics.flyoutX(_origin.x, _entry.width, _w, card.winW)
                y: _origin.y + _targetY
                width:  _w
                height: _panelH
                radius: Math.min(Theme.surfaceRadius, height / 2)
                antialiasing: true
                color: Theme.popup
                transform: Translate { x: _flyout._shift }

                OutlineBorder {
                    radius: _flyout.radius
                    outlineColor: Theme.outline
                }

                Disclosure on opacity { enterEasing: Easing.OutCubic }
                Disclosure on _shift { closedValue: _flyout._closedShift }

                // _subOpener's reference already tells the app when this submenu opens and closes
                onOpenedChanged: if (_entry.sub && opened) _flyout._syncOrigin()

                HoverHandler { id: _flyHover }

                Timer {
                    id: _flyClose
                    interval: 180
                    running: _flyout.opened && !_rowHover.hovered
                        && !TrayMenuState.branchHovered(_flyout, win.contentItem.children)
                    onTriggered: _entry.closeFlyout()
                }

                ShellFlickable {
                    id: _subScroll
                    x: _flyout.pad; y: _flyout.pad
                    width: win.menuWidth
                    height: Math.max(0, _flyout.height - _flyout.pad * 2)
                    contentWidth: width
                    contentHeight: _subCol.implicitHeight
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
                                item.menuDepth = _entry.menuDepth + 1
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
        anchorX: TrayMenuState.effectiveAnchorX
        barBottom: TrayMenuState.barBottom

        readonly property int pad: 6
        readonly property real _maxContentH: Math.max(48, winH - _edgeY - pad * 2 - 8)

        width:  win.menuWidth + pad * 2
        height: Metrics.snap4Up(Math.min(_col.implicitHeight, _maxContentH) + pad * 2)
        // a different tray icon's menu can swap in at a different row count while the card stays open
        MotionBehavior on height {
            gate: card.geometryMotionReady
            NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
        }

        Connections {
            target: TrayMenuState
            function onOpenChanged() { if (TrayMenuState.open) card.forceActiveFocus() }
        }
        Component.onCompleted: if (TrayMenuState.open) card.forceActiveFocus()

        ShellFlickable {
            id: _scroll
            x: card.pad; y: card.pad
            width: win.menuWidth
            height: Math.max(0, card.height - card.pad * 2)
            contentWidth: width
            contentHeight: _col.implicitHeight
            interactive: contentHeight > height

            Column {
                id: _col
                width: win.menuWidth
                spacing: 1

                Repeater {
                    id: _topRows
                    model: _opener.children
                    delegate: _rowDelegate
                    onItemAdded: (index, item) => item.ownerScroll = _scroll
                }

                Item {
                    visible: _hideRow.visible && _topRows.count > 0
                    width: win.menuWidth
                    height: 11

                    Hairline {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.menuDivider
                    }
                }

                Item {
                    id: _hideRow
                    readonly property string _liveId: String(TrayMenuState.sourceItem?.id ?? "")
                    // latched: the source clears on close, and the row must not drop out during the fade
                    property string trayId: ""
                    on_LiveIdChanged: if (TrayMenuState.sourceItem !== null) trayId = _liveId
                    Component.onCompleted: if (_liveId.length > 0) trayId = _liveId
                    Connections {
                        target: TrayMenuState
                        function onOpenChanged() {
                            if (TrayMenuState.open) _hideRow.trayId = _hideRow._liveId
                        }
                    }
                    visible: trayId.length > 0
                    width: win.menuWidth
                    height: Metrics.rowHeightFor(32)
                    enabled: TrayMenuState.open

                    function hide(): void {
                        if (!_hideRow.enabled || _hideRow._liveId.length === 0
                                || _hideRow.trayId !== _hideRow._liveId) return
                        const id = _hideRow.trayId
                        TrayMenuState.close()
                        ShellSettings.setTrayItemHidden(id, true)
                    }

                    Accessible.role: Accessible.MenuItem
                    Accessible.name: "Hide from bar"
                    Accessible.focusable: true
                    Accessible.onPressAction: _hideRow.hide()

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusControl
                        antialiasing: true
                        color: _hideTap.pressed ? Theme.withAlpha(Theme.menuHover, 0.13)
                            : _hideHover.hovered ? Theme.withAlpha(Theme.menuHover, 0.08) : "transparent"
                        ColorFade on color {}
                    }

                    HoverHandler { id: _hideHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: _hideTap; onTapped: _hideRow.hide() }

                    ShellText {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Hide from bar"
                        color: _hideHover.hovered ? Theme.text : Theme.withAlpha(Theme.subtext, 0.86)
                        font.pixelSize: Settings.fontSize
                        elide: Text.ElideRight
                        ColorFade on color {}
                    }
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
