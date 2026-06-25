import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root
    readonly property bool canRead: Network.toolAvailable
    property real _pulseOpacity: 1.0
    readonly property real _baseOpacity: !ShellSettings.barShowNetwork ? 0.0
        : canRead ? (Network.available ? 1.0 : 0.0) : 0.45

    // Pulse to alert on a dropped connection, but don't pulse *forever*, an
    // extended outage would drive the render loop for no new info. After a bit it
    // settles to a static (still-disconnected) icon; the next drop re-arms it.
    readonly property bool _disconnected: ShellSettings.barShowNetwork && canRead && Network.available && !Network.connected && !ShellSettings.reduceMotion
    property bool _pulseSettled: false
    readonly property bool _isPulsing: _disconnected && !_pulseSettled

    opacity:        _baseOpacity * _pulseOpacity
    visible:        opacity > 0
    // On a VPN, optionally append the underlying link's icon ("VPN / wifi") so you
    // can tell at a glance what you're tunnelling over (Settings → Bar → Widgets).
    glyph:          (Network.hasVpn && ShellSettings.netVpnShowLink)
                        ? Network.icon + " · " + Network.underlyingIcon
                        : Network.icon
    maxTextWidth:   220
    shrinkDelay:    0

    Behavior on opacity { enabled: !root._isPulsing; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
    glyphColor:  canRead && Network.connected ? Theme.text : Theme.subtext
    textColor:   Theme.subtext
    accessibleName: !canRead ? "Network status unavailable"
        : !Network.available ? "Network unavailable"
        : !Network.connected ? "Network disconnected"
        : `Network connected, ${root._physicalLabel()}${Network.isWifi && Network.signalStrength > 0 ? `, ${Network.signalStrength} percent signal` : ""}`

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

    text: {
        if (!expanded) {
            // Optionally keep just the live up/down speed pinned beside the icon;
            // hovering still expands to the full link / signal / VPN detail below.
            if (ShellSettings.networkSpeedInline && Network.trafficActive)
                return Network.trafficLabel
            return ""
        }
        if (!canRead) return "nmcli missing"
        if (!Network.connected) return "Disconnected"
        const physical = root._physicalLabel()
        const signal = Network.isWifi && Network.signalStrength > 0
            ? Network.signalStrength + "%"
            : ""
        const traffic = Network.trafficActive ? Network.trafficLabel : ""
        if (traffic.length > 0 && Network.hasVpn && Network.vpnName.length > 0)
            return root._join([traffic, Network.vpnName, physical, signal])
        if (traffic.length > 0)
            return root._join([traffic, physical, signal])
        if (Network.hasVpn && Network.vpnName.length > 0)
            return root._join([Network.vpnName, physical, signal])
        return root._join([physical, signal])
    }

    SequentialAnimation {
        running: root._isPulsing && !Idle.isIdle
        loops:   Animation.Infinite
        NumberAnimation { target: root; property: "_pulseOpacity"; to: 0.3; duration: Motion.ms(800); easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "_pulseOpacity"; to: 1.0; duration: Motion.ms(800); easing.type: Easing.InOutSine }
        onStopped: root._pulseOpacity = 1.0
    }

    Timer {
        id: _pulseSettle
        interval: 30000
        running: root._disconnected && !root._pulseSettled
        onTriggered: root._pulseSettled = true
    }
    Connections {
        target: Network
        function onConnectedChanged() { if (Network.connected) root._pulseSettled = false }
    }
}
