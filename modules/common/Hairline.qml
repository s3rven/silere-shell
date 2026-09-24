import QtQuick
import Quickshell

// one device pixel from the window's own ratio; the screen's rounded ratio made 1/dpr 0.625 of a real pixel
Rectangle {
    property bool vertical: false

    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    readonly property real thickness: Math.max(1, Math.ceil(_dpr - 0.5)) / _dpr

    implicitWidth: vertical ? thickness : 0
    implicitHeight: vertical ? 0 : thickness
    antialiasing: false
}
