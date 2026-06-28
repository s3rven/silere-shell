pragma Singleton

import QtQuick
import Quickshell
import "../services"

// bar spacing tokens — replaces scattered barCompact ? a : b in BarContent/Pill/Dot
Singleton {
    readonly property bool _compact: ShellSettings.barCompact

    // gap between widgets; Spacing = Tight/Normal/Loose (8/11/15); compact reduces it
    readonly property int widgetGap: _compact ? Math.max(3, ShellSettings.barSpacing - 6)
                                              : ShellSettings.barSpacing
    // Clearance the centered window title keeps from each side group.
    readonly property int titleGap:  _compact ? 7 : 10

    // Internal (kept ≤ widgetGap) — a pill's horizontal padding and glyph↔text gap.
    readonly property int pillPad:   _compact ? 2 : 5
    readonly property int pillGap:   _compact ? 3 : 5

    // Width a shown divider reserves; the slash mark leans a touch wider.
    function dotSlot(slash: bool): int {
        return _compact ? (slash ? 5 : 4) : (slash ? 9 : 8)
    }
}
