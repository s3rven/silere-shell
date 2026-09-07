.pragma library

// Every transform rebuilds the list it is given rather than mutating it: the models are
// read through bindings, and an in-place edit updates no consumer.

function workspacesWithActivated(src, id, focused) {
    let output = ""
    for (let i = 0; i < src.length; i++)
        if (src[i] && src[i].id === id) { output = src[i].output ?? ""; break }
    const ws = []
    for (let i = 0; i < src.length; i++) {
        const w = src[i]
        if (!w) { ws.push(w); continue }
        const patch = {}
        if (w.output === output) patch.is_active = w.id === id
        if (focused) patch.is_focused = w.id === id
        ws.push(Object.keys(patch).length ? Object.assign({}, w, patch) : w)
    }
    return { workspaces: ws, output: output }
}

function workspacesWithUrgency(src, id, urgent) {
    const ws = src.slice()
    for (let i = 0; i < ws.length; i++)
        if (ws[i] && ws[i].id === id)
            ws[i] = Object.assign({}, ws[i], { is_urgent: urgent })
    return ws
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
        else if (wins[i] && w.is_focused)
            wins[i] = Object.assign({}, wins[i], { is_focused: false })
    }
    if (!found) wins.push(w)
    return wins
}

function windowsWithout(current, id) {
    return current.filter(w => w && w.id !== id)
}

function windowsWithFocus(current, id) {
    const wins = current.slice()
    for (let i = 0; i < wins.length; i++)
        if (wins[i]) wins[i] = Object.assign({}, wins[i], { is_focused: wins[i].id === id })
    return wins
}

function windowsWithFocusStamp(current, id, stamp) {
    const wins = current.slice()
    for (let i = 0; i < wins.length; i++)
        if (wins[i] && wins[i].id === id)
            wins[i] = Object.assign({}, wins[i], { focus_timestamp: stamp })
    return wins
}
