import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property alias options: _sr.options
    property alias colors: _sr.colors
    property alias activeIndex: _sr.activeIndex
    property alias ringColor: _sr.ringColor
    property bool tintedReadout: false

    signal picked(int index)

    readonly property real _inlineNeededW: 14
        + (root.glyph.length > 0 ? 28 : 0)
        + Math.ceil(_label.implicitWidth)
        + 8 + Math.min(84, Math.ceil(_readout.implicitWidth))
        + 10 + _sr.implicitWidth + 12
    readonly property bool _stacked: root.width > 0
        && root._inlineNeededW > root.width
    readonly property int _headerH: 4 * Math.ceil(Math.max(40,
        _glyph.implicitHeight + 12, _label.implicitHeight + 12,
        _readout.visible ? _readout.implicitHeight + 12 : 0) / 4)
    readonly property int _stackedH: 4 * Math.ceil((root._headerH
        + _sr.implicitHeight) / 4)

    width: parent ? parent.width : 0
    height: _stacked ? root._stackedH : root._headerH
    opacity: enabled ? 1.0 : 0.45
    MotionBehavior on opacity {NumberAnimation { duration: Motion.medium } }

    readonly property int _shownIdx: _sr.hoveredIndex >= 0 ? _sr.hoveredIndex : _sr.activeIndex
    readonly property string _shownName: _shownIdx >= 0 && _shownIdx < _sr.options.length
        ? (_sr.options[_shownIdx].name ?? "") : ""

    ShellText {
        id: _glyph
        anchors.left: parent.left
        anchors.leftMargin: 14
        y: Math.round((root._headerH - height) / 2)
        visible: root.glyph.length > 0
        width: visible ? 18 : 0
        horizontalAlignment: Text.AlignHCenter
        text:           root.glyph
        color:          Theme.withAlpha(Theme.subtext, 0.85)
        font.pixelSize: Settings.iconSize + 2
    }
    ShellText {
        id: _label
        anchors.left: _glyph.right
        anchors.leftMargin: root.glyph.length > 0 ? 10 : 0
        anchors.verticalCenter: _glyph.verticalCenter
        anchors.right: _readout.visible ? _readout.left
            : (root._stacked ? parent.right : _sr.left)
        anchors.rightMargin: 10
        text:           root.label
        elide:          Text.ElideRight
        color:          Theme.withAlpha(Theme.text, 0.85)
        font.pixelSize: Settings.fontSize
    }
    ShellText {
        id: _readout
        visible: root._shownName.length > 0
        anchors.right: root._stacked ? parent.right : _sr.left
        anchors.rightMargin: root._stacked ? 12 : 10
        anchors.verticalCenter: _glyph.verticalCenter
        width: Math.min(84, implicitWidth)
        horizontalAlignment: Text.AlignRight
        text:           root._shownName
        elide:          Text.ElideRight
        color:          root.tintedReadout && !ShellSettings.highContrast && root._shownIdx >= 0
            ? Theme.mix(Theme.subtext, _sr.colorAt(root._shownIdx), 0.62)
            : Theme.withAlpha(Theme.subtext, 0.7)
        font.pixelSize: Settings.fontCaption
        ColorFade on color {}
    }

    SwatchRow {
        id: _sr
        anchors.right: parent.right
        anchors.rightMargin: 12
        y: root._stacked
            ? root.height - height - 4
            : Math.round((root.height - height) / 2)
        width: implicitWidth
        height: implicitHeight
        groupLabel: root.label
        onPicked: (i) => root.picked(i)
    }
}
