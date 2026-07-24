import QtQuick
import "../../config"
import "../../services"

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

    signal toggled()

    readonly property bool _hasDesc: root.description.length > 0
    readonly property bool _canToggle: root.enabled && (root.available || root.checked)
    readonly property bool _showDependsNote: root.dependsNote.length > 0
                                            && (!root.enabled || !root.available)
    readonly property real _noteW: _showDependsNote
        ? Math.min(_noteText.implicitWidth, Math.max(46, root.width * 0.26)) : 0
    readonly property real _rightSlotW: 38 + (_showDependsNote ? _noteW + 8 : 0)
    readonly property string _accessibleDescription: {
        const parts = []
        if (root.description.length > 0) parts.push(root.description)
        if (root._showDependsNote) parts.push(root.dependsNote)
        return parts.join(". ")
    }

    function _activate(): void {
        if (!_canToggle) return
        // animate the knob only on a real user flip; section switches re-run layout and would otherwise slide every checked knob
        _toggle.armFlipAnimation()
        root.toggled()
    }

    // 4px multiple keeps card dividers on whole physical px under fractional scaling; a description grows the row to fit its wrapping subtitle, still snapped
    readonly property int _descPadV: 11
    width:          parent ? parent.width : 0
    height:         _hasDesc ? 4 * Math.ceil((_descPadV * 2 + _textCol.implicitHeight) / 4) : 44
    implicitHeight: height

    opacity: root.enabled && root.available ? 1.0 : (_canToggle ? 0.72 : 0.45)
    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium } }

    activeFocusOnTab: _canToggle
    Accessible.role: Accessible.CheckBox
    Accessible.name: root.label
    Accessible.description: root._accessibleDescription
    Accessible.checked: root.checked
    Accessible.onPressAction: root._activate()
    Keys.onSpacePressed: event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }
    Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }

    HoverHandler { id: _hover; cursorShape: root._canToggle ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler {
        enabled: root._canToggle
        onTapped: root._activate()
    }

    RowHoverBg {
        anchors.fill: parent
        topRadius:    root.topRadius
        bottomRadius: root.bottomRadius
        cardInset:    root.cardInset
        active:       (_hover.hovered || root.activeFocus) && root._canToggle
        focusActive:  root.activeFocus && root._canToggle
        fillOpacity:  root.activeFocus ? 0.13 : 0.08
    }

    Text {
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
        font.family:    Settings.font
        font.pixelSize: Settings.iconSize + 2
        renderType:     Text.NativeRendering
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    Column {
        id: _textCol
        anchors.left:           _glyph.right
        anchors.leftMargin:     10
        anchors.right:          _rightSlot.left
        anchors.rightMargin:    8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            id: _label
            width: parent.width
            text:           root.label
            textFormat:     Text.PlainText
            elide:          Text.ElideRight
            color:          root.checked
                ? Theme.text
                : Theme.withAlpha(Theme.text, 0.85)
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize
            renderType:     Text.NativeRendering
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        Text {
            id: _desc
            visible: root._hasDesc
            width:   parent.width
            text:           root.description
            textFormat:     Text.PlainText
            wrapMode:       Text.WordWrap
            maximumLineCount: 2
            elide:          Text.ElideRight
            color:          Theme.withAlpha(Theme.subtext, 0.52)
            font.family:    Settings.font
            font.pixelSize: Math.max(8, Settings.fontSize - 2)
            lineHeight:     1.1
            renderType:     Text.NativeRendering
        }
    }

    Item {
        id: _rightSlot
        anchors.right:          parent.right
        anchors.rightMargin:    12
        anchors.verticalCenter: parent.verticalCenter
        width: root._rightSlotW
        height: 20

        ToggleSwitch {
            id: _toggle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 38
            height: 20
            checked: root.checked
        }

        Text {
            id: _noteText
            visible: root._showDependsNote
            anchors.right: _toggle.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: root._noteW
            horizontalAlignment: Text.AlignRight
            text: root.dependsNote
            elide: Text.ElideRight
            color: Theme.withAlpha(Theme.subtext, 0.55)
            font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
            renderType: Text.NativeRendering
        }
    }
}
