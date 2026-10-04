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
    readonly property var popupCard: card

    readonly property string _output: Compositor.monitorName(win.screen)

    screen:        targetScreen
    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "silere-quickactions"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // full screen only to catch the closing click: the compositor recomposites every pixel of a surface Qt redraws, so the card animates in its own narrow window
    visible: QuickActionsState.open || cardWin.visible
    // layer surfaces stack in map order: mapped after the card, this window would cover it and take its clicks
    property bool _cardMayMap: false
    onVisibleChanged: {
        if (visible) Qt.callLater(() => win._cardMayMap = win.visible)
        else win._cardMayMap = false
    }

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
            if (QuickActionsState.open) card.forceActiveFocus()
        }
    }

    OutsideTapGuard {
        id: _tapGuard
        open: QuickActionsState.open
    }

    Item { id: _fillArea; anchors.fill: parent }
    mask: Region { item: QuickActionsState.open ? _fillArea : null }
    // an empty region, not none: the silere-quickactions layer rule would otherwise blur the whole screen behind this window
    BackgroundEffect.blurRegion: Region { item: null }

    TapHandler {
        id: _dismiss
        enabled: QuickActionsState.open
        onTapped: {
            if (_tapGuard.ignoring) return
            const p = _dismiss.point.position
            if (p.x < card.x || p.x > card.x + card.width ||
                p.y < card.y || p.y > card.y + card.height)
                QuickActionsState.close()
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

    PanelWindow {
        id: cardWin

        // room for the shadow; snapped so a moving anchor rarely reconfigures the surface
        readonly property int _slack: 48
        readonly property real _screenW: win.screen ? win.screen.width : 0
        readonly property int _left: Math.max(0,
            64 * Math.floor((card.placementSpan.x - _slack) / 64))
        readonly property int _right: Math.min(Math.ceil(_screenW),
            64 * Math.ceil((card.placementSpan.y + card.targetWidth + _slack) / 64))

        screen:        win.screen
        color:         "transparent"
        exclusiveZone: -1
        WlrLayershell.namespace: "silere-quickactions"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: QuickActionsState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        visible: (QuickActionsState.open || card.opacity > 0.001) && win._cardMayMap

        anchors { top: true; bottom: true; left: true }
        margins.left: cardWin._left
        implicitWidth: Math.max(1, cardWin._right - cardWin._left)

        // the card alone: anywhere else in the strip has to fall through to the closing window below
        mask: Region {
            item: QuickActionsState.open ? card : null
            Region { item: _stage; intersection: Intersection.Intersect }
        }
        BackgroundEffect.blurRegion: Region {
            item: card.blurItem
            radius: Math.round(card.radius)
            // a region rebuilds only when one of its own items moves, and the stage carries every card x shift
            Region { item: _stage; intersection: Intersection.Intersect }
        }

        // screen coordinates: the card places itself as it did in a full-screen window
        Item {
            id: _stage
            x: -cardWin._left
            width: cardWin._screenW
            height: parent.height

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
    }
}
