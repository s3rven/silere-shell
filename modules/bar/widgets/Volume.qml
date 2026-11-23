import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    readonly property bool show: ShellSettings.barShowVolume
    property real _baseOpacity: show ? 1.0 : 0.0
    readonly property bool layoutVisible: show || _baseOpacity > 0.001
    collapsed: !show
    opacity: _baseOpacity
    visible: layoutVisible

    MotionBehavior on _baseOpacity {NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

    readonly property bool _canSwitch: Audio.sinkCount > 1

    // a Bluetooth output about to run out warns here at its desktop alert's mark; a shown Bluetooth pill does only for a lone device
    function warnsForOutput(bluetoothShown: bool, connected: int): bool {
        return !(bluetoothShown && connected === 1)
    }
    readonly property int _outputBattery: Audio.sinkBluetoothAddress.length > 0
            && root.warnsForOutput(ShellSettings.barShowBluetooth, Bluetooth.connectedCount)
        ? Bluetooth.batteryForAddress(Audio.sinkBluetoothAddress) : -1
    function outputLow(battery: int): bool {
        return battery >= 0 && battery < SystemAlerts.btLowPct
    }
    readonly property bool _outputLow: root.outputLow(root._outputBattery)
    readonly property string _outputNote: root._outputLow ? "battery " + root._outputBattery + "%" : ""

    glyph:      Audio.icon
    accessibleName: !Audio.ready ? "Volume"
        : (Audio.muted ? "Volume muted" : "Volume " + Math.round(Audio.uiVolume * 100) + "%")
          + (Audio.sinkName.length > 0 ? ", " + Audio.sinkName : "")
          + (root._outputLow ? ", " + root._outputNote : "")
    glyphColor: Audio.muted ? Theme.barSubtext : root._outputLow ? Theme.barWarning : Theme.barText
    textColor:  Theme.barSubtext
    interactive: Audio.ready
    // two digits is the common case; reserving "100%" left a character of air after every reading
    reserveText: "00%"
    readonly property string _level: Math.round(Audio.uiVolume * 100) + "%"
    text: !Audio.ready ? ""
        : (ShellSettings.valuesOnHover && !expanded) ? ""
        : root._level + (expanded && root._outputLow ? " · " + root._outputNote : "")
    maxTextWidth: compact ? 150 : 260
    levelValue: Audio.ready ? Audio.uiVolume : -1
    levelVisible: Audio.ready && ShellSettings.valuesOnHover && ShellSettings.hoverLevelBar && !expanded
    levelColor: Audio.muted ? Theme.barSubtext : Theme.barAccentMark

    wheelKey: "audio:" + root + ":" + (Audio.sink ? String(Audio.sink.id) : "")

    WheelHandler {
        enabled: Audio.ready && root.hoverEnabled
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            event.accepted = true
            if (!Audio.ready || !root.hoverEnabled) return
            const n = Scroll.processLevelWheel(event, root.wheelKey)
            if (n !== 0) Audio.bumpBy(n * Audio.stepPct)
        }
    }

    pressed: _tap.pressed && Audio.ready
    onActivated: if (root.canActivate) Audio.toggleMute()

    TapHandler {
        id: _tap
        enabled: root.canActivate
        acceptedButtons: Qt.LeftButton
        onTapped: root.activated()
    }

    TapHandler {
        enabled: root.canActivate && (Audio.hasSoundSettings || root._canSwitch)
        acceptedButtons: (Audio.hasSoundSettings ? Qt.RightButton : Qt.NoButton)
            | (root._canSwitch ? Qt.MiddleButton : Qt.NoButton)
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onSingleTapped: (point, button) => {
            if (!root.canActivate) return
            if (button === Qt.RightButton) Audio.openSoundSettings()
            else Audio.cycleSink()
        }
    }
}
