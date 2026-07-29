import QtQuick
import "../../config"

// shell-wide text defaults; NativeRendering keeps glyphs crisp under fractional scale
Text {
    font.family: Settings.font
    renderType: Text.NativeRendering
    textFormat: Text.PlainText
}
