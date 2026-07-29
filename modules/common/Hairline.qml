import QtQuick
import QtQuick.Window

// one physical pixel at every fractional output scale
Rectangle {
    property bool vertical: false

    readonly property real thickness: 1 / Math.max(1, Screen.devicePixelRatio)

    implicitWidth: vertical ? thickness : 0
    implicitHeight: vertical ? 0 : thickness
    antialiasing: false
}
