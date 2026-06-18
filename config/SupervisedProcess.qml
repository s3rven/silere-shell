import QtQuick
import Quickshell.Io

// Process that relaunches itself after it exits, while superviseWhen holds.
// Owns onExited; for teardown use onRunningChanged. command/stdout as usual.
//   giveUpCodes  , exit codes that stop retries (e.g. [3] = no sensor)
//   cleanExitOnly, only retry after a clean exit (0/2/130/143), else give up
Process {
    id: proc

    property bool superviseWhen: false
    property int  restartDelay:  1000
    property var  giveUpCodes:   []
    property bool cleanExitOnly: false

    property bool _cooldown: false
    property bool _gaveUp: false
    running: superviseWhen && !_cooldown && !_gaveUp

    onExited: code => {
        if (!superviseWhen) return   // stopped on purpose, not a crash

        if (giveUpCodes.indexOf(code) >= 0 || (cleanExitOnly && code !== 0 && code !== 2 && code !== 130 && code !== 143)) {
            proc._gaveUp = true
            return
        }
        proc._cooldown = true
        _coolTimer.restart()
    }

    onSuperviseWhenChanged: if (!superviseWhen) {
        _coolTimer.stop()
        _cooldown = false
        _gaveUp = false
    }

    property Timer _coolTimer: Timer {
        interval: proc.restartDelay
        onTriggered: proc._cooldown = false
    }

    // superviseWhen = false triggers onSuperviseWhenChanged which cancels the
    // cooldown timer before the process exit can rearm it on a dead object.
    Component.onDestruction: superviseWhen = false
}
