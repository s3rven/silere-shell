import QtQuick
import "../../config"
import "../../services"
import "controls"

Column {
    id: root
    // gates the lookup, not the rows: the picker unloads this list once its fold ends, and until then it is on screen
    property bool open: false
    width: parent ? parent.width : 0
    onOpenChanged: Vpn.requestList(root, root.open)
    Component.onCompleted: {
        root._syncProfiles()
        Vpn.requestList(root, root.open)
    }
    Component.onDestruction: Vpn.requestList(root, false)

    // active profiles sort first; move the existing rows by uuid to keep keyboard focus
    function _syncProfiles(): void {
        const profiles = Vpn.profiles
        for (let i = 0; i < profiles.length; i++) {
            const profile = profiles[i]
            let from = i
            while (from < _rows.count && _rows.get(from).uuid !== profile.uuid) from++
            const roles = { uuid: profile.uuid, profileName: profile.name, connected: profile.active }
            if (from === _rows.count) _rows.insert(i, roles)
            else {
                if (from !== i) _rows.move(from, i, 1)
                _rows.set(i, roles)
            }
        }
        if (_rows.count > profiles.length) _rows.remove(profiles.length, _rows.count - profiles.length)
    }

    ListModel { id: _rows }

    Connections {
        target: Vpn
        function onProfilesChanged() { root._syncProfiles() }
    }

    Repeater {
        model: _rows
        InlineOptionRow {
            required property string uuid
            required property string profileName
            required property bool connected

            glyph: "󰦝"
            label: profileName
            selected: connected
            status: Vpn.pendingUuid === uuid ? "Working…" : connected ? "Disconnect" : "Connect"
            busy: Vpn.pendingUuid.length > 0
            onYChanged: if (activeFocus) Qt.callLater(revealFocusAfterMove)
            onTriggered: Vpn.toggle(uuid)
        }
    }
    HintText {
        visible: Vpn.profiles.length === 0 || Vpn.lastError.length > 0
        text: Vpn.lastError.length > 0 ? Vpn.lastError : Vpn.refreshing ? "Loading saved VPNs…" : "No saved VPN profiles. Add one in network settings."
    }
    InlineOptionRow {
        glyph: "󰖟"
        label: "Network settings"
        status: Settings.networkSettingsCommand.length > 0 ? "Open" : "Needs network editor"
        interactive: Settings.networkSettingsCommand.length > 0
        onTriggered: {
            MenuState.close()
            SystemTools.runOrNotify(Settings.networkSettingsCommand, "Network settings failed")
        }
    }
}
