import QtQuick
import "../../../config"
import "../../common"

Item {
    id: root

    property string glyph:     ""
    property real   value:     0
    property string valueText: ""
    property string valueWidthText: "100%"
    property string wheelKey:  "quickslider"
    property string accessibleName: wheelKey
    property bool   glyphClickable: false
    property string glyphActionName: ""
    property bool   expandable: false
    property bool   expanded:   false
    property string expandLabel: "output device"
    // hold the chevron gutter open on a non-expandable row so stacked sliders keep one track length
    property bool   reserveExpandSlot: false
    readonly property bool _hasChevSlot: root.expandable || root.reserveExpandSlot
    property real   topRadius:    0
    property real   bottomRadius: 0
    property real   cardInset:    1
    property real   cardLeftBleed: 0

    signal moved(real value)
    signal glyphClicked()
    signal expandToggled()

    width:  parent ? parent.width : 0
    height: Metrics.rowHeightFor(40)

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
    Accessible.description: root.valueText + (root.expandable
        ? ", " + root.expandLabel + (root.expanded ? " choices open" : " choices closed") : "")
    Accessible.focusable: root.enabled
    Accessible.onIncreaseAction: if (root.enabled) _track.nudge(1, 1)
    Accessible.onDecreaseAction: if (root.enabled) _track.nudge(-1, 1)
    Keys.onPressed: event => root._handleKey(event)

    HoverHandler { id: _rowHover; enabled: root.enabled }
    RowHoverBg {
        anchors.fill: parent
        topRadius:    root.topRadius
        bottomRadius: root.bottomRadius
        cardInset:    root.cardInset
        leftBleed:    root.cardLeftBleed
        active:       (_rowHover.hovered || root.activeFocus) && root.enabled
        focusActive:  root.activeFocus && root.enabled
    }

    Item {
        id: _g
        anchors.left:           parent.left
        anchors.leftMargin:     14
        anchors.verticalCenter: parent.verticalCenter
        width: 18; height: 18

        activeFocusOnTab: root.enabled && root.glyphClickable
        Accessible.role: root.glyphClickable ? Accessible.Button : Accessible.NoRole
        Accessible.name: root.glyphActionName
        Accessible.onPressAction: if (root.glyphClickable) root.glyphClicked()
        Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) root.glyphClicked(); event.accepted = true }
        Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root.glyphClicked(); event.accepted = true }
        Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) root.glyphClicked(); event.accepted = true }

        ShellText {
            anchors.centerIn: parent
            text: root.glyph
            color: _g.activeFocus ? Theme.accent
                 : (root.glyphClickable && _glyphHover.hovered) ? Theme.text
                 : Theme.withAlpha(Theme.subtext, 0.85)
            font.pixelSize: Settings.iconSize + 2
            ColorFade on color {}
        }

        HoverHandler { id: _glyphHover; enabled: root.glyphClickable; cursorShape: Qt.PointingHandCursor }
        TapHandler   { enabled: root.glyphClickable; margin: 6; onTapped: root.glyphClicked() }
    }

    TextMetrics { id: _vm; font.family: Settings.font; font.pixelSize: Settings.fontLabel; text: root.valueWidthText }
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
        opacity: (_chevHover.hovered || activeFocus) ? 1.0 : 0.7
        MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }

        activeFocusOnTab: root.enabled && root.expandable

        Accessible.role: Accessible.Button
        Accessible.name: root.accessibleName + " " + root.expandLabel
        Accessible.description: root.expanded ? "Open" : "Closed"
        Accessible.onPressAction: root.expandToggled()

        Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) root.expandToggled(); event.accepted = true }
        Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root.expandToggled(); event.accepted = true }
        Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) root.expandToggled(); event.accepted = true }
        Keys.onEscapePressed: event => {
            if (root.expanded) {
                root.expandToggled()
                event.accepted = true
            } else {
                event.accepted = false
            }
        }

        HoverHandler { id: _chevHover; cursorShape: Qt.PointingHandCursor }
        TapHandler   { onTapped: root.expandToggled() }

        ShellText {
            anchors.centerIn: parent
            text: "󰅀"
            color: root.expanded || _chev.activeFocus ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.85)
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
        height: 16

        interactive: root.enabled
        focused:     root.activeFocus
        value: root.value
        wheelKey: "qslider:" + root.wheelKey
        onChanged: value => root.moved(value)
    }
}
