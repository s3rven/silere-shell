import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    property var screen: null

    readonly property bool canRead: Network.toolAvailable
    // Quickshell reads networks through NetworkManager only: under iwd or systemd-networkd a dimmed glyph read as offline
    readonly property bool show: ShellSettings.barShowNetwork && canRead && Network.available
    property real _pulseOpacity: 1.0
    readonly property real _baseOpacity: show ? 1.0 : 0.0
    readonly property bool layoutVisible: show || opacity > 0.001
    collapsed: !show

    readonly property bool _disconnected: ShellSettings.barShowNetwork && canRead && Network.available && !Network.connected && !ShellSettings.reduceMotion
    property bool _pulseSettled: false
    readonly property bool _isPulsing: _disconnected && !_pulseSettled
    readonly property bool _showPhysicalLink: Network.hasVpn
        && ShellSettings.netVpnShowLink
    readonly property string _physical: _physicalLabel()
    readonly property string _signal: Network.isWifi && Network.signalStrength > 0
        ? Network.signalStrength + "%"
        : ""
    readonly property string _physicalWithSignal: root._join([root._physical, root._signal], " ")
    readonly property string _linkSummary: root.compact ? Network.underlyingIcon
        : Network.underlyingIcon + " " + root._physical
    readonly property string _vpnText: (Network.vpnName.length > 0 ? Network.vpnName : "VPN")
        + (Network.vpnAddress.length > 0 ? " " + Network.vpnAddress : "")
    readonly property string _inlineText: {
        const parts = []
        if (root._showPhysicalLink) parts.push(Network.underlyingIcon)
        if (!root.compact && ShellSettings.networkSpeedInline && Network.trafficActive)
            parts.push(Network.trafficLabel)
        return root._join(parts)
    }
    // _detailText is empty until hover and carries link glyphs and a 2s traffic rate
    readonly property string _accessibleDetail: {
        if (!Network.connected) return "disconnected"

        const parts = [Network.connectivityText]
        if (Network.hasVpn) parts.push(root._vpnText)
        if (root._showPhysicalLink || !Network.hasVpn) parts.push(root._physicalWithSignal)
        return root._join(parts)
    }
    readonly property string _detailText: {
        if (!Network.connected) return "Disconnected"

        const signal = root._showPhysicalLink || !Network.hasVpn ? root._signal : ""
        const parts = [root._join([Network.connectivityText, signal], ", ")]
        if (Network.hasVpn) parts.push(root._vpnText)
        if (root._showPhysicalLink) parts.push(root._linkSummary)
        else if (!Network.hasVpn) parts.push(root._physical)
        if (Network.trafficActive) parts.push(Network.trafficLabel)
        return root._join(parts)
    }

    opacity:        _baseOpacity * _pulseOpacity
    visible:        layoutVisible
    // the icon cell is a fixed width: one glyph fits, two overflow it
    glyph:          Network.icon
    accessibleName: "Network, " + root._accessibleDetail
    interactive: root.show
    pressed: _tap.pressed
    onActivated: if (root.canActivate)
        MenuState.showHomeAt(Network.deviceType === "ethernet" || !Network.hasWifiDevice ? "wired" : "wifi",
            root, root.screen)
    hasSecondary: Settings.networkSettingsCommand.length > 0
    onSecondaryActivated: SystemAlerts.runOrNotify(Settings.networkSettingsCommand, "Network settings failed")

    TapHandler {
        id: _tap
        enabled: root.canActivate
        onTapped: root.activated()
    }
    maxTextWidth:   compact ? 150 : 260
    // above the 2s traffic-stats poll: shrinkDelay:0 re-animated the pill's width on every single tick
    shrinkDelay:    2400

    MotionBehavior on opacity { gate: !root._isPulsing; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
    glyphColor:  Network.connected ? Theme.barText : Theme.barSubtext
    textColor:   Theme.barSubtext

    animateText: false

    function _physicalLabel(): string {
        if (Network.isWifi) return Network.connectionName || "Wi-Fi"
        const name = Network.connectionName || Network.deviceName
        return name.length === 0 || root.genericWiredName(name) ? "Wired" : name
    }
    // NetworkManager's default profile names and systemd's interface names (eno1, ens3, enp2s0, enx<mac>, end0, eth0)
    function genericWiredName(name: string): bool {
        return /^(ethernet|wired connection [0-9]+|(en[dops]|eth)[0-9][0-9a-z]*|enx[0-9a-f]{12})$/i.test(name)
    }

    function _join(parts, separator = " · "): string {
        return parts.filter(p => p && p.length > 0).join(separator)
    }

    text: expanded ? _detailText : _inlineText

    PulseLoop {
        active: root.barActive && root._isPulsing && !Idle.isIdle
        target: root; targetProperty: "_pulseOpacity"
        peak: 0.5; floor: 1.0; restValue: 1.0
        duration: Motion.ms(800)
    }

    Timer {
        id: _pulseSettle
        interval: 30000
        running: root.barActive && root._isPulsing && !Idle.isIdle
        onTriggered: root._pulseSettled = true
    }
    Connections {
        target: Network
        function onConnectedChanged() { if (Network.connected) root._pulseSettled = false }
    }
}
