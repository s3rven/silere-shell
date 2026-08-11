pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root

    readonly property real stepPct: 0.05

    readonly property PwNode     sink:  Pipewire.defaultAudioSink
    readonly property PwNodeAudio audio: sink ? sink.audio : null
    readonly property bool ready: Pipewire.ready && sink !== null && sink.ready && audio !== null

    property real targetVolume: ready ? root._clampVolume(audio.volume) : 0
    property bool pendingApply: false
    property bool _componentReady: false

    readonly property real effectiveVolume: root._clampVolume(
        pendingApply ? targetVolume : (ready ? audio.volume : 0))
    property bool _pendingMuted: false
    property bool _desiredMuted: false
    property bool _muteWritePending: false
    readonly property int _maxConfirmRetries: 6
    readonly property real _volumeEpsilon: 0.005
    readonly property real _confirmTolerance: Math.max(_volumeEpsilon, stepPct * 0.5)
    property int _volRetries: 0
    property int _muteRetries: 0
    readonly property bool muted: ready ? _pendingMuted : false
    readonly property real uiVolume: root._clampVolume(muted ? 0 : effectiveVolume)

    readonly property string icon:
        !ready                   ? "󰖁" :
        muted || uiVolume === 0  ? "󰝟" :
        uiVolume < 0.33          ? "󰕿" :
        uiVolume < 0.66          ? "󰖀" : "󰕾"
    readonly property string label: ready ? `${Math.round(uiVolume * 100)}%` : "--%"
    readonly property string sinkName: root.sinkLabel(sink)

    readonly property var sinks: {
        const out = []
        // PipeWire briefly detaches its node model while reconnecting.
        const all = Pipewire.nodes ? (Pipewire.nodes.values || []) : []
        for (let i = 0; i < all.length; i++) {
            const n = all[i]
            if (n && n.isSink && !n.isStream) out.push(n)
        }
        return out
    }
    readonly property int sinkCount: sinks.length

    readonly property var sinkModel: sinks.map(n => ({ value: n, label: root.sinkLabel(n) }))

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    function setSink(node): void {
        if (node) Pipewire.preferredDefaultAudioSink = node
    }

    function sinkLabel(node): string {
        if (!node) return ""
        return IconResolver.boundedText(
            node.description || node.nickname || node.name || "Output", 256)
    }

    function _clampVolume(v: real): real {
        if (!isFinite(v)) return 0
        return Math.max(0, Math.min(1.0, v))
    }

    function _enforceVolumeLimit(): void {
        const a = ready ? audio : null
        if (!a) return
        const clamped = _clampVolume(a.volume)
        if (Math.abs(a.volume - clamped) >= _volumeEpsilon) _writeVolume(clamped)
    }

    function _acceptVolume(actual: real): void {
        targetVolume = _clampVolume(actual)
        pendingApply = false
        _volRetries = 0
        pendingSafety.stop()
    }

    function _syncAudio(): void {
        if (!_componentReady) return
        writeThrottle.stop()
        pendingSafety.stop()
        muteSafety.stop()
        pendingApply = false
        const a = ready ? audio : null
        targetVolume = a ? _clampVolume(a.volume) : 0
        _pendingMuted = a ? a.muted : false
        _desiredMuted = _pendingMuted
        _muteWritePending = false
        _volRetries = 0
        _muteRetries = 0
        if (a) Qt.callLater(root._enforceVolumeLimit)
    }
    onAudioChanged: _syncAudio()
    onReadyChanged: _syncAudio()
    Component.onCompleted: {
        _componentReady = true
        _syncAudio()
    }

    Connections {
        target: root.audio
        enabled: root.ready
        function onVolumesChanged() {
            const a = root.audio
            if (!a) return
            const actual = a.volume
            const clamped = root._clampVolume(actual)
            if (Math.abs(actual - clamped) >= root._volumeEpsilon) {
                root._writeVolume(clamped)
                return
            }
            if (root.pendingApply
                    && Math.abs(clamped - root.targetVolume) <= root._confirmTolerance)
                root._acceptVolume(clamped)
            else if (!root.pendingApply)
                root.targetVolume = clamped
        }
        function onMutedChanged() {
            const a = root.audio
            if (!a) return
            if (root._muteWritePending) {
                if (a.muted === root._desiredMuted) {
                    root._pendingMuted = a.muted
                    root._muteWritePending = false
                    muteSafety.stop()
                }
                return
            }
            root._pendingMuted = a.muted
            root._desiredMuted = a.muted
        }
    }

    Timer {
        id: writeThrottle
        interval: 16
        repeat: false
        onTriggered: {
            const a = root.audio
            if (!a) return
            if (Math.abs(a.volume - root.targetVolume) >= root._volumeEpsilon)
                a.volume = Math.max(0, Math.min(1.0, root.targetVolume))
        }
    }

    Timer {
        id: pendingSafety
        interval: 600
        onTriggered: {
            const a = root.audio
            if (!a || !root.pendingApply) return
            const actual = root._clampVolume(a.volume)
            if (Math.abs(actual - root.targetVolume) > root._confirmTolerance) {
                if (root._volRetries >= root._maxConfirmRetries) {
                    root._acceptVolume(actual)
                    return
                }
                root._volRetries++
                a.volume = Math.max(0, Math.min(1.0, root.targetVolume))
                pendingSafety.restart()
            } else {
                root._acceptVolume(actual)
            }
        }
    }

    Timer {
        id: muteSafety
        interval: 350
        onTriggered: {
            const a = root.audio
            if (!a || !root._muteWritePending) return
            if (a.muted === root._desiredMuted) {
                root._pendingMuted = a.muted
                root._muteWritePending = false
            } else if (root._muteRetries >= root._maxConfirmRetries) {
                root._pendingMuted = a.muted
                root._muteWritePending = false
            } else {
                root._muteRetries++
                a.muted = root._desiredMuted
                muteSafety.restart()
            }
        }
    }

    function bumpBy(delta: real): void {
        const a = ready ? audio : null
        if (!a || delta === 0) return
        if (_pendingMuted) unmute()
        let v = pendingApply ? targetVolume : _clampVolume(a.volume)
        _writeVolume(v + delta)
    }

    function setVolume(v: real): void {
        if (!ready || !audio) return
        if (_pendingMuted && v > 0) unmute()
        _writeVolume(v)
    }

    function _writeVolume(v: real): void {
        const a = ready ? audio : null
        if (!a) return
        v = _clampVolume(v)
        if (Math.abs(v - targetVolume) < _volumeEpsilon && pendingApply) return
        if (!pendingApply && Math.abs(v - _clampVolume(a.volume)) < _volumeEpsilon) return
        targetVolume = v
        pendingApply = true

        if (!writeThrottle.running) {
            a.volume = v
            writeThrottle.restart()
        }
        _volRetries = 0
        pendingSafety.restart()
    }

    function toggleMute(): void {
        if (!ready || !audio) return
        const wasMuted = _pendingMuted
        _setMuted(!wasMuted)
    }

    function unmute(): void {
        if (!ready || !audio || !_pendingMuted) return
        _setMuted(false)
    }

    function _setMuted(shouldMute: bool): void {
        const a = ready ? audio : null
        if (!a) return
        _desiredMuted = shouldMute
        _pendingMuted = shouldMute
        _muteWritePending = true
        _muteRetries = 0
        a.muted = shouldMute
        muteSafety.restart()
    }
}
