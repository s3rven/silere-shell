pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool available: SystemTools.hasNmcli && Network.toolAvailable
    property bool requested: false
    // one list run, so Home can leave the VPN row out when nothing is saved
    property bool _peek: false
    property real _peekedAt: 0
    readonly property bool _wanted: root.available && (root.requested || root._peek) && !Idle.isIdle
    // once a minute at most: Home asks on every open
    function peek(): void {
        const age = Date.now() - root._peekedAt
        if (!root.available || _list.running || (age >= 0 && age < 60000)) return
        root._peekedAt = Date.now()
        root._peek = true
        root.refresh()
    }
    Component.onCompleted: if (root.available) Qt.callLater(root.peek)
    property var profiles: []
    property string pendingUuid: ""
    property string _listError: ""
    property string _actionError: ""
    readonly property string lastError: root._actionError || root._listError
    readonly property bool refreshing: _list.running
    property bool _refreshPending: false
    property int _generation: 0
    property int _listGeneration: 0

    function parseProfiles(raw: string): var {
        const rows = []
        for (const line of raw.split(/\r?\n/)) {
            const fields = Network._splitNmcliLine(line)
            if (fields.length !== 4 || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(fields[0])) continue
            if (["vpn", "wireguard", "tun"].indexOf(fields[1]) < 0) continue
            rows.push({ uuid: fields[0], type: fields[1], name: SafeText.singleLineText(fields[2], 128), active: fields[3] === "yes" })
        }
        return rows.sort((a, b) => a.active !== b.active ? (a.active ? -1 : 1) : a.name.localeCompare(b.name))
    }
    function refresh(): void {
        if (!root._wanted) return
        if (_list.running) { root._refreshPending = true; return }
        root._refreshPending = false
        root._listGeneration = root._generation
        _list.running = true
    }
    on_WantedChanged: {
        if (root._wanted) root.refresh()
        else root._refreshPending = false
    }
    onAvailableChanged: {
        root._generation++
        if (available) Qt.callLater(root.peek)
        else {
            root.profiles = []
            root._listError = ""
        }
    }
    // the bar reports one tunnel; another tunnel or a saved profile can change independently
    Timer {
        interval: 5000
        repeat: true
        running: root.available && root.requested && !Idle.isIdle
        onTriggered: root.refresh()
    }
    Connections {
        target: Network
        function onHasVpnChanged() { root.refresh() }
        function onVpnNameChanged() { root.refresh() }
    }
    // the list repeats its rows off this array and polls every 5 s, so an unchanged answer has
    // to keep the array or every row is rebuilt, taking keyboard focus with it
    function _publishProfiles(next): void {
        const current = root.profiles
        const same = next.length === current.length && next.every((profile, index) => {
            const known = current[index]
            return profile.uuid === known.uuid && profile.type === known.type
                && profile.name === known.name && profile.active === known.active
        })
        if (!same) root.profiles = next
    }
    function toggle(uuid: string): void {
        if (!root.available || root.pendingUuid.length > 0) return
        const profile = root.profiles.find(p => p.uuid === uuid)
        if (!profile) return
        root._actionError = ""
        root.pendingUuid = uuid
        _action.command = ["nmcli", "--wait", "60", "connection", profile.active ? "down" : "up", "uuid", uuid]
        if (Quickshell.env("SILERE_SANDBOX") === "1") {
            root.pendingUuid = ""
            return
        }
        _action.running = true
    }
    BoundedProcess {
        id: _list
        timeoutMs: 5000
        environment: ({ "LC_ALL": "C" })
        command: ["nmcli", "-t", "-f", "UUID,TYPE,NAME,ACTIVE", "connection", "show"]
        stdout: StdioCollector { id: _listOut }
        onExited: code => {
            if (root._wanted && root._listGeneration === root._generation) {
                if (_list.completedSuccessfully(code)) {
                    root._publishProfiles(root.parseProfiles(_listOut.text))
                    root._listError = ""
                } else root._listError = "Could not read VPN profiles. Open network settings to check NetworkManager."
            }
            root._peek = false
            if (root._refreshPending || root._listGeneration !== root._generation)
                Qt.callLater(root.refresh)
        }
    }
    BoundedProcess {
        id: _action
        timeoutMs: 65000
        environment: ({ "LC_ALL": "C" })
        onExited: code => {
            root.pendingUuid = ""
            root._actionError = _action.timedOut ? "VPN request timed out."
                : code !== 0 ? "VPN request failed. Open network settings to check credentials or the connection." : ""
            Network._queueVpnRefresh()
            root.refresh()
        }
    }
}
