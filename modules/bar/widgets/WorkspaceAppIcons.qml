pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "../../../config"
import "../../../services"

Row {
    id: root

    required property var apps
    required property int iconSize
    required property bool hoverFx
    required property real pulseOpacity

    spacing: 4
    opacity: pulseOpacity
    Behavior on opacity {
        enabled: !ShellSettings.reduceMotion
        NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
    }

    Repeater {
        model: root.apps

        delegate: Item {
            id: appIcon
            required property var modelData
            width: root.iconSize
            height: root.iconSize
            scale: root.hoverFx ? 1.08 : 1.0

            Behavior on scale {
                enabled: !ShellSettings.reduceMotion
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }

            readonly property bool _fxNeeded: ShellSettings.wsIconOpacity < 0.995

            Image {
                id: _iconSrc
                anchors.fill: parent
                source: appIcon.modelData.icon
                sourceSize.width: root.iconSize * 3
                sourceSize.height: root.iconSize * 3
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: !appIcon._fxNeeded
            }

            MultiEffect {
                anchors.fill: _iconSrc
                source: _iconSrc
                visible: appIcon._fxNeeded
                opacity: root.hoverFx ? 1.0 : ShellSettings.wsIconOpacity
                colorization: root.hoverFx ? 0.0 : 1.0 - ShellSettings.wsIconOpacity
                colorizationColor: Theme.accent
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                Behavior on colorization { NumberAnimation { duration: Motion.fast } }
            }

            Row {
                visible: appIcon.modelData.count > 1
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: -2
                anchors.bottomMargin: -2
                spacing: 1.5

                Repeater {
                    model: Math.min(appIcon.modelData.count, 3)
                    Rectangle {
                        width: 3.5
                        height: 3.5
                        radius: 1.75
                        antialiasing: true
                        color: Theme.accent
                        border.width: 0.75
                        border.color: Theme.surface
                    }
                }

                Rectangle {
                    visible: appIcon.modelData.count > 3
                    width: 3.5
                    height: 3.5
                    radius: 1.75
                    antialiasing: true
                    color: "transparent"
                    border.width: 0.75
                    border.color: Theme.accent
                }
            }
        }
    }
}
