pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "config"
import "services"

// Every other gate fixes the settings before the surface exists. This one builds
// the surfaces first and then drives the settings underneath them: each bool
// flipped, each number to both ends of its schema range, each enum through every
// value. A binding that only breaks on a live change is invisible to all of them.
ShellRoot {
    id: root

    property string probeRoot: ""
    property var objects: []
    property var labels: []
    property var steps: []
    property int index: -1
    property int failed: 0
    property bool settling: false
    property var restoreValue: null

    Item { id: host; width: 400; height: 800 }

    // a stray NaN or negative propagates silently through anchors; the bound catches
    // a runaway implicitHeight, which is how an unclamped slider used to present
    function scan(item, depth: int, path: string): void {
        if (!item || depth > 6) return
        const names = ["width", "height", "implicitWidth", "implicitHeight"]
        for (let n = 0; n < names.length; n++) {
            const value = item[names[n]]
            if (value === undefined) continue
            const number = Number(value)
            if (!isFinite(number) || number < 0 || number > 60000) {
                console.warn("PROBE-FAIL " + path + " :: " + names[n] + " " + value)
                root.failed++
                return
            }
        }
        const kids = item.children
        if (!kids) return
        for (let i = 0; i < kids.length && i < 48; i++)
            root.scan(kids[i], depth + 1, path + "/" + i)
    }

    function validate(label: string): void {
        for (let i = 0; i < root.objects.length; i++)
            root.scan(root.objects[i], 0, root.labels[i] + " [" + label + "]")
    }

    function build(): void {
        const raw = Quickshell.env("SILERE_PROBE_LIST") || ""
        const paths = raw.split("\n").map(p => p.trim()).filter(p => p.length > 0)
        for (let i = 0; i < paths.length; i++) {
            const c = Qt.createComponent("file://" + root.probeRoot + "/" + paths[i])
            if (c.status === Component.Error) {
                console.warn("PROBE-FAIL " + paths[i] + " :: " + c.errorString().trim())
                root.failed++
                continue
            }
            let obj = c.createObject(host, { width: 400 })
            if (obj === null)
                obj = c.createObject(host, { width: 400, active: true, powerOpen: false })
            if (obj === null)
                obj = c.createObject(host, { width: 400, active: true, powerOpen: false,
                                             viewportHeight: 600 })
            if (obj === null) {
                console.warn("PROBE-FAIL " + paths[i] + " :: createObject returned null")
                root.failed++
                continue
            }
            root.labels.push(paths[i].split("/").pop())
            root.objects.push(obj)
        }
    }

    function plan(): void {
        const schema = ShellSettings._schema
        for (let i = 0; i < schema.length; i++) {
            const s = schema[i]
            if (s.t === "bool") root.steps.push({ k: s.k, v: !ShellSettings[s.k], d: "toggled" })
            else if (s.t === "int" || s.t === "real") {
                root.steps.push({ k: s.k, v: s.min, d: "min" })
                root.steps.push({ k: s.k, v: s.max, d: "max" })
            } else if (s.t === "enum" && s.vals) {
                for (let j = 0; j < s.vals.length; j++)
                    root.steps.push({ k: s.k, v: s.vals[j], d: String(s.vals[j]) })
            }
        }
    }

    Component.onCompleted: {
        root.probeRoot = Quickshell.env("SILERE_PROBE_ROOT") || ""
        void ShellSettings.ready
        // the settings surfaces only build their rows once the menu reports the page open
        MenuState.open = true
        MenuState.showTab(MenuState.settingsTab)
        root.build()
        root.plan()
        if (root.objects.length === 0 || root.steps.length === 0) {
            console.warn("PROBE-MUTATE: nothing to sweep")
            Qt.exit(2)
            return
        }
        _step.start()
    }

    Timer {
        id: _step
        interval: 40
        repeat: true
        onTriggered: {
            if (!root.settling) {
                root.index++
                if (root.index >= root.steps.length) {
                    _step.stop()
                    console.warn("PROBE-MUTATE swept " + root.steps.length + " states over "
                        + root.objects.length + " surfaces")
                    Qt.exit(root.failed === 0 ? 0 : 1)
                    return
                }
                const step = root.steps[root.index]
                root.restoreValue = ShellSettings[step.k]
                ShellSettings[step.k] = step.v
                root.settling = true
                return
            }
            const step = root.steps[root.index]
            root.validate(step.k + "=" + step.d)
            ShellSettings[step.k] = root.restoreValue
            root.settling = false
        }
    }
}
