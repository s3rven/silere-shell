pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland._WlrLayerShell
import "../../config"
import "../../services"
import "../common"

PanelWindow {
    id: bar

    required property ShellScreen targetScreen
    required property bool pickerActive

    WlrLayershell.namespace: "silere-bar"

    readonly property bool atBottom: ShellSettings.barPosition === "bottom"
    readonly property real cornerRadius: ShellSettings.barFloating && ShellSettings.barCornerStyle === "round"
        ? Math.min(ShellSettings.barRadius, ShellSettings.barHeight / 2)
        : 0
    // underline wraps automatically whenever the bar floats, no separate setting
    readonly property bool wrapUnderline: ShellSettings.barFloating
    // Floating-width side gap snaps to a multiple of 8 so the segment's x
    // lands on the 4px grid: at effective scale 2.5× (DPR=2 × 1.25×
    // compositor) that maps to an integer output pixel, avoiding the
    // subpixel-bleed line at the bar's left edge on fractional displays.
    readonly property real surfaceWidth: {
        if (!ShellSettings.barFloating) return width
        const rawGap = width * (1.0 - ShellSettings.barWidth)
        return width - 8 * Math.round(rawGap / 8)
    }
    // Constant 4 keeps the bar edge (and everything stacked below it) on the
    // 4px grid, so hairlines land on whole physical px under fractional
    // scaling.
    readonly property int surfaceInset: ShellSettings.barFloating ? 4 : 0

    // extra window space so the floating shadow bleeds past the surface instead of clipping; input is masked to the surface so the pad never catches the pointer
    readonly property bool shadowOn: ShellSettings.barFloating && ShellSettings.barShadow
    // Always reserved when floating so toggling the shadow never resizes the window.
    // 24 (a 4px-grid multiple) leaves room for the ambient layer (blur 21 + offset 2 = 23px spread).
    readonly property int  shadowPad: ShellSettings.barFloating ? 24 : 0

    // hidden states release the reserved zone so overview windows fill the bar strip instead of leaving a phantom gap; reflow rides the windowsMove anim
    readonly property bool concealed: bar.pickerActive || OverviewState.active

    // shared by the edge line and wrap border so both track the strength slider
    readonly property real lineAlpha: Math.min(0.9, (ShellSettings.neutralTheme ? 0.22 : 0.28) * ShellSettings.barLineStrength)

    screen:        bar.targetScreen
    color:         "transparent"
    // strip height (bar + insets), kept separate from the shadow pad so the reserved zone doesn't bounce when the shadow toggles
    readonly property int _targetCoreHeight: ShellSettings.barHeight + bar.surfaceInset * 2
    property real coreHeight: bar._targetCoreHeight
    Behavior on coreHeight {
        enabled: !ShellSettings.reduceMotion
        NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
    }
    exclusiveZone: bar.concealed ? 0 : bar._targetCoreHeight
    implicitHeight: bar.coreHeight + bar.shadowPad

    // input follows the visible surface, so the concealed bar and a floating bar's side gaps/shadow pad don't catch the pointer
    mask: Region { item: bar.concealed ? null : surface }

    anchors {
        top:    !bar.atBottom
        bottom: bar.atBottom
        left:   true
        right:  true
    }

    Item {
        id: surface
        // Pinned to the screen-facing edge with an explicit height, so the
        // shadow pad only adds empty window space on the desktop side and never
        // touches the surface geometry. Anchoring to both edges instead let a
        // shadowPad toggle change implicitHeight and a margin in separate
        // frames, visibly jolting the surface.
        anchors.top:    bar.atBottom ? undefined : parent.top
        anchors.bottom: bar.atBottom ? parent.bottom : undefined
        anchors.topMargin:    bar.surfaceInset
        anchors.bottomMargin: bar.surfaceInset
        anchors.horizontalCenter: parent.horizontalCenter
        width: bar.surfaceWidth
        height: bar.coreHeight - bar.surfaceInset * 2
        scale: _switchScale
        transformOrigin: bar.atBottom ? Item.Bottom : Item.Top
        transform: Translate { y: surface._switchLift }

        property real _switchLift: 0
        property real _switchScale: 1
        readonly property bool _switchEffectsOn: !ShellSettings.reduceMotion && !bar.concealed

        function _runFloatingSwitchAnimation(): void {
            _floatSwitchAnim.stop()
            _switchLift = 0
            _switchScale = 1
            if (!_switchEffectsOn) return

            const edgeDir = bar.atBottom ? -1 : 1
            _switchScale = 0.982
            _switchLift = edgeDir * (ShellSettings.barFloating ? 6 : -4)
            _floatSwitchAnim.restart()
        }

        Behavior on width {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
        }

        readonly property real radius: Math.min(bar.cornerRadius, width / 2)

        Connections {
            target: ShellSettings
            function onBarFloatingChanged() {
                surface._runFloatingSwitchAnimation()
            }
            function onReduceMotionChanged() {
                if (ShellSettings.reduceMotion) {
                    _floatSwitchAnim.stop()
                    surface._switchLift = 0
                    surface._switchScale = 1
                }
            }
        }

        ParallelAnimation {
            id: _floatSwitchAnim
            NumberAnimation {
                target: surface; property: "_switchLift"
                to: 0; duration: Motion.ms(230); easing.type: Easing.OutQuart
            }
            NumberAnimation {
                target: surface; property: "_switchScale"
                to: 1; duration: Motion.ms(230); easing.type: Easing.OutCubic
            }
        }

        // drop shadow grounding the floating surface, shared with popups; the bar spreads both layers wider than a card
        Loader {
            anchors.fill: parent
            active: bar.shadowOn
            opacity: contents.opacity
            sourceComponent: FloatingShadow {
                radius: surface.radius
                atBottom: bar.atBottom
                ambientBlur: 21
                contactBlur: 8
                contactOffset: 6
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: surface.radius
            antialiasing: surface.radius > 0
            color: Theme.panel
            opacity: contents.opacity
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: surface.radius
            anchors.rightMargin: surface.radius
            y: bar.atBottom ? parent.height - 1 : 0
            height: 1
            antialiasing: false
            visible: ShellSettings.barFloating && (bar.shadowOn || ShellSettings.barBorderVisible) && opacity > 0.001
            opacity: contents.opacity
            color: Theme.withAlpha(Theme.text, ShellSettings.neutralTheme ? 0.045 : 0.065)
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: surface.radius
            anchors.rightMargin: surface.radius
            y: bar.atBottom ? 0 : parent.height - 1
            height: 1
            antialiasing: false
            visible: ShellSettings.barFloating && (bar.shadowOn || ShellSettings.barBorderVisible) && opacity > 0.001
            opacity: contents.opacity
            color: Qt.rgba(0, 0, 0, bar.shadowOn
                ? Math.min(0.16, 0.07 + 0.035 * ShellSettings.barShadowStrength)
                : Math.min(0.11, 0.045 * ShellSettings.barLineStrength))
        }

        // The edge line sits on the side facing the desktop (bottom for a top bar).
        // Positioned via y, not flipped anchors: conditional anchor bindings don't
        // reliably clear the stale edge when the bar moves.
        Rectangle {
            id: _barLine
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.leftMargin:  _lineInset
            anchors.rightMargin: _lineInset
            y: bar.atBottom ? 0 : parent.height - 1
            height: 1
            antialiasing: false
            opacity: contents.opacity
            visible: !bar.wrapUnderline && ShellSettings.barBorderVisible && opacity > 0.001

            readonly property real _lineInset: surface.radius
            readonly property real _a: bar.lineAlpha

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0;  color: "transparent" }
                GradientStop { position: 0.25; color: Theme.withAlpha(Theme.subtext, _barLine._a) }
                GradientStop { position: 0.75; color: Theme.withAlpha(Theme.subtext, _barLine._a) }
                GradientStop { position: 1.0;  color: "transparent" }
            }
        }

        Item {
            id: contents
            anchors.fill: parent
            opacity: 0
            // opacity 0 alone keeps the visualizer canvas + marquee painting into an invisible bar, so stop rendering when hidden
            visible: opacity > 0.001

            readonly property real _hideY: bar.atBottom ? 14 : -14
            property real _slideY: _hideY
            transform: Translate { y: contents._slideY }

            // Born concealed: stay parked hidden, onConcealedChanged reveals later.
            Component.onCompleted: Qt.callLater(function() {
                if (!bar.concealed) _enterAnim.start()
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

            Loader {
                anchors.fill: parent
                active: ShellSettings.underlineGlow && contents.opacity > 0.001 && !bar.concealed
                sourceComponent: Component { BarUnderline {} }
            }

            BarContent {
                screen: bar.targetScreen
                barActive: contents.opacity > 0.001 && !bar.concealed
                anchors.fill:        parent
                anchors.leftMargin:  Settings.hPad
                anchors.rightMargin: Settings.hPad
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: surface.radius
            antialiasing: surface.radius > 0
            color: "transparent"
            border.width: bar.wrapUnderline && ShellSettings.barBorderVisible ? 1 : 0
            border.color: Theme.withAlpha(Theme.mix(Theme.subtext, Theme.accent, 0.30),
                Math.min(0.42, 0.20 * ShellSettings.barLineStrength))
            opacity: contents.opacity
            visible: border.width > 0 && opacity > 0.001
        }
    }
}
