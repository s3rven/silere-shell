import QtQuick
import "../../config"

// Hover/press fill for a row inside a rounded SettingsCard. Per-corner radii
// match whichever card edges this row is flush against (set by SettingsCard._applyRadii).
Item {
    id: root

    property real  topRadius:    0
    property real  bottomRadius: 0
    property real  cardInset:    1
    property bool  active:       false
    property real  fillOpacity:  0.07
    property color fillColor:    Theme.menuHover

    Rectangle {
        readonly property real _topR: Math.max(0, root.topRadius    - root.cardInset)
        readonly property real _botR: Math.max(0, root.bottomRadius - root.cardInset)

        anchors.fill:         parent
        anchors.leftMargin:   root.cardInset
        anchors.rightMargin:  root.cardInset
        anchors.topMargin:    root.topRadius    > 0 ? root.cardInset : 0
        anchors.bottomMargin: root.bottomRadius > 0 ? root.cardInset : 0

        topLeftRadius:     _topR
        topRightRadius:    _topR
        bottomLeftRadius:  _botR
        bottomRightRadius: _botR
        antialiasing:      _topR > 0 || _botR > 0

        color:   root.fillColor
        opacity: root.active ? root.fillOpacity : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
    }
}
