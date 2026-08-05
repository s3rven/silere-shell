import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property string status: ""
    property color accentColor: Theme.accent
    property bool selected: false
    property bool highlighted: false
    property bool warning: false
    property bool interactive: true
    property string labelFontFamily: Settings.font
    property int accessibleRole: Accessible.ListItem
    property string accessibleName: label
    property string accessibleDescription: status

    signal triggered()

    readonly property int rowHeight: 4 * Math.ceil(
        Math.max(32, Settings.capHeight + 12) / 4)
    readonly property bool _hot: _hover.hovered || _tap.pressed || root.activeFocus

    function trigger(): void {
        if (root.enabled && root.interactive) root.triggered()
    }

    width: parent ? parent.width : 0
    height: rowHeight
    opacity: root.enabled && root.interactive ? 1.0 : 0.48
    MotionBehavior on opacity {NumberAnimation { duration: Motion.medium } }
    activeFocusOnTab: root.enabled && root.interactive

    Accessible.role: root.accessibleRole
    Accessible.name: root.accessibleName
    Accessible.description: root.accessibleDescription
    Accessible.focusable: root.enabled && root.interactive
    Accessible.selectable: true
    Accessible.selected: root.selected
    Accessible.checkable: root.accessibleRole === Accessible.RadioButton
    Accessible.checked: root.accessibleRole === Accessible.RadioButton && root.selected
    Accessible.pressed: _tap.pressed
    Accessible.onPressAction: root.trigger()

    Keys.onSpacePressed: event => {
        if (!event.isAutoRepeat) root.trigger()
        event.accepted = true
    }
    Keys.onReturnPressed: event => {
        if (!event.isAutoRepeat) root.trigger()
        event.accepted = true
    }
    Keys.onEnterPressed: event => {
        if (!event.isAutoRepeat) root.trigger()
        event.accepted = true
    }

    HoverHandler {
        id: _hover
        enabled: root.enabled && root.interactive
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        id: _tap
        enabled: root.enabled && root.interactive
        onTapped: root.trigger()
    }

    Rectangle {
        id: _fill
        anchors.fill: parent
        radius: 0
        antialiasing: false
        color: root.warning
            ? Theme.withAlpha(Theme.warning,
                root._hot ? 0.10 : root.selected ? 0.085 : 0.055)
            : root.selected
                ? Theme.withAlpha(root.accentColor,
                    ShellSettings.highContrast ? 0.14
                        : root._hot ? 0.105
                        : ShellSettings.neutralTheme ? 0.065 : 0.085)
                : root.highlighted
                    ? Theme.withAlpha(root.accentColor, root._hot ? 0.075 : 0.050)
                    : root.activeFocus
                        ? Theme.withAlpha(root.accentColor,
                            ShellSettings.highContrast ? 0.12 : 0.055)
                    : _tap.pressed ? Theme.withAlpha(Theme.text, 0.055)
                        : _hover.hovered ? Theme.withAlpha(Theme.text, 0.030)
                            : "transparent"
        ColorFade on color {}
    }

    ShellText {
        id: _glyph
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        horizontalAlignment: Text.AlignHCenter
        text: root.glyph
        color: root.warning ? Theme.warning
            : root.selected || root.highlighted ? root.accentColor
            : Theme.withAlpha(Theme.subtext, 0.78)
        font.pixelSize: Settings.iconSize + 1
        ColorFade on color {}
    }

    ShellText {
        anchors.left: _glyph.right
        anchors.leftMargin: 10
        anchors.right: _status.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        elide: Text.ElideRight
        color: root.selected || root.highlighted ? Theme.text
            : Theme.withAlpha(Theme.text, root._hot ? 0.92 : 0.76)
        font.family: root.labelFontFamily
        font.pixelSize: Settings.fontSize
        font.weight: root.selected ? Font.DemiBold : Font.Normal
        ColorFade on color {}
    }

    ShellText {
        id: _status
        anchors.right: _check.left
        anchors.rightMargin: root.selected ? 6 : 0
        MotionBehavior on anchors.rightMargin { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.max(0, root.width * 0.34))
        horizontalAlignment: Text.AlignRight
        text: root.status
        elide: Text.ElideRight
        color: root.warning ? Theme.warning
            : root.selected ? Theme.mix(root.accentColor, Theme.text, 0.14)
            : Theme.withAlpha(Theme.subtext, root._hot ? 0.70 : 0.54)
        font.pixelSize: Math.max(9, Settings.fontSize - 2)
        font.weight: root.warning || root.selected ? Font.Medium : Font.Normal
        ColorFade on color {}
    }

    ShellText {
        id: _check
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: root.selected ? 18 : 0
        horizontalAlignment: Text.AlignHCenter
        text: "󰄬"
        color: root.warning ? Theme.warning : root.accentColor
        font.pixelSize: Settings.fontSize
        opacity: root.selected ? 0.90 : 0.0
        MotionBehavior on width { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        MotionBehavior on opacity { NumberAnimation { duration: Motion.fast } }
    }
}
