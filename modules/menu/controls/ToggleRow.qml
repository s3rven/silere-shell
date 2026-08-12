import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

MenuRow {
    id: root

    property string label:        ""
    property string description:  ""
    property string key:          ""
    property bool   checked:      root.key.length > 0 ? !!ShellSettings[root.key] : false
    property bool   available:    true
    property string dependsNote:  ""

    rowHovered:     _hover.hovered
    rowInteractive: root._canToggle

    signal toggled(bool nextChecked)

    // Connections, not an onToggled handler: a handler here would be replaced by
    // one written at the use site instead of running alongside it
    Connections {
        target: root
        function onToggled(nextChecked) {
            if (root.key.length > 0) ShellSettings.setValue(root.key, nextChecked)
        }
    }

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

    function _activate(): void {
        if (!_canToggle) return
        // animate the knob only on a real user flip; section switches re-run layout and would otherwise slide every checked knob
        _toggle.armFlipAnimation()
        root.toggled(!root.checked)
    }

    // a description grows the row to fit its wrapping subtitle, still on the shared grid
    readonly property int _descPadV: 11
    height:         _hasDetail ? 4 * Math.ceil((_descPadV * 2 + _textCol.implicitHeight) / 4)
                               : Metrics.rowHeightFor(44)
    // a live dependsNote lengthens the detail text mid-interaction (toggling the update
    // timer appends "Working"), which can rewrap and change this height under the cursor
    MotionBehavior on height {
        NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
    }

    opacity: root.enabled && root.available ? 1.0 : (_canToggle ? 0.72 : 0.52)
    MotionBehavior on opacity {NumberAnimation { duration: Motion.medium } }

    HoverHandler { id: _hover; cursorShape: root._canToggle ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler {
        id: _tap
        enabled: root._canToggle
        onTapped: {
            root._activate()
        }
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
            pressed: _tap.pressed
        }
    }
}
