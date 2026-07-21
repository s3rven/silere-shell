pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"

Item {
    id: root

    required property int workspaceId
    property real pulse: 0
    property bool critical: false

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
        target: Notifications
        enabled: !ShellSettings.reduceMotion
        function onSourcePulse(wsId, critical) {
            if (wsId !== root.workspaceId) return
            root.critical = critical
            _pulseAnim.restart()
        }
    }

    Connections {
        target: ShellSettings
        function onReduceMotionChanged() {
            if (!ShellSettings.reduceMotion) return
            _pulseAnim.stop()
            root.pulse = 0
        }
    }

    SequentialAnimation {
        id: _pulseAnim
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
