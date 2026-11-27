pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../services"
import "../common"

PanelWindow {
    id: bar

    required property ShellScreen targetScreen

    WlrLayershell.namespace: "silere-bar"

    readonly property bool atBottom: Metrics.barAtBottom
    property real floatingProgress: ShellSettings.barFloating ? 1.0 : 0.0
    MotionBehavior on floatingProgress {
        NumberAnimation { duration: Motion.barMorph; easing.type: Easing.OutCubic }
    }
    property real shadowProgress: ShellSettings.barShadow ? 1.0 : 0.0
    MotionBehavior on shadowProgress {
        NumberAnimation { duration: Motion.barMorph; easing.type: Easing.OutCubic }
    }
    property real _cornerRadiusTarget: ShellSettings.barRadius
    MotionBehavior on _cornerRadiusTarget {
        NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
    }
    readonly property real cornerRadius: Math.min(_cornerRadiusTarget,
        bar.surfaceHeight / 2) * floatingProgress
    readonly property bool wrapUnderline: floatingProgress > 0.001
    // multiple of 8 so the segment x lands on the 4px grid and an integer output pixel at 2.5x, else a subpixel bleed line at the left edge
    readonly property real configuredSurfaceWidth: {
        return width - 2 * Metrics.barSideGap(width)
    }
    property real _contentFloorWidth: 0
    // grow by shrinking the side gap in 8px steps; snapping the width puts the centered x off the 4px grid on odd output widths
    readonly property real surfaceWidth: {
        if (_contentFloorWidth <= configuredSurfaceWidth) return configuredSurfaceWidth
        const gap8 = 8 * Math.floor(Math.max(0, width - _contentFloorWidth) / 8)
        return Math.max(configuredSurfaceWidth, width - gap8)
    }

    // published out of band: some widget widths respond to bar width, so a direct parent-child binding loops
    Timer {
        id: _surfaceFitSync
        interval: 1
        onTriggered: bar._contentFloorWidth = _barContent.minimumSurfaceWidth
    }
    // stepped in 4s so the bar edge stays on the 4px grid and hairlines land on whole physical px
    readonly property int surfaceInset: Metrics.barEdgeInset
    // the popup cards glide their bar clearance on this curve (FloatingPopupCard._barInset); a snapped gap left
    // the bar 8 px from the Settings panel it sits over while the gap slider moved
    property real visualSurfaceInset: Metrics.barEdgeInset
    MotionBehavior on visualSurfaceInset {
        NumberAnimation { duration: Motion.barMorph; easing.type: Easing.OutCubic }
    }

    readonly property bool shadowOn: shadowProgress > 0.001
    property real borderProgress: ShellSettings.barBorderVisible ? 1.0 : 0.0
    MotionBehavior on borderProgress {
        NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
    }
    readonly property bool borderOn: borderProgress > 0.001
    // constant, not scaled by shadowProgress: this feeds implicitHeight, so animating it
    // resized the layer-shell window in 4px steps and the bar juddered on every toggle
    readonly property real effectPad: 24
    // the surface sits barGap from the edge, so the window budgets the gap at both ends or it clips the bar
    readonly property int insetPad: Math.max(8, Metrics.barEdgeInset * 2)

    readonly property bool concealed: OverviewState.active

    readonly property real lineAlpha: Math.min(0.9, (ShellSettings.neutralTheme ? 0.22 : 0.28) * ShellSettings.barLineStrength)

    screen:        bar.targetScreen
    color:         "transparent"
    // the edge gap is reserved once: the compositor's own gap already spaces windows from the bar, as it does when docked
    readonly property int _targetCoreHeight: Metrics.barHeight + bar.surfaceInset
    property real surfaceHeight: Metrics.barHeight
    MotionBehavior on surfaceHeight {
        NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
    }
    // niri's overview is live: giving its strip back resized every column into it and back again on close
    exclusiveZone: bar.concealed && !Compositor.overviewIsLive ? 0 : bar._targetCoreHeight
    implicitHeight: 4 * Math.ceil((bar.surfaceHeight
        + bar.insetPad * bar.floatingProgress + bar.effectPad) / 4)

    mask: Region {
        item: bar.concealed ? null : surface
        // a floating bar's gap to the screen edge takes input too: the widgets reach into it (Metrics.barWidgetReach)
        Region {
            x: surface.x
            y: bar.atBottom ? Math.floor(surface.y + surface.height) : 0
            width: bar.concealed ? 0 : surface.width
            height: bar.atBottom ? bar.height - Math.floor(surface.y + surface.height) : Math.ceil(surface.y)
        }
    }
    // at full width the bar's origin is the corner of the screen
    ContextMenuGuard {}
    // blur with no tint over it reads as a frosted slab, so it waits for the fade's midpoint
    BackgroundEffect.blurRegion: Region {
        item: ShellSettings.surfaceBlur && Theme.panelOpacity < 1 && contents.opacity >= 0.5 ? surface : null
        topLeftRadius:     Math.round(bar.atBottom ? surface.innerRadius : surface.outerRadius)
        topRightRadius:    Math.round(bar.atBottom ? surface.innerRadius : surface.outerRadius)
        bottomLeftRadius:  Math.round(bar.atBottom ? surface.outerRadius : surface.innerRadius)
        bottomRightRadius: Math.round(bar.atBottom ? surface.outerRadius : surface.innerRadius)
    }

    anchors {
        top:    !bar.atBottom
        bottom: bar.atBottom
        left:   true
        right:  true
    }

    Item {
        id: surface
        anchors.top:    bar.atBottom ? undefined : parent.top
        anchors.bottom: bar.atBottom ? parent.bottom : undefined
        anchors.topMargin:    bar.visualSurfaceInset
        anchors.bottomMargin: bar.visualSurfaceInset
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(bar.width, _surfaceGlide.value)
        height: bar.surfaceHeight

        // until its first frame the window reports Qt's placeholder width, not the compositor's: a glide from there
        // stretched the bar out from half its width at every start, and the reveal below had ended before it showed
        property bool presented: false
        Connections {
            target: surface.presented ? null : surface.Window.window
            function onFrameSwapped() { surface.presented = true }
        }

        SmoothGlide {
            id: _surfaceGlide
            target: bar.surfaceWidth
            duration: Motion.barMorph
            gate: !bar.concealed && surface.presented
            precision: 0.5
        }

        readonly property real radius: Math.min(bar.cornerRadius, width / 2)
        readonly property bool edgeFlush: bar.visualSurfaceInset < 0.5
        readonly property bool sidesFlush: width > bar.width - 0.5
        // whatever traces the outline runs on past an edge the bar touches, so its rounded corners never notch the screen edge
        readonly property int _bleed: bar.wrapUnderline ? Math.ceil(radius) + 2 : 0
        readonly property int bleedTop:    !bar.atBottom && edgeFlush ? _bleed : 0
        readonly property int bleedBottom: bar.atBottom && edgeFlush ? _bleed : 0
        readonly property int bleedSide:   sidesFlush ? _bleed : 0
        // the blur cannot run past the surface, so it squares those corners instead
        readonly property real outerRadius: edgeFlush || sidesFlush ? 0 : radius
        readonly property real innerRadius: sidesFlush ? 0 : radius

        Item {
            id: _backdrop
            anchors.fill: parent
            anchors.topMargin:    -surface.bleedTop
            anchors.bottomMargin: -surface.bleedBottom
            anchors.leftMargin:   -surface.bleedSide
            anchors.rightMargin:  -surface.bleedSide
        }

        Loader {
            anchors.fill: _backdrop
            active: bar.shadowOn
            opacity: contents.opacity * bar.shadowProgress
            sourceComponent: FloatingShadow {
                hollow: Theme.panel.a < 0.999
                radius: surface.radius
                atBottom: bar.atBottom
                blur: 18
                offset: 4
            }
        }

        Rectangle {
            anchors.fill: _backdrop
            radius: surface.radius
            antialiasing: surface.radius > 0
            color: Theme.panel
            opacity: contents.opacity
        }

        Loader {
            anchors.fill: _backdrop
            active: bar.wrapUnderline && (bar.shadowOn || bar.borderOn)
            opacity: contents.opacity * bar.floatingProgress * Math.max(bar.shadowProgress, bar.borderProgress)
            visible: active && opacity > 0.001
            sourceComponent: Item {
                Hairline {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: surface.radius
                    anchors.rightMargin: surface.radius
                    y: bar.atBottom ? parent.height - height : 0
                    color: Theme.withAlpha(Theme.text, ShellSettings.neutralTheme ? 0.045 : 0.065)
                }
                Hairline {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: surface.radius
                    anchors.rightMargin: surface.radius
                    y: bar.atBottom ? 0 : parent.height - height
                    color: Qt.rgba(0, 0, 0, bar.shadowOn
                        ? Math.min(0.16, 0.07 + 0.035 * ShellSettings.barShadowStrength)
                        : Math.min(0.14, 0.045 * ShellSettings.barLineStrength))
                }
            }
        }

        // positioned via y, not flipped anchors: conditional anchor bindings don't reliably clear the stale edge
        Loader {
            anchors.fill: parent
            active: bar.borderOn
            opacity: contents.opacity * (1.0 - bar.floatingProgress) * bar.borderProgress
            visible: active && opacity > 0.001
            // wrapped: a Loader stretches its root item to the Loader's size, which turns the hairline into a full-height wash over the whole bar
            sourceComponent: Item {
                Hairline {
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    y: bar.atBottom ? 0 : parent.height - height
                    color: Theme.withAlpha(Theme.barLine, bar.lineAlpha)
                }
            }
        }

        Item {
            id: contents
            anchors.fill: parent
            // grown both ways, so centred content stays put. Not a hit shape: Qt skips any subtree whose box misses the
            // point once all its children fit inside it
            anchors.topMargin:    -Metrics.barWidgetReach
            anchors.bottomMargin: -Metrics.barWidgetReach
            opacity: 0
            visible: opacity > 0.001

            readonly property real _hideY: bar.atBottom ? 14 : -14
            property real _slideY: _hideY
            transform: Translate { y: contents._slideY }

            function settle(shown: bool): void {
                _enterAnim.stop()
                _exitAnim.stop()
                contents.opacity = shown ? 1 : 0
                contents._slideY = shown ? 0 : contents._hideY
            }

            // a shown bar reveals from its first frame; one built hidden (check.sh's smoke shells) never draws one
            function _reveal(): void {
                if (ShellSettings.reduceMotion) contents.settle(!bar.concealed)
                else if (!bar.concealed && !_enterAnim.running && contents.opacity < 1) _enterAnim.start()
            }
            Component.onCompleted: Qt.callLater(function() {
                if (bar && (surface.presented || !bar.visible)) contents._reveal()
            })
            Connections {
                target: surface
                function onPresentedChanged() { if (surface.presented) contents._reveal() }
            }

            ParallelAnimation {
                id: _enterAnim
                running: false
                NumberAnimation {
                    target: contents; property: "opacity"
                    to: 1; duration: Motion.ms(170); easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: contents; property: "_slideY"
                    to: 0; duration: Motion.ms(220)
                    easing.type: Easing.OutQuart
                }
            }

            ParallelAnimation {
                id: _exitAnim
                running: false
                NumberAnimation {
                    target: contents; property: "opacity"
                    to: 0; duration: Motion.ms(125); easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: contents; property: "_slideY"
                    to: contents._hideY * 0.7; duration: Motion.ms(145)
                    easing.type: Easing.InCubic
                }
                onFinished: contents._slideY = contents._hideY
            }

            Connections {
                target: bar
                function onConcealedChanged() {
                    if (ShellSettings.reduceMotion) {
                        contents.settle(!bar.concealed)
                        return
                    }
                    if (bar.concealed) {
                        _enterAnim.stop()
                        _exitAnim.start()
                    } else {
                        // a hide still in flight turns back from where it is: resetting it to _hideY snapped a quick overview peek 12 px
                        if (!_exitAnim.running) contents._slideY = contents._hideY
                        _exitAnim.stop()
                        _enterAnim.start()
                    }
                }
            }

            Connections {
                target: ShellSettings
                function onReduceMotionChanged() {
                    if (ShellSettings.reduceMotion)
                        contents.settle(!bar.concealed)
                }
            }

            Item {
                id: _outlineBox
                anchors.fill: parent
                anchors.topMargin:    Metrics.barWidgetReach - surface.bleedTop
                anchors.bottomMargin: Metrics.barWidgetReach - surface.bleedBottom
                anchors.leftMargin:   -surface.bleedSide
                anchors.rightMargin:  -surface.bleedSide
            }

            Loader {
                id: _underline
                anchors.fill: _outlineBox
                active: ShellSettings.underlineGlow && contents.opacity > 0.001 && !bar.concealed
                // by file name, so it compiles when first switched on: off by default, it and its glows (27 KB) compiled
                // at every start before the bar showed
                source: "BarUnderline.qml"
                onLoaded: {
                    item.screen = Qt.binding(() => bar.targetScreen)
                    item.floatingProgress = Qt.binding(() => bar.floatingProgress)
                    item.wrapRadius = Qt.binding(() => surface.radius)
                }
            }

            Loader {
                anchors.fill: _outlineBox
                active: ShellSettings.mediaVisualizerPosition === "underline"
                    && contents.opacity > 0.001 && !bar.concealed
                sourceComponent: Component {
                    Item {
                        id: _spectrumWrap
                        anchors.fill: parent
                        // the underline mirrors itself onto a bottom bar's desktop-facing edge; the spectrum rides the same edge
                        transform: Scale {
                            origin.y: _spectrumWrap.height / 2
                            yScale: bar.atBottom ? -1 : 1
                        }
                        BarSpectrum {
                            screen: bar.targetScreen
                            rimRadius: surface.innerRadius
                            duck:   _underline.item ? Math.min(0.82, _underline.item.eventGlow * 1.7) : 0
                        }
                    }
                }
            }

            BarContent {
                id: _barContent
                screen: bar.targetScreen
                barActive: contents.opacity > 0.001 && !bar.concealed
                // the configured span, not the grown one: surfaceWidth derives from the zone widths, so measuring crowding against it is circular
                fitWidth: bar.configuredSurfaceWidth - Settings.hPad * 2
                maximumWidth: Math.max(0, bar.width - Settings.hPad * 2)
                anchors.fill:        parent
                anchors.leftMargin:  Settings.hPad
                anchors.rightMargin: Settings.hPad
                onMinimumSurfaceWidthChanged: _surfaceFitSync.start()
                Component.onCompleted: _surfaceFitSync.start()
            }
        }

        Loader {
            anchors.fill: _backdrop
            active: bar.wrapUnderline && bar.borderOn
            opacity: contents.opacity * bar.floatingProgress * bar.borderProgress
            visible: active && opacity > 0.001
            sourceComponent: OutlineBorder {
                radius: surface.radius
                outlineColor: Theme.withAlpha(Theme.barLine,
                    Math.min(0.62, 0.20 * ShellSettings.barLineStrength))
            }
        }
    }
}
