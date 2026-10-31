import QtQuick
import "../../config"
import "../../services"
import "controls"

Column {
    id: root
    property bool open: false
    width: parent ? parent.width : 0
    onOpenChanged: Vpn.requested = root.open
    Component.onCompleted: Vpn.requested = root.open
    Component.onDestruction: Vpn.requested = false

    Repeater {
        model: root.open ? Vpn.profiles : []
        InlineOptionRow {
            required property var modelData
            glyph: "󰦝"
            label: modelData.name
            selected: modelData.active
            status: Vpn.pendingUuid === modelData.uuid ? "Working…" : modelData.active ? "Disconnect" : "Connect"
            busy: Vpn.pendingUuid.length > 0
            onTriggered: Vpn.toggle(modelData.uuid)
        }
    }
    HintText {
        visible: root.open && (Vpn.profiles.length === 0 || Vpn.lastError.length > 0)
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
