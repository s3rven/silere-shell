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

    Repeater {
        id: _rep
        model: zone.activeKeys.length
        onItemAdded: zone._repRev++
        onItemRemoved: zone._repRev++

        delegate: Row {
            id: _slot
            required property int index
            readonly property string key: zone.activeKeys[index] || ""
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
