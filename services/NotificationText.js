.pragma library

// notification displays are plain text: strip presentation markup only from prose
// commands and examples inside code must keep their tags, entities and punctuation
function prose(source) {
    return source
        .replace(/<\/?(b|i|u|a|span|small|big|tt|markup|sub|sup|s|em|strong|font|img)\b[^>]*>/gi, "")
        .replace(/<br\s*\/?>|<\/?(p|div)\b[^>]*>/gi, " ")
        .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
        .replace(/&quot;/g, "\"").replace(/&apos;/g, "'")
        .replace(/&#(x[0-9a-f]{1,6}|[0-9]{1,7});/gi, (m, n) => {
            const cp = n[0] === "x" || n[0] === "X" ? parseInt(n.slice(1), 16) : parseInt(n, 10)
            return cp > 0 && cp <= 0x10FFFF && (cp < 0xD800 || cp > 0xDFFF) ? String.fromCodePoint(cp) : m
        })
        .replace(/&nbsp;/g, " ").replace(/&hellip;/g, "…")
        .replace(/&amp;/g, "&")
        .replace(/(^|[^\w*])\*\*(?=[^*\s])([^*\n]*?[^*\s])\*\*(?![\w*])/g, "$1$2")
        .replace(/!?\[([^\]\n]+)\]\([^)\s]+\)/g, "$1")
}

function inlineText(source) {
    // NUL is removed from notification text anyway; reserve it for opaque code
    // tokens so surrounding bold/link markup can be cleaned in one pass
    source = source.replace(/\u0000/g, "")
    const runs = []
    const tokens = /`+|\n/g
    let line = 0
    let match
    while ((match = tokens.exec(source)) !== null) {
        if (match[0] === "\n") { line++; continue }
        runs.push({ at: match.index, end: tokens.lastIndex, length: match[0].length, line: line })
    }
    // index matching delimiters once, so many unmatched runs cannot cause repeated scans
    const next = Object.create(null)
    for (let i = runs.length - 1; i >= 0; i--) {
        const run = runs[i]
        const key = run.line + ":" + run.length
        run.close = next[key]
        if (!/\w/.test(source[run.end] || "")) next[key] = i
    }
    const out = []
    const codeParts = []
    let from = 0
    for (let i = 0; i < runs.length; i++) {
        const run = runs[i]
        if (/\w/.test(source[run.at - 1] || "") || run.close === undefined) continue
        const close = runs[run.close]
        let code = source.slice(run.end, close.at)
        // some terminal agents flatten a fenced block to "```lang text ```"
        if (run.length === 3) code = code.replace(/^[\w+#.-]+[ \t]+/, "").trim()
        out.push(source.slice(from, run.at), "\u0000" + codeParts.length + "\u0000")
        codeParts.push(code)
        from = close.end
        i = run.close
    }
    out.push(source.slice(from))
    return prose(out.join("")).replace(/\u0000([0-9]+)\u0000/g, (m, index) => codeParts[Number(index)])
}

function plainText(source) {
    const lines = source.match(/[^\n]*\n|[^\n]+$/g) || []
    const out = []
    let pending = []
    let fence = ""
    for (const chunk of lines) {
        const line = chunk.replace(/\r?\n$/, "")
        if (fence.length > 0) {
            const close = /^ {0,3}(`{3,}|~{3,})[ \t]*$/.exec(line)
            if (close && close[1][0] === fence[0] && close[1].length >= fence.length) fence = ""
            else out.push(chunk)
            continue
        }
        const open = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(line)
        if (open && (open[1][0] === "~" || !open[2].includes("`"))) {
            out.push(inlineText(pending.join("")))
            pending = []
            fence = open[1]
        } else pending.push(chunk)
    }
    out.push(inlineText(pending.join("")))
    return out.join("")
}
