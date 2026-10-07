pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"

FittedPopupWindow {
    id: win

    open: QuickActionsState.open
    layerNamespace: "silere-quickactions"
    popupCard: card
    onDismissed: QuickActionsState.close()
    onEscapePressed: QuickActionsState.close()

    Connections {
        target: ShellSettings
        function onBarPositionChanged() { if (QuickActionsState.open) QuickActionsState.close() }
    }
    Connections {
        target: QuickActionsState
        function onOpenChanged() {
            if (QuickActionsState.open) card.forceActiveFocus()
        }
    }

    component QuickActionRow: Item {
        id: _row

        property string glyph: ""
        property string label: ""
        property string stateText: ""
        property string detailText: ""
        property bool   active: false
        property bool   highlighted: active
        property bool   error: false
        property bool   warning: false
        property bool   checkable: true
        readonly property bool _canActivate: _row.visible && _row.enabled
        readonly property bool _pressed: _rowTap.pressed
        readonly property int _mainHeight: Metrics.rowHeightFor(38)
        readonly property color _statusColor: error ? Theme.error
            : warning ? Theme.warning : Theme.accent

        signal triggered()

        function _activate(): void {
            if (_row._canActivate) _row.triggered()
        }

        width: parent ? parent.width : 0
        height: _mainHeight + (_detail.visible ? _detail.implicitHeight + 8 : 0)
        // a blocked row stays readable so its explanation shows
        opacity: _canActivate || error || warning ? 1.0 : Theme.disabledOpacity
        MotionBehavior on opacity { NumberAnimation { duration: Motion.medium } }

        Accessible.role: _row.checkable ? Accessible.CheckBox : Accessible.Button
        Accessible.name: _row.label
        Accessible.description: _row.stateText + (_row.detailText.length > 0 ? ". " + _row.detailText : "")
        Accessible.focusable: _row._canActivate
        Accessible.checkable: _row.checkable
        Accessible.checked: _row.checkable && _row.active
        Accessible.onPressAction: _row._activate()

        HoverHandler {
            id: _rowHover
            enabled: _row._canActivate
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: _rowTap
            enabled: _row._canActivate
            onTapped: _row._activate()
        }

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

        ShellText {
            id: _glyph
            anchors.left: parent.left
            anchors.leftMargin: 10
            y: Math.round((_row._mainHeight - height) / 2)
            width: 18
            horizontalAlignment: Text.AlignHCenter
            text: _row.glyph
            color: _row.error || _row.warning || _row.highlighted
                ? Theme.withAlpha(_row._statusColor, 0.95) : Theme.withAlpha(Theme.subtext, 0.85)
            font.pixelSize: Settings.fontSize + 1
            ColorFade on color {}
        }

        ShellText {
            anchors.left: _glyph.right
            anchors.leftMargin: 8
            anchors.right: _state.left
            anchors.rightMargin: 8
            anchors.verticalCenter: _glyph.verticalCenter
            text: _row.label
            color: Theme.text
            font.pixelSize: Settings.fontSize
            elide: Text.ElideRight
        }

        Rectangle {
            id: _state
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: _glyph.verticalCenter
            width: Math.min(_row.width * 0.48, Math.max(30, _stateLabel.implicitWidth + 12))
            height: Math.max(20, _stateLabel.implicitHeight + 4)
            radius: 7
            antialiasing: true
            color: _row.error || _row.warning || _row.highlighted
                ? Theme.withAlpha(_row._statusColor, 0.13) : "transparent"
            ColorFade on color {}
            MotionBehavior on width {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

            OutlineBorder {
                radius: _state.radius
                outlineColor: _row.error || _row.warning || _row.highlighted
                    ? Theme.withAlpha(_row._statusColor, Theme.lineAlpha(0.30)) : "transparent"
                ColorFade on outlineColor {}
            }

            ShellText {
                id: _stateLabel
                anchors.centerIn: parent
                width: Math.min(implicitWidth, _state.width - 12)
                text: _row.stateText
                color: _row.error || _row.warning ? _row._statusColor
                    : _row.highlighted ? Theme.mix(Theme.accent, Theme.text, 0.18)
                    : Theme.withAlpha(Theme.subtext, 0.82)
                font.pixelSize: Settings.fontCaption
                font.weight: Font.Medium
                elide: Text.ElideRight
                ColorFade on color {}
            }
        }

        ShellText {
            id: _detail
            visible: _row.detailText.length > 0
            x: _glyph.x + _glyph.width + 8
            y: _row._mainHeight - 2
            width: Math.max(0, _row.width - x - 10)
            text: _row.detailText
            color: _row.error || _row.warning ? _row._statusColor : Theme.menuTextDetail
            font.pixelSize: Settings.fontCaption
            wrapMode: Text.Wrap
            ColorFade on color {}
        }
    }

    PopupShadow { card: card }

    FloatingPopupCard {
        id: card
        win: win
        open: QuickActionsState.open
        anchorX: QuickActionsState.effectiveAnchorX
        barBottom: QuickActionsState.barBottom

        readonly property int pad: 6
        // label and state pill both grow with the font, so a fixed width elides three of the
        // four rows at raised uiScale. never below 236: the pill's padding and floor do not
        // shrink with the font, so scaling down costs the label more than it saves
        readonly property int contentW: Math.max(236,
            Metrics.snap4(236 * Settings.fontSize / 12))
        width: contentW + pad * 2
        height: Metrics.snap4Up(_rows.implicitHeight + pad * 2)
        // a row can appear or disappear (radios toggled, a profile daemon starting) while the card is open
        MotionBehavior on height {
            gate: card.geometryMotionReady
            NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
        }

        Component.onCompleted: if (QuickActionsState.open) card.forceActiveFocus()

        Column {
            id: _rows
            x: card.pad; y: card.pad
            width: card.contentW
            spacing: 1

            QuickActionRow {
                glyph: Notifications.silencingActive ? "󰂛" : "󰂚"
                label: "Do Not Disturb"
                active: Notifications.dnd
                highlighted: Notifications.silencingActive
                stateText: Notifications.dnd ? "On"
                    : Notifications.effectiveDnd ? "Quiet hours"
                    : Notifications.fullscreenSilenced ? "Fullscreen" : "Off"
                onTriggered: Notifications.toggleDnd()
            }
            QuickActionRow {
                glyph: Idle.keepAwake ? "󰅶" : "󰛊"
                label: "Keep Awake"
                active: Idle.keepAwake
                stateText: Idle.keepAwake ? "On" : "Off"
                onTriggered: Idle.toggleKeepAwake()
            }
            QuickActionRow {
                visible: NightLight.toolAvailable
                glyph: "󰖔"
                label: "Night Light"
                active: NightLight.enabled
                error: NightLight.lastError.length > 0
                detailText: NightLight.lastError
                stateText: NightLight.lastError.length > 0 ? "Failed"
                    : NightLight.enabled ? "On" : "Off"
                onTriggered: NightLight.toggle()
            }
            QuickActionRow {
                visible: PowerProfiles.available
                glyph: PowerProfiles.glyph.length > 0 ? PowerProfiles.glyph : "󰾅"
                label: "Power Mode"
                checkable: false
                enabled: PowerProfiles.profile.length > 0 && !PowerProfiles.changing
                active: PowerProfiles.profile === "performance"
                error: PowerProfiles.lastError.length > 0
                warning: PowerProfiles.degraded
                detailText: PowerProfiles.lastError.length > 0 ? PowerProfiles.lastError
                    : PowerProfiles.degraded ? "Performance is limited by the system" : ""
                stateText: PowerProfiles.changing ? "Changing…"
                         : PowerProfiles.lastError.length > 0 ? "Failed"
                         : PowerProfiles.label.length > 0 ? PowerProfiles.label
                         : "Unavailable"
                onTriggered: PowerProfiles.cycle()
            }
            QuickActionRow {
                visible: Network.toolAvailable && Network.hasWifiDevice
                enabled: QuickActionsState.wifiControllable
                glyph: Network.wifiEnabled ? "󰤨" : "󰤭"
                label: "Wi-Fi"
                active: Network.wifiEnabled
                warning: Network.wifiHardBlocked
                stateText: Network.wifiHardBlocked ? "Blocked" : Network.wifiEnabled ? "On" : "Off"
                detailText: Network.wifiHardBlocked ? "Blocked by the hardware switch" : ""
                onTriggered: Network.toggleWifi()
            }
            QuickActionRow {
                visible: Bluetooth.available
                enabled: QuickActionsState.btControllable
                glyph: Bluetooth.enabled ? "󰂯" : "󰂲"
                label: "Bluetooth"
                active: Bluetooth.enabled
                warning: Bluetooth.hardBlocked
                stateText: Bluetooth.hardBlocked ? "Blocked" : Bluetooth.enabled ? "On" : "Off"
                detailText: Bluetooth.hardBlocked ? "Blocked by the hardware switch" : ""
                onTriggered: Bluetooth.toggle()
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
