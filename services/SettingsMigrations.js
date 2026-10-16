.pragma library

function _copy(input) {
    return JSON.parse(JSON.stringify(input || {}))
}

function _v0ToV1(input) {
    const out = _copy(input)

    // windowTitleCenterGap originally controlled the same placement choice
    if (out.barCenterInGap === undefined && out.windowTitleCenterGap !== undefined)
        out.barCenterInGap = out.windowTitleCenterGap
    delete out.windowTitleCenterGap

    // the two legacy booleans now represent one remembered underline mode
    if (out.underlineGlow === true && out.barBorderVisible === true)
        out.barBorderVisible = false
    if (out.underlineGlow === true) out.underlineLastStyle = "glow"
    else if (out.barBorderVisible === true) out.underlineLastStyle = "static"

    // barCornerStyle folded into the numeric radius, where zero is flat
    if (out.barCornerStyle === "flat") out.barRadius = 0
    delete out.barCornerStyle
    return out
}

const registry = [
    { from: 0, to: 1, apply: _v0ToV1 }
]

function migrate(input, fromVersion, targetVersion) {
    let value = _copy(input)
    let version = Math.max(0, Math.floor(Number(fromVersion) || 0))
    const target = Math.max(version, Math.floor(Number(targetVersion) || 0))
    const applied = []
    while (version < target) {
        let step = null
        for (let i = 0; i < registry.length; i++) {
            if (registry[i].from === version) {
                step = registry[i]
                break
            }
        }
        if (!step || step.to !== version + 1)
            throw new Error("no settings migration from v" + version)
        value = step.apply(value)
        version = step.to
        value.__version = version
        applied.push(version)
    }
    return { value: value, version: version, applied: applied }
}
