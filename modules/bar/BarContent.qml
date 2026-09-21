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
        ? ShellSettings.barCenterInGap
            ? leftZone.implicitWidth + centerZone.implicitWidth
                + rightZone.implicitWidth + gap * 2
            : centerZone.implicitWidth
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
    readonly property real titleFreeLeft:  leftZone.implicitWidth + gap
    readonly property real titleFreeRight: width - rightZone.implicitWidth - gap
    readonly property real titleAvailableWidth: Math.max(0, titleFreeRight - titleFreeLeft)

    // animate the axis, not the zone's x: a title resize recentres at once while a
    // side-widget change still carries the whole middle group
    property real centerAxis: ShellSettings.barCenterInGap
        ? (titleFreeLeft + titleFreeRight) / 2 : width / 2
    // only the gap axis needs easing; width/2 rides the surface's own morph
    MotionBehavior on centerAxis {
        gate: ShellSettings.barCenterInGap
        NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic }
    }

    readonly property bool _compact: effectiveCompact

    readonly property int mediaTextBudget: _compact ? 120 : Metrics.mediaTrackWidth
    // the configured span, not the grown one: the title feeds the width it would measure against
    readonly property real titleWidthBudget: fitWidth > 0 ? fitWidth : 0

    function _queueAutoCompact(): void {
        _compactSync.restart()
    }

    // an empty centre still has to leave the window title somewhere to sit
    readonly property int _bareCenterReserve: 52
    // room the expanded layout must regain before compact is given up, so a bar sitting
    // on the threshold does not flip on every widget that changes a digit
    readonly property int _expandMargin: 56

    function _clearCompactMeasure(): void {
        _autoCompact = false
        _expandedWidthEstimate = 0
        _lastCompactWidth = 0
    }

    // Compact cannot measure what it is hiding: the expanded layout only exists while the
    // bar is expanded. So it is captured on the way in and then carried by the change in
    // compact width, never re-read directly.
    function _syncAutoCompact(): void {
        if (ShellSettings.barCompact || !ShellSettings.barAutoCompact || width <= 0) {
            _clearCompactMeasure()
            _compactModeSettle.stop()
            return
        }

        const layoutW = centerHasWidgets ? _widgetLayoutWidth
            : leftZone.implicitWidth + rightZone.implicitWidth + _bareCenterReserve
        const capacity = fitWidth > 0 ? Math.min(fitWidth, width) : width

        if (!_autoCompact) {
            _expandedWidthEstimate = layoutW
            _lastCompactWidth = 0
            if (layoutW > capacity) {
                _autoCompact = true
                _compactModeSettle.restart()
            }
            return
        }

        // mid-transition widths are the animation, not the layout
        if (_compactModeSettle.running) {
            _lastCompactWidth = layoutW
            return
        }

        if (_lastCompactWidth > 0)
            _expandedWidthEstimate = Math.max(layoutW,
                _expandedWidthEstimate + (layoutW - _lastCompactWidth))
        _lastCompactWidth = layoutW

        if (_expandedWidthEstimate < capacity - _expandMargin) _clearCompactMeasure()
    }

    onWidthChanged: _queueAutoCompact()
    onFitWidthChanged: _queueAutoCompact()

    // entering or leaving the centre swaps _widgetLayoutWidth to the other formula, and
    // the delta estimate below would bank that step as if the content had resized
    readonly property string layoutSignature: leftZone.visibleKeys.join(",")
        + "/" + centerZone.visibleKeys.join(",") + "/" + rightZone.visibleKeys.join(",")
    // settle first: a widget mid-move is briefly counted in both zones
    onLayoutSignatureChanged: if (root._autoCompact) _layoutSettle.restart()

    Timer {
        id: _layoutSettle
        interval: Motion.width + 40
        onTriggered: root._remeasureAutoCompact()
    }

    function _remeasureAutoCompact(): void {
        if (!_autoCompact) return
        _clearCompactMeasure()
        _compactModeSettle.stop()
        _queueAutoCompact()
    }

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
        function onBarCenterInGapChanged() { root._queueAutoCompact() }
        function onShowWindowTitleChanged() { root._queueAutoCompact() }
    }

    // widgets bind height to root.height, not a forced-height Loader - Loader resize-to-fit mis-centres the diamond
    Component { id: _cWorkspaces;  Workspaces       { anchors.verticalCenter: parent.verticalCenter; screen: root.screen; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cShellUpdate; ShellUpdateWidget { anchors.verticalCenter: parent.verticalCenter; height: root.height; screen: root.screen; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cTray;        TrayWidget       { anchors.verticalCenter: parent.verticalCenter; height: root.height; screen: root.screen; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cUpdates;     UpdatesWidget    { anchors.verticalCenter: parent.verticalCenter; height: root.height; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cNetwork;     NetworkWidget    { anchors.verticalCenter: parent.verticalCenter; height: root.height; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cBluetooth;   BluetoothWidget  { anchors.verticalCenter: parent.verticalCenter; height: root.height; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cVolume;      Volume           { anchors.verticalCenter: parent.verticalCenter; height: root.height; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cMic;         MicWidget        { anchors.verticalCenter: parent.verticalCenter; height: root.height; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cBrightness;  BrightnessWidget { anchors.verticalCenter: parent.verticalCenter; height: root.height; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cBattery;     BatteryWidget    { anchors.verticalCenter: parent.verticalCenter; height: root.height; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cMedia;       MediaWidget      { anchors.verticalCenter: parent.verticalCenter; height: root.height; screen: root.screen; textBudget: root.mediaTextBudget; compact: root.effectiveCompact; barActive: root.barActive } }
    Component { id: _cClock;       Clock            { anchors.verticalCenter: parent.verticalCenter; screen: root.screen; compact: root.effectiveCompact; barActive: root.barActive } }

    Component { id: _cWindowTitle; WindowTitle { anchors.verticalCenter: parent.verticalCenter; screen: root.screen; widthBudget: root.titleWidthBudget; compact: root.effectiveCompact; barActive: root.barActive } }

    readonly property var _widgetComponents: ({
        workspaces: _cWorkspaces, windowTitle: _cWindowTitle,
        shellUpdate: _cShellUpdate, tray: _cTray, updates: _cUpdates,
        network: _cNetwork, bluetooth: _cBluetooth, volume: _cVolume, microphone: _cMic,
        brightness: _cBrightness, battery: _cBattery,
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
    readonly property bool _onActiveBar: Monitors.isActive(root.screen)
    readonly property bool _osdBarShowing: ShellSettings.osdEnabled && ShellSettings.osdBarIntegrated
        && root._isOverlayBar && OsdBarState.showing && !OsdBarState.barConcealed
    readonly property bool _centerVizMode: ShellSettings.mediaVisualizerPosition === "center"
    // isQuiet, not isIdle: cava and the canvas both stop at the quiet stage, and isIdle holds the last frame lit
    readonly property bool _centerVizWanted: _centerVizMode && ShellSettings.mediaProgress
        && !ShellSettings.reduceMotion && !Idle.isQuiet
        && root.barActive && root._onActiveBar && Media.shown && Media.playing && Media.cavaReady
    readonly property bool _centerVizHasRoom: titleAvailableWidth >= 48
    // center widgets keep their slot; the visualizer drops behind them instead of being suppressed
    readonly property bool _centerVizBehind: root.centerHasWidgets
    readonly property real _centerVizBehindOpacity: 0.30
    readonly property bool _centerVizShowing: _centerVizWanted && _centerVizHasRoom
        && !root._osdBarShowing
    // snapped to an 8px grid: the Canvas backing this width drops and reallocates its texture on every resize,
    // and titleAvailableWidth moves every frame during the bar's layout animations
    readonly property int _centerVizWidth: 8 * Math.round(Math.max(48, Math.min(560,
        titleAvailableWidth * 0.68
    )) / 8)
    // shares the widgets' axis when the slot is filled; centres in the free span when it is not
    readonly property real _centerVizAnchor: root.centerHasWidgets
        ? root.centerAxis : (titleFreeLeft + titleFreeRight) / 2
    readonly property int _centerVizX: Metrics.centeredSpanX(
        _centerVizAnchor, _centerVizWidth, titleFreeLeft, titleFreeRight)

    BarZone {
        id: centerZone
        anchors.verticalCenter: parent.verticalCenter
        x: Metrics.centeredSpanX(root.centerAxis, width,
            root.titleFreeLeft, root.titleFreeRight)
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
        // unloading in the same frame the opacity drops leaves the fade animating an empty Loader
        readonly property bool _wanted: root._centerVizWanted && root._centerVizHasRoom
        active: _wanted || _vizHold.running
        on_WantedChanged: if (_wanted) _vizHold.stop(); else _vizHold.restart()
        Timer { id: _vizHold; interval: Motion.fast + 60 }
        sourceComponent: Component {
            MediaVisualizer {
                screen: root.screen
                presentationActive: root._centerVizShowing
                holdFrame: true
                // dimmed behind the title/widgets: full rate and bar count buy detail nobody can see
                lowPower: root.effectiveCompact || root._centerVizWidth < 260
                    || root._centerVizBehind
            }
        }
        visible: opacity > 0.001
        opacity: !root._centerVizShowing ? 0.0
            : root._centerVizBehind ? root._centerVizBehindOpacity : 1.0
        scale: root._centerVizShowing ? 1.0 : 0.94
        transformOrigin: Item.Center
        // behind the widgets and the title, still above the bar surface painted by Bar.qml
        z: root._centerVizBehind ? -1 : 1

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
