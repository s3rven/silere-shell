pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import "../../config"
import "../../services"
import "../common"
import "widgets"

Item {
    id: root

    required property ShellScreen screen

    readonly property int gap:    Metrics.titleGap
    readonly property int dotGap: Metrics.widgetGap
    // Free span between the widget groups. The title prefers the bar's true
    // center but slides off-center as a group closes in, instead of clamping
    // its width to symmetric clearance and vanishing while space remains.
    readonly property real titleFreeLeft:  leftGroup.implicitWidth + gap
    readonly property real titleFreeRight: width - rightGroup.implicitWidth - gap
    readonly property real titleAvailableWidth: Math.max(0, titleFreeRight - titleFreeLeft)

    readonly property bool _compact: ShellSettings.barCompact

    // One Component per widget kind, chosen per-slot by whichever zone array
    // currently holds that slot's key. Both zones share this one map.
    //
    // Widgets whose own implicitHeight formula reads `parent.height` (the
    // Pill-based ones, plus Tray/Media) get an explicit `height: root.height`
    // here instead of leaning on a Loader with a forced height: Loader's
    // "resize the loaded item to fit" behavior (triggered by giving the
    // Loader itself an explicit height) stretches the OUTER item, but a
    // widget whose internal layout positions content by a small fixed
    // reference size (Workspaces' diamond, sized off `btnH`, not an anchor)
    // stays pinned to the top of that stretched box instead of recentring.
    // Binding height straight to `root.height` gets every Pill-based widget
    // the same end result without forcing Workspaces/Clock's own height too.
    Component { id: _cWorkspaces;  Workspaces       { anchors.verticalCenter: parent.verticalCenter; screen: root.screen } }
    Component { id: _cShellUpdate; ShellUpdateWidget { anchors.verticalCenter: parent.verticalCenter; height: root.height } }
    Component { id: _cTray;        TrayWidget       { anchors.verticalCenter: parent.verticalCenter; height: root.height; screen: root.screen } }
    Component { id: _cUpdates;     UpdatesWidget    { anchors.verticalCenter: parent.verticalCenter; height: root.height; screen: root.screen } }
    Component { id: _cNetwork;     NetworkWidget    { anchors.verticalCenter: parent.verticalCenter; height: root.height } }
    Component { id: _cVolume;      Volume           { anchors.verticalCenter: parent.verticalCenter; height: root.height; screen: root.screen } }
    Component { id: _cBrightness;  BrightnessWidget { anchors.verticalCenter: parent.verticalCenter; height: root.height } }
    Component { id: _cBattery;     BatteryWidget    { anchors.verticalCenter: parent.verticalCenter; height: root.height } }
    Component { id: _cMedia;       MediaWidget      { anchors.verticalCenter: parent.verticalCenter; height: root.height; screen: root.screen } }
    Component { id: _cClock;       Clock            { anchors.verticalCenter: parent.verticalCenter; screen: root.screen } }

    readonly property var _widgetComponents: ({
        workspaces: _cWorkspaces, shellUpdate: _cShellUpdate, tray: _cTray, updates: _cUpdates,
        network: _cNetwork, volume: _cVolume, brightness: _cBrightness, battery: _cBattery,
        media: _cMedia, clock: _cClock
    })

    function _widgetEnabled(key: string): bool {
        if (key.length === 0) return false
        const meta = ShellSettings.barWidgetMeta[key]
        if (!meta) return false
        const setting = meta.setting || ""
        return setting.length === 0 || ShellSettings[setting] !== false
    }

    // Order-agnostic: reads each live slot through the Repeater instead of
    // fixed named widget ids, so the divider logic holds under any user order
    // or zone assignment. _repRev is bumped as delegates populate
    // (Repeater.itemAt() can return null before that finishes — see
    // ChoiceChipRow's identical _rev pattern).
    property int _repRev: 0
    function _computeSeps(rep): var {
        root._repRev
        const compact = root._compact
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
    readonly property var _sepsLeft:  _computeSeps(_repLeft)
    readonly property var _sepsRight: _computeSeps(_repRight)

    // ── Left ────────────────────────────────────────────────────────────────
    Row {
        id: leftGroup
        anchors.left:           parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        spacing: root.dotGap
        Behavior on spacing { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

        // Fixed integer model, sized to the full canonical key count: slots
        // beyond the zone's real membership resolve to an empty key and
        // render nothing. Never torn down on reorder/zone changes — only the
        // slot(s) whose resolved key actually changed reload their Loader.
        Repeater {
            id: _repLeft
            model: ShellSettings._allBarWidgetKeys.length
            onItemAdded: root._repRev++

            delegate: Row {
                id: _slotL
                required property int index
                readonly property string key:  ShellSettings.barWidgetOrderLeftKeys[index] || ""
                readonly property bool widgetEnabled: root._widgetEnabled(key)
                readonly property bool   show: _loaderL.item ? _loaderL.item.show : false
                // Matches the row's own height, not derived from children —
                // the widgets themselves carry their own height binding now.
                height: parent.height
                spacing: root.dotGap
                // Read the plain `show` property, never `.visible` — Item.visible
                // cascades from ancestors in Qt Quick, so binding this row's own
                // visible to its descendant's visible is a genuine deadlock (an
                // ancestor cannot resolve its visibility from a child whose
                // effective visibility depends on that same ancestor).
                visible: key.length > 0 && show

                Loader {
                    id: _loaderL
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: _slotL.widgetEnabled ? root._widgetComponents[_slotL.key] : null
                }
                Dot { show: root._sepsLeft[_slotL.key] === true }
            }
        }
    }

    // ── Center ──────────────────────────────────────────────────────────────
    // Bar OSD (β) takes over one bar center while it's showing. Loading it
    // only on the overlay bar avoids duplicate text/layout/animation work on
    // every monitor, including while the feature is disabled.
    readonly property bool _isOverlayBar: root.screen && root.screen.name === Monitors.overlayBarName
    readonly property bool _osdBarShowing: ShellSettings.osdEnabled && ShellSettings.osdBarIntegrated
        && root._isOverlayBar && OsdBarState.showing

    Loader {
        id: _wTitle
        anchors.verticalCenter: parent.verticalCenter
        x: Math.round(Math.max(root.titleFreeLeft,
                               Math.min((root.width - width) / 2,
                                        root.titleFreeRight - width)))
        width: item ? Math.min(item.implicitWidth, root.titleAvailableWidth) : 0
        height: parent.height
        active: ShellSettings.showWindowTitle
        sourceComponent: Component {
            WindowTitle {
                screen: root.screen
                availableWidth: root.titleAvailableWidth
            }
        }
        transformOrigin: Item.Center
        visible: opacity > 0.001

        // No Behavior on x: group widths already animate per-frame (pill
        // reveals), so x follows smoothly by itself; an extra Behavior lags
        // those and made the title drift sideways during title swaps (the
        // width change recomputes x while the new text fades in).

        readonly property bool _want: ShellSettings.showWindowTitle && !root._osdBarShowing
        state: _want ? "shown" : "hidden"

        states: [
            State { name: "shown";  PropertyChanges { _wTitle.opacity: 1.0; _wTitle.scale: 1.0 } },
            State { name: "hidden"; PropertyChanges { _wTitle.opacity: 0.0; _wTitle.scale: 0.92 } }
        ]
        transitions: [
            Transition {
                to: "shown"
                SequentialAnimation {
                    // wait for OSD exit to finish before revealing
                    PauseAnimation  { duration: Motion.fast }
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; duration: Motion.normal; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "scale";   duration: Motion.normal; easing.type: Easing.OutCubic }
                    }
                }
            },
            Transition {
                to: "hidden"
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; duration: Motion.fast; easing.type: Easing.InCubic }
                    NumberAnimation { property: "scale";   duration: Motion.fast; easing.type: Easing.InCubic }
                }
            }
        ]
    }

    Loader {
        anchors.centerIn: parent
        z: 1
        active: ShellSettings.osdEnabled && ShellSettings.osdBarIntegrated && root._isOverlayBar
        sourceComponent: Component { OsdBarWidget {} }
    }

    // ── Right ────────────────────────────────────────────────────────────────
    Row {
        id: rightGroup
        anchors.right:          parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        spacing: root.dotGap
        Behavior on spacing { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

        Repeater {
            id: _repRight
            model: ShellSettings._allBarWidgetKeys.length
            onItemAdded: root._repRev++

            delegate: Row {
                id: _slotR
                required property int index
                readonly property string key:  ShellSettings.barWidgetOrderRightKeys[index] || ""
                readonly property bool widgetEnabled: root._widgetEnabled(key)
                readonly property bool   show: _loaderR.item ? _loaderR.item.show : false
                height: parent.height
                spacing: root.dotGap
                visible: key.length > 0 && show

                Loader {
                    id: _loaderR
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: _slotR.widgetEnabled ? root._widgetComponents[_slotR.key] : null
                }
                Dot { show: root._sepsRight[_slotR.key] === true }
            }
        }
    }
}
