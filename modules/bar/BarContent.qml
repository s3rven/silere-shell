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
    property real fitWidth: 0

    property bool _autoCompact: false
    property real _expandedWidthEstimate: 0
    property real _lastCompactWidth: 0
    readonly property bool effectiveCompact: ShellSettings.barCompact || _autoCompact
    readonly property int gap: Metrics.titleGapFor(effectiveCompact)
    readonly property bool centerHasWidgets: centerZone.implicitWidth > 0.5
    readonly property real _widgetLayoutWidth: centerHasWidgets
        ? centerZone.implicitWidth
            + 2 * Math.max(leftZone.implicitWidth, rightZone.implicitWidth)
            + gap * 2
        : leftZone.implicitWidth + rightZone.implicitWidth + gap
    readonly property real _osdLayoutWidth: _osdBarShowing && _osdLoader.item
        ? _osdLoader.item.implicitWidth
            + 2 * Math.max(leftZone.implicitWidth, rightZone.implicitWidth)
            + gap * 2
        : 0
    readonly property real minimumSurfaceWidth:
        Math.max(_widgetLayoutWidth, _osdLayoutWidth) + Settings.hPad * 2
    readonly property int titleMinWidth: effectiveCompact ? 72 : 96
    readonly property real titleFreeLeft:  leftZone.implicitWidth + gap
    readonly property real titleFreeRight: width - rightZone.implicitWidth - gap
    readonly property real titleAvailableWidth: Math.max(0, titleFreeRight - titleFreeLeft)
    readonly property bool titleHasRoom: !centerHasWidgets
        && titleAvailableWidth >= titleMinWidth

    property real titleAnchor: ShellSettings.windowTitleCenterGap
        ? (titleFreeLeft + titleFreeRight) / 2
        : width / 2
    MotionBehavior on titleAnchor {
        NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic }
    }

    readonly property bool _compact: effectiveCompact
    readonly property int mediaTextBudget: {
        const base = _compact ? 120 : 160
        if (!ShellSettings.showWindowTitle || centerHasWidgets) return base
        return Math.max(76, Math.min(base, Math.round(width * 0.065)))
    }

    function _queueAutoCompact(): void {
        _compactSync.restart()
    }

    function _syncAutoCompact(): void {
        if (ShellSettings.barCompact || !ShellSettings.barAutoCompact || width <= 0) {
            _autoCompact = false
            _expandedWidthEstimate = 0
            _lastCompactWidth = 0
            _compactModeSettle.stop()
            return
        }

        const layoutW = centerHasWidgets
            ? _widgetLayoutWidth
            : leftZone.implicitWidth + rightZone.implicitWidth
                + (ShellSettings.showWindowTitle ? 116 : 52)
        const span = fitWidth > 0 ? Math.min(fitWidth, width) : width
        const capacity = span

        if (!_autoCompact) {
            _expandedWidthEstimate = layoutW
            _lastCompactWidth = 0
            if (layoutW > capacity) {
                _autoCompact = true
                _compactModeSettle.restart()
            }
            return
        }

        if (_compactModeSettle.running) {
            _lastCompactWidth = layoutW
            return
        }

        if (_lastCompactWidth > 0) {
            const delta = layoutW - _lastCompactWidth
            _expandedWidthEstimate = Math.max(layoutW,
                _expandedWidthEstimate + delta)
        }
        _lastCompactWidth = layoutW

        if (_expandedWidthEstimate < capacity - 56) {
            _autoCompact = false
            _lastCompactWidth = 0
        }
    }

    onWidthChanged: _queueAutoCompact()
    onFitWidthChanged: _queueAutoCompact()

    Timer {
        id: _compactSync
        interval: 24
        onTriggered: root._syncAutoCompact()
    }

    Timer {
        id: _compactModeSettle
        interval: Motion.width + 20
        onTriggered: root._queueAutoCompact()
    }

    Connections {
        target: ShellSettings
        function onBarAutoCompactChanged() { root._queueAutoCompact() }
        function onBarCompactChanged() { root._queueAutoCompact() }
        function onShowWindowTitleChanged() { root._queueAutoCompact() }
    }

    // widgets bind height to root.height, not a forced-height Loader - Loader resize-to-fit mis-centres the diamond
    Component { id: _cWorkspaces;  Workspaces       { anchors.verticalCenter: parent.verticalCenter; screen: root.screen; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cShellUpdate; ShellUpdateWidget { anchors.verticalCenter: parent.verticalCenter; height: root.height; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cTray;        TrayWidget       { anchors.verticalCenter: parent.verticalCenter; height: root.height; screen: root.screen; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cUpdates;     UpdatesWidget    { anchors.verticalCenter: parent.verticalCenter; height: root.height; screen: root.screen; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cNetwork;     NetworkWidget    { anchors.verticalCenter: parent.verticalCenter; height: root.height; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cVolume;      Volume           { anchors.verticalCenter: parent.verticalCenter; height: root.height; compact: root.effectiveCompact } }
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

    readonly property bool _isOverlayBar: root.screen && root.screen.name === Monitors.overlayBarName
    readonly property bool _onActiveBar: !root.screen || Monitors.activeName === root.screen.name
    readonly property bool _osdBarShowing: ShellSettings.osdEnabled && ShellSettings.osdBarIntegrated
        && root._isOverlayBar && OsdBarState.showing && !OsdBarState.barConcealed
    readonly property bool _centerVizMode: ShellSettings.mediaVisualizerPosition === "center"
    readonly property bool _centerVizWanted: _centerVizMode && ShellSettings.mediaProgress
        && !ShellSettings.reduceMotion && !Idle.isIdle
        && root.barActive && root._onActiveBar && Media.shown && Media.playing && Media.cavaReady
    readonly property bool _centerVizHasRoom: titleAvailableWidth >= 48
    readonly property bool _centerVizShowing: _centerVizWanted && _centerVizHasRoom
        && !root.centerHasWidgets && !root._osdBarShowing
    readonly property int _centerVizWidth: Math.round(Math.max(48, Math.min(560,
        titleAvailableWidth,
        titleAvailableWidth * 0.68
    )))
    readonly property real _centerVizTravel: Math.max(0, titleAvailableWidth - _centerVizWidth)
    readonly property int _centerVizX: Math.round(titleFreeLeft + _centerVizTravel / 2)

    Loader {
        id: _wTitle
        anchors.verticalCenter: parent.verticalCenter
        x: Math.round(Math.max(root.titleFreeLeft,
                               Math.min(root.titleAnchor - width / 2,
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

        // no Behavior on x: titleAnchor already eases, and animating x too drifts the title sideways as new text fades in

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
                enabled: !ShellSettings.reduceMotion
                SequentialAnimation {
                    PauseAnimation  { duration: Motion.fast }
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; duration: Motion.normal; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "scale";   duration: Motion.normal; easing.type: Easing.OutCubic }
                    }
                }
            },
            Transition {
                to: "hidden"
                enabled: !ShellSettings.reduceMotion
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; duration: Motion.fast; easing.type: Easing.InCubic }
                    NumberAnimation { property: "scale";   duration: Motion.fast; easing.type: Easing.InCubic }
                }
            }
        ]
    }

    BarZone {
        id: centerZone
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        orderKeys: ShellSettings.barWidgetOrderCenterKeys
        widgetComponents: root._widgetComponents
        compact: root.effectiveCompact
        opacity: root._osdBarShowing ? 0 : 1
        visible: opacity > 0.001
        onImplicitWidthChanged: root._queueAutoCompact()

        MotionBehavior on opacity {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }
    }

    Loader {
        id: _centerVisualizer
        anchors.verticalCenter: parent.verticalCenter
        x: root._centerVizX
        width: root._centerVizWidth
        height: parent.height
        active: root._centerVizWanted && root._centerVizHasRoom
            && !root.centerHasWidgets
        sourceComponent: Component {
            MediaVisualizer {
                barName: root.screen ? root.screen.name : ""
                presentationActive: root._centerVizShowing
                lowPower: root.effectiveCompact || root._centerVizWidth < 260
            }
        }
        visible: opacity > 0.001
        opacity: root._centerVizShowing ? 1.0 : 0.0
        scale: root._centerVizShowing ? 1.0 : 0.94
        transformOrigin: Item.Center
        z: 1

        MotionBehavior on x {
            NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic }
        }
        MotionBehavior on opacity {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }
        MotionBehavior on scale {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }
    }

    Loader {
        id: _osdLoader
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
