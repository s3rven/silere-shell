pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "services"

// Hyprland 0.57 names the workspace in focusedmon by id, and Quickshell 0.3.2 looks it up by name
// (quickshell#1427), so a monitor showing a named numbered workspace loses its active one when focus
// moves to it. A special workspace shown before the shell starts sends no event the shell can hear.
// test-compositors.sh sets up each case and writes the step's name to the phase file; every write
// prints the active workspace per output and the outputs showing a special one, as the bar reads them
ShellRoot {
    FileView {
        id: _phase
        path: Quickshell.env("SILERE_PROBE_PHASE")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const active = Compositor.workspaces.filter(w => w.active)
                .map(w => w.output + "=" + w.name).sort()
            console.log("PROBE-MONITORS " + _phase.text().trim() + " " + active.join(" ")
                + " special=" + Compositor.specialOutputs.slice().sort().join(","))
        }
    }
}
