pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    function widgetGapFor(compact: bool): int {
        return compact ? Math.max(3, ShellSettings.barSpacing - 6)
                       : ShellSettings.barSpacing
    }

    function titleGapFor(compact: bool): int { return compact ? 7 : 10 }

    function pillPadFor(compact: bool): int { return compact ? 2 : 5 }
    function pillGapFor(compact: bool): int { return compact ? 3 : 5 }

    function clockDateGapFor(compact: bool): int { return compact ? 4 : 8 }

    function dotSlotFor(slash: bool, compact: bool): int {
        return compact ? (slash ? 5 : 4) : (slash ? 9 : 8)
    }

    // Fixed icon cell: Text sizes glyphs by ink, which spans 0.64–1.08× the pixel size
    // across the Nerd icon set — a natural-width slot resizes on every glyph swap and
    // shoves the whole row. 1.1× covers the widest measured ink in every offered family.
    function iconCellFor(pixelSize: int): int { return Math.ceil(pixelSize * 1.1) }
}
