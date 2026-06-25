pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland._WlrLayerShell
import Quickshell.Hyprland
import "../../config"
import "../../services"

// Tray context menu rendered in QML so it speaks Theme instead of the native platform menu.
PanelWindow {
    id: win

    required property ShellScreen targetScreen

    readonly property HyprlandMonitor _monitor: Hyprland.monitorFor(win.screen)
    readonly property int menuWidth: 220
    readonly property real _cardRadius: Theme.radiusPanel
    property bool _ignoreOutsideTap: false

    // holds the last handle through the close fade so rows don't collapse early
    property var _activeMenu: null
    onVisibleChanged: if (!visible) win._activeMenu = null
    // lazy-loaded after openAt() already set the handle, so the change signal
    // fired before this popup existed; seed from the current state on creation
    Component.onCompleted: if (TrayMenuState.menuHandle !== null) win._activeMenu = TrayMenuState.menuHandle
    Connections {
        target: TrayMenuState
        function onMenuHandleChanged() {
            if (TrayMenuState.menuHandle !== null) win._activeMenu = TrayMenuState.menuHandle
        }
    }

    Connections {
        target: win._monitor
        function onActiveWorkspaceChanged() { if (TrayMenuState.open) TrayMenuState.close() }
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
                _placementSettle.stop()
                card._placementSettled = false
                _outsideTapGuard.stop()
                win._ignoreOutsideTap = false
            } else {
                card._placementSettled = false
                card._place()
                _placementSettle.restart()
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
        menu: win._activeMenu
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

            width: win.menuWidth
            height: sep ? 11 : 32

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
                color: (_entry.on && (_rowHover.hovered || _flyout.visible))
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
                    _entry.modelData.sendTriggered()
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
                x: _flip ? -(_w + 4) : (_entry.width + 4)
                y: -pad
                width:  _w
                height: _subCol.implicitHeight + pad * 2
                radius: Math.min(win._cardRadius, height / 2)
                antialiasing: true
                color: Theme.popup
                border.width: 1
                border.color: Theme.outline

                // apps populate submenu children lazily, only after sendOpened()
                onVisibleChanged: {
                    if (!_entry.sub) return
                    if (visible) _entry.modelData.sendOpened()
                    else _entry.modelData.sendClosed()
                }
                Component.onDestruction: if (_entry.sub && _flyout.visible) _entry.modelData?.sendClosed()

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

                Column {
                    id: _subCol
                    x: _flyout.pad; y: _flyout.pad
                    width: win.menuWidth
                    spacing: 1
                    Repeater {
                        model: _subOpener.children
                        delegate: _rowDelegate
                    }
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
        sourceComponent: Item {
            anchors.fill: parent
            readonly property real strength: ShellSettings.barShadowStrength
            RectangularShadow {
                anchors.fill: parent
                radius: card.radius
                blur: 14
                offset: Qt.vector2d(0, card._barBottom ? -2 : 2)
                color: Qt.rgba(0, 0, 0, Math.min(0.28, 0.13 * parent.strength))
            }
            RectangularShadow {
                anchors.fill: parent
                radius: card.radius
                blur: 7
                offset: Qt.vector2d(0, card._barBottom ? -5 : 5)
                color: Qt.rgba(0, 0, 0, Math.min(0.44, 0.26 * parent.strength))
            }
        }
    }

    Rectangle {
        id: card

        readonly property int pad: 6

        readonly property real _originX: Math.max(0, Math.min(width, TrayMenuState.anchorX - x))
        readonly property bool _barBottom: TrayMenuState.barBottom

        readonly property int  _barInset: ShellSettings.barFloating ? 4 : 0
        readonly property int  _edgeY: _barInset + ShellSettings.barHeight + 8
        readonly property real _minX: radius + 4
        readonly property real _maxX: Math.max(_minX, win.width - width - _minX)

        function _clampedPanelX(px: real): real {
            return Math.max(_minX, Math.min(px, _maxX))
        }
        function _targetX(): real {
            const t = Math.max(0, Math.min(win.width, TrayMenuState.anchorX))
            return Math.round(_clampedPanelX(t - width * t / Math.max(1, win.width)))
        }
        function _place(): void {
            x = _targetX()
        }
        function _reclamp(): void {
            const nx = Math.round(_clampedPanelX(x))
            if (Math.abs(nx - x) > 0.5) x = nx
        }

        on_MinXChanged: _reclamp()
        on_MaxXChanged: _reclamp()

        y: Math.round((_barBottom ? (win.height - _edgeY - height) : _edgeY) + edgeOffset)
        width:  win.menuWidth + pad * 2
        height: _col.implicitHeight + pad * 2
        radius: Math.min(win._cardRadius, height / 2)
        antialiasing: true
        color: Theme.popup
        border.width: 1
        border.color: Theme.outline

        property real scaleAmt: 0.985
        property real edgeOffset: _closedOffset
        property bool _placementSettled: false
        readonly property real _closedOffset: _barBottom ? 8 : -8
        transform: Scale { origin.x: card._originX; origin.y: card._barBottom ? card.height : 0; xScale: card.scaleAmt; yScale: card.scaleAmt }
        state: TrayMenuState.open ? "visible" : "hidden"
        layer.enabled: !ShellSettings.reduceMotion && opacity > 0.001 && scaleAmt < 0.999

        Behavior on x {
            enabled: card.state === "visible" && !ShellSettings.reduceMotion && card._placementSettled
            NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
        }

        Connections {
            target: TrayMenuState
            function onAnchorXChanged() { card._place() }
        }
        Connections {
            target: win
            function onWidthChanged() {
                if (!TrayMenuState.open) return
                const nx = card._targetX()
                if (Math.abs(nx - card.x) > 0.5) card._place()
            }
        }
        Component.onCompleted: _place()

        Timer {
            id: _placementSettle
            interval: Math.max(40, Motion.ms(180))
            repeat: false
            onTriggered: card._placementSettled = true
        }

        states: [
            State { name: "hidden";  PropertyChanges { target: card; scaleAmt: 0.985; edgeOffset: card._closedOffset; opacity: 0 } },
            State { name: "visible"; PropertyChanges { target: card; scaleAmt: 1.0;  edgeOffset: 0; opacity: 1 } }
        ]
        transitions: [
            Transition {
                from: "*"; to: "visible"
                ParallelAnimation {
                    NumberAnimation { target: card; property: "scaleAmt";   to: 1.0; duration: Motion.ms(160); easing.type: Easing.OutCubic }
                    NumberAnimation { target: card; property: "edgeOffset"; to: 0;   duration: Motion.ms(160); easing.type: Easing.OutQuart }
                    NumberAnimation { target: card; property: "opacity";    to: 1.0; duration: Motion.ms(100); easing.type: Easing.OutCubic }
                }
            },
            Transition {
                from: "visible"; to: "hidden"
                ParallelAnimation {
                    NumberAnimation { target: card; property: "scaleAmt";   to: 0.985;              duration: Motion.ms(105); easing.type: Easing.InCubic }
                    NumberAnimation { target: card; property: "edgeOffset"; to: card._closedOffset; duration: Motion.ms(105); easing.type: Easing.InCubic }
                    NumberAnimation { target: card; property: "opacity";    to: 0.0;                duration: Motion.ms(90);  easing.type: Easing.InCubic }
                }
            }
        ]

        Column {
            id: _col
            x: card.pad; y: card.pad
            width: win.menuWidth
            spacing: 1

            Repeater {
                model: _opener.children
                delegate: _rowDelegate
            }
        }
    }
}
