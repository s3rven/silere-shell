pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Pipewire

QtObject {
    id: ctl

    // a mute this control did not write: a key bound to wpctl, or another mixer
    signal mutedExternally()

    property PwNode node: null
    readonly property PwNodeAudio audio: node ? node.audio : null
    property bool enabled: true
    // off for app streams: another mixer's boost there is the user's own choice
    property bool capExternal: true
    readonly property bool ready: enabled && node !== null && node.ready && audio !== null

    readonly property real stepPct: 0.05

    function _apply(v: real): void {
        const a = ready ? audio : null
        if (!a) return
        a.volume = ctl._clampVolume(v)
    }

    // audio can notify null before ready re-evaluates, so guard it directly
    property real targetVolume: ready && audio ? ctl._clampVolume(audio.volume) : 0
    property bool pendingApply: false
    property bool _componentReady: false

    readonly property real effectiveVolume: ctl._clampVolume(
        pendingApply ? targetVolume : (ready && audio ? audio.volume : 0))
    property bool _pendingMuted: false
    property bool _desiredMuted: false
    property bool _muteWritePending: false
    readonly property int _maxConfirmRetries: 6
    readonly property real _volumeEpsilon: 0.005
    readonly property real _confirmTolerance: Math.max(_volumeEpsilon, stepPct * 0.5)
    property int _volRetries: 0
    property int _muteRetries: 0
    readonly property bool muted: ready ? _pendingMuted : false
    readonly property real uiVolume: ctl._clampVolume(muted ? 0 : effectiveVolume)

    function _clampVolume(v: real): real {
        if (!isFinite(v)) return 0
        return Math.max(0, Math.min(1.0, v))
    }

    function _volumeMatches(actual: real, wanted: real): bool {
        return isFinite(actual) && Math.abs(actual - wanted) < _volumeEpsilon
    }

    function _enforceVolumeLimit(): void {
        const a = ready ? audio : null
        if (!a) return
        const clamped = _clampVolume(a.volume)
        if (!_volumeMatches(a.volume, clamped)) _writeVolume(clamped)
    }

    function _acceptVolume(actual: real): void {
        targetVolume = _clampVolume(actual)
        pendingApply = false
        _volRetries = 0
        ctl._pendingSafety.stop()
    }

    function sync(): void {
        if (!_componentReady) return
        ctl._writeThrottle.stop()
        ctl._pendingSafety.stop()
        ctl._muteSafety.stop()
        pendingApply = false
        const a = ready ? audio : null
        targetVolume = a ? _clampVolume(a.volume) : 0
        _pendingMuted = a ? a.muted : false
        _desiredMuted = _pendingMuted
        _muteWritePending = false
        _volRetries = 0
        _muteRetries = 0
        if (a && capExternal) Qt.callLater(ctl._enforceVolumeLimit)
    }
    onAudioChanged: sync()
    onReadyChanged: sync()
    Component.onCompleted: {
        _componentReady = true
        sync()
    }

    readonly property Connections _watch: Connections {
        target: ctl.audio
        enabled: ctl.ready
        function onVolumesChanged() {
            const a = ctl.audio
            if (!a) return
            const actual = a.volume
            const clamped = ctl._clampVolume(actual)
            if (ctl.capExternal && !ctl._volumeMatches(actual, clamped)) {
                ctl._writeVolume(clamped)
                return
            }
            if (ctl.pendingApply
                    && Math.abs(clamped - ctl.targetVolume) <= ctl._confirmTolerance)
                ctl._acceptVolume(clamped)
            else if (!ctl.pendingApply)
                ctl.targetVolume = clamped
        }
        function onMutedChanged() {
            const a = ctl.audio
            if (!a) return
            if (ctl._muteWritePending) {
                if (a.muted === ctl._desiredMuted) {
                    ctl._pendingMuted = a.muted
                    ctl._muteWritePending = false
                    ctl._muteSafety.stop()
                }
                return
            }
            const changed = ctl._pendingMuted !== a.muted
            ctl._pendingMuted = a.muted
            ctl._desiredMuted = a.muted
            if (changed) ctl.mutedExternally()
        }
    }

    readonly property Timer _writeThrottle: Timer {
        interval: 16
        repeat: false
        onTriggered: {
            const a = ctl.audio
            if (!a) return
            if (!ctl._volumeMatches(a.volume, ctl.targetVolume))
                ctl._apply(ctl.targetVolume)
        }
    }

    readonly property Timer _pendingSafety: Timer {
        interval: 600
        onTriggered: {
            const a = ctl.audio
            if (!a || !ctl.pendingApply) return
            const actual = ctl._clampVolume(a.volume)
            if (!isFinite(a.volume) || Math.abs(a.volume - ctl.targetVolume) > ctl._confirmTolerance) {
                if (ctl._volRetries >= ctl._maxConfirmRetries) {
                    ctl._acceptVolume(actual)
                    return
                }
                ctl._volRetries++
                ctl._apply(ctl.targetVolume)
                ctl._pendingSafety.restart()
            } else {
                ctl._acceptVolume(actual)
            }
        }
    }

    readonly property Timer _muteSafety: Timer {
        interval: 350
        onTriggered: {
            const a = ctl.audio
            if (!a || !ctl._muteWritePending) return
            if (a.muted === ctl._desiredMuted) {
                ctl._pendingMuted = a.muted
                ctl._muteWritePending = false
            } else if (ctl._muteRetries >= ctl._maxConfirmRetries) {
                ctl._pendingMuted = a.muted
                ctl._muteWritePending = false
            } else {
                ctl._muteRetries++
                a.muted = ctl._desiredMuted
                ctl._muteSafety.restart()
            }
        }
    }

    // a level set elsewhere rejoins the step grid on the first notch instead of staying off it. A level within the
    // write tolerance of a line counts as on it: stepping to that line would be dropped as no change, every notch
    function _stepFrom(v: real, delta: real): real {
        const notches = Math.round(delta / stepPct)
        if (notches === 0) return v + delta
        const at = v / stepPct
        const slop = ctl._volumeEpsilon / stepPct
        const base = notches > 0 ? Math.floor(at + slop) : Math.ceil(at - slop)
        return (base + notches) * stepPct
    }

    function bumpBy(delta: real): void {
        const a = ready ? audio : null
        if (!a || !isFinite(delta) || delta === 0) return
        if (_pendingMuted && delta > 0) unmute()
        // a boost set elsewhere reads as 100% here: a notch up would pull it down to that
        if (delta > 0 && !pendingApply && a.volume > 1.0) return
        const v = pendingApply ? targetVolume : _clampVolume(a.volume)
        _writeVolume(ctl._stepFrom(v, delta))
    }

    function setVolume(v: real): void {
        if (!ready || !audio) return
        if (_pendingMuted && v > 0) unmute()
        _writeVolume(v)
    }

    // the cap holds per channel: Quickshell scales every channel by one ratio, so with a balance of 1.0 / 0.8 an
    // average of 100% put the louder channel at 111%
    function _channelLimit(a): real {
        const vols = a ? a.volumes : null
        if (!vols || vols.length < 2 || !(a.volume > 0)) return 1.0
        let peak = 0
        for (let i = 0; i < vols.length; i++) peak = Math.max(peak, Number(vols[i]) || 0)
        return peak > a.volume ? a.volume / peak : 1.0
    }

    function _writeVolume(v: real): void {
        const a = ready ? audio : null
        if (!a) return
        v = Math.min(_clampVolume(v), ctl._channelLimit(a))
        if (Math.abs(v - targetVolume) < _volumeEpsilon && pendingApply) return
        if (!pendingApply && _volumeMatches(a.volume, v)) return
        targetVolume = v
        pendingApply = true

        if (!ctl._writeThrottle.running) {
            ctl._apply(v)
            ctl._writeThrottle.restart()
        }
        _volRetries = 0
        ctl._pendingSafety.restart()
    }

    function toggleMute(): void {
        if (!ready || !audio) return
        _setMuted(!_pendingMuted)
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
        ctl._muteSafety.restart()
    }
}
