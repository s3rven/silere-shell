import QtQuick
import Quickshell

// Instantiates lazily-loaded UI in isolation. The headless type-check compiles
// every file but never builds one, so a bad property type or a dangling id only
// surfaces when a user opens the surface. SILERE_PROBE_LIST carries newline-
// separated paths relative to SILERE_PROBE_ROOT.
// Quickshell serves the config from a virtual resource root, so the paths must be
// absolute file:// URLs; a relative one resolves under qrc:/qs-blackhole and fails.
ShellRoot {
    id: root

    property string _probeRoot: ""
    property var _paths: []
    property int _index: 0
    property int _failed: 0
    property int _settleTurn: 0
    property var _object: null
    property var _component: null
    // at a fractional scale an outline edge between two device pixels splits its stroke into a soft double line
    readonly property bool _grid: Quickshell.env("SILERE_PROBE_GRID") === "1"

    // a window gives PixelSnap and OutlineBorder the real ratio; offscreen never maps it
    FloatingWindow {
        implicitWidth: 400
        implicitHeight: 800
        visible: true

        Item {
            id: host
            width: 400
            height: 800
            readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1

            function _offGrid(it, out): void {
                if (!it || !it.visible || it.opacity <= 0) return
                if (it._stroke !== undefined && it.outlineWidth > 0 && it.outlineColor.a > 0 && it.width > 0) {
                    const a = it.mapToItem(host, 0, 0), b = it.mapToItem(host, it.width, it.height)
                    if ([a.x, a.y, b.x, b.y].some(v => Math.abs(v * host.dpr - Math.round(v * host.dpr)) > 0.02))
                        out.push(String(it.parent) + " " + it.width + "x" + it.height + " at " + a.x + "," + a.y)
                }
                for (let i = 0; i < it.children.length; i++) host._offGrid(it.children[i], out)
            }

            function _create(c): var {
                // A PageShell subclass needs its required properties before it will
                // build. Try bare first so ordinary sections never see stray
                // properties, then retry with the page contract.
                let obj = c.createObject(host, { width: 400 })
                if (obj === null)
                    obj = c.createObject(host, { width: 400, active: true, powerOpen: false })
                if (obj === null)
                    obj = c.createObject(host, { width: 400, active: true, powerOpen: false,
                                                 viewportHeight: 600 })
                return obj
            }

            function _finiteGeometry(obj, path: string): bool {
                const names = ["width", "height", "implicitWidth", "implicitHeight"]
                for (let i = 0; i < names.length; i++) {
                    const name = names[i]
                    const value = obj[name]
                    if (value === undefined) continue
                    const number = Number(value)
                    if (!isFinite(number) || number < 0) {
                        console.warn("PROBE-FAIL " + path + " :: invalid " + name + " " + value)
                        return false
                    }
                }
                return true
            }

            function _finishCurrent(): void {
                const path = root._paths[root._index]
                if (!host._finiteGeometry(root._object, path)) root._failed++
                if (root._grid) {
                    const off = []
                    host._offGrid(root._object, off)
                    for (const o of off) console.warn("PROBE-FAIL " + path + " :: outline between device pixels: " + o)
                    if (off.length > 0) root._failed++
                }
                root._object.destroy()
                root._component.destroy()
                root._object = null
                root._component = null
                root._index++
                Qt.callLater(host._buildNext)
            }

            function _settleCurrent(): void {
                // three turns exercise zero-delay timers, Qt.callLater work, deferred Loader bindings, and the layout pass after text metrics settle
                root._settleTurn++
                if (root._settleTurn < 3) Qt.callLater(host._settleCurrent)
                // positions from layouts and font metrics need a frame
                else if (root._grid) _gridSettle.restart()
                else host._finishCurrent()
            }

            function _buildNext(): void {
                if (root._index >= root._paths.length) {
                    console.warn("PROBE-SURFACES built "
                        + (root._paths.length - root._failed) + "/" + root._paths.length)
                    // The harness validates this log before terminating the process.
                    // Qt.exit starts teardown too early on newer Quickshell versions.
                    return
                }

                const path = root._paths[root._index]
                const c = Qt.createComponent("file://" + root._probeRoot + "/" + path)
                if (c.status === Component.Error) {
                    console.warn("PROBE-FAIL " + path + " :: " + c.errorString().trim())
                    c.destroy()
                    root._failed++
                    root._index++
                    Qt.callLater(host._buildNext)
                    return
                }
                const obj = host._create(c)
                if (obj === null) {
                    console.warn("PROBE-FAIL " + path + " :: createObject returned null")
                    c.destroy()
                    root._failed++
                    root._index++
                    Qt.callLater(host._buildNext)
                    return
                }
                root._component = c
                root._object = obj
                root._settleTurn = 0
                Qt.callLater(host._settleCurrent)
            }

            Timer { id: _gridSettle; interval: 250; onTriggered: host._finishCurrent() }

            Component.onCompleted: {
                root._probeRoot = Quickshell.env("SILERE_PROBE_ROOT") || ""
                const raw = Quickshell.env("SILERE_PROBE_LIST") || ""
                root._paths = raw.split("\n").map(p => p.trim()).filter(p => p.length > 0)
                if (root._paths.length === 0) {
                    console.warn("PROBE-SURFACES: empty list")
                    Qt.exit(2)
                    return
                }
                Qt.callLater(host._buildNext)
            }
        }
    }
}
