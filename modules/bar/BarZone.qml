pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"

// One side of the bar (left or right). The parent anchors it to its edge and
// gives it a height; it owns the ordered widget slots plus their group
// dividers. Left/right differ only by which order-keys array they read, so both
// sides are one instance of this.
Row {
    id: zone

    // The per-zone ordered widget keys (ShellSettings.barWidgetOrder{Left,Right}Keys).
    required property var orderKeys
    // Shared key→Component map, owned by BarContent so the delegates keep its
    // screen/textBudget closures.
    required property var widgetComponents

    readonly property int dotGap: Metrics.widgetGap
    readonly property bool _compact: ShellSettings.barCompact

    spacing: dotGap
    Behavior on spacing { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

    function _widgetEnabled(key: string): bool {
        if (key.length === 0) return false
        const meta = ShellSettings.barWidgetMeta[key]
        if (!meta) return false
        const setting = meta.setting || ""
        return setting.length === 0 || ShellSettings[setting] !== false
    }

    // Order-agnostic divider map: reads each live slot through the Repeater
    // instead of fixed ids, so it holds under any user order. _repRev is bumped
    // as delegates populate (itemAt() can return null before that finishes).
    property int _repRev: 0
    function _computeSeps(rep): var {
        zone._repRev
        const compact = zone._compact
        const n = rep.count
        const s = []
        for (let i = 0; i < n; i++) {
            const it = rep.itemAt(i)
            const k = it ? it.key : ""
            s.push({ key: k, v: it ? it.show : false, g: k ? ShellSettings.barWidgetMeta[k].group : "" })
        }
        const out = {}
        for (let i = 0; i < s.length; i++) {
            const cur = s[i]
            if (!cur.key) continue
            if (!cur.v) { out[cur.key] = false; continue }
            let after = false, sameGroupAfter = false
            for (let j = i + 1; j < s.length; j++) {
                if (!s[j].v) continue
                after = true
                if (!compact) break
                if (s[j].g === cur.g) { sameGroupAfter = true; break }
            }
            out[cur.key] = after && (compact ? !sameGroupAfter : true)
        }
        return out
    }
    readonly property var _seps: _computeSeps(_rep)

    // Fixed integer model sized to the full canonical key count: slots beyond
    // this zone's real membership resolve to an empty key and render nothing.
    // Never torn down on reorder — only the slot whose resolved key changed
    // reloads its Loader.
    Repeater {
        id: _rep
        model: ShellSettings._allBarWidgetKeys.length
        onItemAdded: zone._repRev++

        delegate: Row {
            id: _slot
            required property int index
            readonly property string key: zone.orderKeys[index] || ""
            readonly property bool widgetEnabled: zone._widgetEnabled(key)
            readonly property bool show: _loader.item ? _loader.item.show : false
            height: parent.height
            spacing: zone.dotGap
            // Read the plain `show`, never `.visible` — Item.visible cascades
            // from ancestors, so binding a row's visible to its descendant's is
            // a deadlock.
            visible: key.length > 0 && show

            Loader {
                id: _loader
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: _slot.widgetEnabled ? zone.widgetComponents[_slot.key] : null
            }
            Dot { show: zone._seps[_slot.key] === true }
        }
    }
}
