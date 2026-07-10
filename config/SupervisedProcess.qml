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
    property int  maxRestartDelay: 60000
    property int  stableAfter: 30000
    property var  giveUpCodes:   []
    property bool cleanExitOnly: false
    readonly property bool gaveUp: _gaveUp

    property bool _cooldown: false
    property bool _gaveUp: false
    property int _restartCount: 0
    readonly property int _effectiveRestartDelay: Math.min(maxRestartDelay,
        restartDelay * Math.pow(2, Math.max(0, _restartCount - 1)))
    // Avoid a declarative Process.running binding here. During a hot reload,
    // Quickshell briefly detaches bindings and would otherwise try to assign an
    // undefined value to the bool property once per supervised process.
    function _syncRunning(): void {
        const wanted = superviseWhen === true && !_cooldown && !_gaveUp
        if (running !== wanted) running = wanted
    }

    Component.onCompleted: _syncRunning()
    on_CooldownChanged: _syncRunning()
    on_GaveUpChanged: _syncRunning()

    onExited: code => {
        _stableTimer.stop()
        if (!superviseWhen) return   // stopped on purpose, not a crash

        if (giveUpCodes.indexOf(code) >= 0 || (cleanExitOnly && code !== 0 && code !== 2 && code !== 130 && code !== 143)) {
            proc._gaveUp = true
            return
        }
        proc._restartCount++
        proc._cooldown = true
        _coolTimer.restart()
    }

    onStarted: _stableTimer.restart()

    onSuperviseWhenChanged: {
        if (!superviseWhen) {
            _coolTimer.stop()
            _stableTimer.stop()
            _cooldown = false
            _gaveUp = false
            _restartCount = 0
        }
        _syncRunning()
    }

    property Timer _coolTimer: Timer {
        interval: proc._effectiveRestartDelay
        onTriggered: proc._cooldown = false
    }

    property Timer _stableTimer: Timer {
        interval: proc.stableAfter
        onTriggered: proc._restartCount = 0
    }

    // superviseWhen=false fires onSuperviseWhenChanged to cancel the cooldown before exit can rearm it on a dead object
    Component.onDestruction: superviseWhen = false
}
