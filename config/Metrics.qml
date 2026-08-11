pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    // an arm-then-confirm row must reject the second half of a double-click; not a Motion
    // token because every one of those returns 0 under reduce motion, which would re-arm the trap
    readonly property int confirmGuardMs: 400

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
        return Math.max(3, Math.min(size / 2, ShellSettings.barRadius))
    }

    function clockDateGapFor(compact: bool): int { return compact ? 4 : 8 }

    // 4px multiples keep dividers on whole physical px under fractional scaling; grows only with the font
    function rowHeightFor(design: real): int {
        return 4 * Math.ceil((design
            + Math.max(0, Settings.capHeight - Settings.capHeightBase)) / 4)
    }

    // fixed icon cell: Nerd glyph ink spans 0.64-1.08x the px size, so a natural-width slot shoves the row on every glyph swap
    function iconCellFor(pixelSize: int): int { return Math.ceil(pixelSize * 1.1) }

    // one height for every bar capsule, focus ring and workspace cell, on the menu rows' grid
    readonly property int barRowHeight: rowHeightFor(24)

    // how far the bar surface sits from the screen edge; every surface that hugs the bar derives from this,
    // so bar geometry has one definition instead of a copy per popup
    readonly property int barEdgeInset: ShellSettings.barFloating ? ShellSettings.barGap : 0

    // the track title sizes to its text and marquees past this; a reserved slot left the pill
    // padded out on short titles and dragged the visualiser along with it
    readonly property int mediaTrackWidth: 160
}
