import QtQuick
import "../../config"
import "../../services"

// Compact one-line slider for the Now page: glyph, track, pinned value.
// Pure bindings, no polling; emits 0..1 on user input.
Item {
    id: root

    property string glyph:     ""
    property real   value:     0
    property string valueText: ""
    property string wheelKey:  "quickslider"
    property string accessibleName: wheelKey
    property bool   glyphClickable: false

    signal moved(real value)
    signal glyphClicked()

    width:  parent ? parent.width : 0
    height: 36

    function _nudge(dir: int): void {
        root.moved(Math.max(0, Math.min(1, root.value + dir * 0.05)))
    }

    activeFocusOnTab: root.enabled
    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName
    Accessible.description: root.valueText
    Keys.onLeftPressed:  event => { root._nudge(-1); event.accepted = true }
    Keys.onDownPressed:  event => { root._nudge(-1); event.accepted = true }
    Keys.onRightPressed: event => { root._nudge(1);  event.accepted = true }
    Keys.onUpPressed:    event => { root._nudge(1);  event.accepted = true }

    Text {
        id: _g
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        width: Settings.fontSize + 8
        text: root.glyph
        color: Theme.withAlpha(Theme.subtext, 0.85)
        font.family: Settings.font
        font.pixelSize: Settings.fontSize + 1
        renderType: Text.NativeRendering

        HoverHandler { enabled: root.glyphClickable; cursorShape: Qt.PointingHandCursor }
        TapHandler   { enabled: root.glyphClickable; margin: 6; onTapped: root.glyphClicked() }
    }

    TextMetrics { id: _vm; font.family: Settings.font; font.pixelSize: Settings.fontSize - 1; text: "100%" }
    Text {
        id: _v
        anchors.right: parent.right; anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: Math.ceil(_vm.advanceWidth)
        horizontalAlignment: Text.AlignRight
        text: root.valueText
        color: Theme.withAlpha(Theme.text, 0.60)
        font.family: Settings.font
        font.pixelSize: Settings.fontSize - 1
        renderType: Text.NativeRendering
    }

    Item {
        id: _track
        anchors.left: _g.right;  anchors.leftMargin: 10
        anchors.right: _v.left;  anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: 16

        readonly property real ratio: Math.max(0, Math.min(1, root.value))

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 4; radius: 2
            antialiasing: true
            color: Theme.withAlpha(Theme.subtext, 0.18)
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: _track.ratio <= 0 ? 0 : Math.max(4, _track.width * _track.ratio)
            height: 4; radius: 2
            antialiasing: true
            // Solid, not translucent — see-through accent over the track looks washed.
            color: _ma.pressed ? Theme.mix(Theme.accent, Theme.text, 0.22) : Theme.accent
            Behavior on width { enabled: !_ma.pressed && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.instant; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
        Rectangle {
            width: 12; height: 12; radius: 6
            antialiasing: true
            anchors.verticalCenter: parent.verticalCenter
            x: _track.ratio * (_track.width - width)
            color: _ma.pressed ? Theme.accent : Theme.text
            scale: (_h.hovered || _ma.pressed || root.activeFocus) ? 1.0 : 0.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutBack; easing.overshoot: 1.5 } }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        HoverHandler { id: _h; cursorShape: Qt.PointingHandCursor }
        MouseArea {
            id: _ma
            anchors.fill: parent
            anchors.topMargin: -10; anchors.bottomMargin: -10
            preventStealing: true
            function _r(px) { return _track.width > 0 ? Math.max(0, Math.min(1, px / _track.width)) : 0 }
            onPressed:         (m) => root.moved(_r(m.x))
            onPositionChanged: (m) => { if (pressed) root.moved(_r(m.x)) }
            onWheel: (w) => {
                const n = Scroll.processControlWheel(w, "qslider:" + root.wheelKey)
                if (n !== 0) root.moved(Math.max(0, Math.min(1, root.value + n * 0.05)))
            }
        }
    }
}
