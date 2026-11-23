import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

// a script's reading, drawn as waybar's custom modules draw it: its text at rest, its tooltip on hover, warning or
// critical in their colours. The settings come first, so a bar with the widget off reads nothing from the service
Pill {
    id: root
    property var screen: null

    readonly property bool _set: ShellSettings.barShowCustom && ShellSettings.customCommand.trim().length > 0
    readonly property string _reading: root._set ? CustomCommand.text : ""
    readonly property string _detail: root._set ? CustomCommand.tooltip : ""
    readonly property int _level: root._set ? CustomCommand.level : 0
    readonly property bool show: root._reading.length > 0
    readonly property bool layoutVisible: show || opacity > 0.001
    collapsed: !show
    visible: layoutVisible
    opacity: show ? 1 : 0
    MotionBehavior on opacity { NumberAnimation { duration: Motion.fast } }

    // scripts carry their own icon in the text
    glyph: ""
    text: root.expanded && root._detail.length > 0 ? root._detail : root._reading
    textColor: root._level === 2 ? Theme.barError : root._level === 1 ? Theme.barWarning : Theme.barText
    maxTextWidth: compact ? 160 : 320
    accessibleName: root._detail.length > 0 ? root._reading + ", " + root._detail : root._reading

    interactive: root.show
    onActivated: if (root.canActivate) CustomCommand.activate()
    pressed: _tap.pressed
    TapHandler { id: _tap; enabled: root.canActivate; onTapped: root.activated() }
}
