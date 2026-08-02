pragma ComponentBehavior: Bound

import QtQuick
import "../../services"
import "../common"

Row {
    id: zone

    required property var orderKeys
    required property var widgetComponents
    required property bool compact

    spacing: 0

    function _widgetEnabled(key: string): bool {
        if (key.length === 0) return false
        const meta = ShellSettings.barWidgetMeta[key]
        if (!meta) return false
        if (!ShellSettings.barWidgetConfiguredVisible(key)) return false
        if (key === "battery" && !Battery.available) return false
        if (key === "brightness" && !Brightness.controllable) return false
        if (key === "media" && !Media.shown) return false
        if (key === "shellUpdate"
                && !ShellUpdate.pending && !ShellUpdate.checking && !ShellUpdate.applying) return false
        return true
    }

    // rebuild off the rendered delegates: widgets only report real visibility once loaded, and per-key state goes stale on reorder
    property var _visibleKeys: []
    readonly property var visibleKeys: _visibleKeys

    function _queueVisibilitySync(): void {
        _visibilitySync.restart()
    }

    function _syncVisibility(): void {
        const next = []
        for (let i = 0; i < widgetRepeater.count; i++) {
            const slot = widgetRepeater.itemAt(i)
            if (slot && slot.show && slot.key.length > 0) next.push(slot.key)
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
            readonly property bool show: _loader.loadedKey === key && _loader.item
                && (_loader.item.layoutVisible !== undefined
                    ? _loader.item.layoutVisible
                    : wanted && _loader.item.show)
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
            spacing: 0
            // child visible cascades from this row, so use its non-cascading layout state
            visible: key.length > 0 && show
            onShowChanged: zone._queueVisibilitySync()
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
                onTriggered: _slot.keepLoaded = false
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
                onLoaded: loadedKey = _slot.key
            }

            BarDivider {
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
