import QtQuick
import "../../../config"
import "../../common"

MenuRow {
    id: root

    property real   value:     0
    property string valueText: ""
    property string wheelKey:  "quickslider"
    property string accessibleName: ""
    property bool   glyphClickable: false
    property bool   expandable: false
    property bool   expanded:   false
    // hold the chevron gutter open on a non-expandable row so stacked sliders keep one track length
    property bool   reserveExpandSlot: false
    readonly property bool _hasChevSlot: root.expandable || root.reserveExpandSlot

    rowHovered:     _rowHover.hovered
    rowPressed:     _track.dragging
    rowInteractive: root.enabled

    signal moved(real value)
    signal glyphClicked()
    signal expandToggled()

    function _requestExpand(): void {
        root.expandToggled()
    }

    // matches ControlRow: the Home page reads as one row rhythm, not two
    height: Metrics.rowHeightFor(48)

    HoverHandler { id: _rowHover; enabled: root.enabled }

    Item {
        id: _g
        anchors.left:           parent.left
        anchors.leftMargin:     14
        anchors.verticalCenter: parent.verticalCenter
        width: 18; height: 18

        ShellText {
            anchors.centerIn: parent
            text: root.glyph
            color: root.glyphClickable && (_glyphHover.hovered || _glyphTap.pressed)
                ? Theme.text : Theme.withAlpha(Theme.subtext, 0.85)
            font.pixelSize: Settings.iconSize + 2
            ColorFade on color {}
        }

        HoverHandler { id: _glyphHover; enabled: root.enabled && root.glyphClickable; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            id: _glyphTap
            enabled: root.enabled && root.glyphClickable
            margin: 6
            onTapped: {
                root.glyphClicked()
            }
        }

        Accessible.role: root.glyphClickable
            ? Accessible.Button : Accessible.StaticText
        Accessible.name: root.glyphClickable
            ? "Mute " + root.accessibleName.toLowerCase() : ""
        Accessible.focusable: root.enabled && root.glyphClickable
        Accessible.onPressAction: if (root.enabled && root.glyphClickable)
            root.glyphClicked()
    }

    TextMetrics { id: _vm; font.family: Settings.font; font.pixelSize: Settings.fontLabel; text: "100%" }
    ShellText {
        id: _v
        anchors.right: parent.right; anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: Math.ceil(_vm.advanceWidth)
        horizontalAlignment: Text.AlignRight
        text: root.valueText
        color: Theme.withAlpha(Theme.text, 0.60)
        font.pixelSize: Settings.fontLabel
        elide: Text.ElideRight
    }

    Item {
        id: _chev
        anchors.right: _v.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: root._hasChevSlot ? 24 : 0
        height: parent.height
        visible: root.expandable
        opacity: (_chevHover.hovered) ? 1.0 : 0.7
        MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }

        HoverHandler { id: _chevHover; enabled: root.enabled && root.expandable; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            enabled: root.enabled && root.expandable
            onTapped: {
                root._requestExpand()
            }
        }

        ShellText {
            anchors.centerIn: parent
            text: "󰅀"
            color: root.expanded ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.85)
            font.pixelSize: Settings.fontSize
            rotation: root.expanded ? 180 : 0
            transformOrigin: Item.Center
            MotionBehavior on rotation {NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
            ColorFade on color {}
        }
    }

    SliderTrack {
        id: _track
        anchors.left: _g.right;  anchors.leftMargin: 10
        anchors.right: root._hasChevSlot ? _chev.left : _v.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        height: 20

        interactive: root.enabled
        accessibleName: root.accessibleName
        accessibleValueText: root.valueText
        value: root.value
        wheelKey: "qslider:" + root.wheelKey
        onChanged: value => root.moved(value)
    }
}
