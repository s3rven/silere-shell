import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph:        ""
    property string label:        ""
    // Optional muted subtitle under the label: one plain-language line on what
    // the toggle actually does. Empty keeps the row compact (single-line, 44px).
    property string description:  ""
    property bool   checked:      false
    property real   topRadius:    0
    property real   bottomRadius: 0
    property bool   available:    true
    property string dependsNote:  ""
    property string badge:        ""   // small tag after the label, e.g. "beta"
    // tag colour by kind: warning for experimental ("beta"), neutral for info ("net")
    readonly property color _badgeColor: badge === "beta" ? Theme.warning : Theme.subtext
    // Matches the enclosing card's border width, keeps the hover fill inside
    // the stroke and aligned with the card's INNER rounded edge.
    property real   cardInset:    1

    signal toggled()

    readonly property bool _hasDesc: root.description.length > 0
    readonly property bool _canToggle: root.enabled && (root.available || root.checked)
    readonly property bool _showDependsNote: root.dependsNote.length > 0
                                            && (!root.enabled || (!root.available && !root.checked))
    readonly property real _rightSlotW: _showDependsNote
        ? Math.min(_noteText.implicitWidth, Math.max(54, root.width * 0.34))
        : 34

    function _activate(): void {
        if (!_canToggle) return
        // Animate the knob only on a real user flip; section switches re-run
        // layout and would otherwise slide every checked knob.
        _toggle.armFlipAnimation()
        root.toggled()
    }

    // 4px multiple: keeps card dividers on whole physical px under
    // fractional scaling. A description grows the row to fit its (wrapping)
    // subtitle, still snapped to the grid.
    readonly property int _descPadV: 11
    width:          parent ? parent.width : 0
    height:         _hasDesc ? 4 * Math.ceil((_descPadV * 2 + _textCol.implicitHeight) / 4) : 44
    implicitHeight: height

    opacity: _canToggle ? 1.0 : 0.45
    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium } }

    activeFocusOnTab: _canToggle
    Accessible.role: Accessible.CheckBox
    Accessible.name: root.label
    Accessible.description: root.description.length > 0 ? root.description : root.dependsNote
    Accessible.checked: root.checked
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
        fillOpacity:  root.activeFocus ? 0.13 : 0.08
    }

    Text {
        id: _glyph
        anchors.left:           parent.left
        anchors.leftMargin:     12
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        horizontalAlignment: Text.AlignHCenter
        text:           root.glyph
        color:          root.checked
            ? Theme.withAlpha(Theme.accent, 0.9)
            : Theme.withAlpha(Theme.subtext, 0.85)
        font.family:    Settings.font
        font.pixelSize: Settings.fontSize + 1
        renderType:     Text.NativeRendering
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    // Label (with optional badge) stacked over the optional description; the
    // whole block sits centred against the row so single- and two-line rows
    // both read balanced next to the glyph and toggle.
    Column {
        id: _textCol
        anchors.left:           _glyph.right
        anchors.leftMargin:     8
        anchors.right:          _rightSlot.left
        anchors.rightMargin:    8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Item {
            width:  parent.width
            height: _label.implicitHeight
            clip: true

            Text {
                id: _label
                anchors.left:           parent.left
                anchors.verticalCenter: parent.verticalCenter
                // Cap the width so the tag that follows always stays on the row:
                // a long label elides rather than shoving the badge off the edge.
                width: Math.min(implicitWidth, parent.width - (_badge.visible ? _badge.width + 7 : 0))
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

            Rectangle {
                id: _badge
                // Sits flush after the label so the tag reads as part of it,
                // not a stray chip drifting against the toggle.
                anchors.left:           _label.right
                anchors.leftMargin:     7
                anchors.verticalCenter: _label.verticalCenter
                visible: root.badge.length > 0
                width:  _badgeText.implicitWidth + 9
                height: _badgeText.implicitHeight + 3
                radius: 3
                antialiasing: true
                color: Theme.withAlpha(root._badgeColor, 0.10)
                border.width: 1
                border.color: Theme.withAlpha(root._badgeColor, 0.30)
                Text {
                    id: _badgeText
                    anchors.centerIn: parent
                    text:           root.badge
                    color:          Theme.withAlpha(root._badgeColor, 0.9)
                    font.family:    Settings.font
                    font.pixelSize: Settings.fontSize - 4
                    font.weight:    Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing:  0.4
                    renderType:     Text.NativeRendering
                }
            }
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
        height: 18

        ToggleSwitch {
            id: _toggle
            anchors.fill: parent
            visible: !root._showDependsNote
            checked: root.checked
        }

        Text {
            id: _noteText
            visible: root._showDependsNote
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: root.dependsNote
            elide: Text.ElideRight
            color: Theme.withAlpha(Theme.subtext, 0.55)
            font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
            renderType: Text.NativeRendering
        }
    }
}
