pragma Singleton

import QtQuick
import Quickshell

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
        if (text.length <= cap) return text
        const limit = Math.max(0, cap - 1)
        let end = 0
        while (end < text.length) {
            const next = root._graphemeEnd(text, end)
            if (next > limit) break
            end = next
        }
        return text.slice(0, end) + "…"
    }

    function _codePointWidth(value: int): int {
        return value > 0xFFFF ? 2 : 1
    }

    function _isGraphemeTail(value: int): bool {
        return (value >= 0x0300 && value <= 0x036F)
            || (value >= 0x1AB0 && value <= 0x1AFF)
            || (value >= 0x1DC0 && value <= 0x1DFF)
            || (value >= 0x20D0 && value <= 0x20FF)
            || (value >= 0xFE00 && value <= 0xFE0F)
            || (value >= 0xFE20 && value <= 0xFE2F)
            || (value >= 0x1F3FB && value <= 0x1F3FF)
            || (value >= 0xE0100 && value <= 0xE01EF)
            || root._isIndicMark(value)
    }

    // devanagari..malayalam share one layout: signs at 00-03, 3a-4f (3d is a letter), 51-57, 62-63
    function _isIndicMark(value: int): bool {
        if (value < 0x0900 || value > 0x0D7F) return false
        const o = value & 0x7F
        return o <= 0x03 || (o >= 0x3A && o <= 0x4F && o !== 0x3D)
            || (o >= 0x51 && o <= 0x57) || o === 0x62 || o === 0x63
    }

    function _graphemeEnd(text: string, start: int): int {
        let at = start
        const first = text.codePointAt(at)
        at += root._codePointWidth(first)
        if (first >= 0x1F1E6 && first <= 0x1F1FF && at < text.length) {
            const pair = text.codePointAt(at)
            if (pair >= 0x1F1E6 && pair <= 0x1F1FF)
                at += root._codePointWidth(pair)
        }
        while (at < text.length) {
            const value = text.codePointAt(at)
            if (root._isGraphemeTail(value)) {
                at += root._codePointWidth(value)
                // a virama joins the next consonant into the same conjunct
                if (value >= 0x0900 && value <= 0x0D7F && (value & 0x7F) === 0x4D && at < text.length) {
                    const next = text.codePointAt(at)
                    if (next >= 0x0900 && next <= 0x0D7F && !root._isIndicMark(next))
                        at += root._codePointWidth(next)
                }
                continue
            }
            if (value !== 0x200D) break
            at += 1
            if (at >= text.length) break
            const joined = text.codePointAt(at)
            at += root._codePointWidth(joined)
        }
        return at
    }

    function boundedText(value, limit): string {
        return root._clip(String(value ?? ""), root._cap(limit, root.maxIdentityChars))
    }

    // Labels supplied by other processes belong on one visual/accessibility
    // line. C0/C1 controls can break layout, while bidi embedding/override
    // controls can make a title appear to say something other than its value.
    // Natural RTL text still works without those explicit formatting controls.
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

    // stderr from a package helper or gamma tool is often several lines of
    // noise; the last non-empty one is usually the actual failure
    function lastNonEmptyLine(value, fallback: string, limit): string {
        const lines = String(value ?? "").split(/\r?\n/)
        for (let i = lines.length - 1; i >= 0; i--) {
            const line = lines[i].trim()
            if (line.length > 0) return root.singleLineText(line, limit)
        }
        return fallback
    }

    function initial(value, fallback: string): string {
        const text = root.singleLineText(value, 128)
        if (text.length === 0) return fallback
        return text.slice(0, root._graphemeEnd(text, 0)).toUpperCase()
    }
}
