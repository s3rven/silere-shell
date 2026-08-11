import QtQuick

Item {
    id: root

    property string glyph:         ""
    // SettingsCard writes these four; a row must never set them itself
    property real   topRadius:     0
    property real   bottomRadius:  0
    property real   cardInset:     1
    property real   cardLeftBleed: 0

    property bool rowHovered:     false
    property bool rowFocused:     false
    property bool rowInteractive: true

    width:          parent ? parent.width : 0
    implicitHeight: height

    RowHoverBg {
        anchors.fill: parent
        topRadius:    root.topRadius
        bottomRadius: root.bottomRadius
        cardInset:    root.cardInset
        leftBleed:    root.cardLeftBleed
        active:       (root.rowHovered || root.rowFocused) && root.rowInteractive
        focusActive:  root.rowFocused && root.rowInteractive
    }
}
