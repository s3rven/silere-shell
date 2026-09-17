import QtQuick
import Quickshell

// Builds the layer-shell surfaces, which no other pass reaches. test-surfaces.sh
// filters out every root carrying a required property, and all of these require a
// targetScreen; check.sh's smoke pass loads shell.qml but leaves the popups closed,
// so a bad property inside one only appears when a user opens it.
//
// These cannot run under QT_QPA_PLATFORM=offscreen: a PanelWindow without a Wayland
// layer-shell backend fails construction with "No PanelWindow backend loaded". The
// harness supplies the real display instead, and visible stays false so nothing maps.
ShellRoot {
    id: root

    property string _probeRoot: ""
    property var _paths: []
    property int _index: 0
    property int _failed: 0
    property int _settleTurn: 0
    property var _object: null
    property var _component: null

    Item {
        id: host

        function _finishCurrent(): void {
            root._object.destroy()
            root._component.destroy()
            root._object = null
            root._component = null
            root._index++
            Qt.callLater(host._buildNext)
        }

        function _settleCurrent(): void {
            root._settleTurn++
            if (root._settleTurn < 3) Qt.callLater(host._settleCurrent)
            else host._finishCurrent()
        }

        function _buildNext(): void {
            if (root._index >= root._paths.length) {
                console.warn("PROBE-PANELS built "
                    + (root._paths.length - root._failed) + "/" + root._paths.length)
                Qt.exit(root._failed === 0 ? 0 : 1)
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
            // assigning visible here replaces the declared binding, so a surface whose
            // state singleton says open still cannot map
            const obj = c.createObject(null, {
                targetScreen: Quickshell.screens[0] ?? null,
                visible: false
            })
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

        Component.onCompleted: {
            root._probeRoot = Quickshell.env("SILERE_PROBE_ROOT") || ""
            const raw = Quickshell.env("SILERE_PROBE_LIST") || ""
            root._paths = raw.split("\n").map(p => p.trim()).filter(p => p.length > 0)
            if (root._paths.length === 0) {
                console.warn("PROBE-PANELS: empty list")
                Qt.exit(2)
                return
            }
            if ((Quickshell.screens || []).length === 0) {
                console.warn("PROBE-PANELS: no screen")
                Qt.exit(3)
                return
            }
            Qt.callLater(host._buildNext)
        }
    }
}
