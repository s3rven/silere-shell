import QtQuick
import Quickshell.Io

Process {
    id: proc

    property bool superviseWhen: false
    property int  restartDelay:  1000
    property int  maxRestartDelay: 60000
    property int  stableAfter: 30000
    property var  giveUpCodes:   []
    property bool cleanExitOnly: false

    property bool _cooldown: false
    property bool _gaveUp: false
    property int _restartCount: 0
    property int _lastExitCode: 0
    property bool _hasExited: false
    readonly property bool retrying: _cooldown
    readonly property bool gaveUp: _gaveUp
    readonly property int restartCount: _restartCount
    readonly property int lastExitCode: _lastExitCode
    readonly property bool hasExited: _hasExited
    readonly property int _effectiveRestartDelay: Math.min(maxRestartDelay,
        restartDelay * Math.pow(2, Math.max(0, _restartCount - 1)))
    // no declarative running binding: a hot reload detaches bindings and assigns undefined to the bool
    function _syncRunning(): void {
        const wanted = superviseWhen === true && !_cooldown && !_gaveUp
        if (running !== wanted) running = wanted
    }

    Component.onCompleted: _syncRunning()
    on_CooldownChanged: _syncRunning()
    on_GaveUpChanged: _syncRunning()

    onExited: code => {
        _stableTimer.stop()
        proc._lastExitCode = code
        proc._hasExited = true
        if (!superviseWhen) return

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
            _lastExitCode = 0
            _hasExited = false
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
