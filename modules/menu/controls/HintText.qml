import QtQuick
import "../../../config"
import "../../common"

Item {
    id: root

    property string text: ""
    readonly property bool suppressDividerAbove: true
    readonly property int _hPad: Math.max(10, Settings.hPad - 2)
    readonly property int _topPad: 4
    readonly property int _bottomPad: 8
    readonly property int _fontPx: Math.max(8, Settings.fontSize - 2)

    width: parent ? parent.width : 0
    // snapped to 4 so rows below stay on the divider grid
    implicitHeight: 4 * Math.ceil((_text.implicitHeight + _topPad + _bottomPad) / 4)
    clip: true

    ShellText {
        id: _text
        x: root._hPad
        y: root._topPad
        width: Math.max(0, parent.width - root._hPad * 2)
        text:        root.text
        color:       Theme.withAlpha(Theme.subtext, 0.52)
        font.pixelSize: root._fontPx
        wrapMode:    Text.WordWrap
    }
}
