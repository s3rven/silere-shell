.pragma library

// the rules behind notification history, apart from the service that applies them: how many rows it keeps, when a
// row expires, which rows a full history gives up, and what a saved file or a restored map may bring back

// the history file's format; a file from a later one is left as it is
var storeVersion = 1

// settings.json loads asynchronously: trimming to the default before it lands drops rows a larger configured limit
// keeps, and the trim is written straight back
function capacityFor(limit, ceiling, settingsReady) {
    const configured = Math.max(5, limit)
    return settingsReady ? configured : Math.max(configured, ceiling)
}

function expiredAt(time, days, now, settingsReady) {
    return settingsReady && days > 0 && isFinite(time) && isFinite(now)
        && time <= now - days * 86400000
}

// until the first of these times expires. Qt timers use a signed 32-bit interval: a distant deadline needs a second
// one-shot wait, rather than overflow or a background poll
function expiryDelay(times, days, now) {
    let next = Infinity
    for (let i = 0; i < times.length; i++) next = Math.min(next, times[i] + days * 86400000)
    return isFinite(next) ? Math.max(1, Math.min(2147483647, Math.ceil(next - now))) : 0
}

// a full history takes from the app holding the most rows, its oldest first: one busy chat pushed every other app
// out of the default 20 rows within the hour. Among equals, the app whose oldest row is oldest gives way. Rows are
// newest first; the indices come back highest first
function evictions(apps, capacity) {
    const excess = (apps ? apps.length : 0) - capacity
    if (excess <= 0) return []
    // the rail's key, so the app counted here is the app shown there
    const keys = apps.map(name => String(name ?? "").trim() || "Unknown")
    const counts = Object.create(null)
    for (const key of keys) counts[key] = (counts[key] || 0) + 1
    const gone = keys.map(() => false)
    const out = []
    for (let n = 0; n < excess; n++) {
        let pick = -1
        let most = 0
        for (let i = keys.length - 1; i >= 0; i--) {
            if (!gone[i] && counts[keys[i]] > most) { most = counts[keys[i]]; pick = i }
        }
        gone[pick] = true
        counts[keys[pick]]--
        out.push(pick)
    }
    return out.sort((a, b) => b - a)
}

// the per-notification maps keep an empty prototype, so a malformed key restored from JSON cannot change how they behave
function cloneMap(map) {
    const out = Object.create(null)
    if (!map || typeof map !== "object") return out
    const keys = Object.keys(map)
    for (let i = 0; i < keys.length; i++) out[keys[i]] = map[keys[i]]
    return out
}

// a copy without these keys, or null when none of them is there: an unchanged map keeps its identity, so nothing
// bound to it re-evaluates
function withoutKeys(map, keys) {
    if (!map || typeof map !== "object") return null
    let out = null
    for (let i = 0; i < keys.length; i++) {
        if (!(keys[i] in map)) continue
        if (out === null) out = cloneMap(map)
        delete out[keys[i]]
    }
    return out
}

function parseJson(raw, fallback) {
    try { return JSON.parse(raw || "") }
    catch (e) { return fallback }
}

function validStateId(value) {
    const text = String(value)
    if (!/^(0|[1-9][0-9]{0,9})$/.test(text)) return false
    const id = Number(text)
    return isFinite(id) && id <= 2147483647
}

function seenMapFrom(map) {
    const out = Object.create(null)
    if (!map || typeof map !== "object" || Array.isArray(map)) return out
    const keys = Object.keys(map)
    for (let i = 0; i < keys.length; i++) {
        if (validStateId(keys[i]) && map[keys[i]] === true) out[keys[i]] = true
    }
    return out
}

function timesMapFrom(map) {
    const out = Object.create(null)
    if (!map || typeof map !== "object" || Array.isArray(map)) return out
    const keys = Object.keys(map)
    for (let i = 0; i < keys.length; i++) {
        const value = Number(map[keys[i]])
        if (validStateId(keys[i]) && isFinite(value) && value > 0 && value <= 8.64e15) out[keys[i]] = value
    }
    return out
}

// rowsJson is already compact JSON of the rows; splicing it in skips a parse and a re-stringify
function storeText(rowsJson) {
    return '{"__version":' + storeVersion + ',"history":' + (rowsJson || "[]") + '}'
}

// the rows a saved file holds, and whether a later release wrote it: its entries may carry fields this format would
// drop on the next save. Throws on a file that is not a history at all
function readStore(text) {
    const j = JSON.parse(text || "{}")
    if (j === null || Array.isArray(j) || typeof j !== "object")
        throw new Error("notification history root must be an object")
    const version = Number(j.__version ?? 0)
    const fromFuture = isFinite(version) && version > storeVersion
    if (!fromFuture && j.history !== undefined && !Array.isArray(j.history))
        throw new Error("notification history must be an array")
    return { rows: Array.isArray(j.history) ? j.history : [], fromFuture: fromFuture }
}
