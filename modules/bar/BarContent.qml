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
    readonly property bool _vUpdates: Updates.available || Updates.isChecking
    readonly property bool _vNetwork: ShellSettings.barShowNetwork
        && (!Network.toolAvailable || Network.available)
    readonly property bool _vBright:  Brightness.maxBrightness > 0
    readonly property bool _vBattery: ShellSettings.barShowBattery && Battery.available
        && !(ShellSettings.batteryAutoHide && (Battery.charging || Battery.full))
    readonly property bool _vMedia:   mediaWidget.show
    readonly property bool _vClock:   ShellSettings.barShowClock

    // slot order: shell · tray · updates network · vol bri battery · media · clock
    readonly property var _seps: {
        const compact = root._compact
        const s = [
            { key: "shell",   v: shellUpdateWidget._show, g: "shell"  },
            { key: "tray",    v: trayWidget.show,         g: "tray"   },
            { key: "updates", v: root._vUpdates,          g: "status" },
            { key: "network", v: root._vNetwork,          g: "status" },
            { key: "volume",  v: true,                    g: "levels" },
            { key: "bright",  v: root._vBright,           g: "levels" },
            { key: "battery", v: root._vBattery,          g: "levels" },
            { key: "media",   v: root._vMedia,            g: "media"  },
            { key: "clock",   v: root._vClock,            g: "clock"  }
        ]
        const out = {}
        for (let i = 0; i < s.length; i++) {
            const cur = s[i]
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

    // ── Left ────────────────────────────────────────────────────────────────
    Row {
        id: leftGroup
        anchors.left:           parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        spacing: root.dotGap
        Behavior on spacing { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

        Workspaces {
            anchors.verticalCenter: parent.verticalCenter
            screen: root.screen
        }

    }


    // ── Center ──────────────────────────────────────────────────────────────
    // Bar OSD (β) takes over one bar center while it's showing. Loading it
    // only on the overlay bar avoids duplicate text/layout/animation work on
    // every monitor, including while the feature is disabled.
    readonly property bool _isOverlayBar: root.screen && root.screen.name === Monitors.overlayBarName
    readonly property bool _osdBarShowing: ShellSettings.osdBarIntegrated
        && root._isOverlayBar && OsdBarState.showing

    WindowTitle {
        id: _wTitle
        anchors.verticalCenter: parent.verticalCenter
        x: Math.round(Math.max(root.titleFreeLeft,
                               Math.min((root.width - width) / 2,
                                        root.titleFreeRight - width)))
        screen: root.screen
        width:   Math.min(implicitWidth, root.titleAvailableWidth)
        availableWidth: root.titleAvailableWidth
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
        active: ShellSettings.osdBarIntegrated && root._isOverlayBar
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

        ShellUpdateWidget { id: shellUpdateWidget; anchors.verticalCenter: parent.verticalCenter }
        Dot             { show: root._seps.shell }
        TrayWidget      { id: trayWidget; anchors.verticalCenter: parent.verticalCenter; screen: root.screen }
        Dot             { show: root._seps.tray }
        UpdatesWidget   { anchors.verticalCenter: parent.verticalCenter; screen: root.screen }
        Dot             { show: root._seps.updates }
        NetworkWidget   { anchors.verticalCenter: parent.verticalCenter }
        Dot             { show: root._seps.network }
        Volume          { anchors.verticalCenter: parent.verticalCenter; screen: root.screen }
        Dot             { show: root._seps.volume }
        BrightnessWidget{ anchors.verticalCenter: parent.verticalCenter }
        Dot             { show: root._seps.bright }
        BatteryWidget   { anchors.verticalCenter: parent.verticalCenter }
        Dot             { show: root._seps.battery }
        MediaWidget     { id: mediaWidget; anchors.verticalCenter: parent.verticalCenter; screen: root.screen }
        Dot             { show: root._seps.media }
        Clock           { visible: root._vClock; anchors.verticalCenter: parent.verticalCenter; screen: root.screen }
    }
}
