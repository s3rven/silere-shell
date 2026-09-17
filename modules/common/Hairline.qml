import QtQuick

// 1 logical px, never 1/dpr: dpr reports 2 while the output scale is 1.25, so 1/dpr is 0.625 of a
// real pixel and survives or vanishes on sub-pixel phase alone
Rectangle {
    property bool vertical: false

    readonly property real thickness: 1

    implicitWidth: vertical ? thickness : 0
    implicitHeight: vertical ? 0 : thickness
    antialiasing: false
}
