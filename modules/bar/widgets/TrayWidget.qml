pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
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
    property var trayModel: SystemTray.items
    readonly property var _trayItems: root.trayModel
        ? (Array.isArray(root.trayModel) ? root.trayModel : (root.trayModel.values ?? [])) : []
    readonly property bool show: ShellSettings.trayWidget
        && root._trayItems.some(i => i && !ShellSettings.trayItemHidden(i.id))
    readonly property bool contentVisible: root.show
    readonly property bool layoutVisible: show || implicitWidth > 0.5
    // the bar height is a ceiling, not the source: the old barHeight*0.44 ignored uiScale
    // entirely, so tray icons were the one thing that could not follow the interface scale
    readonly property int iconSize: Math.max(12,
        Math.min(Math.round(ShellSettings.barHeight * 0.62),
            Math.round(ShellSettings.barIconSize * ShellSettings.uiScale) + 4))
    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    readonly property int _pillPad: Metrics.pillPadFor(compact)

    // only appearing/leaving eases; hover growth is already eased by the label, and a second ease on top lags the slot behind its own content
    property real _showProgress: show ? 1.0 : 0.0
    implicitWidth:  (_row.implicitWidth + _pillPad * 2) * _showProgress
    implicitHeight: parent ? parent.height : 24
    visible: layoutVisible
    clip: _showProgress < 0.999

    MotionBehavior on _showProgress {NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }

    function _syncMenuAnchors(): void {
        for (let i = 0; i < _items.count; i++) {
            const tile = _items.itemAt(i)
            if (tile) tile.syncMenuAnchor()
        }
    }

    onXChanged: root._syncMenuAnchors()
    onYChanged: root._syncMenuAnchors()
    onImplicitWidthChanged: root._syncMenuAnchors()

    // an item without its own menu still opens one, holding only the hide entry
    function _openMenu(item, tile): void {
        tile.syncMenuAnchor()
        TrayMenuState.toggleAt(
            tile.menuAnchorX,
            root.screen,
            item.hasMenu ? item.menu : null,
            Metrics.barAtBottom,
            tile,
            item
        )
    }

    function _activateItem(item, tile): void {
        if (!root.show || !item || ShellSettings.trayItemHidden(item.id)) return
        if (item.onlyMenu) root._openMenu(item, tile)
        else if (!WindowActions.focusTrayItem(item.id, item.title, item.tooltipTitle))
            item.activate()
    }

    Row {
        id: _row
        x: root._pillPad
        anchors.verticalCenter: parent.verticalCenter
        spacing: Math.max(3, Metrics.widgetGapFor(root.compact) - 2)

        Repeater {
            id: _items
            // a quick off/on keeps each item's image and event handlers intact
            model: root.trayModel

            delegate: Item {
                id: _tile
                required property var modelData
                readonly property string label: SafeText.singleLineText(
                    String(modelData.tooltipTitle || "").length > 0 ? modelData.tooltipTitle
                    : String(modelData.title || "").length > 0 ? modelData.title
                    : modelData.id, 128)
                readonly property string _providedIconSource: IconResolver.trayIconSource(modelData.icon)
                property bool _providedIconFailed: false
                readonly property string iconSource: IconResolver.trayAppIconSource(
                    _tile._providedIconFailed ? "" : _tile._providedIconSource, modelData.id)
                readonly property bool fallbackVisible: !_icon.ready
                    && (_tile.iconSource.length === 0 || _icon.status === Image.Error || _tile._fallbackDue)
                on_ProvidedIconSourceChanged: _tile._providedIconFailed = false
                readonly property bool passive: modelData.status === Status.Passive
                readonly property bool needsAttention: modelData.status === Status.NeedsAttention
                readonly property bool hidden: ShellSettings.trayItemHidden(modelData.id)
                onHiddenChanged: if (!_tile.hidden) _tile._providedIconFailed = false
                // hidden, not filtered out: a filtered model recreates the icon on every un-hide
                visible: !hidden
                property real menuAnchorX: 0
                property real attnPulse: 1.0
                property bool _attentionSettled: false
                property bool _dwelled: false

                onNeedsAttentionChanged: _attentionSettled = false
                onModelDataChanged: {
                    _tile._providedIconFailed = false
                    _tile._fallbackDue = false
                    _tile._dwelled = false
                    if (!_icon.ready) _fallbackTimer.restart()
                }

                Accessible.role: Accessible.Button
                Accessible.name: _tile.label
                Accessible.description: SafeText.singleLineText(modelData.tooltipDescription, 256)
                Accessible.focusable: root.show && !_tile.hidden
                Accessible.onPressAction: root._activateItem(_tile.modelData, _tile)

                width: root.iconSize + (_hoverLabel.width > 0 ? _hoverLabel.width + 5 : 0)
                height: root.iconSize
                opacity: passive ? 0.78 : 1.0
                anchors.verticalCenter: parent.verticalCenter

                function syncMenuAnchor(): void {
                    // labels grow to the right on hover; the popup belongs to the icon, so its anchor must not wander with the label width
                    const pt = _tile.mapToItem(null, root.iconSize / 2, 0)
                    if (isFinite(pt.x)) _tile.menuAnchorX = pt.x
                }

                Component.onCompleted: _tile.syncMenuAnchor()
                onXChanged: _tile.syncMenuAnchor()
                onYChanged: _tile.syncMenuAnchor()

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
                         : Theme.withAlpha(Theme.mix(Theme.text, Theme.accent, 0.30), 0.07)
                    opacity: _tile.needsAttention ? _tile.attnPulse
                           : _ma.pressed          ? 1.0
                           : (_iconHover.hovered && ShellSettings.barHoverHighlight) ? 1.0
                           : 0.0
                    visible: opacity > 0.001

                    MotionBehavior on opacity {NumberAnimation { duration: Motion.color } }
                    ColorFade on color {}
                }

                PulseLoop {
                    active: root.barActive && _tile.visible && _tile.needsAttention && !_tile._attentionSettled
                        && !Idle.isIdle
                    target: _tile; targetProperty: "attnPulse"
                    peak: 0.4; floor: 1.0; restValue: 1.0
                    duration: Motion.ms(900)
                }

                Timer {
                    interval: 15000
                    running: root.barActive && _tile.needsAttention
                        && !_tile._attentionSettled
                        && Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)
                    onTriggered: _tile._attentionSettled = true
                }

                property bool _fallbackDue: false
                Timer {
                    id: _fallbackTimer
                    interval: 300
                    running: root.show && !_tile.hidden && _icon.status === Image.Loading
                    onTriggered: _tile._fallbackDue = true
                }

                Rectangle {
                    width: root.iconSize
                    height: root.iconSize
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Math.min(width, height) / 2
                    color: Theme.withAlpha(Theme.subtext, 0.12)
                    visible: _tile.fallbackVisible

                    ShellText {
                        anchors.centerIn: parent
                        text: SafeText.initial(_tile.label, "?")
                        color: Theme.subtext
                        font.pixelSize: Math.max(9, Math.round(root.iconSize * 0.68))
                    }
                }

                CollapsingText {
                    id: _hoverLabel
                    x: root.iconSize + 5
                    color: Theme.subtext
                    text: SafeText.boundedText(_tile.label, 22)
                    expanded: ((_tile._dwelled && !root.compact))
                        && _tile.label.length > 0 && !TrayMenuState.open
                }

                IconImage {
                    id: _icon
                    readonly property bool ready: status === Image.Ready
                    onStatusChanged: {
                        if (status === Image.Error && !_tile._providedIconFailed
                                && _tile._providedIconSource.length > 0)
                            _tile._providedIconFailed = true
                    }
                    width: root.iconSize
                    height: root.iconSize
                    anchors.verticalCenter: parent.verticalCenter
                    // a hidden app can keep animating its icon, and each frame goes through the icon theme loader
                    source: _tile.hidden ? "" : _tile.iconSource
                    implicitSize: root.iconSize
                    // loaded at device size: mipmap takes the image out of the texture atlas, and that path SEGVs the render thread
                    backer.sourceSize.width:  Math.ceil(root.iconSize * root._dpr)
                    backer.sourceSize.height: Math.ceil(root.iconSize * root._dpr)
                    // apps reuse an icon url across restarts and updates; a reload must not keep an earlier failed image
                    backer.cache: false
                    asynchronous: true
                    transform: PixelSnap { item: _icon; dpr: root._dpr }
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
                        if (hovered) {
                            _labelDwell.restart()
                        } else {
                            _labelDwell.stop()
                            _tile._dwelled = false
                        }
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
                        const r = Scroll.processTrayWheel(wheel, "tray:" + _tile.modelData.id)
                        if (r.steps !== 0) _tile.modelData.scroll(r.steps * Scroll.notch, r.horizontal)
                    }
                }

            }
        }
    }
}
