pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

Rectangle {
    id: root

    property string glyph: ""
    property string label: ""
    property string value: ""
    property bool interactive: true
    property bool dangerous: false
    property bool confirm: false
    property bool armed: false
    property bool tintedGlyph: false
    property string confirmLabel: "Press again"
    property int confirmTimeout: 3000
    property color accentColor: Theme.accent

    signal triggered()

    readonly property bool _hot: root.enabled && root.interactive && (_hover.hovered || root.activeFocus)
    readonly property bool _showValue: root.value.length > 0 && !root.armed
    readonly property int _valueMaxW: Math.max(42, Math.min(86, Math.round(root.width * 0.52)))
    property real _shift: root._hot || root.armed ? 0.5 : 0.0
    readonly property color _fg: root.armed
        ? Theme.text
        : root.dangerous
            ? Theme.mix(Theme.text, Theme.error, root._hot ? 0.18 : 0.08)
            : Theme.withAlpha(Theme.mix(Theme.subtext, Theme.text, 0.18), root._hot ? 0.94 : 0.78)
    readonly property color _glyphFg: root.armed
        ? Theme.error
        : root.tintedGlyph
            ? Theme.withAlpha(root.accentColor, root.interactive ? (root._hot ? 0.90 : 0.72) : 0.86)
            : root.dangerous
                ? Theme.withAlpha(Theme.error, root._hot ? 0.86 : 0.60)
                : Theme.withAlpha(Theme.subtext, root._hot ? 0.78 : 0.56)

    width: parent ? parent.width : implicitWidth
    height: 30
    radius: 8
    antialiasing: true
    opacity: root.enabled ? 1.0 : 0.38
    color: root.armed
        ? Theme.withAlpha(Theme.error, 0.105)
        : root._hot ? Theme.withAlpha(Theme.text, 0.045) : "transparent"
    border.width: root.armed || root.activeFocus ? 1 : 0
    border.color: root.armed ? Theme.withAlpha(Theme.error, 0.54)
        : root.dangerous ? Theme.withAlpha(Theme.error, 0.34)
        : Theme.menuControlLineHot
    activeFocusOnTab: root.enabled && root.interactive

    Accessible.role: root.interactive ? Accessible.Button : Accessible.StaticText
    Accessible.name: root.armed ? root.label + ", press again to confirm" : root.label
    Accessible.description: root.value

    function disarm(): void {
        root.armed = false
    }

    function activate(): void {
        if (!root.enabled || !root.interactive) return
        if (!root.confirm || root.armed) {
            root.disarm()
            root.triggered()
        } else {
            root.armed = true
            _armTimer.restart()
        }
    }

    onEnabledChanged: if (!root.enabled) root.disarm()
    onInteractiveChanged: if (!root.interactive) root.disarm()
    onConfirmChanged: if (!root.confirm) root.disarm()

    onArmedChanged: {
        _fuseAnim.stop()
        if (!root.armed) return
        if (ShellSettings.reduceMotion) _fuse.width = _fuse._fullW
        else _fuseAnim.restart()
    }

    Timer {
        id: _armTimer
        interval: root.confirmTimeout
        onTriggered: root.disarm()
    }

    // fuse: depletes over the confirm window so the arm timeout is visible, not a surprise
    Rectangle {
        id: _fuse
        anchors.left: parent.left
        anchors.leftMargin: 13
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        height: 2
        radius: 1
        antialiasing: true
        visible: root.armed
        width: 0
        color: Theme.withAlpha(Theme.error, 0.55)
        readonly property real _fullW: Math.max(0, root.width - 26)
    }
    NumberAnimation {
        id: _fuseAnim
        target: _fuse; property: "width"
        from: _fuse._fullW; to: 0
        duration: root.confirmTimeout
    }

    HoverHandler {
        id: _hover
        enabled: root.enabled && root.interactive
        cursorShape: root.enabled && root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        enabled: root.enabled && root.interactive
        onTapped: root.activate()
    }

    Keys.onSpacePressed: event => { if (!event.isAutoRepeat) root.activate(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root.activate(); event.accepted = true }
    Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root.activate(); event.accepted = true }
    // armed rows eat the first Escape as a disarm; unarmed rows let it fall through to close the rail
    Keys.onEscapePressed: event => {
        if (root.armed) { root.disarm(); event.accepted = true }
        else event.accepted = false
    }

    Behavior on color {
        enabled: !ShellSettings.reduceMotion
        ColorAnimation { duration: Motion.fast }
    }
    Behavior on border.color {
        enabled: !ShellSettings.reduceMotion
        ColorAnimation { duration: Motion.fast }
    }
    Behavior on _shift {
        enabled: !ShellSettings.reduceMotion
        NumberAnimation { duration: Motion.ms(105); easing.type: Easing.OutCubic }
    }

    Text {
        id: _glyph
        anchors.left: parent.left
        anchors.leftMargin: 13
        anchors.verticalCenter: parent.verticalCenter
        width: 19
        horizontalAlignment: Text.AlignHCenter
        text: root.glyph
        color: root._glyphFg
        font.family: Settings.font
        font.pixelSize: Settings.fontSize
        renderType: Text.NativeRendering
        transform: Translate { x: root._shift }
        Behavior on color {
            enabled: !ShellSettings.reduceMotion
            ColorAnimation { duration: Motion.fast }
        }
    }

    Text {
        id: _value
        visible: root._showValue
        anchors.right: parent.right
        anchors.rightMargin: 11
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root._valueMaxW)
        text: root.value
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
        color: Theme.withAlpha(Theme.menuTextMuted, root._hot ? 0.84 : 0.66)
        font.family: Settings.font
        font.pixelSize: Settings.fontSize - 2
        font.weight: Font.Medium
        renderType: Text.NativeRendering
        Behavior on color {
            enabled: !ShellSettings.reduceMotion
            ColorAnimation { duration: Motion.fast }
        }
    }

    Text {
        anchors.left: _glyph.right
        anchors.leftMargin: 9
        anchors.right: parent.right
        anchors.rightMargin: root._showValue ? Math.round(_value.width + 19) : 11
        anchors.verticalCenter: parent.verticalCenter
        text: root.armed ? root.confirmLabel : root.label
        elide: Text.ElideRight
        color: root._fg
        font.family: Settings.font
        font.pixelSize: Settings.fontSize - 1
        font.weight: root.armed ? Font.DemiBold : Font.Normal
        renderType: Text.NativeRendering
        transform: Translate { x: root._shift }
        Behavior on color {
            enabled: !ShellSettings.reduceMotion
            ColorAnimation { duration: Motion.fast }
        }
    }
}
