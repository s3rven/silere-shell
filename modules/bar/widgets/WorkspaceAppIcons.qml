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

    readonly property bool _mono: ShellSettings.wsIconMono && !hoverFx
    // keyed off the setting, not _mono: swapping render paths mid-hover would snap instead of fade
    readonly property bool _fxNeeded: ShellSettings.wsIconMono || ShellSettings.wsIconOpacity < 0.995

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

            Image {
                id: _iconSrc
                anchors.fill: parent
                source: appIcon.modelData.icon
                // exactly the 2x buffer size; a larger texture gets resampled twice and turns to mush
                sourceSize.width: root.iconSize * 2
                sourceSize.height: root.iconSize * 2
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: !root._fxNeeded
            }

            MultiEffect {
                anchors.fill: _iconSrc
                source: _iconSrc
                visible: root._fxNeeded
                opacity: root.hoverFx ? 1.0 : ShellSettings.wsIconOpacity
                saturation: root._mono ? -1.0 : 0.0
                Behavior on opacity {
                    enabled: !ShellSettings.reduceMotion
                    NumberAnimation { duration: Motion.fast }
                }
                Behavior on saturation {
                    enabled: !ShellSettings.reduceMotion
                    NumberAnimation { duration: Motion.fast }
                }
            }

            Rectangle {
                visible: appIcon.modelData.count > 1
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: -1
                anchors.bottomMargin: -1
                width: 6
                height: 6
                radius: 3
                antialiasing: true
                color: Theme.accent
                border.width: 1
                border.color: Theme.surface
            }
        }
    }
}
