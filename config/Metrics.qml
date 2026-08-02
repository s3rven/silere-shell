pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
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

    // fixed icon cell: Nerd glyph ink spans 0.64-1.08x the px size, so a natural-width slot shoves the row on every glyph swap
    function iconCellFor(pixelSize: int): int { return Math.ceil(pixelSize * 1.1) }
}
