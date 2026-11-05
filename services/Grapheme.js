.pragma library

// out of QML on purpose: SafeText runs inside bindings, and a binding records a dependency for every id it looks up,
// without de-duplicating, from a pool Qt never shrinks. Walking a long string through `root` held tens of MB for good
function clip(text, cap) {
    if (text.length <= cap) return text
    const limit = Math.max(0, cap - 1)
    let end = 0
    while (end < text.length) {
        const next = graphemeEnd(text, end)
        if (next > limit) break
        end = next
    }
    return text.slice(0, end) + "…"
}

function codePointWidth(value) {
    return value > 0xFFFF ? 2 : 1
}

function isGraphemeTail(value) {
    return (value >= 0x0300 && value <= 0x036F)
        || (value >= 0x1AB0 && value <= 0x1AFF)
        || (value >= 0x1DC0 && value <= 0x1DFF)
        || (value >= 0x20D0 && value <= 0x20FF)
        || (value >= 0xFE00 && value <= 0xFE0F)
        || (value >= 0xFE20 && value <= 0xFE2F)
        || (value >= 0x1F3FB && value <= 0x1F3FF)
        || (value >= 0xE0100 && value <= 0xE01EF)
        || isIndicMark(value)
}

// devanagari..malayalam share one layout: signs at 00-03, 3a-4f (3d is a letter), 51-57, 62-63
function isIndicMark(value) {
    if (value < 0x0900 || value > 0x0D7F) return false
    const o = value & 0x7F
    return o <= 0x03 || (o >= 0x3A && o <= 0x4F && o !== 0x3D)
        || (o >= 0x51 && o <= 0x57) || o === 0x62 || o === 0x63
}

function graphemeEnd(text, start) {
    let at = start
    const first = text.codePointAt(at)
    at += codePointWidth(first)
    if (first >= 0x1F1E6 && first <= 0x1F1FF && at < text.length) {
        const pair = text.codePointAt(at)
        if (pair >= 0x1F1E6 && pair <= 0x1F1FF)
            at += codePointWidth(pair)
    }
    while (at < text.length) {
        const value = text.codePointAt(at)
        if (isGraphemeTail(value)) {
            at += codePointWidth(value)
            // a virama joins the next consonant into the same conjunct
            if (value >= 0x0900 && value <= 0x0D7F && (value & 0x7F) === 0x4D && at < text.length) {
                const next = text.codePointAt(at)
                if (next >= 0x0900 && next <= 0x0D7F && !isIndicMark(next))
                    at += codePointWidth(next)
            }
            continue
        }
        if (value !== 0x200D) break
        at += 1
        if (at >= text.length) break
        const joined = text.codePointAt(at)
        at += codePointWidth(joined)
    }
    return at
}
