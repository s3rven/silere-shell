pragma ComponentBehavior: Bound

import QtQuick
import "../../../../config"
import "../../../common"

Row {
    id: root

    required property var apps
    required property int iconSize
    required property real pulseOpacity

    spacing: 4
    // already eased by the urgent pulse; a second animation here only lags it
    opacity: pulseOpacity

    Repeater {
        model: root.apps

        delegate: Item {
            id: appIcon
            required property var modelData
            width: root.iconSize
            height: root.iconSize

            // in the app's own colours, like the tray: a muted icon only reads as a disabled one
            Image {
                id: _iconSrc
                anchors.fill: parent
                source: appIcon.modelData.icon
                // exactly the 2x buffer size; a larger texture gets resampled twice and turns to mush
                sourceSize.width: root.iconSize * 2
                sourceSize.height: root.iconSize * 2
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Theme.withAlpha(Theme.subtext, 0.12)
                visible: _iconSrc.status === Image.Error
                    || appIcon.modelData.icon.length === 0

                ShellText {
                    anchors.centerIn: parent
                    text: appIcon.modelData.fallback || "?"
                    color: Theme.subtext
                    font.pixelSize: Math.max(9, Math.round(root.iconSize * 0.68))
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
                OutlineBorder {
                    radius: parent.radius
                    outlineColor: Theme.surface
                }
            }
        }
    }
}
