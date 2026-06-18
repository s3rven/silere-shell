import QtQuick
import QtQuick.Effects
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
    readonly property bool wrapUnderline: ShellSettings.barFloating && ShellSettings.underlineFloatingWrap
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

    // Extra window space on the desktop-facing side so the floating shadow can
    // bleed past the surface instead of clipping at the window edge. Input is
    // masked to the surface, so the pad never catches the pointer.
    readonly property bool shadowOn: ShellSettings.barFloating && ShellSettings.barShadow
    // Always reserved when floating so toggling the shadow never resizes the window.
    // 24 (a 4px-grid multiple) leaves room for the ambient layer (blur 18 + offset 2 = 20px spread).
    readonly property int  shadowPad: ShellSettings.barFloating ? 24 : 0

    // Hidden states share one exit/enter animation and also release the
    // reserved zone: during the overview the tiled windows expand into the
    // bar strip, so workspace cards show full-bleed content instead of a
    // phantom gap where the bar was. The reflow rides the normal windowsMove
    // animation and reverses when the bar returns.
    readonly property bool concealed: bar.pickerActive || OverviewState.active

    // Shared by the edge line and the wrap border so both react to the
    // strength slider identically.
    readonly property real lineAlpha: Math.min(0.9, (ShellSettings.neutralTheme ? 0.22 : 0.28) * ShellSettings.barLineStrength)

    screen:        bar.targetScreen
    color:         "transparent"
    // Animated strip height (bar + insets), kept separate from the shadow pad
    // so the reserved zone follows height changes smoothly but doesn't bounce
    // when the shadow toggles.
    readonly property int _targetCoreHeight: ShellSettings.barHeight + bar.surfaceInset * 2
    property real coreHeight: bar._targetCoreHeight
    Behavior on coreHeight {
        enabled: !ShellSettings.reduceMotion
        NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
    }
    exclusiveZone: bar.concealed ? 0 : bar._targetCoreHeight
    implicitHeight: bar.coreHeight + bar.shadowPad

    // Input follows the visible surface: the concealed bar (overview, picker)
    // must not eat clicks in its strip, and a floating bar's side gaps and
    // shadow pad shouldn't catch the pointer either.
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

        Behavior on width {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
        }

        readonly property real radius: Math.min(bar.cornerRadius, width / 2)

        // Drop shadow grounding the floating surface: a wide ambient halo plus a
        // tighter contact shadow cast toward the desktop. Two analytic layers (no
        // FBO, no per-frame cost) read as real elevation instead of one flat smear;
        // built only while floating + enabled. Strength slider scales both alphas.
        Loader {
            anchors.fill: parent
            active: bar.shadowOn
            opacity: contents.opacity
            sourceComponent: Item {
                anchors.fill: parent
                readonly property real strength: ShellSettings.barShadowStrength
                RectangularShadow {
                    anchors.fill: parent
                    radius: surface.radius
                    blur: 18
                    offset: Qt.vector2d(0, bar.atBottom ? -2 : 2)
                    color: Qt.rgba(0, 0, 0, Math.min(0.38, 0.20 * parent.strength))
                }
                RectangularShadow {
                    anchors.fill: parent
                    radius: surface.radius
                    blur: 9
                    offset: Qt.vector2d(0, bar.atBottom ? -6 : 6)
                    color: Qt.rgba(0, 0, 0, Math.min(0.58, 0.34 * parent.strength))
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: surface.radius
            antialiasing: surface.radius > 0
            color: Theme.panel
            border.width: bar.wrapUnderline && ShellSettings.barBorderVisible ? 1 : 0
            border.color: Theme.withAlpha(Theme.subtext, bar.lineAlpha)
            opacity: contents.opacity
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
            // Faded out (wallpaper picker) must also stop rendering: opacity 0 alone
            // keeps the visualizer canvas + marquee painting into an invisible bar.
            visible: opacity > 0.001

            readonly property real _hideY: bar.atBottom ? 14 : -14
            property real _slideY: _hideY
            transform: Translate { y: contents._slideY }

            Component.onCompleted: Qt.callLater(function() {
                _enterAnim.start()
            })

            ParallelAnimation {
                id: _enterAnim
                running: false
                NumberAnimation {
                    target: contents; property: "opacity"
                    to: 1; duration: Motion.ms(340); easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: contents; property: "_slideY"
                    to: 0; duration: Motion.ms(400)
                    easing.type: Easing.OutBack; easing.overshoot: 0.65
                }
            }

            ParallelAnimation {
                id: _exitAnim
                running: false
                NumberAnimation {
                    target: contents; property: "opacity"
                    to: 0; duration: Motion.ms(210); easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: contents; property: "_slideY"
                    to: contents._hideY * 0.7; duration: Motion.ms(210)
                    easing.type: Easing.InBack; easing.overshoot: 0.5
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

            BarUnderline {
                anchors.fill: parent
            }

            BarContent {
                screen: bar.targetScreen
                anchors.fill:        parent
                anchors.leftMargin:  Settings.hPad
                anchors.rightMargin: Settings.hPad
            }
        }
    }
}
