pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    function deviceId(node): string {
        if (!node || !node.ready || !node.properties || node.properties["device.api"] !== "bluez5") return ""
        const id = String(node.properties["device.id"] ?? "")
        return /^[0-9]+$/.test(id) ? id : ""
    }

    function deviceIdentity(node): string {
        if (!node) return ""
        const address = String((node.properties || {})["api.bluez5.address"] || "")
        if (/^[0-9a-f]{2}([:_][0-9a-f]{2}){5}$/i.test(address)) return address.replace(/_/g, ":").toLowerCase()
        const match = /bluez_output[._]([0-9a-f]{2}(?:[_:][0-9a-f]{2}){5})/i.exec(String(node.name || ""))
        return match ? match[1].replace(/_/g, ":").toLowerCase() : ""
    }

    function kindOf(name: string): string {
        if (/duplex/.test(name) || /^headset[-_]head[-_]unit/.test(name)) return "calls"
        return /^(a2dp|bap)[-_]sink/.test(name) ? "listening" : ""
    }

    function nodeSerial(node): string {
        return node ? String((node.properties || {})["object.serial"] ?? node.id) : ""
    }

    function profilesFor(dump, id: string): var {
        const found = { listening: -1, calls: -1, active: "" }
        const device = Array.isArray(dump) ? dump.find(d => d && String(d.id) === id
            && d.type === "PipeWire:Interface:Device") : null
        const params = device && device.info ? device.info.params : null
        if (!params || !Array.isArray(params.EnumProfile)) return found
        const priorities = { listening: -Infinity, calls: -Infinity }
        const active = Array.isArray(params.Profile) && params.Profile[0] ? params.Profile[0].index : -1
        for (const profile of params.EnumProfile) {
            if (!profile || profile.available === "no" || !Number.isInteger(profile.index) || profile.index < 0) continue
            const kind = root.kindOf(String(profile.name || ""))
            if (!kind) continue
            if (profile.index === active) found.active = kind
            const priority = Number(profile.priority) || 0
            if (priority > priorities[kind]) { priorities[kind] = priority; found[kind] = profile.index }
        }
        return found
    }

    readonly property string _device: root.deviceId(Audio.sink)
    readonly property string _identity: root.deviceIdentity(Audio.sink)
    readonly property string _serial: root.nodeSerial(Audio.sink)
    readonly property string _nodeMode: root.kindOf(Audio.sink ? String((Audio.sink.properties || {})["api.bluez5.profile"] || "") : "")
    property string _listedDevice: ""
    property var _profiles: ({ listening: -1, calls: -1, active: "" })
    property int _generation: 0
    property bool _refreshPending: false
    readonly property string current: root._listedDevice === root._device && root._profiles.active
        ? root._profiles.active : root._nodeMode
    readonly property bool available: Audio.backendReady && SystemTools.hasWpctl && SystemTools.hasPwDump
        && root._device.length > 0 && root._identity.length > 0 && root._listedDevice === root._device
        && root._profiles.listening >= 0 && root._profiles.calls >= 0
    readonly property bool _wanted: ControlSurfaces.anyOpen && !Idle.isIdle
        && SystemTools.hasWpctl && SystemTools.hasPwDump && root._device.length > 0
    property string _pending: ""
    readonly property bool switching: root._pending.length > 0
    readonly property string mode: root.switching ? root._pending : root.current
    property string _switchDevice: ""
    property string _switchIdentity: ""
    property string _switchSerial: ""
    property bool _profileVerified: false
    property bool _setSucceeded: false
    property string _readError: ""
    property string _switchError: ""
    readonly property string lastError: root._switchError || root._readError

    function refresh(force: bool): void {
        if ((!root._wanted && !root.switching) || root._device.length === 0
                || (root.switching && (!root._setSucceeded || root._device !== root._switchDevice
                    || root._identity !== root._switchIdentity))
                || (!force && root._listedDevice === root._device)) return
        if (_list.running) { root._refreshPending = true; return }
        root._refreshPending = false
        _list.device = root._device
        _list.identity = root._identity
        _list.generation = root._generation
        _list.exec(["pw-dump", root._device])
    }

    on_WantedChanged: if (root._wanted) root.refresh(true)
    function _targetChanged(): void {
        if (root.switching) { Qt.callLater(root._observe); Qt.callLater(root.refresh, true); return }
        root._generation++
        root._listedDevice = ""
        root._profiles = ({ listening: -1, calls: -1, active: "" })
        root._readError = ""
        root._switchError = ""
        Qt.callLater(root.refresh, true)
    }
    on_DeviceChanged: root._targetChanged()
    on_IdentityChanged: root._targetChanged()
    on_SerialChanged: Qt.callLater(root.refresh, true)
    on_NodeModeChanged: {
        if (root.switching) Qt.callLater(root._observe)
        Qt.callLater(root.refresh, true)
    }
    readonly property bool _targetReady: Audio.backendReady && !!Audio.sink && Audio.sink.ready && !!Audio.sink.audio
        && root._device === root._switchDevice && root._identity === root._switchIdentity
        && (root._nodeMode === root._pending || (root._profileVerified && root._profiles.active === root._pending
            && root.nodeSerial(Audio.sink) !== root._switchSerial))
    on_TargetReadyChanged: if (root.switching) Qt.callLater(root._observe)
    Component.onCompleted: root.refresh(true)
    Connections {
        target: SystemTools
        function onScanRevisionChanged() { root.refresh(true) }
    }
    Connections {
        target: Audio
        function onBackendReadyChanged() {
            if (root.switching && !Audio.backendReady)
                root._finish("PipeWire disconnected. Audio controls were restored.")
        }
    }

    function setMode(kind: string): void {
        if (!root.available || root.switching || _set.running || kind === root.current
                || ["listening", "calls"].indexOf(kind) < 0
                || (Quickshell.env("SILERE_SANDBOX") === "1" && !SystemTools.preview)) return
        root._switchDevice = root._device
        root._switchIdentity = root._identity
        root._switchSerial = root.nodeSerial(Audio.sink)
        root._profileVerified = false
        root._generation++
        root._setSucceeded = false
        root._switchError = ""
        Audio.beginProfileSwitch()
        root._pending = kind
        _settle.restart()
        _set.exec(["wpctl", "set-profile", root._switchDevice, String(root._profiles[kind])])
    }

    function _observe(): void {
        if (root.switching && root._setSucceeded && root._targetReady) root._finish("")
    }

    function _finish(error: string): void {
        if (!root.switching) return
        _settle.stop()
        root._switchError = error
        if (!error) root._profiles = Object.assign({}, root._profiles, { active: root._pending })
        root._pending = ""
        Audio.endProfileSwitch()
        root._generation++
        if (root._device !== root._switchDevice || root._identity !== root._switchIdentity) root._listedDevice = ""
        Qt.callLater(root.refresh, true)
    }

    readonly property Timer _settleTimer: Timer {
        id: _settle
        interval: 8000
        onTriggered: root._finish("The headset mode could not be confirmed. Audio controls were restored.")
    }

    BoundedProcess {
        id: _list
        property string device: ""
        property string identity: ""
        property int generation: -1
        timeoutMs: 5000
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector { id: _listOut }
        onExited: code => {
            if (generation === root._generation && device === root._device && identity === root._identity) {
                if (completedSuccessfully(code)) {
                    try {
                        root._profiles = root.profilesFor(JSON.parse(_listOut.text), device)
                        root._listedDevice = device
                        root._readError = ""
                        if (root.switching && root._setSucceeded) root._profileVerified = true
                        Qt.callLater(root._observe)
                    } catch (error) { root._readError = "Could not read headset modes. Open sound settings to check profiles." }
                } else root._readError = "Could not read headset modes. Open sound settings to check profiles."
            }
            if (root._refreshPending || device !== root._device || identity !== root._identity) Qt.callLater(root.refresh, true)
        }
    }
    BoundedProcess {
        id: _set
        timeoutMs: 5000
        environment: ({ "LC_ALL": "C" })
        onTimeoutReached: root._finish("Headset mode change timed out. Audio controls were restored.")
        onExited: code => {
            if (!root.switching) return
            if (!completedSuccessfully(code)) root._finish("Headset mode could not be changed. Open sound settings to check profiles.")
            else { root._setSucceeded = true; Qt.callLater(root._observe); Qt.callLater(root.refresh, true) }
        }
    }
}
