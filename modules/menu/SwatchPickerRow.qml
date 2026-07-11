import QtQuick
import "../../config"
import "../../services"

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

    property real topRadius: 0
    property real bottomRadius: 0
    property real cardInset: 1

    width: parent ? parent.width : 0
    height: 44
    opacity: enabled ? 1.0 : 0.45
    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium } }

    readonly property int _shownIdx: _sr.hoveredIndex >= 0 ? _sr.hoveredIndex : _sr.activeIndex
    readonly property string _shownName: _shownIdx >= 0 && _shownIdx < _sr.options.length
        ? (_sr.options[_shownIdx].name ?? "") : ""

    HoverHandler { id: _hover; enabled: root.enabled }
    RowHoverBg {
        anchors.fill: parent
        topRadius: root.topRadius
        bottomRadius: root.bottomRadius
        cardInset: root.cardInset
        active: _hover.hovered && root.enabled
        fillOpacity: 0.08
    }

    Text {
        id: _glyph
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        visible: root.glyph.length > 0
        width: visible ? 18 : 0
        horizontalAlignment: Text.AlignHCenter
        text:           root.glyph
        color:          Theme.withAlpha(Theme.subtext, 0.85)
        font.family:    Settings.font
        font.pixelSize: Settings.iconSize + 2
        renderType:     Text.NativeRendering
    }
    Text {
        id: _label
        anchors.left: _glyph.right
        anchors.leftMargin: root.glyph.length > 0 ? 10 : 0
        anchors.verticalCenter: parent.verticalCenter
        text:           root.label
        textFormat:     Text.PlainText
        color:          Theme.withAlpha(Theme.text, 0.85)
        font.family:    Settings.font
        font.pixelSize: Settings.fontSize
        renderType:     Text.NativeRendering
    }
    Text {
        anchors.left: _label.right
        anchors.leftMargin: 10
        anchors.right: _sr.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text:           root._shownName
        textFormat:     Text.PlainText
        elide:          Text.ElideRight
        color:          root.tintedReadout && !ShellSettings.highContrast && root._shownIdx >= 0
            ? Theme.mix(Theme.subtext, _sr.colorAt(root._shownIdx), 0.62)
            : Theme.withAlpha(Theme.subtext, 0.7)
        font.family:    Settings.font
        font.pixelSize: Settings.fontSize - 2
        renderType:     Text.NativeRendering
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    SwatchRow {
        id: _sr
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: implicitWidth
        onPicked: (i) => root.picked(i)
    }
}
