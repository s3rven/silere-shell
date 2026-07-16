pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"

// one side of the bar; owns the ordered widget slots + group dividers. left/right differ only by which order-keys array they read
Row {
    id: zone

    // The per-zone ordered widget keys (ShellSettings.barWidgetOrder{Left,Right}Keys).
    required property var orderKeys
    // Shared key→Component map, owned by BarContent so the delegates keep its
    // screen/textBudget closures.
    required property var widgetComponents
    property bool compact: ShellSettings.barCompact

    readonly property int dotGap: Metrics.widgetGapFor(compact)
    readonly property bool _compact: compact

    spacing: dotGap
    Behavior on spacing { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

    function _widgetEnabled(key: string): bool {
        if (key.length === 0) return false
        const meta = ShellSettings.barWidgetMeta[key]
        if (!meta) return false
        const setting = meta.setting || ""
        if (setting.length > 0 && ShellSettings[setting] === false) return false
        // Avoid constructing hardware-only widget trees on machines where the
        // capability does not exist. Their services remain live so hotplug or
        // delayed discovery can add the widget later.
        if (key === "battery" && !Battery.available) return false
        if (key === "brightness" && (!Brightness.toolAvailable || Brightness.maxBrightness <= 0)) return false
        return true
    }
    readonly property var activeKeys: orderKeys.filter(key => zone._widgetEnabled(key))

    // order-agnostic divider map: reads live slots through the Repeater (not fixed ids) so it holds under any order. _repRev bumps as delegates populate — itemAt() can return null before that
    property int _repRev: 0
    // single reverse pass: a widget takes a divider when anything visible follows it,
    // except in compact mode where later same-group widgets suppress it (group dividers)
    function _computeSeps(rep): var {
        zone._repRev
        const compact = zone._compact
        const out = {}
        const groupsAfter = {}
        let anyAfter = false
        for (let i = rep.count - 1; i >= 0; i--) {
            const it = rep.itemAt(i)
            if (!it || !it.key) continue
            if (!it.show) { out[it.key] = false; continue }
            const g = ShellSettings.barWidgetMeta[it.key].group
            out[it.key] = anyAfter && (!compact || groupsAfter[g] !== true)
            anyAfter = true
            groupsAfter[g] = true
        }
        return out
    }
    readonly property var _seps: _computeSeps(_rep)

    Repeater {
        id: _rep
        // Bind delegates to their keys, not only to the array length. Reusing
        // numeric slots across a same-length reorder can leave a Loader paired
        // with the component that previously occupied that index.
        model: zone.activeKeys
        onItemAdded: zone._repRev++
        onItemRemoved: zone._repRev++

        delegate: Row {
            id: _slot
            required property string modelData
            readonly property string key: modelData
            readonly property bool widgetEnabled: zone._widgetEnabled(key)
            readonly property bool show: widgetEnabled && _loader.loadedKey === key
                && (_loader.item ? _loader.item.show : false)
            height: parent.height
            spacing: zone.dotGap
            // Read the plain `show`, never `.visible` — Item.visible cascades
            // from ancestors, so binding a row's visible to its descendant's is
            // a deadlock.
            visible: key.length > 0 && show

            Loader {
                id: _loader
                anchors.verticalCenter: parent.verticalCenter
                property string loadedKey: ""
                active: _slot.widgetEnabled && _slot.key.length > 0
                sourceComponent: _slot.key.length > 0 ? zone.widgetComponents[_slot.key] : null
                onSourceComponentChanged: loadedKey = ""
                onActiveChanged: if (!active) loadedKey = ""
                onLoaded: loadedKey = _slot.key
            }
            Dot {
                compact: zone.compact
                show: zone._seps[_slot.key] === true
            }
        }
    }
}
