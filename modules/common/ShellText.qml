import QtQuick
import "../../config"

// shell-wide text defaults. QtRendering, not NativeRendering: distance-field glyphs survive the
// hover and press scales that wrap most button labels, which a rasterised glyph cannot
Text {
    font.family: Settings.fontForText(text)
    renderType: Text.QtRendering
    textFormat: Text.PlainText
    // left to itself, Text right-aligns Hebrew or Arabic, so a network or device name in a row drifted away from its
    // icon into the status beside it. Labels keep to the start; a message paragraph, such as a notification's body,
    // sets its own alignment from the direction of its first letter
    horizontalAlignment: Text.AlignLeft
}
