import QtQuick
import Quickshell
import "../../config/PixelGeometry.js" as PixelGeometry

// one device pixel from the window's own ratio; the screen's rounded ratio made 1/dpr 0.625 of a real pixel
Rectangle {
    property bool vertical: false

    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    readonly property real thickness: PixelGeometry.stroke(1, _dpr)

    implicitWidth: vertical ? thickness : 0
    implicitHeight: vertical ? 0 : thickness
    antialiasing: false
}
