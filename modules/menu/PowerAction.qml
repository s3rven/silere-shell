import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property real glyphOffsetX: 0
    property real glyphOffsetY: 0
    property bool confirm: false
    property bool armed: false

    readonly property color _box:       Theme.menuControl
    readonly property color _boxHot:    Theme.mix(Theme.menuControl, Theme.text, 0.035)
    // armed = one press from firing; error-tinted so the wait-to-confirm state is unmistakable
    readonly property color _boxArmed:  Theme.mix(Theme.menuControl, Theme.error, 0.12)
    readonly property color _line:      Theme.menuControlLine
    readonly property color _lineHot:   Theme.menuControlLineHot
    readonly property color _lineArmed: Theme.withAlpha(Theme.error, 0.38)
    readonly property color _text:      Theme.text
    readonly property color _textDim:   Theme.withAlpha(Theme.text, 0.72)
    readonly property bool _hot: root.enabled && (_hover.hovered || root.activeFocus || root.armed)
    readonly property bool _pressed: _tap.pressed

    signal triggered()

    width: parent ? parent.width : 0
    height: 54
    opacity: root.enabled ? 1.0 : 0.38
    scale: root._pressed ? 0.965 : 1.0
    transformOrigin: Item.Center
    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast } }
    Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

    function disarm(): void { root.armed = false }
    function _activate(): void {
        if (!root.enabled) return
        if (!root.confirm || root.armed) root.triggered()
        else { root.armed = true; _armTimer.restart() }
    }

    Timer { id: _armTimer; interval: 3000; onTriggered: root.disarm() }
    onEnabledChanged: if (!root.enabled) root.disarm()

    activeFocusOnTab: root.enabled
    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.description: root.armed ? "Activate again to confirm" : ""
    Keys.onSpacePressed:  e => { if (!e.isAutoRepeat) root._activate(); e.accepted = true }
    Keys.onReturnPressed: e => { if (!e.isAutoRepeat) root._activate(); e.accepted = true }
    Keys.onEnterPressed:  e => { if (!e.isAutoRepeat) root._activate(); e.accepted = true }

    HoverHandler { id: _hover; cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler   { id: _tap; enabled: root.enabled; onTapped: root._activate() }

    Rectangle {
        id: _surface
        anchors.fill: parent
        radius: 13
        antialiasing: true
        color: root.armed ? root._boxArmed
             : root._hot ? root._boxHot
             : root._box
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Theme.withAlpha(Theme.text, 0.34)
                    : root.armed ? root._lineArmed
                    : root._hot ? root._lineHot
                    : root._line
        Behavior on color        { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.fast } }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            height: Math.round(parent.height * 0.46)
            radius: parent.radius - 1
            antialiasing: true
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.withAlpha(Theme.text, root._hot ? 0.052 : 0.030) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        Item {
            id: _icon
            anchors.fill: parent

            Text {
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.glyph
                color: root.armed || root._hot ? root._text : root._textDim
                font.family: Settings.font
                font.pixelSize: Settings.fontSize + 8
                font.weight: Font.Normal
                renderType: Text.NativeRendering
                transform: Translate {
                    x: root.glyphOffsetX
                    y: root.glyphOffsetY
                }
                Behavior on color { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.fast } }
            }
        }
    }

    // glyph-only tile: the hover chip is its visible name
    Rectangle {
        readonly property bool _show: (_hover.hovered || root.activeFocus || root.armed) && root.enabled
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 7
        width: _tipText.implicitWidth + 16
        height: 22
        radius: 8
        antialiasing: true
        // theme-derived so matugen/black tones restyle it; ~the old charcoal value
        color: Theme.mix(Theme.background, Theme.text, 0.020)
        border.width: 1
        border.color: root.armed ? Theme.withAlpha(Theme.error, 0.38)
                    : root._hot ? Theme.menuControlLineHot
                    : Theme.menuCardBorder
        opacity: _show ? 1 : 0
        scale: _show ? 1 : 0.96
        visible: opacity > 0.01
        z: 10
        Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast } }
        Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

        Text {
            id: _tipText
            anchors.centerIn: parent
            text: root.armed ? "Press again: " + root.label : root.label
            color: root.armed ? root._text : Theme.withAlpha(Theme.text, 0.82)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize - 2
            font.weight: root.armed ? Font.DemiBold : Font.Medium
            renderType: Text.NativeRendering
        }
    }
}
