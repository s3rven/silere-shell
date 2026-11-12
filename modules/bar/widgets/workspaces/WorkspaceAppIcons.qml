pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../../config"
import "../../../common"

Row {
    id: root

    required property var apps
    required property int iconSize
    required property real pulseOpacity
    property int overflowCount: 0

    spacing: 4
    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
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
            ShellIcon {
                id: _iconSrc
                anchors.centerIn: parent
                side: root.iconSize
                source: appIcon.modelData.icon
                asynchronous: true
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Theme.withAlpha(Theme.barSubtext, 0.12)
                visible: _iconSrc.status === Image.Error
                    || appIcon.modelData.icon.length === 0

                ShellText {
                    anchors.centerIn: parent
                    text: appIcon.modelData.fallback || "?"
                    color: Theme.barSubtext
                    font.pixelSize: Math.max(9, Math.round(root.iconSize * 0.68))
                }
            }

            Rectangle {
                id: _countBadge
                visible: appIcon.modelData.count > 1
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: -1
                anchors.bottomMargin: -1
                width: Metrics.devicePx(6, root._dpr)
                height: width
                radius: width / 2
                antialiasing: true
                color: Theme.barAccent
                transform: PixelSnap { item: _countBadge; dpr: root._dpr }
                OutlineBorder {
                    radius: parent.radius
                    outlineColor: Theme.surface
                }
            }
        }
    }

    ShellText {
        objectName: "workspace-app-overflow"
        anchors.verticalCenter: parent.verticalCenter
        visible: root.overflowCount > 0
        width: Metrics.workspaceOverflowWidthFor(root.overflowCount, root.iconSize)
        text: root.overflowCount > 9 ? "9+" : "+" + root.overflowCount
        color: Theme.barSubtext
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Settings.fontCaption
    }
}
