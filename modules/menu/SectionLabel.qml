import QtQuick
import "../../config"

// Sub-group heading inside a settings page: an accent tick + uppercase mono
// label + a hairline rule that runs to the right edge, so groups of cards read
// as labelled sections rather than floating apart. Carries its own breathing
// room (a gap above, a small gap to the card below) so callers don't sprinkle
// spacer Items — set `first: true` for the first label in a section, which sits
// just under the page header and so wants almost no gap above.
Item {
    id: root

    property string label: ""
    property bool   first: false

    readonly property int _topGap: first ? 2 : Theme.gapSection
    readonly property int _botGap: 6

    width: parent ? parent.width : 0
    // 4px grid so the cards below stay on whole physical px under fractional
    // scaling; the rounding slack falls into the (invisible) gap above.
    implicitHeight: 4 * Math.ceil((_topGap + _text.implicitHeight + _botGap) / 4)
    height: implicitHeight

    Rectangle {
        id: _tick
        anchors.left:           parent.left
        anchors.leftMargin:     2
        anchors.verticalCenter: _text.verticalCenter
        width:  3
        height: Math.round(_text.implicitHeight * 0.82)
        radius: 1.5
        antialiasing: true
        color:  Theme.withAlpha(Theme.accent, 0.75)
    }

    Text {
        id: _text
        anchors.left:         _tick.right
        anchors.leftMargin:   7
        anchors.bottom:       parent.bottom
        anchors.bottomMargin: root._botGap
        // A whisper of accent so the heading reads as part of the accent system
        // (like the sidebar group labels) rather than flat grey; the tick carries
        // most of the accent, the text only leans into it.
        text:        root.label
        color:       Theme.withAlpha(Theme.mix(Theme.subtext, Theme.accent, 0.22), 0.74)
        font.family: Settings.font
        font.pixelSize: Settings.fontSize - 3
        font.letterSpacing:  0.4
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        renderType:  Text.NativeRendering
    }

    Rectangle {
        anchors.left:           _text.right
        anchors.leftMargin:     10
        anchors.right:          parent.right
        anchors.rightMargin:    0
        anchors.verticalCenter: _text.verticalCenter
        height: 1
        color:  Theme.withAlpha(Theme.subtext, 0.10)
    }
}
