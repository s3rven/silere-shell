import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    property var screen: null

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
    // one device's charge, -1 for none or for several: a lone number beside two headsets would name neither
    readonly property int _battery: root._linked && Bluetooth.connectedCount === 1 ? Bluetooth.connectedBattery : -1
    // a device about to run out warns on the glyph, at the mark its desktop alert uses
    function lowCharge(battery: int): bool {
        return battery >= 0 && battery < SystemAlerts.btLowPct
    }
    readonly property bool _batteryLow: root.lowCharge(root._battery)
    glyphColor: root._batteryLow ? Theme.warning : root._linked ? Theme.barText : Theme.barSubtext
    textColor:  Theme.barSubtext
    animateText: false
    maxTextWidth: compact ? 130 : 220

    // with values shown at rest, the charge reads beside the glyph as the volume's level does
    function restText(valuesOnHover: bool, battery: int): string {
        return !valuesOnHover && battery >= 0 ? battery + "%" : ""
    }
    readonly property string _restText: root.restText(ShellSettings.valuesOnHover, root._battery)
    reserveText: root._restText.length > 0 ? "00%" : ""
    text: expanded ? Bluetooth.statusText : root._restText
    accessibleName: "Bluetooth, " + Bluetooth.statusText
    interactive: root.show
    pressed: _tap.pressed
    onActivated: if (root.canActivate) MenuState.showHomeAt("bt", root, root.screen)
    hasSecondary: Settings.bluetoothSettingsCommand.length > 0
    onSecondaryActivated: SystemTools.runOrNotify(Settings.bluetoothSettingsCommand, "Bluetooth manager failed")

    TapHandler {
        id: _tap
        enabled: root.canActivate
        onTapped: root.activated()
    }
}
