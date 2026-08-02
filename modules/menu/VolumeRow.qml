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

    function _focusCurrentSink(): void {
        if (!root.open) return
        for (let i = 0; i < _sinkRepeater.count; i++) {
            const item = _sinkRepeater.itemAt(i)
            if (item && item.active) {
                item.forceActiveFocus()
                return
            }
        }
        const first = _sinkRepeater.itemAt(0)
        if (first) first.forceActiveFocus()
    }

    function _focusSinkIndex(index: int): void {
        if (!root.open || _sinkRepeater.count <= 0) return
        const i = Math.max(0, Math.min(_sinkRepeater.count - 1, index))
        const item = _sinkRepeater.itemAt(i)
        if (item) item.forceActiveFocus()
    }

    Connections {
        target: Audio
        function onSinkCountChanged() { if (Audio.sinkCount <= 1) root.open = false }
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
        wheelKey: "volume"
        accessibleName: "Volume"
        value: Audio.uiVolume
        valueText: Audio.label
        glyphClickable: true
        glyphActionName: Audio.muted ? "Unmute" : "Mute"
        expandable: Audio.sinkCount > 1
        expanded: root.open
        reserveExpandSlot: root.reserveExpandSlot
        onGlyphClicked: Audio.toggleMute()
        onExpandToggled: {
            root.open = !root.open
            if (root.open) Qt.callLater(root._focusCurrentSink)
        }
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
                    required property int index
                    readonly property bool active: modelData.value === Audio.sink

                    width: _optCol.width
                    glyph: "󰓃"
                    label: modelData.label
                    status: active ? "Current" : ""
                    selected: active
                    accessibleDescription: active ? "Current output" : "Output device"

                    function _choose(): void {
                        Audio.setSink(_opt.modelData.value)
                        root.open = false
                        _slider.forceActiveFocus()
                    }

                    activeFocusOnTab: root.open
                    onTriggered: _choose()
                    Keys.onEscapePressed: event => { root.open = false; _slider.forceActiveFocus(); event.accepted = true }
                    Keys.onUpPressed:     event => { root._focusSinkIndex(_opt.index - 1); event.accepted = true }
                    Keys.onDownPressed:   event => { root._focusSinkIndex(_opt.index + 1); event.accepted = true }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Home) {
                            root._focusSinkIndex(0)
                            event.accepted = true
                        } else if (event.key === Qt.Key_End) {
                            root._focusSinkIndex(_sinkRepeater.count - 1)
                            event.accepted = true
                        }
                    }
                }
            }
        }
    }
}
