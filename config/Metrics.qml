pragma Singleton

import QtQuick
import Quickshell
import "../services"

// bar spacing tokens — replaces scattered barCompact ? a : b in BarContent/Pill/Dot
Singleton {
    readonly property bool _compact: ShellSettings.barCompact

    // gap between widgets; Spacing = Tight/Normal/Loose (8/11/15); compact reduces it
    function widgetGapFor(compact: bool): int {
        return compact ? Math.max(3, ShellSettings.barSpacing - 6)
                       : ShellSettings.barSpacing
    }
    readonly property int widgetGap: widgetGapFor(_compact)

    // Clearance the centered window title keeps from each side group.
    function titleGapFor(compact: bool): int { return compact ? 7 : 10 }
    readonly property int titleGap:  titleGapFor(_compact)

    // Internal (kept ≤ widgetGap) — a pill's horizontal padding and glyph↔text gap.
    function pillPadFor(compact: bool): int { return compact ? 2 : 5 }
    function pillGapFor(compact: bool): int { return compact ? 3 : 5 }
    readonly property int pillPad:   pillPadFor(_compact)
    readonly property int pillGap:   pillGapFor(_compact)

    function clockDateGapFor(compact: bool): int { return compact ? 4 : 8 }

    // Width a shown divider reserves; the slash mark leans a touch wider.
    function dotSlotFor(slash: bool, compact: bool): int {
        return compact ? (slash ? 5 : 4) : (slash ? 9 : 8)
    }
    function dotSlot(slash: bool): int { return dotSlotFor(slash, _compact) }

    // Fixed icon cell: Text sizes glyphs by ink, which spans 0.64–1.08× the pixel size
    // across the Nerd icon set — a natural-width slot resizes on every glyph swap and
    // shoves the whole row. 1.1× covers the widest measured ink in every offered family.
    function iconCellFor(pixelSize: int): int { return Math.ceil(pixelSize * 1.1) }
}
