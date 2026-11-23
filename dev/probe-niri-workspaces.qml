pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "services"

ShellRoot {
    id: root

    property int _sourceIndex: -1
    property int _targetIndex: -1
    property int _step: 0
    property string _previousLayout: ""

    FloatingWindow {
        id: window
        title: "Silere workspace probe"
        implicitWidth: 200
        implicitHeight: 120
    }

    // a second subscription sees what niri did while the action's model holds its old snapshot
    CompositorNiri { id: live }

    Process {
        id: reorder
        command: ["niri", "msg", "action", "move-workspace-to-index",
            "--reference", "silere-target", String(root._sourceIndex)]
        onExited: code => {
            if (code !== 0) {
                console.error("PROBE-NIRI-WORKSPACES could not reorder the workspace")
                Quickshell.exit(1)
            }
        }
    }

    Process {
        id: screenshot
        command: ["niri", "msg", "action", "screenshot-screen", "--write-to-disk", "false"]
        onExited: code => {
            if (code !== 0) {
                console.error("PROBE-NIRI-WORKSPACES could not take a clipboard screenshot")
                Quickshell.exit(1)
            }
        }
    }

    Connections {
        target: live
        function onScreenshotTaken(path) {
            if (root._step !== 7 || path !== "") return
            root._step = 8
            console.log("PROBE-NIRI-WORKSPACES passed")
        }
    }

    Timer {
        interval: 50
        repeat: true
        running: root._step < 7
        onTriggered: {
            const source = live.workspaces.find(w => w.name === "silere-source")
            const target = live.workspaces.find(w => w.name === "silere-target")
            if (!source || !target) return
            switch (root._step) {
            case 0: {
                const selected = Compositor.workspaces.find(w => w.ref === target.ref)
                const active = Compositor.activeToplevel
                if (!selected || !active || active.wsRef !== source.ref || active.title !== window.title) return
                root._sourceIndex = source.wsId
                root._targetIndex = selected.wsId
                Compositor._be._eventSocket.parser = null
                reorder.running = true
                root._step = 1
                break
            }
            case 1:
                if (target.wsId !== root._sourceIndex) return
                Compositor.moveActiveToWorkspace(root._targetIndex, target.output)
                root._step = 2
                break
            case 2:
                if (!source.active || !live.toplevels.some(w => w.wsRef === target.ref && w.title === window.title)) return
                Compositor.focusWorkspace(root._targetIndex, target.output)
                root._step = 3
                break
            case 3:
                if (!target.active) return
                live.focusWorkspace(source.wsId, source.output)
                root._step = 4
                break
            case 4: {
                const moved = live.toplevels.find(w => w.wsRef === target.ref && w.title === window.title)
                if (!source.active || !moved) return
                Compositor.focusToplevel(moved)
                root._step = 5
                break
            }
            case 5:
                if (!target.active || live.activeToplevel?.title !== window.title || live.keyboardLayoutCount !== 2) return
                root._previousLayout = live.keyboardLayout
                // the probe owns the nested keyboard; the facade's sandbox guard protects the host one
                Compositor._be.cycleKeyboardLayout()
                root._step = 6
                break
            case 6:
                if (live.keyboardLayout === root._previousLayout || !live.keyboardLayout) return
                root._step = 7
                screenshot.running = true
                break
            }
        }
    }
}
