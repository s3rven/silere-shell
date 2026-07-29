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
        const setting = meta.setting || ""
        if (setting.length > 0 && ShellSettings[setting] === false) return false
        if (key === "battery" && !Battery.available) return false
        if (key === "brightness" && (!Brightness.toolAvailable || Brightness.maxBrightness <= 0)) return false
        return true
    }
    readonly property var activeKeys: orderKeys.filter(key => zone._widgetEnabled(key))

    // widgets only report real visibility once loaded, so rebuild off the
    // rendered delegates rather than per-key state a reorder can leave stale
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

    onActiveKeysChanged: _queueVisibilitySync()

    Timer {
        id: _visibilitySync
        interval: 0
        onTriggered: zone._syncVisibility()
    }

    Repeater {
        id: widgetRepeater
        // Bind delegates to their keys, not only to the array length. Reusing
        // numeric slots across a same-length reorder can leave a Loader paired
        // with the component that previously occupied that index.
        model: zone.activeKeys
        onItemAdded: zone._queueVisibilitySync()
        onItemRemoved: zone._queueVisibilitySync()
        delegate: Row {
            id: _slot
            required property string modelData
            readonly property string key: modelData
            readonly property bool show: _loader.loadedKey === key
                && (_loader.item ? _loader.item.show : false)
            // per-slot primitives: a placement change invalidates one divider,
            // not a shared object map rebuilt for every widget
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
            // Read the plain `show`, never `.visible` — Item.visible cascades
            // from ancestors, so binding a row's visible to its descendant's is
            // a deadlock.
            visible: key.length > 0 && show
            onShowChanged: zone._queueVisibilitySync()
            Component.onCompleted: zone._queueVisibilitySync()

            Loader {
                id: _loader
                anchors.verticalCenter: parent.verticalCenter
                // Native text often reports fractional implicit widths. Round
                // the slot, otherwise every later 1px divider inherits a
                // different subpixel phase and appears alternately thin/thick.
                width: item ? Math.ceil(item.implicitWidth) : 0
                property string loadedKey: ""
                active: _slot.key.length > 0
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
