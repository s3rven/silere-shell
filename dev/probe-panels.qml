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

        function _retentionPanel(item): var {
            if (!item) return null
            if (typeof item._syncPageRetention === "function") return item
            const children = item.children || []
            for (let i = 0; i < children.length; i++) {
                const found = host._retentionPanel(children[i])
                if (found) return found
            }
            return null
        }

        // the surface's own import resolves by file url, so only a file-url import reaches its singleton
        function _service(name: string): var {
            const bridge = Qt.createQmlObject('import QtQuick\nimport "file://'
                + root._probeRoot + '/services"\nQtObject { readonly property var state: ' + name + ' }',
                host, "panel-service-bridge")
            const state = bridge.state
            bridge.destroy()
            return state
        }

        function _checkWarmMenuReopen(obj): void {
            const MenuState = host._service("MenuState")
            const settings = host._service("ShellSettings")
            const panel = host._retentionPanel(obj.popupCard || obj.contentItem)
            if (!panel) {
                console.warn("PROBE-FAIL MenuWindow :: retention panel missing")
                root._failed++
                return
            }
            const previousTab = MenuState._activeTab
            const previousOpen = MenuState.open
            const previousReduceMotion = settings.reduceMotion
            const geometryReady = panel._geometryReady
            MenuState.open = false
            MenuState._activeTab = MenuState.settingsTab
            panel._settingsRetained = false
            MenuState.open = true
            if (!panel._settingsRetained) {
                console.warn("PROBE-FAIL MenuWindow :: warm reopen did not retain the active page")
                root._failed++
            }
            // Exercise the actual width, rail and padding together, without
            // mapping a test window onto the user's desktop.
            MenuState.open = false
            settings.reduceMotion = false
            MenuState.selectTab(MenuState.homeTab)
            const initialInner = panel.innerW
            panel._geometryReady = true
            MenuState.open = true
            MenuState.selectTab(MenuState.settingsTab)
            if (panel.pageLayoutW > initialInner + 12 && panel.pageViewportReady) {
                console.warn("PROBE-FAIL MenuWindow :: incoming page revealed before its viewport widened")
                root._failed++
            }
            const glides = panel.data.filter(item => typeof item._advance === "function")
            for (let frame = 0; frame < 12; frame++)
                for (const glide of glides) glide._advance(1 / 240)
            MenuState.selectTab(MenuState.homeTab)
            MenuState.selectTab(MenuState.settingsTab)
            for (let frame = 0; frame < 240; frame++)
                for (const glide of glides) glide._advance(1 / 240)
            if (Math.abs(panel.width - panel.panelW) > 0.1
                    || Math.abs(panel.railW - panel.railExpandedW) > 0.1
                    || !panel.pageViewportReady) {
                console.warn("PROBE-FAIL MenuWindow :: rapid tab reversals did not settle the viewport")
                root._failed++
            }
            MenuState.open = false
            panel._geometryReady = geometryReady
            settings.reduceMotion = previousReduceMotion
            MenuState._activeTab = previousTab
            MenuState.open = previousOpen
        }

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
            // assigning visible here replaces the declared binding, so a surface whose state singleton says open still cannot map
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
            if (path === "modules/menu/MenuWindow.qml") host._checkWarmMenuReopen(obj)
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
