import QtQuick
import "../../config"

// Hover/press fill for a row inside a rounded SettingsCard. One rounded
// Rectangle, clipped so only the corners matching topRadius/bottomRadius round
// off, square corners are pushed outside the clip and cut. A single rect keeps
// the alpha uniform (overlapping rects stacked alpha into a two-tone seam where a
// rounded cap met a flat body). Place with `anchors.fill: parent`.
Item {
    id: root

    property real  topRadius:    0
    property real  bottomRadius: 0
    // Matches the card's border width so the fill sits inside the stroke, aligned
    // with the card's INNER rounded edge.
    property real  cardInset:    1
    property bool  active:       false
    property real  fillOpacity:  0.07
    property color fillColor:    Theme.menuHover

    Item {
        anchors.fill:         parent
        anchors.leftMargin:   root.cardInset
        anchors.rightMargin:  root.cardInset
        anchors.topMargin:    root.topRadius    > 0 ? root.cardInset : 0
        anchors.bottomMargin: root.bottomRadius > 0 ? root.cardInset : 0
        clip: true

        Rectangle {
            // Inner radius = card outer radius − card border width.
            readonly property real innerR: Math.max(
                Math.max(0, root.topRadius    - root.cardInset),
                Math.max(0, root.bottomRadius - root.cardInset)
            )

            // Extend past the clip on any square side so its rounded portion lands
            // outside the clip area and gets cut.
            x: 0
            y: root.topRadius > 0 ? 0 : -innerR
            width:  parent.width
            height: parent.height
                  + (root.topRadius    > 0 ? 0 : innerR)
                  + (root.bottomRadius > 0 ? 0 : innerR)

            radius:       innerR
            antialiasing: innerR > 0
            color:        root.fillColor
            opacity:      root.active ? root.fillOpacity : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
    }
}
