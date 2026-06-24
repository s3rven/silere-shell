pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../../../config"
import "../../../services"

// StatusNotifier tray. Invisible while no app exposes an item, so it costs
// nothing at rest. Left-click jumps to the app's window (switching workspace),
// falling back to the item's own activation or menu when it has no live window;
// right-click opens the menu, middle-click secondary-activates, scroll passes
// through to the item.
Item {
    id: root

    property var screen: null   // ShellScreen this bar sits on, for menu placement
    readonly property bool show: ShellSettings.trayWidget && _items.count > 0
    readonly property int iconSize: Math.max(14, Math.min(18, Math.round(ShellSettings.barHeight * 0.44)))

    implicitWidth:  show ? _row.implicitWidth : 0
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

    Row {
        id: _row
        anchors.verticalCenter: parent.verticalCenter
        // tracks the Spacing setting (one notch tighter: icons read as a cluster)
        spacing: Math.max(5, ShellSettings.barSpacing - 4)

        Repeater {
            id: _items
            // Do not decode icons or create attention animations while the
            // tray feature is disabled.
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

                width: root.iconSize
                height: root.iconSize
                opacity: passive ? 0.78 : 1.0
                anchors.verticalCenter: parent.verticalCenter

                Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.color } }

                // Unified backing pill: hover wash or attention halo (attention wins).
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 6
                    height: parent.height + 6
                    radius: Math.min(width, height) / 2
                    color: _tile.needsAttention
                        ? Theme.withAlpha(Theme.accent, 0.20)
                        : Theme.withAlpha(Theme.accent, _ma.pressed ? 0.26 : 0.14)
                    opacity: _tile.needsAttention ? _tile.attnPulse
                           : _ma.pressed          ? 1.0
                           : _iconHover.hovered   ? 1.0
                           : 0.0
                    visible: opacity > 0.001

                    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.color } }
                    Behavior on color   { enabled: !ShellSettings.reduceMotion; ColorAnimation  { duration: Motion.color } }
                }

                SequentialAnimation on attnPulse {
                    running: _tile.needsAttention && !ShellSettings.reduceMotion && !Idle.isIdle
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.4; duration: Motion.ms(900); easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.4; to: 1.0; duration: Motion.ms(900); easing.type: Easing.InOutSine }
                    onRunningChanged: if (!running) _tile.attnPulse = 1.0
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Math.min(width, height) / 2
                    color: Theme.withAlpha(Theme.subtext, 0.12)
                    visible: !_icon.ready

                    Text {
                        anchors.centerIn: parent
                        text: _tile.label.length > 0 ? _tile.label.charAt(0).toUpperCase() : "?"
                        color: Theme.subtext
                        font.family: Settings.font
                        font.pixelSize: Math.max(9, Math.round(root.iconSize * 0.68))
                        renderType: Text.NativeRendering
                    }
                }

                IconImage {
                    id: _icon
                    readonly property bool ready: status === Image.Ready
                    anchors.fill: parent
                    source: _tile.modelData.icon
                    // generous request: SNI providers pick their largest pixmap,
                    // and downscaling beats upscaling a 22px app icon
                    implicitSize: root.iconSize
                    backer.sourceSize.width:  64
                    backer.sourceSize.height: 64
                    mipmap: true
                    asynchronous: true
                    visible: ready
                    transformOrigin: Item.Center
                    scale: _ma.pressed ? 0.86 : 1.0
                    Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                }

                HoverHandler { id: _iconHover }

                MouseArea {
                    id: _ma
                    anchors.fill: parent
                    enabled: root.show
                    // MouseArea overrides the cursor beneath it, so the pointer
                    // shape must live here, not on the HoverHandler
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onClicked: (mouse) => {
                        const it = _tile.modelData
                        if (mouse.button === Qt.RightButton)
                            root._openMenu(it, _tile)
                        else if (mouse.button === Qt.MiddleButton)
                            it.secondaryActivate()
                        // Left-click: prefer landing on the actual window. Only if
                        // the app has no live window (minimised-to-tray / daemon)
                        // do we fall through to its own activation. Menu is a
                        // right-click concern; onlyMenu means the item explicitly
                        // has no activate path (system indicators, etc.).
                        else if (!HyprActions.focusTrayItem(it.id, it.title, it.tooltipTitle)) {
                            if (it.onlyMenu) root._openMenu(it, _tile)
                            else it.activate()
                        }
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
            }
        }
    }
}
