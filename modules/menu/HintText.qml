import QtQuick
import "../../config"

Item {
    id: root

    property string text: ""
    // tells SettingsCard not to draw a divider above this item (it's a
    // sub-note for the row above, not a new section)
    readonly property bool suppressDividerAbove: true

    width: parent ? parent.width : 0
    // snapped to 4 so rows below stay on the divider grid
    implicitHeight: 4 * Math.ceil((_text.implicitHeight + 12) / 4)

    Text {
        id: _text
        x: 12; y: 4
        width: parent.width - 12 - 12
        text:        root.text
        color:       Theme.withAlpha(Theme.subtext, 0.52)
        font.family: Settings.font
        font.pixelSize: Settings.fontSize - 2
        renderType:  Text.NativeRendering
        wrapMode:    Text.WordWrap
    }
}
