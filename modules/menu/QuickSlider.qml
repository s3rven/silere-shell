import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph:     ""
    property real   value:     0
    property string valueText: ""
    property string valueWidthText: "100%"
    property string wheelKey:  "quickslider"
    property string accessibleName: wheelKey
    property bool   glyphClickable: false
    // Optional trailing chevron — toggles an owner-supplied dropdown.
    property bool   expandable: false
    property bool   expanded:   false
    property real   _shownValue: value

    signal moved(real value)
    signal glyphClicked()
    signal expandToggled()

    width:  parent ? parent.width : 0
    height: 40

    onValueChanged: if (!_ma.pressed) _shownValue = value

    function _clamp(v: real): real { return Math.max(0, Math.min(1, v)) }
    function _setFromUser(v: real): void {
        const next = _clamp(v)
        if (Math.abs(next - root._shownValue) < 0.000001) return
        root._shownValue = next
        root.moved(next)
    }
    function _nudge(dir: int, mult: int): void {
        root._setFromUser(root._shownValue + dir * 0.05 * mult)
    }
    function _handleKey(event): void {
        const big = (event.modifiers & Qt.ShiftModifier) ? 10 : 1
        switch (event.key) {
        case Qt.Key_Left:
        case Qt.Key_Down:
            root._nudge(-1, big); event.accepted = true; return
        case Qt.Key_Right:
        case Qt.Key_Up:
            root._nudge(1, big); event.accepted = true; return
        case Qt.Key_PageDown:
            root._nudge(-1, 10); event.accepted = true; return
        case Qt.Key_PageUp:
            root._nudge(1, 10); event.accepted = true; return
        case Qt.Key_Home:
            root._setFromUser(0); event.accepted = true; return
        case Qt.Key_End:
            root._setFromUser(1); event.accepted = true; return
        }
    }

    activeFocusOnTab: root.enabled
    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName
    Accessible.description: root.valueText
    Keys.onPressed: event => root._handleKey(event)

    // matches ControlRow icon slot so all rows share one left edge
    Item {
        id: _g
        anchors.left:           parent.left
        anchors.leftMargin:     14
        anchors.verticalCenter: parent.verticalCenter
        width: 18; height: 18

        Text {
            anchors.centerIn: parent
            text: root.glyph
            color: Theme.withAlpha(Theme.subtext, 0.85)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize + 2
            renderType: Text.NativeRendering
        }

        HoverHandler { enabled: root.glyphClickable; cursorShape: Qt.PointingHandCursor }
        TapHandler   { enabled: root.glyphClickable; margin: 6; onTapped: root.glyphClicked() }
    }

    TextMetrics { id: _vm; font.family: Settings.font; font.pixelSize: Math.max(11, Settings.fontSize - 1); text: root.valueWidthText }
    Text {
        id: _v
        anchors.right: parent.right; anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: Math.ceil(_vm.advanceWidth)
        horizontalAlignment: Text.AlignRight
        text: root.valueText
        color: Theme.withAlpha(Theme.text, 0.60)
        font.family: Settings.font
        font.pixelSize: Math.max(11, Settings.fontSize - 1)
        renderType: Text.NativeRendering
        elide: Text.ElideRight
    }

    Item {
        id: _chev
        anchors.right: _v.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: root.expandable ? 24 : 0
        height: parent.height
        visible: root.expandable
        opacity: _chevHover.hovered ? 1.0 : 0.7

        Accessible.role: Accessible.Button
        Accessible.name: root.accessibleName + " output device"

        HoverHandler { id: _chevHover; cursorShape: Qt.PointingHandCursor }
        TapHandler   { onTapped: root.expandToggled() }

        Text {
            anchors.centerIn: parent
            text: "󰅀"
            color: root.expanded ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.85)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize
            renderType: Text.NativeRendering
            rotation: root.expanded ? 180 : 0
            transformOrigin: Item.Center
        }
    }

    Item {
        id: _track
        anchors.left: _g.right;  anchors.leftMargin: 10
        anchors.right: root.expandable ? _chev.left : _v.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        height: 16

        readonly property real ratio: root._clamp(root._shownValue)

        Rectangle {
            id: _trackBg
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 4; radius: height / 2
            antialiasing: true
            color: Theme.menuTrack
            clip: true

            Rectangle {
                width: parent.width * _track.ratio
                height: parent.height
                radius: parent.radius
                antialiasing: true
                color: Theme.accent
            }
        }
        Item {
            id: _thumb
            width: 14; height: 14
            anchors.verticalCenter: parent.verticalCenter
            x: _track.width * _track.ratio - width / 2

            Rectangle {
                anchors.centerIn: parent
                width: 12
                height: width
                radius: width / 2
                antialiasing: true
                color: root.activeFocus ? Theme.accent : Theme.mix(Theme.text, Theme.accent, 0.12)
                border.width: root.activeFocus ? 1 : 0
                border.color: Theme.withAlpha(Theme.accent, 0.55)
            }
        }

        MouseArea {
            id: _ma
            anchors.fill: parent
            anchors.topMargin: -10; anchors.bottomMargin: -10
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            function _r(px) { return _track.width > 0 ? Math.max(0, Math.min(1, px / _track.width)) : 0 }
            onPressed:         (m) => root._setFromUser(_r(m.x))
            onPositionChanged: (m) => { if (pressed) root._setFromUser(_r(m.x)) }
            onCanceled:        root._shownValue = root.value
            onWheel: (w) => {
                const n = Scroll.processControlWheel(w, "qslider:" + root.wheelKey)
                if (n !== 0) root._nudge(n, 1)
            }
        }
    }
}
