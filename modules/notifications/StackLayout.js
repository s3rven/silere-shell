.pragma library

// a multiple of 4 like the chips, or every card under the clear chip lands half an output pixel off at 1.25
var columnSpacing = 8

// one pass serves every card's position and the viewport height. Reading the live
// slots here lets the QML binding follow height changes throughout an animation
function measure(stack, newestFirst) {
    const tops = new Array(stack.count)
    let height = 0
    for (let step = 0; step < stack.count; step++) {
        const index = newestFirst ? stack.count - 1 - step : step
        tops[index] = height
        const slot = stack.itemAt(index)
        if (slot && slot.shouldLoad) height += slot.height
    }
    return { tops: tops, height: height }
}

// a leaving card keeps its slot until its exit ends: unloading it then destroys the card before it can ask
// to be dismissed, so the notification stayed in the stack and came back once the stack shrank.
// A card with a reply open keeps it too: a newer notification would otherwise destroy the draft
function slotLoads(index, count, maxVisible, showAll, critical, leaving, replying) {
    return leaving || replying || showAll || maxVisible <= 0 || index < 0 || index >= count - maxVisible || critical
}

// a removed slot keeps the state captured before its index became -1. The caller must not read
// the loader this decision controls, or folding and destroying its card re-enters the binding
function slotInLimit(index, count, maxVisible, showAll, critical, leaving, replying, keepRemoved) {
    if (index < 0) return keepRemoved
    return slotLoads(index, count, maxVisible, showAll, critical, leaving, replying)
}
