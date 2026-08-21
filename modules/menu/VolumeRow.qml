pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"
import "controls"

Item {
    id: root

    property bool open: false
    property real topRadius:    0
    property real bottomRadius: 0
    property real cardInset:    1
    property real cardLeftBleed: 0
    property bool reserveExpandSlot: false

    width: parent ? parent.width : 0
    implicitHeight: _slider.height + _options.height
    height: implicitHeight
    readonly property bool _optionsShown: root.open || _options.height > 0.5

    function closeInline(): bool {
        if (!root.open) return false
        root.open = false
        return true
    }

    Connections {
        target: Audio
        function onSinkCountChanged() {
            if (Audio.sinkCount <= 1) root.closeInline()
        }
    }

    QuickSlider {
        id: _slider
        y: 0
        width: parent.width
        topRadius:    root.topRadius
        bottomRadius: root._optionsShown ? 0 : root.bottomRadius
        cardInset:    root.cardInset
        cardLeftBleed: root.cardLeftBleed
        glyph: Audio.icon
        accessibleName: "Volume"
        wheelKey: "volume"
        value: Audio.uiVolume
        valueText: Audio.label
        glyphClickable: true
        expandable: Audio.sinkCount > 1
        expanded: root.open
        reserveExpandSlot: root.reserveExpandSlot
        onGlyphClicked: Audio.toggleMute()
        onExpandToggled: root.open = !root.open
        onMoved: (v) => Audio.setVolume(v)
    }

    CollapsibleSection {
        id: _options
        y: _slider.height
        width: parent.width
        expanded: root.open

        Column {
            id: _optCol
            width: parent.width
            bottomPadding: 2

            Hairline {
                x: 14
                width: parent.width - 28
                color: Theme.menuDivider
            }
            Item { width: parent.width; height: 1 }

            Repeater {
                id: _sinkRepeater
                model: root._optionsShown ? Audio.sinkModel : []
                delegate: InlineOptionRow {
                    id: _opt
                    required property var modelData
                    readonly property bool active: modelData.value === Audio.sink

                    width: _optCol.width
                    glyph: "󰓃"
                    label: modelData.label
                    status: active ? "Current" : ""
                    selected: active

                    function _choose(): void {
                        Audio.setSink(_opt.modelData.value)
                        root.open = false
                    }

                    onTriggered: _choose()
                }
            }
        }
    }
}
