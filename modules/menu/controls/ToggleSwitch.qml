import QtQuick
import Quickshell
import "../../../config"
import "../../../services"
import "../../common"

// arm only for direct input so binding changes do not replay the slide
Item {
    id: root

    property bool checked: false
    property bool highlighted: false
    property bool pressed: false
    property color accentColor: Theme.accent
    implicitWidth:  36
    implicitHeight: 20
    transform: PixelSnap { item: root; dpr: root._dpr }

    // the track, knob and inset on whole device pixels: at 1.25 a 14px knob fringes on all four edges
    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    readonly property real _inset: Metrics.devicePx(3, _dpr)
    readonly property real _knobSize: Metrics.devicePx(height, _dpr) - 2 * _inset

    property bool _animateX: false
    function armFlipAnimation(): void {
        if (!ShellSettings.reduceMotion) { root._animateX = true; _disarm.restart() }
    }

    Timer { id: _disarm; interval: Motion.normal + Motion.ms(40); onTriggered: root._animateX = false }

    Rectangle {
        id: _track
        anchors.fill: parent
        radius: Theme.radiusField
        antialiasing: true
        // a plain scale held the outline between device pixels for as long as the pointer rested
        transform: PixelScale {
            item: _track
            dpr: root._dpr
            factor: root.pressed ? 0.985 : root.highlighted ? 1.01 : 1.0
            hoverFactor: 1.01
        }
        color: Theme.switchTrackFill(root.accentColor, root.checked,
            root.highlighted, root.pressed)
        ColorFade on color {}

        OutlineBorder {
            radius: _track.radius
            outlineWidth: 1
            outlineColor: Theme.controlTrackLine(root.accentColor, root.checked,
                root.highlighted, root.pressed)
            ColorFade on outlineColor {}
        }

        Rectangle {
            id: _knob
            y: root._inset
            // a held knob stretches toward where it will travel; its outer edge stays pinned
            width: root.pressed ? root._knobSize + Metrics.devicePx(5, root._dpr) : root._knobSize
            height: root._knobSize
            radius: 4
            antialiasing: true
            x: root.checked ? Metrics.devicePx(parent.width, root._dpr) - width - root._inset : root._inset
            // the same hover lift as the slider handle; a smaller one rounds to nothing at 1.25
            transform: PixelScale {
                item: _knob
                dpr: root._dpr
                factor: root.highlighted && !root.pressed ? 1.06 : 1.0
                hoverFactor: 1.06
            }
            MotionBehavior on width {
                NumberAnimation { duration: Motion.press; easing.type: Easing.OutCubic }
            }
            color: Theme.controlKnobFill(root.accentColor, root.checked,
                root.highlighted, root.pressed)

            MotionBehavior on x     { gate: root._animateX; NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
            ColorFade on color {}
        }
    }
}
