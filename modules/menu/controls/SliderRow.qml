import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

MenuRow {
    id: root

    property string label:        ""
    property string displayValue: {
        const range = max - min
        if (range <= 0) return "0%"
        const ratio = Math.max(0, Math.min(1, (value - min) / range))
        return Math.round(ratio * 100) + "%"
    }
    property string key:          ""
    readonly property var _schema: root.key.length > 0 ? ShellSettings.schemaFor(root.key) : null
    property real   value:        root.key.length > 0 ? Number(ShellSettings[root.key]) : 0.5
    property real   min:          root._schema ? Number(root._schema.min) : 0.0
    property real   max:          root._schema ? Number(root._schema.max) : 1.0
    property real   step:         root._schema && root._schema.t === "int" ? 1 : 0.05
    property color  glyphColor:   Theme.withAlpha(Theme.subtext, 0.85)

    FocusVisual { id: _focusVisual; target: root }

    rowHovered:     _rowHover.hovered
    rowFocused:     _focusVisual.active
    rowInteractive: root.enabled

    signal changed(real value)

    Connections {
        target: root
        function onChanged(value) {
            if (root.key.length > 0) ShellSettings.setValue(root.key, value)
        }
    }

    // 4px multiple so row.y inside SettingsCard lands on whole physical px and every divider renders one thickness
    height:         Metrics.rowHeightFor(56)
    opacity: root.enabled ? 1.0 : 0.45
    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.medium }
    }

    activeFocusOnTab: root.enabled || root.activeFocus
    Accessible.role: Accessible.Slider
    Accessible.name: root.label
    Accessible.description: root.displayValue
    Accessible.focusable: root.enabled
    Accessible.onIncreaseAction: if (root.enabled) _track.nudge(1, 1)
    Accessible.onDecreaseAction: if (root.enabled) _track.nudge(-1, 1)
    Keys.onPressed: event => {
        _focusVisual.noteKeyboardInput()
        _track.handleKey(event)
    }

    HoverHandler { id: _rowHover; enabled: root.enabled }

    Item {
        id: _head
        anchors.left:       parent.left
        anchors.leftMargin: 14
        anchors.right:      _valueText.left
        anchors.rightMargin: 10
        anchors.top:        parent.top
        anchors.topMargin:  8
        height: 20
        clip: true

        ShellText {
            id: _glyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyph.length > 0
            width: visible ? 18 : 0
            horizontalAlignment: Text.AlignHCenter
            text:           root.glyph
            color:          root.glyphColor
            font.pixelSize: Settings.iconSize + 2
        }
        ShellText {
            id: _label
            anchors.left:           _glyph.right
            anchors.leftMargin:     root.glyph.length > 0 ? 10 : 0
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            text:           root.label
            elide:          Text.ElideRight
            color:          Theme.withAlpha(Theme.text, 0.85)
            font.pixelSize: Settings.fontSize
        }
    }

    TextMetrics {
        id: _vm
        font.family: Settings.font
        font.pixelSize: Settings.fontLabel
        font.weight: Font.DemiBold
        text: "100%"
    }
    ShellText {
        id: _valueText
        anchors.right:          parent.right
        anchors.rightMargin:    12
        anchors.verticalCenter: _head.verticalCenter
        width: Math.max(Math.ceil(_vm.advanceWidth), Math.ceil(implicitWidth))
        horizontalAlignment: Text.AlignRight
        text:           root.displayValue
        color:          Theme.withAlpha(Theme.text, 0.58)
        font.pixelSize: Settings.fontLabel
        font.weight:    Font.DemiBold
    }

    SliderTrack {
        id: _track
        anchors.left:         parent.left
        anchors.right:        parent.right
        anchors.leftMargin:   14
        anchors.rightMargin:  12
        anchors.bottom:       parent.bottom
        anchors.bottomMargin: 4
        height: 20
        hitPad: 8

        interactive: root.enabled
        focused:     _focusVisual.active
        value: root.value
        min:   root.min
        max:   root.max
        step:  root.step
        wheelKey: "slider:" + root.label
        onInteractionStarted: _focusVisual.takePointerFocus()
        onChanged: value => root.changed(value)
    }
}
