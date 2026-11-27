pragma ComponentBehavior: Bound

import QtQuick
import "../../services"
import "../common"

Row {
    id: zone

    required property var orderKeys
    required property var widgetComponents
    required property bool compact
    property real textFitScale: 1


    // the pointer anywhere over the zone holds its widgets' hover details open: one closing as the pointer moved on slid
    // its neighbours out from under it, and aimed at a neighbour's centre, two moves in three landed on the next one over;
    // not readonly, so a test can stand in for the pointer, which synthetic moves cannot reach reliably under load
    property bool pointerInside: _zoneHover.hovered || _leaveGrace.running
    HoverHandler {
        id: _zoneHover
        onHoveredChanged: if (hovered) _leaveGrace.stop(); else _leaveGrace.restart()
    }
    // a dip below the bar and straight back finds the details as they were, instead of folding and reopening them
    Timer { id: _leaveGrace; interval: 200 }
    // a popup opened from here takes the pointer (Hyprland's grab lets only the popup hear it), and the details folding
    // then shifted the whole zone sideways under it as it faded in; they wait for it to close instead
    property bool _popupHold: false
    Connections {
        target: OverlayCoordinator
        function onAnyOpenChanged() { zone._popupHold = OverlayCoordinator.anyOpen && zone.pointerInside }
    }
    readonly property bool holding: zone.pointerInside || zone._popupHold
    // settling on a widget closes the details left behind, unless one folding would slide that widget out from under the
    // pointer: in a zone hung from the right, a detail folding moves everything left of it (battery to brightness: 64 px,
    // onto Wi-Fi). Those stay open until the pointer leaves the zone
    property int anchoredAt: Qt.AlignLeft
    property var _heldKeys: []
    function _indexOf(key: string): int {
        for (let i = 0; i < widgetRepeater.count; i++) if (widgetRepeater.itemAt(i)?.key === key) return i
        return -1
    }
    function claimHold(key: string): void {
        const at = zone._indexOf(key)
        zone._heldKeys = zone._heldKeys.filter(k => k !== key && (zone.anchoredAt === Qt.AlignRight ? zone._indexOf(k) > at
            : zone.anchoredAt === Qt.AlignLeft ? zone._indexOf(k) < at : true)).concat([key])
    }
    onHoldingChanged: if (!holding) zone._heldKeys = []

    function _widgetEnabled(key: string): bool {
        if (key.length === 0) return false
        const meta = ShellSettings.barWidgetMeta[key]
        if (!meta) return false
        if (!ShellSettings.barWidgetConfiguredVisible(key)) return false
        if (key === "battery" && !Battery.available && !Battery.lowPeripheral) return false
        if (key === "bluetooth" && !Bluetooth.available) return false
        if (key === "keyboard" && !InputState.available) return false
        if (key === "system" && !SysInfo.monitorHasReadings) return false
        if (key === "brightness" && !Brightness.controllable && !DisplayBrightness.hasControl) return false
        if (key === "media" && !Media.shown) return false
        if (key === "indicators" && Indicators.items.length === 0) return false
        if (key === "shellUpdate"
                && !ShellUpdate.pending && !ShellUpdate.checking && !ShellUpdate.applying) return false
        return true
    }

    // the widgets loaded with the zone arrive with the bar; only one switched on or moved here later unfolds
    property bool _built: false
    Component.onCompleted: Qt.callLater(() => { if (zone) zone._built = true })

    // rebuild off the rendered delegates: widgets only report real visibility once loaded, and per-key state goes stale on reorder
    property var _visibleKeys: []
    readonly property var visibleKeys: _visibleKeys

    // never read the fitted widths here: this feeds the budget that fits them
    readonly property var widthMetrics: {
        void zone.visibleKeys
        let fixed = 0, flexible = 0, pendingWidth = 0
        for (let i = 0; i < widgetRepeater.count; i++) {
            const slot = widgetRepeater.itemAt(i)
            if (!slot || (slot.flexible ? slot.flexibleWidth <= 0 : !slot.show)) continue
            fixed += slot.fixedWidth
            flexible += slot.flexibleWidth
            pendingWidth += slot.pendingWidth
        }
        return { fixed: fixed, flexible: flexible, pendingWidth: pendingWidth }
    }
    // what the system monitor's width budget leaves out, apart from widthMetrics: that one also adds up the monitor's
    // own width, which follows the budget, so reading it there looped on every resize while the bar mapped
    readonly property var budgetMetrics: {
        void zone.visibleKeys
        let fixed = 0, occupied = false
        for (let i = 0; i < widgetRepeater.count; i++) {
            const slot = widgetRepeater.itemAt(i)
            if (!slot || (slot.flexible ? slot.flexibleWidth <= 0 : !slot.show)) continue
            occupied = true
            fixed += slot.key === "system" ? slot.dividerWidth : slot.fixedWidth
        }
        return { fixedWithoutMonitor: fixed, occupied: occupied }
    }

    function _queueVisibilitySync(): void {
        _visibilitySync.restart()
    }

    function _syncVisibility(): void {
        const next = []
        for (let i = 0; i < widgetRepeater.count; i++) {
            const slot = widgetRepeater.itemAt(i)
            if (slot && slot.contentShown && slot.key.length > 0) next.push(slot.key)
        }

        if (next.length === zone._visibleKeys.length
                && next.every((key, i) => key === zone._visibleKeys[i])) return
        zone._visibleKeys = next
    }

    onOrderKeysChanged: _queueVisibilitySync()

    Timer {
        id: _visibilitySync
        interval: 0
        onTriggered: zone._syncVisibility()
    }

    Repeater {
        id: widgetRepeater
        // keep the model stable so transient state only unloads its own widget
        model: zone.orderKeys
        onItemAdded: zone._queueVisibilitySync()
        onItemRemoved: zone._queueVisibilitySync()
        delegate: Row {
            id: _slot
            required property string modelData
            readonly property string key: modelData
            readonly property bool wanted: zone._widgetEnabled(key)
            property bool keepLoaded: false
            readonly property bool widthClosing: _loader.item?.collapsed === true && _loader.width > 0
            readonly property bool show: _loader.loadedKey === key && _loader.item
                && (widthClosing || (_loader.item.layoutVisible !== undefined
                    ? _loader.item.layoutVisible
                    : wanted && _loader.item.show))
            // a widget can keep its reserved width while its own content already faded out;
            // divider placement follows content, not a lingering width-collapse animation. Without its own
            // content flag a widget's target state stands in: its layout stays visible until the fold ends,
            // and the divider then left the bar in one step after the pill had slid shut
            readonly property bool contentShown: _loader.loadedKey === key && _loader.item
                && (_loader.item.contentVisible !== undefined ? _loader.item.contentVisible
                    : _loader.item.show !== undefined ? wanted && _loader.item.show
                    : show)
            readonly property bool flexible: key === "windowTitle" || key === "media"
            readonly property real flexibleWidth: flexible && _loader.item
                ? Math.ceil(_loader.item.preferredWidth) : 0
            readonly property real dividerWidth: _divider.implicitWidth
            readonly property real fixedWidth: dividerWidth + (flexible ? 0 : _loader.width)
            readonly property real pendingWidth: flexible ? 0
                : Math.ceil(_loader.item?.layoutWidthTarget ?? _loader.width) - _loader.width
            // per-slot primitives so a placement change invalidates one divider, not a map rebuilt for every widget
            readonly property int visibleIndex: zone.visibleKeys.indexOf(key)
            readonly property bool hasNext: visibleIndex >= 0
                && visibleIndex + 1 < zone.visibleKeys.length
            readonly property string nextKey: hasNext
                ? zone.visibleKeys[visibleIndex + 1] : ""
            readonly property var currentMeta: ShellSettings.barWidgetMeta[key] ?? null
            readonly property var nextMeta: ShellSettings.barWidgetMeta[nextKey] ?? null
            readonly property bool groupBreak: hasNext
                && currentMeta !== null && nextMeta !== null
                && currentMeta.group !== nextMeta.group
            height: parent.height
            // child visible cascades from this row, so use its non-cascading layout state
            visible: key.length > 0 && show
            onShowChanged: zone._queueVisibilitySync()
            onContentShownChanged: zone._queueVisibilitySync()
            onWantedChanged: {
                if (wanted) {
                    _unload.stop()
                    keepLoaded = true
                } else if (keepLoaded) {
                    _unload.restart()
                }
            }
            Component.onCompleted: {
                keepLoaded = wanted
                zone._queueVisibilitySync()
            }

            Timer {
                id: _unload
                interval: 300
                onTriggered: {
                    if (_slot.widthClosing) restart()
                    else _slot.keepLoaded = false
                }
            }

            Loader {
                id: _loader
                anchors.verticalCenter: parent.verticalCenter
                // round the slot: fractional implicit widths give every later 1px divider a different subpixel phase
                width: item ? Math.ceil(item.implicitWidth) : 0
                property string loadedKey: ""
                active: _slot.keepLoaded && _slot.key.length > 0
                sourceComponent: _slot.key.length > 0 ? zone.widgetComponents[_slot.key] : null
                onSourceComponentChanged: loadedKey = ""
                onActiveChanged: if (!active) loadedKey = ""
                onLoaded: {
                    loadedKey = _slot.key
                    // a reorder rebuilds every slot; only a widget that was not on show here unfolds
                    if (zone._built && zone._visibleKeys.indexOf(_slot.key) < 0
                            && typeof item.unfold === "function") item.unfold()
                }
            }

            Binding {
                target: _loader.item && _loader.item.holdOpen !== undefined ? _loader.item : null
                property: "holdOpen"
                value: zone.holding && zone._heldKeys.indexOf(_slot.key) >= 0
            }
            // settled on, not passed over on the way to another: the claim waits as long as a reveal does
            HoverHandler {
                id: _slotHover
                onHoveredChanged: if (hovered) _claimDwell.restart(); else _claimDwell.stop()
            }
            Timer { id: _claimDwell; interval: 80; onTriggered: zone.claimHold(_slot.key) }
            // a quick click opens its popup before the dwell ends; the detail under it is the one to keep
            Connections {
                target: OverlayCoordinator
                function onAnyOpenChanged() { if (OverlayCoordinator.anyOpen && _slotHover.hovered) zone.claimHold(_slot.key) }
            }

            Binding {
                target: _slot.flexible ? _loader.item : null
                property: "layoutWidthLimit"
                value: Math.floor(_slot.flexibleWidth * zone.textFitScale)
                when: _slot.flexible && _loader.item !== null
            }

            BarDivider {
                id: _divider
                compact: zone.compact
                hasNext: _slot.hasNext
                marked: _slot.hasNext
                    && (ShellSettings.barSeparatorMode === "widgets"
                        || _slot.groupBreak)
                groupBreak: _slot.groupBreak
            }
        }
    }

}
