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
        color: Theme.controlTrackFill(root.accentColor, root.checked,
            root.highlighted, root.pressed)
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
            outlineColor: Theme.controlTrackLine(root.accentColor, root.checked,
                root.highlighted, root.pressed)
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
            color: Theme.controlKnobFill(root.accentColor, root.checked,
                root.highlighted, root.pressed)

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
