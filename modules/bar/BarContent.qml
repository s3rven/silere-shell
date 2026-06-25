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

    readonly property int gap:    ShellSettings.barCompact ? 7 : 10
    readonly property int dotGap: ShellSettings.barCompact
        ? Math.max(3, ShellSettings.barSpacing - 6)
        : ShellSettings.barSpacing
    // Free span between the widget groups. The title prefers the bar's true
    // center but slides off-center as a group closes in, instead of clamping
    // its width to symmetric clearance and vanishing while space remains.
    readonly property real titleFreeLeft:  leftGroup.implicitWidth + gap
    readonly property real titleFreeRight: width - rightGroup.implicitWidth - gap
    readonly property real titleAvailableWidth: Math.max(0, titleFreeRight - titleFreeLeft)

    // Each separator is owned by the widget on its LEFT and shows only while that
    // widget shows, so a hidden widget takes its divider with it — never a leading,
    // trailing, or doubled dot. Volume is always present.
    // Compact (β) keeps the same scan order but uses tighter pill spacing and
    // only marks semantic group edges:
    // [updates network] · [vol bri battery] · [media] · [clock]
    readonly property bool _compact: ShellSettings.barCompact
    readonly property bool _vUpdates: Updates.available || Updates.isChecking
    readonly property bool _vNetwork: !Network.toolAvailable || Network.available
    readonly property bool _vBright:  Brightness.maxBrightness > 0
    readonly property bool _vBattery: Battery.available
        && !(ShellSettings.batteryAutoHide && (Battery.charging || Battery.full))
    readonly property bool _vMedia:   mediaWidget.show

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
        Dot             { show: shellUpdateWidget._show }   // own group: shell self-update activity
        TrayWidget      { id: trayWidget; anchors.verticalCenter: parent.verticalCenter; screen: root.screen }
        Dot             { show: trayWidget.show }   // tray stays its own group, even compact
        UpdatesWidget   { anchors.verticalCenter: parent.verticalCenter; screen: root.screen }
        Dot             { show: root._vUpdates && !root._compact }   // intra-group: fuses with network
        NetworkWidget   { anchors.verticalCenter: parent.verticalCenter }
        // Status group trailing dot. Compact fuses [updates network], so this
        // marks the group boundary whenever *either* member shows — not just
        // network — or a hidden network would drop the whole group's divider.
        Dot             { show: root._compact ? (root._vUpdates || root._vNetwork) : root._vNetwork }
        Volume          { anchors.verticalCenter: parent.verticalCenter; screen: root.screen }
        Dot             { show: !root._compact }                     // intra-group: fuses with brightness
        BrightnessWidget{ anchors.verticalCenter: parent.verticalCenter }
        // Levels group trailing dot. Non-compact: shows when bri is present.
        // Compact: hide when battery follows (battery's own dot marks the group
        // boundary instead); show only when bri is present but battery is absent.
        Dot             { show: root._vBright && (!root._compact || !root._vBattery) }
        BatteryWidget   { anchors.verticalCenter: parent.verticalCenter }
        Dot             { show: root._vBattery }
        MediaWidget     { id: mediaWidget; anchors.verticalCenter: parent.verticalCenter; screen: root.screen }
        Dot             { show: root._vMedia }
        Clock           { anchors.verticalCenter: parent.verticalCenter; screen: root.screen }
    }
}
