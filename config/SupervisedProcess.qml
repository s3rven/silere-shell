import QtQuick
import Quickshell.Io

Process {
    id: proc

    property bool superviseWhen: false
    property int  restartDelay:  1000
    property int  maxRestartDelay: 60000
    property int  stableAfter: 30000
    property var  giveUpCodes:   []

    property bool _cooldown: false
    property bool _gaveUp: false
    // consumers gate their own "this feature is off for good" copy on it
    readonly property bool gaveUp: _gaveUp
    property int _restartCount: 0
    readonly property int _effectiveRestartDelay: Math.min(maxRestartDelay,
        restartDelay * Math.pow(2, Math.max(0, _restartCount - 1)))
    // no declarative running binding: a hot reload detaches bindings and assigns undefined to the bool
    function _syncRunning(): void {
        const wanted = superviseWhen === true && !_cooldown && !_gaveUp
        if (running !== wanted) running = wanted
    }

    function retry(): void {
        // Hold the process stopped until every backoff flag is reset; otherwise
        // clearing gaveUp can launch once with the old cooldown state.
        _cooldown = true
        _coolTimer.stop()
        _stableTimer.stop()
        _gaveUp = false
        _restartCount = 0
        _cooldown = false
        _syncRunning()
    }

    Component.onCompleted: _syncRunning()
    on_CooldownChanged: _syncRunning()
    on_GaveUpChanged: _syncRunning()

    onExited: (code, status) => {
        _stableTimer.stop()
        if (!superviseWhen) return

        // status 0 is QProcess.NormalExit, which QML sees as a plain number because the
        // enum is not registered. A crash reports its signal number in code, so matching
        // giveUpCodes without this retires the process on a signal that shares a number
        // with a real exit code.
        if (status === 0 && giveUpCodes.indexOf(code) >= 0) {
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
