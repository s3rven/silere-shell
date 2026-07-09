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
    // Card-edge rounding for the hover fill — assigned by SettingsCard.
    property real   topRadius:    0
    property real   bottomRadius: 0
    property real   cardInset:    1

    signal moved(real value)
    signal glyphClicked()
    signal expandToggled()

    width:  parent ? parent.width : 0
    height: 40

    function _handleKey(event): void {
        if (root.expandable && (event.modifiers & Qt.AltModifier)) {
            if (event.key === Qt.Key_Down) {
                if (!root.expanded) root.expandToggled()
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_Up) {
                if (root.expanded) root.expandToggled()
                event.accepted = true
                return
            }
        }
        if (root.expandable && root.expanded && event.key === Qt.Key_Escape) {
            root.expandToggled()
            event.accepted = true
            return
        }
        _track.handleKey(event)
    }

    activeFocusOnTab: root.enabled
    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName
    Accessible.description: root.valueText + (root.expandable ? (root.expanded ? ", output devices open" : ", output devices closed") : "")
    Keys.onPressed: event => root._handleKey(event)

    HoverHandler { id: _rowHover; enabled: root.enabled }
    RowHoverBg {
        anchors.fill: parent
        topRadius:    root.topRadius
        bottomRadius: root.bottomRadius
        cardInset:    root.cardInset
        active:       (_rowHover.hovered || root.activeFocus) && root.enabled
        fillOpacity:  root.activeFocus ? 0.13 : 0.08
    }

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
            font.pixelSize: Settings.iconSize + 2
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
        opacity: (_chevHover.hovered || activeFocus) ? 1.0 : 0.7

        activeFocusOnTab: root.enabled && root.expandable

        Accessible.role: Accessible.Button
        Accessible.name: root.accessibleName + " output device"
        Accessible.description: root.expanded ? "Open" : "Closed"

        Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) root.expandToggled(); event.accepted = true }
        Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root.expandToggled(); event.accepted = true }
        Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) root.expandToggled(); event.accepted = true }
        Keys.onEscapePressed: event => { if (root.expanded) root.expandToggled(); event.accepted = true }

        HoverHandler { id: _chevHover; cursorShape: Qt.PointingHandCursor }
        TapHandler   { onTapped: root.expandToggled() }

        Text {
            anchors.centerIn: parent
            text: "󰅀"
            color: root.expanded || _chev.activeFocus ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.85)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize
            renderType: Text.NativeRendering
            rotation: root.expanded ? 180 : 0
            transformOrigin: Item.Center
            Behavior on rotation { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
            Behavior on color    { ColorAnimation { duration: Motion.fast } }
        }
    }

    SliderTrack {
        id: _track
        anchors.left: _g.right;  anchors.leftMargin: 10
        anchors.right: root.expandable ? _chev.left : _v.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        height: 16

        interactive: root.enabled
        focused:     root.activeFocus
        value: root.value
        wheelKey: "qslider:" + root.wheelKey
        onChanged: value => root.moved(value)
    }
}
