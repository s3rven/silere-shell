import QtQuick
import "../../config"

Item {
    id: root

    property string text: ""
    property string kind: ""

    readonly property string _kind: (kind.length > 0 ? kind : text).toLowerCase()
    readonly property color tint:
        _kind === "beta" || _kind === "warn" || _kind === "fallback" ? Theme.warning
      : _kind === "custom" || _kind === "ok" ? Theme.success
      : _kind === "error" ? Theme.error
      : _kind === "tool" || _kind === "cava" || _kind === "matugen"
            || _kind === "hyprsunset" || _kind === "inotify" || _kind === "systemd"
            || _kind === "pkg" || _kind === "multi" ? Theme.accent
      : Theme.subtext

    visible: text.length > 0
    implicitWidth:  _label.implicitWidth + 9
    implicitHeight: _label.implicitHeight + 3
    width:  visible ? implicitWidth : 0
    height: visible ? implicitHeight : 0

    Rectangle {
        anchors.fill: parent
        radius: 3
        antialiasing: true
        color: Theme.withAlpha(root.tint, 0.10)
        border.width: 1
        border.color: Theme.withAlpha(root.tint, 0.30)
    }

    Text {
        id: _label
        anchors.centerIn: parent
        text: root.text
        color: Theme.withAlpha(root.tint, 0.9)
        font.family: Settings.font
        font.pixelSize: Math.max(7, Settings.fontSize - 4)
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0
        renderType: Text.NativeRendering
    }
}
