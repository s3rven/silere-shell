pragma Singleton

import QtQuick
import Quickshell
import "../config"

// Owns all OSD trigger logic + state. Display layers (OsdWindow pill, the
// bar OSD widget) read this and run their own entrance/icon animations.
Singleton {
    id: root

    property string kind:    ""      // "volume" | "brightness" | "battery" | "temp" | "notif"
    property bool   showing: false
    property string icon:    ""
    property string nextIcon: ""
    property real   value:   0
    property string label:   ""
    property bool   muted:   false
    property color  fillColor: Theme.accent
    readonly property bool hasBar: _hasBarKind(kind)
    readonly property real clamped: Math.max(0, Math.min(1, value))
    property alias entries: _entries
    readonly property int activeCount: _entries.count
    Behavior on fillColor { ColorAnimation { duration: Motion.medium } }

    // emitted when a show() lands while already visible — display layers kick a bump
    signal bumped()
    signal entryBumped(string kind)

    // volume bar warms toward the warning hue near max — a "loud" cue
    readonly property color barColor: _barColor(kind, value, muted, fillColor)

    // A fast scroll burst pushes updates faster than an eased Behavior can
    // settle, so it perpetually chases and looks stuck — display layers
    // should snap instead of animate while this is true.
    property real _lastUpdateAt: 0
    property bool rapid: false
    Timer { id: _rapidTimer; interval: 180; repeat: false; onTriggered: root.rapid = false }
    function _markUpdate(): void {
        const now = Date.now()
        rapid = (now - _lastUpdateAt) < 150
        _lastUpdateAt = now
        _rapidTimer.restart()
    }

    // skip the first brightness event, initial device scan can fire before we're ready
    property bool _seenInitialBrightness: false

    property bool _armed: false
    Timer {
        interval: 600
        running:  true
        repeat:   false
        onTriggered: root._armed = true
    }

    ListModel { id: _entries }

    property int _serial: 0
    property var _expiresAt: ({})
    property var _removeAt: ({})
    property var _closingSig: ({})
    readonly property int _removeDelay: Motion.ms(170) + 70

    function _sig(kind: string, value: real, muted: bool): string {
        return kind + ":" + Math.round(value * 100) + (muted ? ":m" : "")
    }

    function _hasBarKind(kind: string): bool {
        return kind !== "battery" && kind !== "temp" && kind !== "notif"
    }

    function _barColor(kind: string, value: real, muted: bool, base: color): color {
        return (kind === "volume" && !muted && value > 0.85 && ShellSettings.osdVolumeTint)
            ? Theme.mix(base, Theme.warning, Math.min(1, (value - 0.85) / 0.15))
            : base
    }

    function _entryIndex(kind: string): int {
        for (let i = 0; i < _entries.count; i++) {
            if (_entries.get(i).kind === kind) return i
        }
        return -1
    }

    function _setExpiry(kind: string): void {
        _expiresAt[kind] = Date.now() + Math.max(500, ShellSettings.osdTimeout)
        _expiresAt = _expiresAt
        delete _removeAt[kind];   _removeAt = _removeAt
        delete _closingSig[kind]; _closingSig = _closingSig
        _scheduleSweep()
    }

    function _syncPrimary(): void {
        let best = null
        for (let i = 0; i < _entries.count; i++) {
            const e = _entries.get(i)
            if (e.closing) continue
            if (best === null || e.serial > best.serial) best = e
        }

        if (best === null) {
            showing = false
            return
        }

        kind = best.kind
        icon = best.icon
        nextIcon = best.icon
        value = best.value
        label = best.label
        muted = best.muted
        fillColor = best.fillColor
        showing = true
    }

    function _upsertEntry(kind: string, icon: string, value: real, label: string, muted: bool, fillColor: color): bool {
        const sig = _sig(kind, value, muted)
        const idx = _entryIndex(kind)
        const serial = ++_serial
        const data = {
            kind: kind,
            icon: icon,
            value: value,
            label: label,
            muted: muted,
            fillColor: fillColor,
            hasBar: _hasBarKind(kind),
            clamped: Math.max(0, Math.min(1, value)),
            barColor: _barColor(kind, value, muted, fillColor),
            closing: false,
            serial: serial,
            sig: sig
        }

        if (idx >= 0) {
            const old = _entries.get(idx)
            if (old.closing && _closingSig[kind] === sig) return false
            for (const k in data) {
                if (old[k] !== data[k]) _entries.setProperty(idx, k, data[k])
            }
        } else {
            _entries.append(data)
        }

        _markUpdate()
        _setExpiry(kind)
        _syncPrimary()
        return true
    }

    function _closeEntry(index: int): void {
        const e = _entries.get(index)
        if (e.closing) return

        _entries.setProperty(index, "closing", true)

        _removeAt[e.kind] = Date.now() + _removeDelay
        _removeAt = _removeAt
        _closingSig[e.kind] = e.sig
        _closingSig = _closingSig

        _syncPrimary()
        _scheduleSweep()
    }

    function _setEntryProperty(kind: string, role: string, value): void {
        const idx = _entryIndex(kind)
        if (idx < 0) return
        _entries.setProperty(idx, role, value)
        _syncPrimary()
    }

    function _applyValues(kind: string, icon: string, value: real, label: string, muted: bool, color: color): void {
        const idx = _entryIndex(kind)
        const wasShowing = idx >= 0 && !_entries.get(idx).closing
        if (!_upsertEntry(kind, icon, value, label, muted, color)) return
        if (wasShowing && !ShellSettings.reduceMotion) {
            root.bumped()
            root.entryBumped(kind)
        }
    }

    function show(kind: string, icon: string, value: real, label: string, muted: bool): void {
        if (!_armed) return
        if (!ShellSettings.osdEnabled) return
        // the menu's quick sliders already show these levels live; a
        // simultaneous OSD is double feedback
        if (MenuState.open) return
        if (ShellSettings.osdKindFilter === "volume"     && kind !== "volume")     return
        if (ShellSettings.osdKindFilter === "brightness" && kind !== "brightness") return

        root.fillColor = Theme.accent
        _applyValues(kind, icon, value, label, muted, Theme.accent)
    }

    function showAlert(kind: string, icon: string, value: real, label: string, fillColor: color): void {
        if (!_armed || !ShellSettings.osdEnabled) return
        root.fillColor = fillColor
        _applyValues(kind, icon, value, label, false, fillColor)
    }

    function _nextDeadline(): real {
        let next = 0
        for (let i = 0; i < _entries.count; i++) {
            const e = _entries.get(i)
            const t = e.closing ? (_removeAt[e.kind] || 0) : (_expiresAt[e.kind] || 0)
            if (t > 0 && (next === 0 || t < next)) next = t
        }
        return next
    }

    function _scheduleSweep(): void {
        const next = _nextDeadline()
        if (next <= 0) {
            _entrySweep.stop()
            return
        }
        _entrySweep.interval = Math.max(1, next - Date.now())
        _entrySweep.restart()
    }

    function _sweepEntries(): void {
        const now = Date.now()
        for (let i = _entries.count - 1; i >= 0; i--) {
            const e = _entries.get(i)
            if (e.closing) {
                if ((_removeAt[e.kind] || 0) <= now) {
                    delete _expiresAt[e.kind];  _expiresAt = _expiresAt
                    delete _removeAt[e.kind];   _removeAt = _removeAt
                    delete _closingSig[e.kind]; _closingSig = _closingSig
                    _entries.remove(i)
                }
            } else if ((_expiresAt[e.kind] || 0) <= now) {
                _closeEntry(i)
            }
        }
        _syncPrimary()
        _scheduleSweep()
    }

    Timer {
        id: _entrySweep
        repeat: false
        onTriggered: root._sweepEntries()
    }

    property string _lastSinkName: ""
    property bool   _showDeviceName: false

    Timer {
        id: _deviceNameTimer
        interval: 3000
        repeat: false
        onTriggered: {
            root._showDeviceName = false
            if (root.kind === "volume" && root.showing && !root.muted) {
                root.label = Audio.label
                root._setEntryProperty("volume", "label", Audio.label)
            }
        }
    }

    function _updateVolume(): void {
        const effectiveMuted = Audio.muted || Audio.uiVolume <= 0
        const lbl = effectiveMuted ? "Muted"
            : (root._showDeviceName && Audio.sinkName ? `${Audio.sinkName} · ${Audio.label}` : Audio.label)
        root.show("volume", Audio.icon, Audio.uiVolume, lbl, effectiveMuted)
    }

    Connections {
        target: Audio
        // A mute toggle changes BOTH muted and uiVolume (uiVolume = muted ? 0 :
        // vol) in one frame. Defer through Qt.callLater, which dedups identical
        // callbacks within a tick, so the two signals collapse into one show()
        // instead of firing it twice (the second one stamped a spurious bump).
        function onUiVolumeChanged() {
            Qt.callLater(root._updateVolume)
        }
        function onMutedChanged() {
            Qt.callLater(root._updateVolume)
        }
        function onSinkNameChanged() {
            const name = Audio.sinkName
            if (!name || name === root._lastSinkName) return
            const isFirst = root._lastSinkName === ""
            root._lastSinkName = name
            if (isFirst) return
            root._showDeviceName = true
            _deviceNameTimer.restart()
            // same muted test as _updateVolume, so the bar fill renders consistently
            const effectiveMuted = Audio.muted || Audio.uiVolume <= 0
            root.show("volume", Audio.icon, Audio.uiVolume, `${name} · ${Audio.label}`, effectiveMuted)
        }
    }

    Connections {
        target: Brightness
        function onPctChanged() {
            if (!Brightness.ready) return
            if (!root._seenInitialBrightness) {
                root._seenInitialBrightness = true
                return
            }
            root.show("brightness", Brightness.icon, Brightness.pct, Brightness.label, false)
        }
    }

    Connections {
        target: Battery
        function onLowChanged() {
            if (!Battery.low || !ShellSettings.osdBatteryWarn) return
            const label = "Low Battery · " + Math.round(Battery.pct) + "%"
                + (Battery.timeLabel ? "  " + Battery.timeLabel : "")
            root.showAlert("battery", Battery.icon, Battery.pct / 100, label, Theme.warning)
        }
        function onCriticalChanged() {
            if (!Battery.critical || !ShellSettings.osdBatteryWarn) return
            const label = "Critical Battery · " + Math.round(Battery.pct) + "%"
                + (Battery.timeLabel ? "  " + Battery.timeLabel : "")
            root.showAlert("battery", Battery.icon, Battery.pct / 100, label, Theme.error)
        }
        function onFullChanged() {
            if (!Battery.full || !Battery.charging || !ShellSettings.osdChargedNotify) return
            root.showAlert("battery", Battery.icon, 1.0, "Fully charged · 100%", Theme.success)
        }
    }

    Connections {
        target: CpuTemp
        function onHotChanged() {
            if (!CpuTemp.hot || !ShellSettings.osdTempWarn) return
            root.showAlert("temp", "󰔏", Math.min(1.0, (CpuTemp.temp - 50) / 65),
                "CPU Hot · " + Math.round(CpuTemp.temp) + "°", Theme.warning)
        }
        function onCriticalChanged() {
            if (!CpuTemp.critical || !ShellSettings.osdTempWarn) return
            root.showAlert("temp", "󰔏", Math.min(1.0, (CpuTemp.temp - 50) / 65),
                "CPU Critical · " + Math.round(CpuTemp.temp) + "°", Theme.error)
        }
    }

    // One-time at startup: another notification daemon holds the bus, so silere's
    // notifications are dead. Flash it once (NotifWatch also logs the culprit).
    Connections {
        target: NotifWatch
        function onConflictChanged() {
            if (NotifWatch.conflict.length === 0) return
            root.showAlert("notif", "󰂛", 0, "Notifications blocked · " + NotifWatch.conflict, Theme.warning)
        }
    }
}
