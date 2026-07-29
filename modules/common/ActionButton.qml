import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string label: ""
    property string glyph: ""
    property string accessibleName: label
    property bool emphasis: false
    property bool confirm: false
    property bool armed: false
    property int confirmTimeout: 3000
    property color accentColor: Theme.accent
    property real radius: Theme.radiusControl

    signal triggered()

    // ceil: a fractional width lands the outline stroke off-pixel under fractional scaling
    readonly property real contentWidth: Math.ceil(_row.implicitWidth) + 22
    readonly property bool _emphasis: root.emphasis || root.armed
    readonly property color _accent: root.armed ? Theme.error : root.accentColor
    property bool _keyboardPressed: false
    readonly property bool pressed: _tap.pressed || root._keyboardPressed

    height: 34
    opacity: root.enabled ? 1.0 : 0.42
    Behavior on opacity {
        enabled: !ShellSettings.reduceMotion
        NumberAnimation { duration: Motion.fast }
    }

    function disarm(): void {
        _armTimer.stop()
        root.armed = false
    }
    function activate(): void {
        if (!root.enabled) return
        if (!root.confirm || root.armed) {
            root.disarm()
            root.triggered()
        } else {
            root.armed = true
            _armTimer.restart()
        }
    }

    Timer { id: _armTimer; interval: root.confirmTimeout; onTriggered: root.disarm() }
    onEnabledChanged: {
        if (!root.enabled) {
            root._keyboardPressed = false
            root.disarm()
        }
    }
    onActiveFocusChanged: if (!activeFocus) root._keyboardPressed = false

    activeFocusOnTab: root.enabled
    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.description: root.armed ? "Activate again to confirm" : ""
    Accessible.onPressAction: root.activate()
    Keys.onPressed: event => {
        if (!root.enabled || event.isAutoRepeat
                || (event.key !== Qt.Key_Space
                    && event.key !== Qt.Key_Return
                    && event.key !== Qt.Key_Enter)) return
        root._keyboardPressed = true
        event.accepted = true
    }
    Keys.onReleased: event => {
        if (!root._keyboardPressed
                || (event.key !== Qt.Key_Space
                    && event.key !== Qt.Key_Return
                    && event.key !== Qt.Key_Enter)) return
        root._keyboardPressed = false
        event.accepted = true
        root.activate()
    }
    Keys.onEscapePressed: event => {
        if (root.armed) { root.disarm(); event.accepted = true }
        else event.accepted = false
    }

    HoverHandler {
        id: _hover
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        id: _tap
        enabled: root.enabled
        onTapped: root.activate()
    }

    Rectangle {
        id: _surface
        anchors.fill: parent
        radius: root.radius
        antialiasing: true
        scale: root.pressed ? 0.965 : 1.0
        color: root._emphasis
            ? Theme.mix(Theme.menuControl, root._accent,
                root.pressed ? 0.40 : _hover.hovered || root.armed ? 0.34 : 0.26)
            : root.pressed
                ? Theme.withAlpha(Theme.subtext, 0.21)
                : (_hover.hovered ? Theme.withAlpha(Theme.subtext, 0.16) : Theme.menuControl)

        Behavior on scale {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }

        Behavior on color {
            enabled: !ShellSettings.reduceMotion
            ColorAnimation { duration: Motion.fast }
        }

        OutlineBorder {
            radius: _surface.radius
            outlineWidth: root.activeFocus ? 2 : 1
            outlineColor: root.activeFocus
                ? Theme.withAlpha(root._accent, 0.82)
                : root._emphasis
                    ? Theme.withAlpha(root._accent, 0.48)
                    : _hover.hovered ? Theme.menuControlLineHot : Theme.menuControlLine

            Behavior on outlineColor {
                enabled: !ShellSettings.reduceMotion
                ColorAnimation { duration: Motion.fast }
            }
        }

        Row {
            id: _row
            anchors.centerIn: parent
            spacing: root.glyph.length > 0 && root.label.length > 0 ? 7 : 0

            Text {
                visible: root.glyph.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.glyph
                color: root._emphasis ? root._accent : Theme.withAlpha(Theme.subtext, 0.90)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize
                renderType: Text.NativeRendering
            }
            Text {
                visible: root.label.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.armed ? "Press again" : root.label
                color: root._emphasis ? Theme.text : Theme.withAlpha(Theme.text, 0.84)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 1
                font.weight: root._emphasis ? Font.DemiBold : Font.Normal
                renderType: Text.NativeRendering
            }
        }
    }
}
