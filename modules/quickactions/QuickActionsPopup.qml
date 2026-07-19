pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../services"
import "../common"

// quick actions under the workspace diamond (right-click): one-tap toggles that don't warrant the full menu.
// rows stay open after a flip so the state reads; Escape/outside tap closes. render-only while open.
PanelWindow {
    id: win

    required property ShellScreen targetScreen

    readonly property string _output: Compositor.monitorName(win.screen)

    screen:        targetScreen
    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "silere-quickactions"
    WlrLayershell.keyboardFocus: QuickActionsState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: QuickActionsState.open || card.opacity > 0.001

    anchors { top: true; left: true; right: true; bottom: true }

    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: QuickActionsState.open; onActivated: QuickActionsState.close() }

    Connections {
        target: Compositor
        function onWorkspaceActivated(output) {
            if (output === win._output && QuickActionsState.open) QuickActionsState.close()
        }
    }
    Connections {
        target: ShellSettings
        function onBarPositionChanged() { if (QuickActionsState.open) QuickActionsState.close() }
    }
    // both anchor under the diamond — the full menu supersedes
    Connections {
        target: MenuState
        function onOpenChanged() { if (MenuState.open && QuickActionsState.open) QuickActionsState.close() }
    }
    // power profile is deliberately read-on-open, no monitor process
    Connections {
        target: QuickActionsState
        function onOpenChanged() {
            if (QuickActionsState.open) {
                PowerProfiles.refresh()
                card.forceActiveFocus()
            }
        }
    }

    Item { id: _fillArea; anchors.fill: parent }
    mask: Region { item: QuickActionsState.open ? _fillArea : null }

    TapHandler {
        id: _dismiss
        enabled: QuickActionsState.open && card.scaleAmt > 0.95
        onTapped: {
            const p = _dismiss.point.position
            if (p.x < card.x || p.x > card.x + card.width ||
                p.y < card.y || p.y > card.y + card.height)
                QuickActionsState.close()
        }
    }

    // Floating drop shadow, same elevation cue as the bar/calendar/tray menu.
    Loader {
        active: QuickActionsState.open && ShellSettings.barFloating && ShellSettings.barShadow
        anchors.fill: card
        opacity: card.opacity
        z: -1
        sourceComponent: FloatingShadow {
            radius: card.radius
            atBottom: card.barBottom
        }
    }

    component QuickActionRow: Item {
        id: _row

        property string glyph: ""
        property string label: ""
        property string stateText: ""
        property bool   active: false
        property bool   checkable: true
        readonly property bool isMenuRow: true
        readonly property bool on: true
        property bool _keyboardPressed: false
        readonly property bool _pressed: _rowTap.pressed || _keyboardPressed

        signal triggered()

        function _menuRows(): var {
            const sibs = _row.parent ? _row.parent.children : []
            const rows = []
            for (let k = 0; k < sibs.length; k++) {
                const c = sibs[k]
                if (c && c.isMenuRow === true && c.visible) rows.push(c)
            }
            return rows
        }
        function _moveFocus(dir: int): void {
            const rows = _menuRows()
            const i = rows.indexOf(_row)
            if (i >= 0 && rows.length > 0)
                rows[(i + dir + rows.length) % rows.length].forceActiveFocus()
        }
        function _focusEdge(last: bool): void {
            const rows = _menuRows()
            if (rows.length > 0) rows[last ? rows.length - 1 : 0].forceActiveFocus()
        }
        function _activate(): void {
            if (_row.visible) _row.triggered()
        }

        width: parent ? parent.width : 0
        height: 38

        activeFocusOnTab: visible
        Accessible.role: _row.checkable ? Accessible.CheckBox : Accessible.Button
        Accessible.name: _row.label
        Accessible.description: _row.stateText
        Accessible.checked: _row.checkable && _row.active
        Accessible.focusable: _row.visible
        Accessible.onPressAction: _row._activate()
        onActiveFocusChanged: if (!activeFocus) _keyboardPressed = false
        Keys.onUpPressed:     e => { _row._moveFocus(-1); e.accepted = true }
        Keys.onDownPressed:   e => { _row._moveFocus(1);  e.accepted = true }
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Home) {
                _row._focusEdge(false)
                e.accepted = true
                return
            }
            if (e.key === Qt.Key_End) {
                _row._focusEdge(true)
                e.accepted = true
                return
            }
            if (e.isAutoRepeat || (e.key !== Qt.Key_Space
                    && e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter)) return
            _row._keyboardPressed = true
            e.accepted = true
        }
        Keys.onReleased: e => {
            if (!_row._keyboardPressed || (e.key !== Qt.Key_Space
                    && e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter)) return
            _row._keyboardPressed = false
            e.accepted = true
            _row._activate()
        }

        HoverHandler { id: _rowHover; cursorShape: Qt.PointingHandCursor }
        TapHandler   { id: _rowTap; onTapped: _row._activate() }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusControl
            antialiasing: true
            color: _row._pressed
                ? Theme.withAlpha(Theme.accent, 0.14)
                : (_rowHover.hovered || _row.activeFocus)
                    ? Theme.withAlpha(Theme.menuHover, 0.12) : "transparent"
            Behavior on color { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.fast } }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 3
            anchors.verticalCenter: parent.verticalCenter
            width: 2; height: 14; radius: 1
            antialiasing: true
            color: Theme.accent
            opacity: _row.active ? 0.82 : 0.0
            scale: _row.active ? 1.0 : 0.5
            Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast } }
            Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        }

        Text {
            id: _glyph
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            horizontalAlignment: Text.AlignHCenter
            text: _row.glyph
            color: _row.active ? Theme.withAlpha(Theme.accent, 0.95) : Theme.withAlpha(Theme.subtext, 0.85)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize + 1
            renderType: Text.NativeRendering
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        Text {
            anchors.left: _glyph.right
            anchors.leftMargin: 8
            anchors.right: _state.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: _row.label
            textFormat: Text.PlainText
            color: Theme.text
            font.family: Settings.font
            font.pixelSize: Settings.fontSize
            renderType: Text.NativeRendering
            elide: Text.ElideRight
        }

        Rectangle {
            id: _state
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(30, _stateLabel.implicitWidth + 12)
            height: 20
            radius: 7
            antialiasing: true
            color: _row.active
                ? Theme.withAlpha(Theme.accent, 0.13) : "transparent"
            border.width: _row.active ? 1 : 0
            border.color: Theme.withAlpha(Theme.accent, 0.22)
            Behavior on color { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.fast } }

            Text {
                id: _stateLabel
                anchors.centerIn: parent
                text: _row.stateText
                color: _row.active ? Theme.mix(Theme.accent, Theme.text, 0.18) : Theme.withAlpha(Theme.subtext, 0.62)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 2
                font.weight: Font.Medium
                renderType: Text.NativeRendering
                Behavior on color { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.fast } }
            }
        }
    }

    FloatingPopupCard {
        id: card
        win: win
        open: QuickActionsState.open
        anchorX: QuickActionsState.anchorX
        barBottom: QuickActionsState.barBottom

        readonly property int pad: 6
        readonly property int contentW: 236
        width: contentW + pad * 2
        height: _rows.implicitHeight + pad * 2

        // The card holds focus on open (paints nothing); Down/Tab enters rows.
        function _focusFirstRow(): void {
            const sibs = _rows.children
            for (let k = 0; k < sibs.length; k++) {
                const c = sibs[k]
                if (c && c.isMenuRow === true && c.visible) { c.forceActiveFocus(); return }
            }
        }
        Keys.onDownPressed: e => { card._focusFirstRow(); e.accepted = true }
        Keys.onUpPressed:   e => { card._focusFirstRow(); e.accepted = true }
        Component.onCompleted: if (QuickActionsState.open) card.forceActiveFocus()

        Column {
            id: _rows
            x: card.pad; y: card.pad
            width: card.contentW
            spacing: 1

            QuickActionRow {
                glyph: Notifications.effectiveDnd ? "󰂛" : "󰂚"
                label: "Do Not Disturb"
                active: Notifications.effectiveDnd
                stateText: Notifications.dnd ? "On" : (Notifications.effectiveDnd ? "Quiet hours" : "Off")
                onTriggered: Notifications.toggleDnd()
            }
            QuickActionRow {
                visible: NightLight.toolAvailable
                glyph: "󰖔"
                label: "Night Light"
                active: NightLight.enabled
                stateText: NightLight.enabled ? "On" : "Off"
                onTriggered: NightLight.toggle()
            }
            QuickActionRow {
                visible: PowerProfiles.available
                checkable: false
                glyph: PowerProfiles.glyph.length > 0 ? PowerProfiles.glyph : "󰾅"
                label: "Power Mode"
                active: PowerProfiles.profile === "performance"
                stateText: PowerProfiles.label.length > 0 ? PowerProfiles.label : "…"
                onTriggered: PowerProfiles.cycle()
            }
            QuickActionRow {
                // airplane = every controllable radio off; toggling flips them together
                readonly property bool _wifiCtl: Network.toolAvailable && Network.hasWifiDevice
                readonly property bool _btCtl:   Bluetooth.available
                readonly property bool _anyOn:   (_wifiCtl && Network.wifiEnabled) || (_btCtl && Bluetooth.enabled)
                visible: _wifiCtl || _btCtl
                glyph: "󰀝"
                label: "Airplane Mode"
                active: !_anyOn
                stateText: _anyOn ? "Off" : "On"
                onTriggered: {
                    const wantOn = _anyOn ? false : true
                    if (_wifiCtl && Network.wifiEnabled !== wantOn) Network.toggleWifi()
                    if (_btCtl && Bluetooth.enabled !== wantOn) Bluetooth.toggle()
                }
            }
        }
    }
}
