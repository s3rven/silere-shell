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

    // hover surfaces borrow the bar's own corner rounding; a capsule inside a gently rounded bar reads as a foreign shape
    function hoverRadiusFor(size: real): real {
        const corner = ShellSettings.barCornerStyle === "round" ? ShellSettings.barRadius : 0
        return Math.max(3, Math.min(size / 2, corner))
    }

    function clockDateGapFor(compact: bool): int { return compact ? 4 : 8 }

    // one grid for every menu row and button: 4px multiples keep card dividers on whole
    // physical px under fractional scaling, and a row grows past its design height only
    // when the font does, so a raised uiScale cannot crush the label
    function rowHeightFor(design: real): int {
        return 4 * Math.ceil((design
            + Math.max(0, Settings.capHeight - Settings.capHeightBase)) / 4)
    }

    // fixed icon cell: Nerd glyph ink spans 0.64-1.08x the px size, so a natural-width slot shoves the row on every glyph swap
    function iconCellFor(pixelSize: int): int { return Math.ceil(pixelSize * 1.1) }

    // one height for every bar capsule, focus ring and workspace cell, on the menu rows' grid
    readonly property int barRowHeight: rowHeightFor(24)
}
