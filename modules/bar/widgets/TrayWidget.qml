pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.SystemTray
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    property var screen: null
    property bool compact: ShellSettings.barCompact
    property bool barActive: true
    property var trayModel: SystemTray.items
    Component.onCompleted: TrayMenuState.recoverOrphanItems()
    readonly property var _trayItems: root.trayModel
        ? (Array.isArray(root.trayModel) ? root.trayModel : (root.trayModel.values ?? [])) : []
    readonly property bool show: ShellSettings.trayWidget
        && root._trayItems.some(i => i && !ShellSettings.trayItemHidden(i.id))
    readonly property bool contentVisible: root.show
    readonly property bool _canInteract: root.enabled && root.visible && root.show && root.barActive && !Idle.isIdle
    readonly property bool layoutVisible: show || implicitWidth > 0.5
    // the bar height is a ceiling, not the source: the old barHeight*0.44 ignored uiScale
    // entirely, so tray icons were the one thing that could not follow the interface scale
    readonly property int iconSize: Math.max(12,
        Math.min(Math.round(Metrics.barHeight * 0.62),
            Math.round(ShellSettings.barIconSize * ShellSettings.uiScale) + 4))
    readonly property int _pad: Metrics.pillPadFor(compact)
    readonly property int _labelGap: Metrics.pillGapFor(compact)
    // each icon owns a pill's padding, so the hover cap fills its cell, as on a glyph pill
    readonly property int cellWidth: root.iconSize + root._pad * 2
    // icons sit two thirds as far apart as the widgets around them, edge to edge, so the tray reads as one group at every gap setting
    readonly property int itemGap: Math.max(0, Math.round(
        2 * (2 * root._pad + Metrics.widgetGapFor(root.compact)) / 3) - 2 * root._pad)
    // the right zone is pinned to its right edge: a label grown to the right there carries the hovered icon out from under the pointer
    readonly property bool labelLeads: ShellSettings.barWidgetOrderRightKeys.indexOf("tray") >= 0

    readonly property string accessibleName: "System tray"
    Accessible.role: Accessible.Grouping
    Accessible.name: root.accessibleName

    // only appearing/leaving eases; hover growth is already eased by the label, and a second ease on top lags the slot behind its own content
    property real _showProgress: show ? 1.0 : 0.0
    implicitWidth:  _row.implicitWidth * _showProgress
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
        if (!root._canInteract || !item || ShellSettings.trayItemHidden(item.id)) return
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
        if (!root._canInteract || !item || ShellSettings.trayItemHidden(item.id)) return
        if (item.onlyMenu) root._openMenu(item, tile)
        else if (!WindowActions.focusTrayItem(item.id, item.title, item.tooltipTitle))
            item.activate()
    }

    Row {
        id: _row
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.itemGap

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
                readonly property bool fallbackVisible: !_icon.shown
                    && (_tile.iconSource.length === 0 || _icon.status === Image.Error || _tile._fallbackDue)
                on_ProvidedIconSourceChanged: _tile._providedIconFailed = false
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
                    // another app's last frame is not this one's to hold
                    _icon._hadImage = false
                    if (!_icon.shown) _fallbackTimer.restart()
                }

                Accessible.role: Accessible.Button
                Accessible.name: _tile.label
                Accessible.description: SafeText.singleLineText(modelData.tooltipDescription, 256)
                Accessible.focusable: root._canInteract && !_tile.hidden
                Accessible.onPressAction: root._activateItem(_tile.modelData, _tile)
                KeyboardFocus { interactive: control ? control.Accessible.focusable : false; listNavigation: true; onActivated: { if (control) control.Accessible.pressAction() } }

                // the gap opens with the label's first pixels, so the cell never jumps by it
                readonly property real _labelSpan: _hoverLabel.width > 0
                    ? _hoverLabel.width + Math.min(root._labelGap, _hoverLabel.width) : 0
                readonly property real _iconX: root.labelLeads
                    ? _tile.width - root._pad - root.iconSize : root._pad
                width: root.cellWidth + _tile._labelSpan
                height: Metrics.barRowHeight
                anchors.verticalCenter: parent.verticalCenter

                function syncMenuAnchor(): void {
                    // the popup belongs to the icon, so its anchor must not wander with the label width
                    const pt = _tile.mapToItem(null, _tile._iconX + root.iconSize / 2, 0)
                    if (isFinite(pt.x)) _tile.menuAnchorX = pt.x
                }

                Component.onCompleted: _tile.syncMenuAnchor()
                onXChanged: _tile.syncMenuAnchor()
                onYChanged: _tile.syncMenuAnchor()
                on_IconXChanged: _tile.syncMenuAnchor()

                Timer {
                    id: _labelDwell
                    interval: 80
                    onTriggered: _tile._dwelled = true
                }

                Rectangle {
                    id: _hoverCap
                    anchors.fill: parent
                    radius: Metrics.hoverRadiusFor(height)
                    color: _tile.needsAttention ? Theme.withAlpha(Theme.accent, 0.20)
                         : _ma.pressed           ? Theme.barPressed
                         : Theme.barHover
                    opacity: _tile.needsAttention ? _tile.attnPulse
                           : _ma.pressed          ? 1.0
                           : (_iconHover.hovered && ShellSettings.barHoverHighlight) ? 1.0
                           : 0.0
                    visible: opacity > 0.001

                    // attention already has a pulse driver; easing every pulse sample again makes its highlight trail the icon
                    MotionBehavior on opacity {
                        id: _attentionFade
                        gate: !_tile.needsAttention
                        NumberAnimation {
                            duration: _attentionFade.targetValue > 0.5 ? Motion.hoverIn : Motion.hoverOut
                            easing.type: Easing.OutCubic
                        }
                    }
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
                    x: _tile._iconX
                    width: root.iconSize
                    height: root.iconSize
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Math.min(width, height) / 2
                    color: Theme.withAlpha(Theme.barSubtext, 0.12)
                    visible: _tile.fallbackVisible

                    ShellText {
                        anchors.centerIn: parent
                        text: SafeText.initial(_tile.label, "?")
                        color: Theme.barSubtext
                        font.pixelSize: Math.max(9, Math.round(root.iconSize * 0.68))
                    }
                }

                CollapsingText {
                    id: _hoverLabel
                    x: root.labelLeads ? root._pad : root._pad + root.iconSize + Math.min(root._labelGap, width)
                    color: Theme.barSubtext
                    text: SafeText.boundedText(_tile.label, 22)
                    // a name peek, like the clock's date and the workspace names: none of them while hover reveals are off
                    expanded: _tile._dwelled && !root.compact && ShellSettings.valuesOnHover
                        && _tile.label.length > 0 && !TrayMenuState.open
                }

                ShellIcon {
                    id: _icon
                    readonly property bool ready: status === Image.Ready
                    // an app that redraws its icon (an unread count, a sync spinner) sends a new
                    // pixmap url each time; the last frame stays up instead of dipping to nothing
                    property bool _hadImage: false
                    readonly property bool shown: ready || (status === Image.Loading && _hadImage)
                    onStatusChanged: {
                        if (status !== Image.Loading) _hadImage = status === Image.Ready
                        if (status === Image.Error && !_tile._providedIconFailed
                                && _tile._providedIconSource.length > 0)
                            _tile._providedIconFailed = true
                    }
                    side: root.iconSize
                    x: _tile._iconX + (root.iconSize - width) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    // a hidden app can keep animating its icon, and each frame goes through the icon theme loader
                    source: _tile.hidden ? "" : _tile.iconSource
                    // apps reuse an icon url across restarts and updates; a reload must not keep an earlier failed image
                    backer.cache: false
                    backer.retainWhileLoading: true
                    asynchronous: true
                    visible: opacity > 0.01
                    opacity: shown ? 1.0 : 0.0
                    transformOrigin: Item.Center
                    scale: _ma.pressed ? 0.94 : 1.0
                    MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }
                    MotionBehavior on scale   {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                }

                HoverHandler {
                    id: _iconHover
                    enabled: root._canInteract && !_tile.hidden
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
                    enabled: root._canInteract && !_tile.hidden
                    // MouseArea overrides the cursor beneath it, so the pointer shape must live here not on the HoverHandler
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (!root._canInteract || _tile.hidden) return
                        const it = _tile.modelData
                        if (mouse.button === Qt.RightButton)
                            root._openMenu(it, _tile)
                        else if (mouse.button === Qt.MiddleButton)
                            it.secondaryActivate()
                        else root._activateItem(it, _tile)
                    }
                    onWheel: (wheel) => {
                        if (!root._canInteract || _tile.hidden) { wheel.accepted = false; return }
                        wheel.accepted = true
                        const r = Scroll.processTrayWheel(wheel, "tray:" + _tile.modelData.id)
                        if (r.steps !== 0) _tile.modelData.scroll(r.steps * Scroll.notch, r.horizontal)
                    }
                }

            }
        }
    }
}
