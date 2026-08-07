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

    readonly property bool atBottom: ShellSettings.barPosition === "bottom"
    property real floatingProgress: ShellSettings.barFloating ? 1.0 : 0.0
    MotionBehavior on floatingProgress {
        NumberAnimation { duration: Motion.barMorph; easing.type: Easing.OutCubic }
    }
    property real shadowProgress: ShellSettings.barShadow ? 1.0 : 0.0
    MotionBehavior on shadowProgress {
        NumberAnimation { duration: Motion.barMorph; easing.type: Easing.OutCubic }
    }
    property real _cornerRadiusTarget: ShellSettings.barCornerStyle === "round"
        ? ShellSettings.barRadius
        : 0
    MotionBehavior on _cornerRadiusTarget {
        NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
    }
    readonly property real cornerRadius: Math.min(_cornerRadiusTarget,
        bar.surfaceHeight / 2) * floatingProgress
    readonly property bool wrapUnderline: floatingProgress > 0.001
    // multiple of 8 so the segment x lands on the 4px grid and an integer output pixel at 2.5x, else a subpixel bleed line at the left edge
    readonly property real configuredSurfaceWidth: {
        if (!ShellSettings.barFloating) return width
        const rawGap = width * (1.0 - ShellSettings.barWidth)
        return width - 8 * Math.round(rawGap / 8)
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
    // constant 4 keeps the bar edge on the 4px grid so hairlines land on whole physical px
    readonly property int surfaceInset: ShellSettings.barFloating ? 4 : 0
    readonly property real visualSurfaceInset: 4 * floatingProgress

    readonly property bool shadowOn: shadowProgress > 0.001 && floatingProgress > 0.001
    readonly property real effectPad: Math.max(
        24 * shadowProgress,
        ShellSettings.underlineGlow ? 8 : 0)
    readonly property int insetPad: 8

    readonly property bool concealed: OverviewState.active

    readonly property real lineAlpha: Math.min(0.9, (ShellSettings.neutralTheme ? 0.22 : 0.28) * ShellSettings.barLineStrength)

    screen:        bar.targetScreen
    color:         "transparent"
    readonly property int _targetCoreHeight: ShellSettings.barHeight + bar.surfaceInset * 2
    property real surfaceHeight: ShellSettings.barHeight
    MotionBehavior on surfaceHeight {
        NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
    }
    exclusiveZone: bar.concealed ? 0 : bar._targetCoreHeight
    implicitHeight: 4 * Math.ceil((bar.surfaceHeight
        + (bar.insetPad + bar.effectPad) * bar.floatingProgress) / 4)

    mask: Region { item: bar.concealed ? null : surface }

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
        width: bar.surfaceWidth
        height: bar.surfaceHeight

        MotionBehavior on width {
            NumberAnimation { duration: Motion.barMorph; easing.type: Easing.OutCubic }
        }

        readonly property real radius: Math.min(bar.cornerRadius, width / 2)

        Loader {
            anchors.fill: parent
            active: bar.shadowOn
            opacity: contents.opacity * bar.floatingProgress * bar.shadowProgress
            sourceComponent: FloatingShadow {
                radius: surface.radius
                atBottom: bar.atBottom
                blur: 18
                offset: 4
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: surface.radius
            antialiasing: surface.radius > 0
            color: Theme.panel
            opacity: contents.opacity
        }

        Loader {
            anchors.fill: parent
            active: bar.wrapUnderline && (bar.shadowOn || ShellSettings.barBorderVisible)
            opacity: contents.opacity * bar.floatingProgress
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
            active: ShellSettings.barBorderVisible
            opacity: contents.opacity * (1.0 - bar.floatingProgress)
            visible: active && opacity > 0.001
            // wrapped: a Loader stretches its root item to the Loader's size, which turns the
            // hairline into a full-height wash over the whole bar
            sourceComponent: Item {
                Hairline {
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    y: bar.atBottom ? 0 : parent.height - height
                    color: Theme.withAlpha(Theme.subtext, bar.lineAlpha)
                }
            }
        }

        Item {
            id: contents
            anchors.fill: parent
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

            Component.onCompleted: Qt.callLater(function() {
                if (ShellSettings.reduceMotion) contents.settle(!bar.concealed)
                else if (!bar.concealed) _enterAnim.start()
            })

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
                        _exitAnim.stop()
                        contents._slideY = contents._hideY
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

            Loader {
                anchors.fill: parent
                active: ShellSettings.underlineGlow && contents.opacity > 0.001 && !bar.concealed
                sourceComponent: Component {
                    BarUnderline {
                        floatingProgress: bar.floatingProgress
                        wrapRadius: surface.radius
                    }
                }
            }

            BarContent {
                id: _barContent
                screen: bar.targetScreen
                barActive: contents.opacity > 0.001 && !bar.concealed
                // the configured span, not the grown one: surfaceWidth derives from the zone widths, so measuring crowding against it is circular
                fitWidth: bar.configuredSurfaceWidth - Settings.hPad * 2
                anchors.fill:        parent
                anchors.leftMargin:  Settings.hPad
                anchors.rightMargin: Settings.hPad
                onMinimumSurfaceWidthChanged: _surfaceFitSync.restart()
                Component.onCompleted: _surfaceFitSync.restart()
            }
        }

        Loader {
            anchors.fill: parent
            active: bar.wrapUnderline && ShellSettings.barBorderVisible
            opacity: contents.opacity * bar.floatingProgress
            visible: active && opacity > 0.001
            sourceComponent: OutlineBorder {
                radius: surface.radius
                outlineColor: Theme.withAlpha(Theme.mix(Theme.subtext, Theme.accent, 0.30),
                    Math.min(0.62, 0.20 * ShellSettings.barLineStrength))
            }
        }
    }
}
