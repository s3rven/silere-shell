pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "services"

// test-audio.sh drives a private PipeWire and reads here what the bar and the OSD would draw
ShellRoot {
    IpcHandler {
        target: "probe"
        function state(): string {
            const name = node => node ? node.name : "none"
            return "ready=" + (Pipewire.ready ? 1 : 0)
                + " sink=" + name(Audio.sink)
                + " source=" + name(Audio.source)
                + " vol=" + (Audio.ready ? Math.round(Audio.uiVolume * 100) : "none")
                + " muted=" + (Audio.muted ? 1 : 0)
                + " osd=" + (OsdBarState.activeCount > 0 ? OsdBarState.label : "none")
        }
    }
}
