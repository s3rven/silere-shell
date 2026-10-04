import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    readonly property bool show: ShellSettings.barShowBluetooth && Bluetooth.available
    readonly property bool layoutVisible: show || opacity > 0.001
    readonly property bool _linked: Bluetooth.enabled && Bluetooth.connectedCount > 0

    collapsed: !show
    visible:   layoutVisible
    opacity:   !show ? 0.0 : Bluetooth.enabled ? 1.0 : 0.45
    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
    }

    // routing, not the rendered glyph: the volume pill swaps to mute and would hand the device straight back here on every mute
    readonly property bool _glyphEchoesVolume: ShellSettings.barShowVolume
        && Audio.sinkClass === "headset"
        && Bluetooth.connectedGlyph === Bluetooth.deviceGlyph("headset")

    glyph: !Bluetooth.enabled ? "󰂲"
        : root._linked && Bluetooth.connectedCount === 1
              && Bluetooth.connectedGlyph.length > 0 && !root._glyphEchoesVolume
            ? Bluetooth.connectedGlyph : "󰂯"
    glyphColor: root._linked ? Theme.text : Theme.subtext
    textColor:  Theme.subtext
    animateText: false
    maxTextWidth: compact ? 130 : 220

    text: expanded ? Bluetooth.statusText : ""
    accessibleName: "Bluetooth, " + Bluetooth.statusText
}
