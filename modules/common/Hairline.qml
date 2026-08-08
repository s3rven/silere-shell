import QtQuick

// 1 logical px, never 1/dpr: Qt reports dpr 2 while the compositor downscales to 1.25, making that 0.625 real px
Rectangle {
    property bool vertical: false

    readonly property real thickness: 1

    implicitWidth: vertical ? thickness : 0
    implicitHeight: vertical ? 0 : thickness
    antialiasing: false
}
