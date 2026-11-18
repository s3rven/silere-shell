pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "services"

// Hyprland 0.57 names the workspace in focusedmon by id, and Quickshell 0.3.2 looks it up by name
// (quickshell#1427), so a monitor showing a named numbered workspace loses its active one when focus
// moves to it. A special workspace shown before the shell starts sends no event the shell can hear.
// test-compositors.sh sets up each case and writes the step's name to the phase file; every write
// prints the active workspace per output, the focused window's title and the outputs showing a special
// one, as the bar reads them. A "busy" step holds this probe's thread while a window opens, so
// Hyprland's openwindow and activewindowv2 reach it in one read, as they do a shell busy animating
ShellRoot {
    FileView {
        id: _phase
        path: Quickshell.env("SILERE_PROBE_PHASE")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const phase = _phase.text().trim()
            if (phase === "busy") for (const end = Date.now() + 1500; Date.now() < end;) {}
            const active = Compositor.workspaces.filter(w => w.active)
                .map(w => w.output + "=" + w.name).sort()
            const focused = Compositor.activeToplevel
            const outputs = Compositor.toplevels.map(t => t.title + "@" + t.output).sort().join("|")
            console.log("PROBE-MONITORS " + phase + " " + active.join(" ")
                + " outputs=" + outputs
                + " window=" + (focused ? focused.title : "")
                + " special=" + Compositor.specialOutputs.slice().sort().join(","))
        }
    }
}
