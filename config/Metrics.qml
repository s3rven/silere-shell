pragma Singleton

import QtQuick
import Quickshell
import "../services"

// bar spacing tokens — replaces scattered barCompact ? a : b in BarContent/Pill/Dot.
// every token takes `compact` as an argument: callers must pass BarContent.effectiveCompact, which folds in
// auto-tighten. a token reading ShellSettings.barCompact itself would silently ignore it and skew the gaps.
Singleton {
    // gap between widgets; Spacing = Tight/Normal/Loose (8/11/15); compact reduces it
    function widgetGapFor(compact: bool): int {
        return compact ? Math.max(3, ShellSettings.barSpacing - 6)
                       : ShellSettings.barSpacing
    }

    // Clearance the centered window title keeps from each side group.
    function titleGapFor(compact: bool): int { return compact ? 7 : 10 }

    // Internal (kept ≤ widgetGap) — a pill's horizontal padding and glyph↔text gap.
    function pillPadFor(compact: bool): int { return compact ? 2 : 5 }
    function pillGapFor(compact: bool): int { return compact ? 3 : 5 }

    function clockDateGapFor(compact: bool): int { return compact ? 4 : 8 }

    // Width a shown divider reserves; the slash mark leans a touch wider.
    function dotSlotFor(slash: bool, compact: bool): int {
        return compact ? (slash ? 5 : 4) : (slash ? 9 : 8)
    }

    // Fixed icon cell: Text sizes glyphs by ink, which spans 0.64–1.08× the pixel size
    // across the Nerd icon set — a natural-width slot resizes on every glyph swap and
    // shoves the whole row. 1.1× covers the widest measured ink in every offered family.
    function iconCellFor(pixelSize: int): int { return Math.ceil(pixelSize * 1.1) }
}
