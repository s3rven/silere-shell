.pragma library

// One pass serves every card's position and the viewport height. Reading the live
// slots here lets the QML binding follow height changes throughout an animation.
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
