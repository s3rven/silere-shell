pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import "../../config"
import "../../services"
import "widgets"

Item {
    id: root

    required property ShellScreen screen

    readonly property int gap: Metrics.titleGap
    // Free span between the widget groups. The title prefers the bar's true
    // center but slides off-center as a group closes in, instead of clamping
    // its width to symmetric clearance and vanishing while space remains.
    readonly property real titleFreeLeft:  leftZone.implicitWidth + gap
    readonly property real titleFreeRight: width - rightZone.implicitWidth - gap
    readonly property real titleAvailableWidth: Math.max(0, titleFreeRight - titleFreeLeft)
    readonly property bool titleHasRoom: titleAvailableWidth >= 96

    readonly property bool _compact: ShellSettings.barCompact
    readonly property int mediaTextBudget: {
        const base = _compact ? 120 : 160
        if (!ShellSettings.showWindowTitle) return base
        return Math.max(76, Math.min(base, Math.round(width * 0.065)))
    }

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
    Component { id: _cMedia;       MediaWidget      { anchors.verticalCenter: parent.verticalCenter; height: root.height; screen: root.screen; textBudget: root.mediaTextBudget } }
    Component { id: _cClock;       Clock            { anchors.verticalCenter: parent.verticalCenter; screen: root.screen } }

    readonly property var _widgetComponents: ({
        workspaces: _cWorkspaces, shellUpdate: _cShellUpdate, tray: _cTray, updates: _cUpdates,
        network: _cNetwork, volume: _cVolume, brightness: _cBrightness, battery: _cBattery,
        media: _cMedia, clock: _cClock
    })

    // ── Left ────────────────────────────────────────────────────────────────
    BarZone {
        id: leftZone
        anchors.left:           parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        orderKeys: ShellSettings.barWidgetOrderLeftKeys
        widgetComponents: root._widgetComponents
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
        width: item && root.titleHasRoom ? Math.min(item.implicitWidth, root.titleAvailableWidth) : 0
        height: parent.height
        active: ShellSettings.showWindowTitle
        sourceComponent: Component {
            WindowTitle {
                screen: root.screen
                availableWidth: root.titleHasRoom ? root.titleAvailableWidth : 0
            }
        }
        transformOrigin: Item.Center
        visible: opacity > 0.001

        // No Behavior on x: group widths already animate per-frame (pill
        // reveals), so x follows smoothly by itself; an extra Behavior lags
        // those and made the title drift sideways during title swaps (the
        // width change recomputes x while the new text fades in).

        readonly property bool _want: ShellSettings.showWindowTitle && root.titleHasRoom && !root._osdBarShowing
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
    BarZone {
        id: rightZone
        anchors.right:          parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        orderKeys: ShellSettings.barWidgetOrderRightKeys
        widgetComponents: root._widgetComponents
    }
}
