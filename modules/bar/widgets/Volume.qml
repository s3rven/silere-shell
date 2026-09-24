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

    glyph:      Audio.icon
    accessibleName: !Audio.ready ? "Volume"
        : (Audio.muted ? "Volume muted, " : "Volume ")
          + Math.round(Audio.effectiveVolume * 100) + "%"
          + (Audio.sinkName.length > 0 ? ", " + Audio.sinkName : "")
    glyphColor: Audio.muted ? Theme.subtext : Theme.text
    textColor:  Theme.subtext
    interactive: Audio.ready
    reserveText: "100%"
    text: !Audio.ready ? ""
        : (ShellSettings.valuesOnHover && !expanded) ? ""
        : (Math.round(Audio.effectiveVolume * 100) + "%")
    levelValue: Audio.ready ? Audio.uiVolume : -1
    levelVisible: Audio.ready && ShellSettings.valuesOnHover && ShellSettings.hoverLevelBar && !expanded
    levelColor: Audio.muted ? Theme.subtext : Theme.accent

    WheelHandler {
        enabled: Audio.ready
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            event.accepted = true
            if (!Audio.ready) return
            const n = Scroll.processLevelWheel(event, "audio")
            if (n !== 0) Audio.bumpBy(n * Audio.stepPct)
        }
    }

    pressed: _tap.pressed && Audio.ready
    onActivated: Audio.toggleMute()

    TapHandler {
        id: _tap
        enabled: root.interactive
        acceptedButtons: Qt.LeftButton
        onTapped: root.activated()
    }

    // only claim the buttons that lead somewhere; the hint already names exactly these,
    // and a swallowed click with nothing behind it reads as a dead widget
    TapHandler {
        enabled: root.interactive && (Audio.hasSoundSettings || root._canSwitch)
        acceptedButtons: (Audio.hasSoundSettings ? Qt.RightButton : Qt.NoButton)
            | (root._canSwitch ? Qt.MiddleButton : Qt.NoButton)
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onSingleTapped: (point, button) => {
            if (button === Qt.RightButton) Audio.openSoundSettings()
            else Audio.cycleSink()
        }
    }
}
