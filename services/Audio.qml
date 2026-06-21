pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root

    property real stepPct: 0.05

    readonly property PwNode     sink:  Pipewire.defaultAudioSink
    readonly property PwNodeAudio audio: sink ? sink.audio : null
    readonly property bool ready: audio !== null

    property real targetVolume: ready ? audio.volume : 0
    property bool pendingApply: false
    property bool _componentReady: false

    readonly property real effectiveVolume: Math.max(0, Math.min(1.0,
        pendingApply ? targetVolume : (ready ? audio.volume : 0)))
    // optimistic mute, flips immediately, confirmed async by Pipewire
    property bool _pendingMuted: false
    property bool _desiredMuted: false
    property bool _muteWritePending: false
    // Bound the confirm-retry timers, a sink that never acks must not self-rearm forever.
    readonly property int _maxConfirmRetries: 6
    property int _volRetries: 0
    property int _muteRetries: 0
    readonly property bool muted: ready ? _pendingMuted : false
    readonly property real uiVolume: Math.max(0, Math.min(1, muted ? 0 : effectiveVolume))

    readonly property string icon:
        !ready                   ? "󰖁" :
        muted || uiVolume === 0  ? "󰖁" :
        uiVolume < 0.33          ? "󰕿" :
        uiVolume < 0.66          ? "󰖀" : "󰕾"
    readonly property string label: ready ? `${Math.round(uiVolume * 100)}%` : "--%"
    readonly property string sinkName: sink ? (sink.description || "") : ""

    PwObjectTracker { objects: sink ? [sink] : [] }

    function _syncAudio(): void {
        if (!_componentReady) return
        writeThrottle.stop()
        pendingSafety.stop()
        muteSafety.stop()
        pendingApply = false
        targetVolume = ready ? audio.volume : 0
        _pendingMuted = ready ? audio.muted : false
        _desiredMuted = _pendingMuted
        _muteWritePending = false
        _volRetries = 0
        _muteRetries = 0
    }
    onAudioChanged: _syncAudio()
    Component.onCompleted: {
        _componentReady = true
        _syncAudio()
    }

    Connections {
        target: audio
        enabled: root.ready
        function onVolumesChanged() {
            if (root.pendingApply && Math.abs(audio.volume - root.targetVolume) < 0.005)
                root.pendingApply = false
            else if (!root.pendingApply)
                root.targetVolume = audio.volume
        }
        function onMutedChanged() {
            if (root._muteWritePending) {
                if (audio.muted === root._desiredMuted) {
                    root._pendingMuted = audio.muted
                    root._muteWritePending = false
                    muteSafety.stop()
                }
                return
            }
            root._pendingMuted = audio.muted
            root._desiredMuted = audio.muted
        }
    }

    // Throttle writes to Pipewire, without this, fast touchpad scrolls
    // flood the daemon and writes get dropped silently.
    Timer {
        id: writeThrottle
        interval: 16     // ~60Hz, matches display refresh
        repeat: false
        onTriggered: {
            if (!root.ready) return
            if (Math.abs(root.audio.volume - root.targetVolume) >= 0.005)
                root.audio.volume = Math.max(0, Math.min(1.0, root.targetVolume))
        }
    }

    // retry if Pipewire doesn't confirm within 600ms
    Timer {
        id: pendingSafety
        interval: 600
        onTriggered: {
            if (!root.ready || !root.pendingApply) return
            if (Math.abs(root.audio.volume - root.targetVolume) >= 0.005) {
                if (root._volRetries >= root._maxConfirmRetries) { root.pendingApply = false; return }
                root._volRetries++
                root.audio.volume = Math.max(0, Math.min(1.0, root.targetVolume))
                pendingSafety.restart()
            } else {
                root.pendingApply = false
            }
        }
    }

    Timer {
        id: muteSafety
        interval: 350
        onTriggered: {
            if (!root.ready || !root._muteWritePending) return
            if (root.audio.muted === root._desiredMuted) {
                root._pendingMuted = root.audio.muted
                root._muteWritePending = false
            } else if (root._muteRetries >= root._maxConfirmRetries) {
                // sink won't confirm, accept its actual state instead of looping forever
                root._pendingMuted = root.audio.muted
                root._muteWritePending = false
            } else {
                root._muteRetries++
                root.audio.muted = root._desiredMuted
                muteSafety.restart()
            }
        }
    }

    function bumpBy(delta: real): void {
        if (!ready) return
        let v = pendingApply ? targetVolume : audio.volume
        _writeVolume(v + delta)
    }

    function setVolume(v: real): void {
        if (!ready) return
        if (_pendingMuted && v > 0) unmute()
        _writeVolume(v)
    }

    function _writeVolume(v: real): void {
        v = Math.max(0, Math.min(1.0, v))
        if (v === targetVolume && pendingApply) return
        targetVolume = v
        pendingApply = true

        // Leading-edge: write immediately if throttle window is open
        if (!writeThrottle.running) {
            audio.volume = v
            writeThrottle.restart()
        }
        _volRetries = 0
        pendingSafety.restart()
    }

    function toggleMute(): void {
        if (!ready) return
        const wasMuted = _pendingMuted
        _setMuted(!wasMuted)
    }

    function unmute(): void {
        if (!ready || !_pendingMuted) return
        _setMuted(false)
    }

    function _setMuted(shouldMute: bool): void {
        if (!ready) return
        _desiredMuted = shouldMute
        _pendingMuted = shouldMute
        _muteWritePending = true
        _muteRetries = 0
        audio.muted = shouldMute
        muteSafety.restart()
    }
}
