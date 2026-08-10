pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    property var screen: null
    property bool compact: ShellSettings.barCompact
    property bool barActive: true
    readonly property bool show: ShellSettings.trayWidget && _items.count > 0
    readonly property bool layoutVisible: show || implicitWidth > 0.5
    readonly property int iconSize: Math.max(14, Math.min(18, Math.round(ShellSettings.barHeight * 0.44)))
    readonly property int _pillPad: Metrics.pillPadFor(compact)

    // only appearing/leaving eases; hover growth is already eased by the label, and a second ease on top lags the slot behind its own content
    property real _showProgress: show ? 1.0 : 0.0
    implicitWidth:  (_row.implicitWidth + _pillPad * 2) * _showProgress
    implicitHeight: parent ? parent.height : 24
    visible: layoutVisible
    clip: _showProgress < 0.999

    MotionBehavior on _showProgress {NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }

    function _openMenu(item, tile): void {
        if (!item.hasMenu) return
        TrayMenuState.openAt(
            tile.mapToItem(null, tile.width / 2, 0).x,
            root.screen,
            item.menu,
            ShellSettings.barPosition === "bottom"
        )
    }

    function _activateItem(item, tile): void {
        if (!HyprActions.focusTrayItem(item.id, item.title, item.tooltipTitle)) {
            if (item.onlyMenu) root._openMenu(item, tile)
            else item.activate()
        }
    }

    Row {
        id: _row
        x: root._pillPad
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.compact ? Math.max(2, ShellSettings.barSpacing - 6)
                              : Math.max(5, ShellSettings.barSpacing - 4)

        Repeater {
            id: _items
            model: ShellSettings.trayWidget ? SystemTray.items : null

            delegate: Item {
                id: _tile
                required property var modelData
                readonly property string label: modelData.tooltipTitle.length > 0 ? modelData.tooltipTitle
                    : modelData.title.length > 0 ? modelData.title
                    : modelData.id
                readonly property bool passive: modelData.status === Status.Passive
                readonly property bool needsAttention: modelData.status === Status.NeedsAttention
                property real attnPulse: 1.0
                property bool _attentionSettled: false
                property bool _dwelled: false

                onNeedsAttentionChanged: _attentionSettled = false

                width: root.iconSize + (_hoverLabel.width > 0 ? _hoverLabel.width + 5 : 0)
                height: root.iconSize
                opacity: passive ? 0.78 : 1.0
                anchors.verticalCenter: parent.verticalCenter

                MotionBehavior on opacity {NumberAnimation { duration: Motion.color } }

                Timer {
                    id: _labelDwell
                    interval: 80
                    onTriggered: _tile._dwelled = true
                }

                Rectangle {
                    id: _hoverCap
                    x: -3
                    anchors.verticalCenter: parent.verticalCenter
                    width: _tile.width + 6
                    height: Metrics.barRowHeight
                    radius: Metrics.hoverRadiusFor(height)
                    color: _tile.needsAttention ? Theme.withAlpha(Theme.accent, 0.20)
                         : _ma.pressed           ? Theme.withAlpha(Theme.accent, 0.18)
                         : _tile.activeFocus     ? Theme.withAlpha(Theme.accent, 0.14)
                         : Theme.withAlpha(Theme.mix(Theme.text, Theme.accent, 0.30), 0.07)
                    opacity: _tile.needsAttention ? _tile.attnPulse
                           : _ma.pressed          ? 1.0
                           : (_iconHover.hovered && ShellSettings.barHoverHighlight) ? 1.0
                           : _tile.activeFocus    ? 1.0
                           : 0.0
                    visible: opacity > 0.001

                    OutlineBorder {
                        radius: _hoverCap.radius
                        outlineColor: _tile.activeFocus ? Theme.withAlpha(Theme.accent, Theme.focusRingAlpha) : "transparent"
                    }

                    MotionBehavior on opacity {NumberAnimation { duration: Motion.color } }
                    ColorFade on color {}
                }

                PulseLoop {
                    active: root.barActive && _tile.needsAttention && !_tile._attentionSettled
                        && !Idle.isIdle
                    target: _tile; targetProperty: "attnPulse"
                    peak: 0.4; floor: 1.0; restValue: 1.0
                    duration: Motion.ms(900)
                }

                Timer {
                    interval: 15000
                    running: root.barActive && _tile.needsAttention
                        && !_tile._attentionSettled && !Idle.isIdle
                    onTriggered: _tile._attentionSettled = true
                }

                property bool _fallbackDue: false
                Timer {
                    interval: 300
                    running: !_icon.ready
                    onTriggered: _tile._fallbackDue = true
                }

                Rectangle {
                    width: root.iconSize
                    height: root.iconSize
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Math.min(width, height) / 2
                    color: Theme.withAlpha(Theme.subtext, 0.12)
                    visible: !_icon.ready && _tile._fallbackDue

                    ShellText {
                        anchors.centerIn: parent
                        text: _tile.label.length > 0 ? _tile.label.charAt(0).toUpperCase() : "?"
                        color: Theme.subtext
                        font.pixelSize: Math.max(9, Math.round(root.iconSize * 0.68))
                    }
                }

                CollapsingText {
                    id: _hoverLabel
                    x: root.iconSize + 5
                    color: Theme.subtext
                    text: _tile.label.length > 22 ? _tile.label.slice(0, 21) + "…" : _tile.label
                    expanded: ((_tile._dwelled && !root.compact) || _tile.activeFocus)
                        && _tile.label.length > 0 && !TrayMenuState.open
                }

                IconImage {
                    id: _icon
                    readonly property bool ready: status === Image.Ready
                    width: root.iconSize
                    height: root.iconSize
                    anchors.verticalCenter: parent.verticalCenter
                    source: _tile.modelData.icon
                    implicitSize: root.iconSize
                    backer.sourceSize.width:  64
                    backer.sourceSize.height: 64
                    mipmap: true
                    asynchronous: true
                    visible: opacity > 0.01
                    opacity: ready ? 1.0 : 0.0
                    transformOrigin: Item.Center
                    scale: _ma.pressed ? 0.94 : 1.0
                    MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }
                    MotionBehavior on scale   {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                }

                HoverHandler {
                    id: _iconHover
                    onHoveredChanged: {
                        if (hovered) _labelDwell.restart()
                        else { _labelDwell.stop(); _tile._dwelled = false }
                    }
                }

                MouseArea {
                    id: _ma
                    anchors.fill: parent
                    enabled: root.show
                    // MouseArea overrides the cursor beneath it, so the pointer shape must live here not on the HoverHandler
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onClicked: (mouse) => {
                        const it = _tile.modelData
                        if (mouse.button === Qt.RightButton)
                            root._openMenu(it, _tile)
                        else if (mouse.button === Qt.MiddleButton)
                            it.secondaryActivate()
                        else root._activateItem(it, _tile)
                    }
                    onWheel: (wheel) => {
                        wheel.accepted = true
                        const horizontal = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y)
                        const delta = horizontal ? wheel.angleDelta.x : wheel.angleDelta.y
                        if (delta !== 0) _tile.modelData.scroll(delta, horizontal)
                    }
                }

                Accessible.role: Accessible.Button
                Accessible.name: label
                Accessible.description: modelData.tooltipDescription
                Accessible.onPressAction: root._activateItem(_tile.modelData, _tile)
                activeFocusOnTab: root.show || activeFocus
                function _keyActivate(event): void {
                    if (event.isAutoRepeat) { event.accepted = true; return }
                    if (event.modifiers & Qt.ShiftModifier) root._openMenu(_tile.modelData, _tile)
                    else root._activateItem(_tile.modelData, _tile)
                    event.accepted = true
                }
                Keys.onSpacePressed:  event => _tile._keyActivate(event)
                Keys.onReturnPressed: event => _tile._keyActivate(event)
                Keys.onEnterPressed:  event => _tile._keyActivate(event)
                Keys.onMenuPressed:   event => {
                    if (!event.isAutoRepeat) root._openMenu(_tile.modelData, _tile)
                    event.accepted = true
                }
            }
        }
    }
}
