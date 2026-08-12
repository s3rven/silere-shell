import QtQuick
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
        scale: root.pressed ? 0.985
            : root.highlighted ? 1.01 : 1.0
        transformOrigin: Item.Center
        color: root.checked
            ? Theme.mix(Theme.menuControl, root.accentColor,
                ShellSettings.neutralTheme
                    ? (root.pressed ? 0.78 : root.highlighted ? 0.73 : 0.68)
                    : (root.pressed ? 0.84 : root.highlighted ? 0.79 : 0.74))
            : Theme.mix(Theme.menuControl, Theme.text,
                root.pressed ? 0.13 : root.highlighted ? 0.085 : 0.035)
        ColorFade on color {}
        MotionBehavior on scale {
            NumberAnimation {
                duration: root.pressed ? Motion.press
                    : root.highlighted ? Motion.hoverIn : Motion.hoverOut
                easing.type: Easing.OutCubic
            }
        }

        OutlineBorder {
            radius: _track.radius
            outlineWidth: 1
            outlineColor: root.checked
                    ? (root.highlighted
                        ? Theme.withAlpha(root.accentColor, 0.48)
                        : "transparent")
                    : root.highlighted
                        ? Theme.menuControlLineHot : Theme.menuControlLine
            ColorFade on outlineColor {}
        }

        Rectangle {
            id: _knob
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            radius: 4
            antialiasing: true
            x: root.checked ? parent.width - width - 3 : 3
            scale: root.pressed ? 0.90
                : root.highlighted ? 1.04 : 1.0
            color: root.checked
                ? Theme.mix(Theme.text, root.accentColor, 0.06)
                : Theme.mix(Theme.subtext, Theme.text, 0.18)

            MotionBehavior on x     { gate: root._animateX; NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
            MotionBehavior on scale {
                NumberAnimation {
                    duration: root.pressed ? Motion.press
                        : root.highlighted ? Motion.hoverIn : Motion.hoverOut
                    easing.type: Easing.OutCubic
                }
            }
            ColorFade on color {}
        }
    }
}
