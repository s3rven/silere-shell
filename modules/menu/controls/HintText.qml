import QtQuick
import "../../../config"
import "../../common"

Item {
    id: root

    property string text: ""
    property color textColor: Theme.menuTextDetail
    readonly property bool suppressDividerAbove: true
    // the row text spine: 14 card pad + 18 icon + 10 gap; dividers keep the bare 14
    readonly property int _leftPad: 42
    readonly property int _rightPad: 14
    readonly property int _topPad: 4
    readonly property int _bottomPad: 8
    readonly property int _fontPx: Settings.fontCaption

    width: parent ? parent.width : 0
    // snapped to 4 so rows below stay on the divider grid
    implicitHeight: 4 * Math.ceil((_text.implicitHeight + _topPad + _bottomPad) / 4)
    clip: true

    ShellText {
        id: _text
        x: root._leftPad
        y: root._topPad
        width: Math.max(0, parent.width - root._leftPad - root._rightPad)
        text:        root.text
        color:       root.textColor
        ColorFade on color {}
        font.pixelSize: root._fontPx
        wrapMode:    Text.WordWrap
    }
}
