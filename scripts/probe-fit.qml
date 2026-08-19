import QtQuick
import Quickshell

// Builds each settings section at the shipped detail-pane width and reports any
// text Qt itself marks as truncated. The surface probe proves a section builds;
// this proves its labels still fit, which a type-check and a build cannot see.
// Text.truncated is the authority here rather than a width comparison: it is set
// for a vertical clip as well as an elide, and only once layout has settled.
ShellRoot {
    id: root

    property string base: String(Quickshell.env("FIT_ROOT") || "")
    property int contentWidth: Number(Quickshell.env("FIT_W") || 388)
    property var paths: String(Quickshell.env("FIT_LIST") || "")
        .split("\n").filter(p => p.length > 0)

    property int index: 0
    property int findings: 0
    property int built: 0
    property var object: null
    property var component: null

    Item {
        id: host
        width: root.contentWidth
        // tall enough that nothing clips for lack of room rather than lack of fit
        height: 6000
    }

    function _scan(item, path: string, depth: int): void {
        if (!item || depth > 40) return
        const kids = item.children
        if (!kids) return
        for (let i = 0; i < kids.length; i++) {
            const child = kids[i]
            if (!child || child.visible === false) continue
            if (child.truncated === true && String(child.text || "").length > 0) {
                console.warn("FIT-TRUNC " + path + " :: \"" + String(child.text).slice(0, 48)
                    + "\" fits " + Math.round(child.width)
                    + " needs " + Math.round(child.implicitWidth))
                root.findings++
            }
            root._scan(child, path, depth + 1)
        }
    }

    function _next(): void {
        if (root.object) { root.object.destroy(); root.object = null }
        if (root.component) { root.component.destroy(); root.component = null }
        if (root.index >= root.paths.length) {
            console.warn("FIT-DONE built " + root.built + " of " + root.paths.length
                + " at width " + root.contentWidth + ", findings " + root.findings)
            Qt.exit(root.findings > 0 ? 1 : 0)
            return
        }
        const path = root.paths[root.index++]
        root.component = Qt.createComponent("file://" + root.base + "/" + path)
        if (root.component.status === Component.Error) {
            console.warn("FIT-FAIL " + path + " :: " + root.component.errorString())
            root.findings++
            _step.restart()
            return
        }
        root.object = root.component.createObject(host, { width: root.contentWidth })
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
        // one interval, not a frame callback: a section's rows size off font metrics
        // and a collapsing group, both of which settle after the first paint
        interval: 260
        onTriggered: {
            root._scan(root.object, root.paths[root.index - 1], 0)
            _step.restart()
        }
    }

    Component.onCompleted: _step.restart()
}
