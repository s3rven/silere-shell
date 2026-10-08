.pragma library

// Changed rows get a new object and list so bindings see them. Unchanged events keep
// the original list, avoiding a rebuild of every workspace and window consumer.

function focusedWorkspaceChangeOutput(previous, next) {
    let oldId = null
    for (let i = 0; i < previous.length; i++)
        if (previous[i] && previous[i].is_focused) { oldId = previous[i].id; break }
    for (let i = 0; i < next.length; i++)
        if (next[i] && next[i].is_focused)
            return next[i].id === oldId ? null : (next[i].output ?? "")
    return null
}

function workspacesWithActivated(src, id, focused) {
    let target = null
    for (let i = 0; i < src.length; i++)
        if (src[i] && src[i].id === id) { target = src[i]; break }
    // a late activation can name a workspace removed by the preceding snapshot
    if (!target) return { workspaces: src, output: "" }
    const output = target.output ?? ""
    let ws = src
    for (let i = 0; i < src.length; i++) {
        const w = src[i]
        if (!w) continue
        const activeChanged = (w.output ?? "") === output && !!w.is_active !== (w.id === id)
        const focusChanged = focused && !!w.is_focused !== (w.id === id)
        if (!activeChanged && !focusChanged) continue
        if (ws === src) ws = src.slice()
        const next = Object.assign({}, w)
        if (activeChanged) next.is_active = w.id === id
        if (focusChanged) next.is_focused = w.id === id
        ws[i] = next
    }
    return { workspaces: ws, output: output }
}

function workspacesWithUrgency(src, id, urgent) {
    for (let i = 0; i < src.length; i++) {
        if (!src[i] || src[i].id !== id) continue
        if (!!src[i].is_urgent === urgent) return src
        const ws = src.slice()
        ws[i] = Object.assign({}, src[i], { is_urgent: urgent })
        return ws
    }
    return src
}

function indexOfWindow(current, id) {
    for (let i = 0; i < current.length; i++)
        if (current[i] && current[i].id === id) return i
    return -1
}

// a newly focused window unfocuses every other one in the same pass, so the model never
// reports two focused windows between events
function windowsWithUpsert(current, w) {
    const wins = current.slice()
    let found = false
    for (let i = 0; i < wins.length; i++) {
        if (wins[i] && wins[i].id === w.id) { wins[i] = w; found = true }
        else if (wins[i] && w.is_focused && wins[i].is_focused)
            wins[i] = Object.assign({}, wins[i], { is_focused: false })
    }
    if (!found) wins.push(w)
    return wins
}

function windowsWithout(current, id) {
    if (indexOfWindow(current, id) < 0) return current
    return current.filter(w => w && w.id !== id)
}

function windowsWithFocus(current, id) {
    let wins = current
    for (let i = 0; i < current.length; i++) {
        const w = current[i]
        if (!w || !!w.is_focused === (w.id === id)) continue
        if (wins === current) wins = current.slice()
        wins[i] = Object.assign({}, w, { is_focused: w.id === id })
    }
    return wins
}

function windowsWithFocusStamp(current, id, stamp) {
    const at = indexOfWindow(current, id)
    if (at < 0) return current
    const previous = current[at].focus_timestamp
    if (previous === stamp || (previous && stamp
            && previous.secs === stamp.secs && previous.nanos === stamp.nanos)) return current
    const wins = current.slice()
    wins[at] = Object.assign({}, current[at], { focus_timestamp: stamp })
    return wins
}
