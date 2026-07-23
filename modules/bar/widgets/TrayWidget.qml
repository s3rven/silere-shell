pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../../../config"
import "../../../services"
import "../../common"

// StatusNotifier tray; invisible with no items so it costs nothing at rest. left-click jumps to the app window
// (falls back to activate/menu when no live window), right-click menu, middle secondary-activate, scroll passes through.
Item {
    id: root

    property var screen: null   // ShellScreen this bar sits on, for menu placement
    property bool compact: ShellSettings.barCompact
    property bool barActive: true
    readonly property bool show: ShellSettings.trayWidget && _items.count > 0
    readonly property int iconSize: Math.max(14, Math.min(18, Math.round(ShellSettings.barHeight * 0.44)))
    readonly property int _pillPad: Metrics.pillPadFor(compact)

    // pillPad insets match the pills' edge margin so gaps read even across the bar
    implicitWidth:  show ? _row.implicitWidth + _pillPad * 2 : 0
    implicitHeight: parent ? parent.height : 24
    visible: show

    Behavior on implicitWidth { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }

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
        // tracks the Spacing setting (one notch tighter: icons read as a cluster)
        spacing: Math.max(5, ShellSettings.barSpacing - 4)

        Repeater {
            id: _items
            // don't decode icons or run attention anims while the tray feature is disabled
            model: ShellSettings.trayWidget ? SystemTray.items : null

            delegate: Item {
                id: _tile
                required property var modelData
                readonly property string label: modelData.tooltipTitle.length > 0 ? modelData.tooltipTitle
                    : modelData.title.length > 0 ? modelData.title
                    : modelData.id
                readonly property bool passive: modelData.status === Status.Passive
                readonly property bool needsAttention: modelData.status === Status.NeedsAttention
                // Drives the attention halo; stays at full for the reduceMotion path.
                property real attnPulse: 1.0
                property bool _attentionSettled: false
                // SNI tooltip title as a quiet inline reveal: only after the pointer rests, or on keyboard focus
                property bool _dwelled: false

                onNeedsAttentionChanged: _attentionSettled = false

                width: root.iconSize + (_hoverLabel.width > 0 ? _hoverLabel.width + 5 : 0)
                height: root.iconSize
                opacity: passive ? 0.78 : 1.0
                anchors.verticalCenter: parent.verticalCenter

                Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.color } }

                Timer {
                    id: _labelDwell
                    interval: 350
                    onTriggered: _tile._dwelled = true
                }

                // Unified backing pill: hover wash or attention halo (attention wins).
                Rectangle {
                    x: -3
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.iconSize + 6
                    height: root.iconSize + 6
                    radius: Math.min(width, height) / 2
                    color: _tile.needsAttention
                        ? Theme.withAlpha(Theme.accent, 0.20)
                        : Theme.withAlpha(Theme.accent, _ma.pressed ? 0.26 : 0.14)
                    opacity: _tile.needsAttention ? _tile.attnPulse
                           : _ma.pressed          ? 1.0
                           : (_iconHover.hovered && ShellSettings.barHoverHighlight) ? 1.0
                           : _tile.activeFocus    ? 1.0
                           : 0.0
                    visible: opacity > 0.001

                    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.color } }
                    Behavior on color   { enabled: !ShellSettings.reduceMotion; ColorAnimation  { duration: Motion.color } }
                }

                PulseLoop {
                    running: root.barActive && _tile.needsAttention && !_tile._attentionSettled
                        && !ShellSettings.reduceMotion && !Idle.isIdle
                    target: _tile; targetProperty: "attnPulse"
                    peak: 0.4; floor: 1.0; restValue: 1.0
                    duration: Motion.ms(900)
                }

                // NeedsAttention can be held forever; stop pulsing, keep the static halo
                Timer {
                    interval: 15000
                    running: root.barActive && _tile.needsAttention
                        && !_tile._attentionSettled && !Idle.isIdle
                    onTriggered: _tile._attentionSettled = true
                }

                // letter fallback only for genuinely slow/missing icons — showing it instantly flashes a
                // grey badge on every tray enable while the async decode catches up
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

                    Text {
                        anchors.centerIn: parent
                        text: _tile.label.length > 0 ? _tile.label.charAt(0).toUpperCase() : "?"
                        color: Theme.subtext
                        font.family: Settings.font
                        font.pixelSize: Math.max(9, Math.round(root.iconSize * 0.68))
                        renderType: Text.NativeRendering
                    }
                }

                CollapsingText {
                    id: _hoverLabel
                    x: root.iconSize + 5
                    color: Theme.subtext
                    text: _tile.label.length > 22 ? _tile.label.slice(0, 21) + "…" : _tile.label
                    expanded: (_tile._dwelled || _tile.activeFocus)
                        && _tile.label.length > 0 && !TrayMenuState.open
                }

                IconImage {
                    id: _icon
                    readonly property bool ready: status === Image.Ready
                    width: root.iconSize
                    height: root.iconSize
                    anchors.verticalCenter: parent.verticalCenter
                    source: _tile.modelData.icon
                    // generous request: SNI providers pick their largest pixmap, downscaling beats upscaling a 22px icon
                    implicitSize: root.iconSize
                    backer.sourceSize.width:  64
                    backer.sourceSize.height: 64
                    mipmap: true
                    asynchronous: true
                    visible: opacity > 0.01
                    opacity: ready ? 1.0 : 0.0
                    transformOrigin: Item.Center
                    scale: _ma.pressed ? 0.86 : 1.0
                    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast } }
                    Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
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
                        // prefer landing on the actual window; only fall through to the item's own
                        // activation when it has no live window (minimised-to-tray / daemon). onlyMenu = no activate path
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
                activeFocusOnTab: root.show
                // shift+activate or the Menu key opens the context menu (keyboard mirror of right-click)
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
