import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root
    property bool barActive: true

    readonly property bool canRead: Network.toolAvailable
    readonly property bool show: ShellSettings.barShowNetwork
        && (canRead ? Network.available : true)
    property real _pulseOpacity: 1.0
    readonly property real _baseOpacity: !show ? 0.0 : canRead ? 1.0 : 0.45
    readonly property bool layoutVisible: show || opacity > 0.001

    readonly property bool _disconnected: ShellSettings.barShowNetwork && canRead && Network.available && !Network.connected && !ShellSettings.reduceMotion
    property bool _pulseSettled: false
    readonly property bool _isPulsing: _disconnected && !_pulseSettled
    readonly property bool _showPhysicalLink: Network.hasVpn
        && ShellSettings.netVpnShowLink
    readonly property string _physical: _physicalLabel()
    readonly property string _signal: Network.isWifi && Network.signalStrength > 0
        ? Network.signalStrength + "%"
        : ""
    readonly property string _linkSummary: {
        if (!Network.connected) return ""
        const label = root.compact ? Network.underlyingIcon
            : Network.underlyingIcon + " " + root._physical
        return root._signal.length > 0 ? label + " " + root._signal : label
    }
    readonly property string _inlineText: {
        const parts = []
        if (root._showPhysicalLink) parts.push(Network.underlyingIcon)
        if (!root.compact && ShellSettings.networkSpeedInline && Network.trafficActive)
            parts.push(Network.trafficLabel)
        return root._join(parts)
    }
    readonly property string _detailText: {
        if (!root.canRead) return "Network backend unavailable"
        if (!Network.connected) return "Disconnected"

        const parts = []
        if (Network.hasVpn) parts.push(Network.vpnName.length > 0 ? Network.vpnName : "VPN")
        if (root._showPhysicalLink) parts.push(root._linkSummary)
        else if (!Network.hasVpn) {
            const physical = root._signal.length > 0
                ? root._physical + " " + root._signal
                : root._physical
            parts.push(physical)
        }
        if (Network.trafficActive) parts.push(Network.trafficLabel)
        return root._join(parts)
    }

    opacity:        _baseOpacity * _pulseOpacity
    visible:        layoutVisible
    // the icon cell is a fixed width: one glyph fits, two overflow it
    glyph:          Network.icon
    maxTextWidth:   compact ? 150 : 260
    // above the 2s traffic-stats poll: shrinkDelay:0 re-animated the pill's width on every single tick
    shrinkDelay:    2400
    activeFocusOnTab: show
    Accessible.focusable: true

    MotionBehavior on opacity { gate: !root._isPulsing; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
    glyphColor:  canRead && Network.connected ? Theme.text : Theme.subtext
    textColor:   Theme.subtext
    accessibleName: !canRead ? "Network backend unavailable"
        : !Network.available ? "Network unavailable"
        : !Network.connected ? "Network disconnected"
        : Network.hasVpn
            ? `VPN ${Network.vpnName || "active"}, over ${root._physical}${Network.isWifi && Network.signalStrength > 0 ? `, ${Network.signalStrength} percent signal` : ""}`
            : `Network connected, ${root._physical}${Network.isWifi && Network.signalStrength > 0 ? `, ${Network.signalStrength} percent signal` : ""}`

    animateText: false

    function _physicalLabel(): string {
        const name = Network.connectionName || Network.deviceName
        if (!Network.isWifi) {
            const generic = /^(wired connection [0-9]+|ethernet|enp[0-9a-z]+|eth[0-9]+)$/i
            if (name.length === 0 || generic.test(name)) return "Wired"
        }
        return name
    }

    function _join(parts): string {
        return parts.filter(p => p && p.length > 0).join(" · ")
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
        running: root.barActive && root._disconnected && !root._pulseSettled
        onTriggered: root._pulseSettled = true
    }
    Connections {
        target: Network
        function onConnectedChanged() { if (Network.connected) root._pulseSettled = false }
    }
}
