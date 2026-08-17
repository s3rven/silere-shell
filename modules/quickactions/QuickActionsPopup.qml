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

    PopupShadow { card: card }

    component QuickActionRow: Item {
        id: _row

        property string glyph: ""
        property string label: ""
        property string stateText: ""
        property bool   active: false
        property bool   checkable: true
        readonly property bool _pressed: _rowTap.pressed

        signal triggered()

        function _activate(): void {
            if (_row.visible) _row.triggered()
        }

        width: parent ? parent.width : 0
        height: Metrics.rowHeightFor(38)

        HoverHandler { id: _rowHover; cursorShape: Qt.PointingHandCursor }
        TapHandler   { id: _rowTap; onTapped: _row._activate() }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusControl
            antialiasing: true
            color: _row._pressed
                ? Theme.withAlpha(Theme.accent, 0.14)
                : (_rowHover.hovered)
                    ? Theme.withAlpha(Theme.menuHover, 0.08) : "transparent"
            ColorFade on color {}
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
            MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }
            MotionBehavior on scale {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        }

        ShellText {
            id: _glyph
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            horizontalAlignment: Text.AlignHCenter
            text: _row.glyph
            color: _row.active ? Theme.withAlpha(Theme.accent, 0.95) : Theme.withAlpha(Theme.subtext, 0.85)
            font.pixelSize: Settings.fontSize + 1
            ColorFade on color {}
        }

        ShellText {
            anchors.left: _glyph.right
            anchors.leftMargin: 8
            anchors.right: _state.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: _row.label
            color: Theme.text
            font.pixelSize: Settings.fontSize
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
            ColorFade on color {}
            MotionBehavior on width {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

            OutlineBorder {
                radius: _state.radius
                outlineColor: _row.active ? Theme.withAlpha(Theme.accent, 0.22) : "transparent"
                ColorFade on outlineColor {}
            }

            ShellText {
                id: _stateLabel
                anchors.centerIn: parent
                text: _row.stateText
                color: _row.active ? Theme.mix(Theme.accent, Theme.text, 0.18) : Theme.withAlpha(Theme.subtext, 0.62)
                font.pixelSize: Settings.fontCaption
                font.weight: Font.Medium
                ColorFade on color {}
            }
        }
    }

    FloatingPopupCard {
        id: card
        win: win
        open: QuickActionsState.open
        anchorX: QuickActionsState.effectiveAnchorX
        barBottom: QuickActionsState.barBottom

        readonly property int pad: 6
        readonly property int contentW: 236
        width: contentW + pad * 2
        height: _rows.implicitHeight + pad * 2

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
                stateText: NightLight.lastError.length > 0 ? "Failed"
                    : NightLight.enabled ? "On" : "Off"
                onTriggered: NightLight.toggle()
            }
            QuickActionRow {
                visible: PowerProfiles.available && PowerProfiles.profile.length > 0
                checkable: false
                glyph: PowerProfiles.glyph.length > 0 ? PowerProfiles.glyph : "󰾅"
                label: "Power Mode"
                active: PowerProfiles.profile === "performance"
                stateText: PowerProfiles.label.length > 0 ? PowerProfiles.label : "…"
                onTriggered: PowerProfiles.cycle()
            }
            QuickActionRow {
                visible: QuickActionsState.airplaneAvailable
                glyph: "󰀝"
                label: "Airplane Mode"
                active: !QuickActionsState.radiosOn
                stateText: QuickActionsState.radiosOn ? "Off" : "On"
                onTriggered: QuickActionsState.toggleAirplane()
            }
        }
    }
}
