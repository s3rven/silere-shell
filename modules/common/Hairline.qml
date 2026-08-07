import QtQuick

// 1 logical px, matching OutlineBorder's stroke. it used to be 1/devicePixelRatio, but Qt reports
// dpr 2 while the compositor downscales the buffer to a 1.25 output scale — that made the line
// 0.625 of a real pixel, so it survived or vanished depending on sub-pixel phase.
Rectangle {
    property bool vertical: false

    readonly property real thickness: 1

    implicitWidth: vertical ? thickness : 0
    implicitHeight: vertical ? 0 : thickness
    antialiasing: false
}
