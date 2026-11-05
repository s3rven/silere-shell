pragma Singleton

import QtQuick
import Quickshell
import "Grapheme.js" as Grapheme

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
        return Grapheme.clip(text, cap)
    }

    function boundedText(value, limit): string {
        return root._clip(String(value ?? ""), root._cap(limit, root.maxIdentityChars))
    }

    // labels supplied by other processes belong on one visual/accessibility
    // line. C0/C1 controls can break layout, while bidi embedding/override
    // controls can make a title appear to say something other than its value.
    // Natural RTL text still works without those explicit formatting controls
    function singleLineText(value, limit): string {
        const cap = root._cap(limit, root.maxIdentityChars)
        const raw = String(value ?? "")
        // bounded before the regexes: a runaway title would otherwise be scanned whole on every change
        const text = (raw.length > cap * 8 + 64 ? raw.slice(0, cap * 8 + 64) : raw)
            .replace(/[\u0000-\u001F\u007F-\u009F\u061C\u200B\u200E\u200F\u202A-\u202E\u2066-\u206F]/g, " ")
            .replace(/\s+/g, " ")
            .trim()
        return root._clip(text, cap)
    }

    // stderr from a package helper or gamma tool is often several lines of noise; the last non-empty one is usually the actual failure
    function lastNonEmptyLine(value, fallback: string, limit): string {
        const text = String(value ?? "")
        let end = text.length
        while (end > 0) {
            const start = text.lastIndexOf("\n", end - 1) + 1
            const line = root.singleLineText(text.slice(start, end).trim(), limit)
            if (line.length > 0) return line
            end = start - 1
        }
        return fallback
    }

    function initial(value, fallback: string): string {
        const text = root.singleLineText(value, 128)
        if (text.length === 0) return fallback
        return text.slice(0, Grapheme.graphemeEnd(text, 0)).toUpperCase()
    }
}
