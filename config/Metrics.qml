pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    // shared so selection, focus and section marks rasterize alike at 1.25x
    readonly property int menuMarkerWidth: 3
    readonly property int menuMarkerHeight: 18
    readonly property real menuMarkerRadius: 1.5
    readonly property real menuMarkerOpacity: 0.82

    function widgetGapFor(compact: bool): int {
        return compact ? Math.max(4, Math.round(ShellSettings.barSpacing * 0.5))
                       : ShellSettings.barSpacing
    }

    // the divider owns the whole span between two widgets, not gap + mark + gap
    function dividerSpanFor(compact: bool): int {
        const gap = widgetGapFor(compact)
        return compact ? Math.max(9, gap + 4)
                       : Math.max(14, gap + 6)
    }

    function titleGapFor(compact: bool): int {
        return Math.max(compact ? 6 : 9, widgetGapFor(compact))
    }

    function pillPadFor(compact: bool): int { return compact ? 2 : 5 }
    function pillGapFor(compact: bool): int { return compact ? 3 : 5 }

    function clockDateGapFor(compact: bool): int { return compact ? 4 : 8 }

    // Fixed icon cell: Text sizes glyphs by ink, which spans 0.64–1.08× the pixel size
    // across the Nerd icon set — a natural-width slot resizes on every glyph swap and
    // shoves the whole row. 1.1× covers the widest measured ink in every offered family.
    function iconCellFor(pixelSize: int): int { return Math.ceil(pixelSize * 1.1) }
}
