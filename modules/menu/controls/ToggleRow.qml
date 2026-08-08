import QtQuick
import "../../../config"
import "../../common"

Item {
    id: root

    property string glyph:        ""
    property string label:        ""
    property string description:  ""
    property bool   checked:      false
    property real   topRadius:    0
    property real   bottomRadius: 0
    property bool   available:    true
    property string dependsNote:  ""
    property real   cardInset:    1
    property real   cardLeftBleed: 0

    signal toggled(bool nextChecked)

    readonly property bool _canToggle: root.enabled && (root.available || root.checked)
    readonly property bool _showDependsNote: root.dependsNote.length > 0
                                            && (!root.enabled || !root.available)
    readonly property bool _hasDetail: root.description.length > 0
                                    || root._showDependsNote
    readonly property string _detailText: {
        if (!root._showDependsNote) return root.description
        if (root.description.length === 0) return root.dependsNote
        return root.description + " · " + root.dependsNote
    }
    readonly property string _accessibleDescription: {
        const parts = []
        if (root.description.length > 0) parts.push(root.description)
        if (root._showDependsNote) parts.push(root.dependsNote)
        return parts.join(". ")
    }

    FocusVisual { id: _focusVisual; target: root }
    readonly property bool pointerFocusActive:
        root.activeFocus && _focusVisual.pointerOwned

    function _activate(): void {
        if (!_canToggle) return
        // animate the knob only on a real user flip; section switches re-run layout and would otherwise slide every checked knob
        _toggle.armFlipAnimation()
        root.toggled(!root.checked)
    }

    // a description grows the row to fit its wrapping subtitle, still on the shared grid
    readonly property int _descPadV: 11
    width:          parent ? parent.width : 0
    height:         _hasDetail ? 4 * Math.ceil((_descPadV * 2 + _textCol.implicitHeight) / 4)
                               : Metrics.rowHeightFor(44)
    implicitHeight: height

    opacity: root.enabled && root.available ? 1.0 : (_canToggle ? 0.72 : 0.52)
    MotionBehavior on opacity {NumberAnimation { duration: Motion.medium } }

    activeFocusOnTab: _canToggle
    Accessible.role: Accessible.Switch
    Accessible.name: root.label
    Accessible.description: root._accessibleDescription
    Accessible.checked: root.checked
    Accessible.onPressAction: root._activate()
    Accessible.onToggleAction: root._activate()
    Keys.onPressed: _focusVisual.noteKeyboardInput()
    Keys.onSpacePressed: event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }
    Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }

    HoverHandler { id: _hover; cursorShape: root._canToggle ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler {
        id: _tap
        enabled: root._canToggle
        onTapped: {
            _focusVisual.takePointerFocus()
            root._activate()
        }
    }

    RowHoverBg {
        anchors.fill: parent
        topRadius:    root.topRadius
        bottomRadius: root.bottomRadius
        cardInset:    root.cardInset
        leftBleed:    root.cardLeftBleed
        active:       (_hover.hovered || _focusVisual.active) && root._canToggle
        focusActive:  _focusVisual.active && root._canToggle
    }

    ShellText {
        id: _glyph
        anchors.left:           parent.left
        anchors.leftMargin:     14
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        horizontalAlignment: Text.AlignHCenter
        text:           root.glyph
        color:          root.checked
            ? Theme.withAlpha(Theme.accent, 0.9)
            : Theme.withAlpha(Theme.subtext, 0.85)
        font.pixelSize: Settings.iconSize + 2
        ColorFade on color {}
    }

    Column {
        id: _textCol
        anchors.left:           _glyph.right
        anchors.leftMargin:     10
        anchors.right:          _rightSlot.left
        anchors.rightMargin:    10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        ShellText {
            id: _label
            width: parent.width
            text:           root.label
            elide:          Text.ElideRight
            color:          root.checked
                ? Theme.text
                : Theme.withAlpha(Theme.text, 0.85)
            font.pixelSize: Settings.fontSize
            ColorFade on color {}
        }

        ShellText {
            id: _desc
            visible: root._hasDetail
            width:   parent.width
            text:           root._detailText
            wrapMode:       Text.WordWrap
            maximumLineCount: 2
            elide:          Text.ElideRight
            color:          root._showDependsNote
                ? Theme.withAlpha(Theme.mix(Theme.subtext, Theme.warning, 0.30), 0.72)
                : Theme.withAlpha(Theme.subtext, 0.52)
            font.pixelSize: Settings.fontCaption
            lineHeight:     1.1
        }
    }

    Item {
        id: _rightSlot
        anchors.right:          parent.right
        anchors.rightMargin:    12
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: 20

        ToggleSwitch {
            id: _toggle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 20
            checked: root.checked
            highlighted: _hover.hovered && root._canToggle
            focused: _focusVisual.active && root._canToggle
            pressed: _tap.pressed
        }
    }
}
