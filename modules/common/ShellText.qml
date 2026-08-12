import QtQuick
import "../../config"

// Shell-wide text defaults. QtRendering, not NativeRendering: the outputs run at scale
// 1.25 but Qt reports dpr 2, so the compositor already resamples every buffer by 0.625 and
// there is no device pixel grid left to snap to. Distance-field glyphs also survive the
// hover and press scales that wrap most button labels, which a rasterised glyph cannot.
Text {
    font.family: Settings.font
    renderType: Text.QtRendering
    textFormat: Text.PlainText
}
