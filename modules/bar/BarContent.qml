pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import "../../config"
import "../../services"
import "widgets"

Item {
    id: root

    required property ShellScreen screen
    property bool barActive: true

    property bool _autoCompact: false
    readonly property bool effectiveCompact: ShellSettings.barCompact || _autoCompact
    readonly property int gap: Metrics.titleGapFor(effectiveCompact)
    readonly property int titleMinWidth: effectiveCompact ? 72 : 96
    // free span between the groups; the title prefers true center but slides off-center as a group closes in, rather than clamping to symmetric clearance and vanishing while space remains
    readonly property real titleFreeLeft:  leftZone.implicitWidth + gap
    readonly property real titleFreeRight: width - rightZone.implicitWidth - gap
    readonly property real titleAvailableWidth: Math.max(0, titleFreeRight - titleFreeLeft)
    readonly property bool titleHasRoom: titleAvailableWidth >= titleMinWidth

    readonly property bool _compact: effectiveCompact
    readonly property int mediaTextBudget: {
        const base = _compact ? 120 : 160
        if (!ShellSettings.showWindowTitle) return base
        return Math.max(76, Math.min(base, Math.round(width * 0.065)))
    }

    function _queueAutoCompact(): void {
        if (!_compactSync.running) _compactSync.restart()
    }

    function _syncAutoCompact(): void {
        if (ShellSettings.barCompact || !ShellSettings.barAutoCompact || width <= 0) {
            _autoCompact = false
            return
        }

        const sideW = leftZone.implicitWidth + rightZone.implicitWidth
        const reserve = ShellSettings.showWindowTitle ? 116 : 52
        const turnOn = width - reserve
        const turnOff = width - reserve - 72

        if (!_autoCompact && sideW > turnOn)
            _autoCompact = true
        else if (_autoCompact && sideW < turnOff)
            _autoCompact = false
    }

    onWidthChanged: _queueAutoCompact()

    Timer {
        id: _compactSync
        interval: 1
        onTriggered: root._syncAutoCompact()
    }

    Connections {
        target: ShellSettings
        function onBarAutoCompactChanged() { root._queueAutoCompact() }
        function onBarCompactChanged() { root._queueAutoCompact() }
        function onBarSpacingChanged() { root._queueAutoCompact() }
        function onShowWindowTitleChanged() { root._queueAutoCompact() }
        function onValuesOnHoverChanged() { root._queueAutoCompact() }
        function onNetworkSpeedInlineChanged() { root._queueAutoCompact() }
        function onClockShowDateChanged() { root._queueAutoCompact() }
        function onShowSecondsChanged() { root._queueAutoCompact() }
    }

    // one Component per widget kind, chosen per-slot by whichever zone array holds the key; both zones share this map.
    // Pill/Tray/Media widgets bind height straight to root.height instead of a forced-height Loader: a Loader's
    // resize-to-fit stretches the outer item, and a widget sized off a fixed reference (Workspaces' diamond off
    // btnH, not an anchor) then stays pinned to the top instead of recentring.
    Component { id: _cWorkspaces;  Workspaces       { anchors.verticalCenter: parent.verticalCenter; screen: root.screen } }
    Component { id: _cShellUpdate; ShellUpdateWidget { anchors.verticalCenter: parent.verticalCenter; height: root.height; compact: root.effectiveCompact } }
    Component { id: _cTray;        TrayWidget       { anchors.verticalCenter: parent.verticalCenter; height: root.height; screen: root.screen; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cUpdates;     UpdatesWidget    { anchors.verticalCenter: parent.verticalCenter; height: root.height; screen: root.screen; compact: root.effectiveCompact } }
    Component { id: _cNetwork;     NetworkWidget    { anchors.verticalCenter: parent.verticalCenter; height: root.height; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cVolume;      Volume           { anchors.verticalCenter: parent.verticalCenter; height: root.height; screen: root.screen; compact: root.effectiveCompact } }
    Component { id: _cBrightness;  BrightnessWidget { anchors.verticalCenter: parent.verticalCenter; height: root.height; compact: root.effectiveCompact } }
    Component { id: _cBattery;     BatteryWidget    { anchors.verticalCenter: parent.verticalCenter; height: root.height; compact: root.effectiveCompact } }
    Component { id: _cMedia;       MediaWidget      { anchors.verticalCenter: parent.verticalCenter; height: root.height; screen: root.screen; textBudget: root.mediaTextBudget; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cClock;       Clock            { anchors.verticalCenter: parent.verticalCenter; screen: root.screen; compact: root.effectiveCompact } }

    readonly property var _widgetComponents: ({
        workspaces: _cWorkspaces, shellUpdate: _cShellUpdate, tray: _cTray, updates: _cUpdates,
        network: _cNetwork, volume: _cVolume, brightness: _cBrightness, battery: _cBattery,
        media: _cMedia, clock: _cClock
    })

    BarZone {
        id: leftZone
        anchors.left:           parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        orderKeys: ShellSettings.barWidgetOrderLeftKeys
        widgetComponents: root._widgetComponents
        compact: root.effectiveCompact
        onImplicitWidthChanged: root._queueAutoCompact()
    }

    // bar OSD (β) takes one bar center while showing; loaded only on the overlay bar to avoid duplicate layout/anim work on every monitor
    readonly property bool _isOverlayBar: root.screen && root.screen.name === Monitors.overlayBarName
    readonly property bool _onActiveBar: !root.screen || Monitors.activeName === root.screen.name
    readonly property bool _osdBarShowing: ShellSettings.osdEnabled && ShellSettings.osdBarIntegrated
        && root._isOverlayBar && OsdBarState.showing
    readonly property bool _centerVizMode: ShellSettings.mediaVisualizerPosition === "center"
    readonly property bool _centerVizWanted: _centerVizMode && ShellSettings.mediaProgress
        && root.barActive && root._onActiveBar && Media.shown && Media.playing && Media.cavaReady
    readonly property bool _centerVizHasRoom: titleAvailableWidth >= 48
    readonly property bool _centerVizShowing: _centerVizWanted && _centerVizHasRoom && !root._osdBarShowing
    readonly property int _centerVizWidth: Math.round(Math.max(48, Math.min(
        titleAvailableWidth,
        titleAvailableWidth * ShellSettings.mediaVisualizerCenterWidth
    )))
    readonly property real _centerVizTravel: Math.max(0, titleAvailableWidth - _centerVizWidth)
    readonly property int _centerVizX: Math.round(titleFreeLeft
        + _centerVizTravel * ((ShellSettings.mediaVisualizerCenterOffset + 1) / 2))

    Loader {
        id: _wTitle
        anchors.verticalCenter: parent.verticalCenter
        x: Math.round(Math.max(root.titleFreeLeft,
                               Math.min((root.width - width) / 2,
                                        root.titleFreeRight - width)))
        width: item && root.titleHasRoom ? Math.min(item.implicitWidth, root.titleAvailableWidth) : 0
        height: parent.height
        active: ShellSettings.showWindowTitle && root.titleHasRoom
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

        readonly property bool _want: ShellSettings.showWindowTitle && root.titleHasRoom
            && !root._osdBarShowing && !root._centerVizShowing
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
        id: _centerVisualizer
        anchors.verticalCenter: parent.verticalCenter
        x: root._centerVizX
        width: root._centerVizShowing ? root._centerVizWidth : 0
        height: parent.height
        active: root._centerVizWanted && root._centerVizHasRoom
        sourceComponent: Component {
            MediaVisualizer { barName: root.screen ? root.screen.name : "" }
        }
        visible: opacity > 0.001
        opacity: root._centerVizShowing ? 1.0 : 0.0
        scale: root._centerVizShowing ? 1.0 : 0.94
        transformOrigin: Item.Center
        z: 1

        Behavior on x {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic }
        }
        Behavior on width {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }
    }

    Loader {
        anchors.centerIn: parent
        z: 2
        active: ShellSettings.osdEnabled && ShellSettings.osdBarIntegrated && root._isOverlayBar
        sourceComponent: Component { OsdBarWidget {} }
    }

    BarZone {
        id: rightZone
        anchors.right:          parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        orderKeys: ShellSettings.barWidgetOrderRightKeys
        widgetComponents: root._widgetComponents
        compact: root.effectiveCompact
        onImplicitWidthChanged: root._queueAutoCompact()
    }
}
