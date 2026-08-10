import QtQuick
import Quickshell

// Instantiates lazily-loaded UI in isolation. The headless type-check compiles
// every file but never builds one, so a bad property type or a dangling id only
// surfaces when a user opens the surface. SILERE_PROBE_LIST carries newline-
// separated paths relative to SILERE_PROBE_ROOT.
// Quickshell serves the config from a virtual resource root, so the paths must be
// absolute file:// URLs; a relative one resolves under qrc:/qs-blackhole and fails.
ShellRoot {
    Item {
        id: host

        Component.onCompleted: {
            const root = Quickshell.env("SILERE_PROBE_ROOT") || ""
            const raw = Quickshell.env("SILERE_PROBE_LIST") || ""
            const paths = raw.split("\n").filter(p => p.trim().length > 0)
            if (paths.length === 0) {
                console.warn("PROBE-SURFACES: empty list")
                Qt.exit(2)
                return
            }
            let failed = 0
            for (let i = 0; i < paths.length; i++) {
                const path = paths[i].trim()
                const c = Qt.createComponent("file://" + root + "/" + path)
                if (c.status === Component.Error) {
                    console.warn("PROBE-FAIL " + path + " :: " + c.errorString().trim())
                    failed++
                    continue
                }
                // A PageShell subclass needs its required properties before it will
                // build. Try bare first so ordinary sections never see stray
                // properties, then retry with the page contract.
                let obj = c.createObject(host, { width: 400 })
                if (obj === null)
                    obj = c.createObject(host, { width: 400, active: true, powerOpen: false })
                if (obj === null)
                    obj = c.createObject(host, { width: 400, active: true, powerOpen: false,
                                                 viewportHeight: 600 })
                if (obj === null) {
                    console.warn("PROBE-FAIL " + path + " :: createObject returned null")
                    failed++
                    continue
                }
                obj.destroy()
                c.destroy()
            }
            console.warn("PROBE-SURFACES built " + (paths.length - failed) + "/" + paths.length)
            Qt.exit(failed === 0 ? 0 : 1)
        }
    }
}
