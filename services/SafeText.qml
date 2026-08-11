pragma Singleton

import QtQuick
import Quickshell

// One place for turning text that another program supplied into something safe
// to lay out. Every service that reads a window title, player tag, device name
// or process output goes through here rather than truncating on its own.
Singleton {
    id: root

    readonly property int maxIdentityChars: 512
    readonly property int maxTextChars: 65536

    function _cap(limit, fallback: int): int {
        const requested = Number(limit)
        return isFinite(requested) && requested > 0
            ? Math.min(root.maxTextChars, Math.floor(requested)) : fallback
    }

    function _clip(text: string, cap: int): string {
        return text.length <= cap ? text : text.slice(0, Math.max(0, cap - 1)) + "…"
    }

    function boundedText(value, limit): string {
        return root._clip(String(value ?? ""), root._cap(limit, root.maxIdentityChars))
    }

    // Labels supplied by other processes belong on one visual/accessibility
    // line. C0/C1 controls can break layout, while bidi embedding/override
    // controls can make a title appear to say something other than its value.
    // Natural RTL text still works without those explicit formatting controls.
    function singleLineText(value, limit): string {
        const text = String(value ?? "")
            .replace(/[\u0000-\u001F\u007F-\u009F\u202A-\u202E\u2066-\u2069]/g, " ")
            .replace(/\s+/g, " ")
            .trim()
        return root._clip(text, root._cap(limit, root.maxIdentityChars))
    }

    // charAt() hands back half a surrogate pair, so a name starting with an emoji
    // renders as tofu; codePointAt is the only unicode-aware read in this engine
    function initial(value, fallback: string): string {
        const text = root.singleLineText(value, 128)
        if (text.length === 0) return fallback
        return String.fromCodePoint(text.codePointAt(0)).toUpperCase()
    }
}
