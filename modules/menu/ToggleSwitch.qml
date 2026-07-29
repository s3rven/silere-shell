import QtQuick
import "../../config"
import "../../services"
import "../common"

// Pill switch shared by ToggleRow and other checked/unchecked controls. Call
// armFlipAnimation() before a real tap so state rebinds do not replay the slide.
Item {
    id: root

    property bool checked: false
    property bool highlighted: false
    property color accentColor: Theme.accent
    implicitWidth:  38
    implicitHeight: 20

    property bool _animateX: false
    function armFlipAnimation(): void {
        if (!ShellSettings.reduceMotion) { root._animateX = true; _disarm.restart() }
    }

    Timer { id: _disarm; interval: Motion.normal + Motion.ms(40); onTriggered: root._animateX = false }

    Rectangle {
        id: _track
        anchors.fill: parent
        radius: 10; antialiasing: true
        color: root.checked
            ? Theme.mix(Theme.menuControl, root.accentColor, ShellSettings.neutralTheme ? 0.22 : 0.38)
            : Theme.mix(Theme.menuControl, Theme.text, root.highlighted ? 0.025 : 0)
        MotionBehavior on color {ColorAnimation { duration: Motion.fast } }

        readonly property color _outlineColor: root.checked
            ? (ShellSettings.neutralTheme ? Theme.withAlpha(root.accentColor, 0.46)
                                          : Theme.mix(Theme.menuCard, root.accentColor, 0.62))
            : root.highlighted ? Theme.menuControlLineHot : Theme.menuControlLine

        OutlineBorder {
            radius: _track.radius
            outlineColor: _track._outlineColor
            MotionBehavior on outlineColor {ColorAnimation { duration: Motion.fast } }
        }

        Rectangle {
            id: _knob
            anchors.verticalCenter: parent.verticalCenter
            width: 16; height: 16; radius: 8
            antialiasing: true
            x:     root.checked ? parent.width - width - 2 : 2
            color: root.checked ? root.accentColor : Theme.mix(Theme.subtext, root.accentColor, 0.16)

            Behavior on x     { enabled: root._animateX && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutQuart } }
            MotionBehavior on color {ColorAnimation { duration: Motion.fast } }
        }
    }
}
