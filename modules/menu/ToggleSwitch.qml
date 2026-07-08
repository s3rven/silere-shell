import QtQuick
import "../../config"
import "../../services"

// pill switch shared by ToggleRow and other checked/unchecked controls. call armFlipAnimation() right before
// flipping `checked` on a real tap — the knob only slides+stretches on deliberate flips, not section re-checks.
Item {
    id: root

    property bool checked: false
    property color accentColor: Theme.accent
    implicitWidth:  34
    implicitHeight: 18

    property bool _animateX: false
    function armFlipAnimation(): void {
        if (!ShellSettings.reduceMotion) { root._animateX = true; _disarm.restart() }
    }

    Timer { id: _disarm; interval: Motion.fast + Motion.medium + Motion.ms(80); onTriggered: root._animateX = false }

    Rectangle {
        anchors.fill: parent
        radius: 9; antialiasing: true
        color: root.checked
            ? Theme.mix(Theme.menuControl, root.accentColor, ShellSettings.neutralTheme ? 0.22 : 0.38)
            : Theme.menuControl
        border.width: 1
        border.color: root.checked
            ? (ShellSettings.neutralTheme ? Theme.withAlpha(root.accentColor, 0.46)
                                          : Theme.mix(Theme.menuCard, root.accentColor, 0.62))
            : Theme.menuControlLine
        Behavior on color        { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

        Rectangle {
            id: _knob
            anchors.verticalCenter: parent.verticalCenter
            width: 14; height: 14; radius: 7
            antialiasing: true
            x:     root.checked ? parent.width - width - 2 : 2
            color: root.checked ? root.accentColor : Theme.mix(Theme.subtext, root.accentColor, 0.16)

            property real _stretch: 1.0
            transform: Scale {
                origin.x: _knob.width  / 2
                origin.y: _knob.height / 2
                xScale: _knob._stretch
                yScale: 1.0
            }

            Behavior on x     { enabled: root._animateX && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutQuart } }
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            Connections {
                target: root
                function onCheckedChanged() {
                    if (ShellSettings.reduceMotion) { _knob._stretch = 1.0; return }
                    if (!root._animateX) { _knob._stretch = 1.0; return }
                    _knobStretch.restart()
                }
            }
            Connections {
                target: ShellSettings
                function onReduceMotionChanged() {
                    if (ShellSettings.reduceMotion) { _knobStretch.stop(); _knob._stretch = 1.0 }
                }
            }
            SequentialAnimation {
                id: _knobStretch
                NumberAnimation { target: _knob; property: "_stretch"; to: 1.22; duration: Motion.fast;   easing.type: Easing.OutQuad }
                NumberAnimation { target: _knob; property: "_stretch"; to: 1.0;  duration: Motion.medium; easing.type: Easing.OutCubic }
            }
        }
    }
}
