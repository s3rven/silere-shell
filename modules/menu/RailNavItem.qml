import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property bool active: false
    property color accentColor: Theme.accent
    property int railW: 44

    signal tapped()

    width: railW
    height: 34
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: root.label

    HoverHandler { id: _hover; cursorShape: Qt.PointingHandCursor }
    TapHandler   { id: _tap; onTapped: root.tapped() }
    Keys.onSpacePressed: event => { if (!event.isAutoRepeat) root.tapped(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root.tapped(); event.accepted = true }
    Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root.tapped(); event.accepted = true }

    // Nerd Font glyphs have uneven bearings; measure ink to centre the icon in the pill
    TextMetrics {
        id: _ink
        font.family: Settings.font
        font.pixelSize: Settings.fontSize + 2
        text: root.glyph
    }

    Rectangle {
        id: _activeBg
        anchors.centerIn: parent
        width: 28; height: 28; radius: 8
        antialiasing: true
        color: root.active ? Theme.menuControl
                           : (_hover.hovered || root.activeFocus ? Theme.withAlpha(Theme.text, 0.045) : "transparent")
        border.width: root.active || _hover.hovered || root.activeFocus ? 1 : 0
        border.color: root.active ? Theme.menuControlLine
                                  : Theme.menuControlLineHot
        scale: (root.active || _hover.hovered || root.activeFocus) ? 1.0 : 0.90
        transformOrigin: Item.Center
        Behavior on color { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.fast } }
        Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(135); easing.type: Easing.OutCubic } }
    }

    Text {
        id: _iconText
        anchors.centerIn: parent
        anchors.horizontalCenterOffset:
            _iconText.implicitWidth / 2 - (_ink.tightBoundingRect.x + _ink.tightBoundingRect.width / 2)
        text: root.glyph
        color: root.active
            ? Theme.mix(root.accentColor, Theme.text, 0.10)
            : Theme.withAlpha(Theme.mix(Theme.subtext, root.accentColor, _hover.hovered || root.activeFocus ? 0.24 : 0),
                               _hover.hovered || root.activeFocus ? 0.78 : 0.50)
        font.family: Settings.font
        font.pixelSize: Settings.fontSize + 2
        renderType: Text.NativeRendering
        scale: _tap.pressed ? 0.92 : (root.active ? 1.015 : 1.0)
        transformOrigin: Item.Center
        Behavior on color { enabled: !ShellSettings.reduceMotion; ColorAnimation  { duration: Motion.fast } }
        Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(115); easing.type: Easing.OutCubic } }
    }

    // hides faster than it reveals so it doesn't linger over content
    Rectangle {
        id: _pill
        readonly property bool _show: _hover.hovered && !root.active

        x: root.railW + 6
        anchors.verticalCenter: parent.verticalCenter
        width: _pillLabel.implicitWidth + 18
        height: 22; radius: 8
        color: Theme.menuCard
        border.width: 1; border.color: Theme.menuCardBorder
        antialiasing: true
        opacity: _show ? 1.0 : 0.0
        scale:   _show ? 1.0 : 0.96
        visible: opacity > 0.01
        transformOrigin: Item.Left
        z: 10
        Behavior on opacity {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: _pill._show ? Motion.fast : Motion.instant; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: _pill._show ? Motion.fast : Motion.instant; easing.type: Easing.OutCubic }
        }
        Text {
            id: _pillLabel
            anchors.centerIn: parent
            text: root.label
            color: Theme.withAlpha(Theme.text, 0.78)
            font.family: Settings.font; font.pixelSize: Settings.fontSize - 1
            renderType: Text.NativeRendering
        }
    }
}
