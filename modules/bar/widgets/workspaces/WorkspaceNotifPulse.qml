pragma ComponentBehavior: Bound

import QtQuick
import "../../../../config"
import "../../../../services"

Item {
    id: root

    required property bool barActive
    property real pulse: 0
    property bool critical: false
    signal finished()

    function _settle(): void {
        _pulseAnim.stop()
        root.pulse = 0
        root.finished()
    }

    function play(isCritical: bool): void {
        if (!root.barActive || ShellSettings.reduceMotion || Idle.isIdle) {
            root.finished()
            return
        }
        root.critical = isCritical
        _pulseAnim.restart()
    }

    onBarActiveChanged: if (!barActive) root._settle()

    Rectangle {
        anchors.centerIn: parent
        width: 24
        height: 24
        radius: 12
        antialiasing: true
        color: root.critical ? Theme.error : Theme.accent
        opacity: root.pulse * 0.10
        visible: opacity > 0.01
    }

    Rectangle {
        anchors.centerIn: parent
        width: 14
        height: 14
        radius: 7
        antialiasing: true
        color: root.critical ? Theme.error : Theme.accent
        opacity: root.pulse * 0.22
        visible: opacity > 0.01
    }

    Rectangle {
        anchors.centerIn: parent
        width: 7
        height: 7
        radius: 3.5
        antialiasing: true
        color: root.critical ? Theme.error : Theme.accent
        opacity: root.pulse * 0.50
        visible: opacity > 0.01
    }

    Connections {
        target: ShellSettings
        function onWsNotifPulseChanged() {
            if (!ShellSettings.wsNotifPulse) root._settle()
        }
        function onReduceMotionChanged() {
            if (ShellSettings.reduceMotion) root._settle()
        }
    }

    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (Idle.isIdle) root._settle()
        }
    }

    SequentialAnimation {
        id: _pulseAnim
        onFinished: root.finished()
        NumberAnimation {
            target: root
            property: "pulse"
            to: 1.0
            duration: Motion.ms(150)
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "pulse"
            to: 0.0
            duration: Motion.ms(1100)
            easing.type: Easing.OutCubic
        }
    }
}
