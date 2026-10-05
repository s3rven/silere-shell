import QtQuick
import Quickshell

// Builds each surface at the width it actually ships at and reports any text Qt
// itself marks as truncated. The surface probe proves a surface builds; this proves
// its labels still fit, which a type-check and a build cannot see.
// Text.truncated is the authority here rather than a width comparison: it is set
// for a vertical clip as well as an elide, and only once layout has settled.
// A list entry is "path" or "path|width"; the pane widths differ per tab.
ShellRoot {
    id: root

    property string base: String(Quickshell.env("FIT_ROOT") || "")
    property int contentWidth: Number(Quickshell.env("FIT_W") || 388)
    property var paths: String(Quickshell.env("FIT_LIST") || "")
        .split("\n").filter(p => p.length > 0)

    property int index: 0
    property int paneWidth: 0
    property int findings: 0
    property int built: 0
    property int texts: 0
    property int clipped: 0
    property var object: null
    property var component: null

    Item {
        id: host
        width: root.paneWidth > 0 ? root.paneWidth : root.contentWidth
        // tall enough that nothing clips for lack of room rather than lack of fit
        height: 6000
    }

    function _forceLayouts(item): void {
        if (!item) return
        // offscreen, nothing polishes positioners, so flush child layouts before measuring
        for (const child of item.children || []) root._forceLayouts(child)
        if (typeof item.forceLayout === "function") item.forceLayout()
    }

    function _scan(item, path: string, depth: int, clipItem): void {
        if (!item || depth > 40) return
        const kids = item.children
        if (!kids) return
        for (let i = 0; i < kids.length; i++) {
            const child = kids[i]
            if (!child || child.visible === false) continue
            const label = String(child.text || "")
            if (label.length > 0) root.texts++
            if (child.truncated === true && label.length > 0) {
                console.warn("FIT-TRUNC " + path + " :: \"" + label.slice(0, 48)
                    + "\" fits " + Math.round(child.width)
                    + " needs " + Math.round(child.implicitWidth))
                root.findings++
            }
            root._overflow(child, path, clipItem)
            root._paintsWide(child, path, label)
            root._shrunk(child, path, label)
            root._scan(child, path, depth + 1, child.clip === true ? child : clipItem)
        }
    }

    // Wrapped text whose longest line has no break opportunity overflows its own box
    // instead of eliding, and Qt reports truncated:false for it — so neither the elide
    // check nor the clip check sees glyphs painting outside the width they were given.
    function _paintsWide(child, path: string, label: string): void {
        if (label.length === 0 || child.contentWidth === undefined) return
        if (!(child.width > 0) || child.contentWidth <= child.width + 0.5) return
        console.warn("FIT-WIDE " + path + " :: \"" + label.slice(0, 40)
            + "\" paints " + Math.round(child.contentWidth)
            + " into " + Math.round(child.width))
        root.findings++
    }

    // A fontSizeMode text shrinks its own glyphs rather than eliding, so it reports
    // truncated:false and a contentWidth inside the box while rendering a size smaller
    // than the row around it. implicitWidth is the size it asked for before the shrink.
    function _shrunk(child, path: string, label: string): void {
        if (label.length === 0 || child.fontSizeMode === undefined) return
        if (child.fontSizeMode === Text.FixedSize) return
        if (!(child.width > 0) || child.implicitWidth <= child.width + 0.5) return
        console.warn("FIT-SHRINK " + path + " :: \"" + label.slice(0, 40)
            + "\" asked " + Math.round(child.implicitWidth)
            + " got " + Math.round(child.width))
        root.findings++
    }

    // Text.truncated cannot see this: an item pushed past a clipping ancestor is cut
    // with no elide, so it just goes missing. Horizontal only — the host is 6000 tall
    // on purpose, so a vertical comparison would measure the probe, not the layout.
    function _overflow(child, path: string, clipItem): void {
        if (!clipItem || !(child.width > 0)) return
        root.clipped++
        const left = child.mapToItem(clipItem, 0, 0).x
        const right = left + child.width
        if (left >= -0.5 && right <= clipItem.width + 0.5) return
        console.warn("FIT-CLIP " + path + " :: " + String(child).split("(")[0]
            + " spans " + Math.round(left) + ".." + Math.round(right)
            + " inside " + Math.round(clipItem.width))
        root.findings++
    }

    // PageShell subclasses declare required properties; widen the set until one takes
    function _build(): var {
        const w = root.paneWidth
        const ladder = [
            { width: w },
            { width: w, active: true, powerOpen: false },
            { width: w, active: true, powerOpen: false, viewportHeight: 520, height: 520 }
        ]
        for (let i = 0; i < ladder.length; i++) {
            let built = null
            try { built = root.component.createObject(host, ladder[i]) } catch (e) { built = null }
            if (built) return built
        }
        return null
    }

    function _next(): void {
        if (root.object) { root.object.destroy(); root.object = null }
        if (root.component) { root.component.destroy(); root.component = null }
        if (root.index >= root.paths.length) {
            console.warn("FIT-DONE built " + root.built + " of " + root.paths.length
                + " texts " + root.texts + " clipped " + root.clipped
                + ", findings " + root.findings)
            Qt.exit(root.findings > 0 ? 1 : 0)
            return
        }
        const entry = root.paths[root.index++]
        const split = entry.indexOf("|")
        const path = split < 0 ? entry : entry.slice(0, split)
        root.paneWidth = split < 0 ? root.contentWidth : Number(entry.slice(split + 1))
        root.component = Qt.createComponent("file://" + root.base + "/" + path)
        if (root.component.status === Component.Error) {
            console.warn("FIT-FAIL " + path + " :: " + root.component.errorString())
            root.findings++
            _step.restart()
            return
        }
        root.object = root._build()
        if (root.object === null) {
            console.warn("FIT-FAIL " + path + " :: could not build")
            root.findings++
            _step.restart()
            return
        }
        root.built++
        _settle.restart()
    }

    Timer { id: _step; interval: 30; onTriggered: root._next() }
    Timer {
        id: _settle
        // one interval, not a frame callback: a section's rows size off font metrics and a collapsing group, both of which settle after the first paint
        interval: 260
        onTriggered: {
            root._forceLayouts(root.object)
            root._scan(root.object, root.paths[root.index - 1], 0, null)
            if (root.object && typeof root.object.layoutFailures === "function") {
                const failures = root.object.layoutFailures()
                for (const failure of failures) {
                    console.warn("FIT-FAIL " + root.paths[root.index - 1] + " :: " + failure)
                    root.findings++
                }
            }
            _step.restart()
        }
    }

    Component.onCompleted: _step.restart()
}
