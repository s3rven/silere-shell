import QtQuick
import "../../config"

// Shell-wide text defaults. QtRendering, not NativeRendering: distance-field glyphs survive the
// hover and press scales that wrap most button labels, which a rasterised glyph cannot.
Text {
    font.family: Settings.font
    renderType: Text.QtRendering
    textFormat: Text.PlainText
}
