pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"
import "controls"

Item {
    id: root

    property bool open: false
    // as InlinePicker's: the list folds on the curve of the one opening in its place
    property bool symmetricFold: false
    property real topRadius: 0
    property real bottomRadius: 0
    property real cardInset: 1
    property real cardLeftBleed: 0
    property bool reserveExpandSlot: false
    // external displays fold under the backlight's slider, one Home row for every display; one the selected kernel DDC
    // backlight already drives is that slider
    readonly property var _externalDisplays: DisplayBrightness.controllableDisplays
        .filter(d => Brightness.deviceName !== "ddcci" + d.bus).map(d => ({ key: d.key, label: d.label }))
    readonly property bool expandable: Brightness.devices.length > 1 || root._externalDisplays.length > 0
    onExpandableChanged: if (!root.expandable) root.closeInline()

    width: parent ? parent.width : 0
    implicitHeight: _slider.height + _options.height
    height: implicitHeight
    readonly property bool _optionsShown: root.open || _options.height > 0.5
    // with the bar below, the card grows upward: the choices open above so the slider stays under the pointer
    readonly property bool _optionsAbove: Metrics.barAtBottom
    ScrollHold {
        id: _hold
        item: _slider
        watched: root
    }
    onOpenChanged: if (root._optionsAbove) _hold.arm(root.open)

    function closeInline(): bool {
        if (!root.open) return false
        _slider.restorePickerFocus(_options)
        root.open = false
        return true
    }

    QuickSlider {
        id: _slider
        width: parent.width
        y: root._optionsAbove ? _options.height : 0
        topRadius:    root._optionsShown && root._optionsAbove ? 0 : root.topRadius
        bottomRadius: root._optionsShown && !root._optionsAbove ? 0 : root.bottomRadius
        cardInset: root.cardInset
        cardLeftBleed: root.cardLeftBleed
        glyph: Brightness.icon
        accessibleName: "Brightness"
        wheelKey: "brightness"
        interactionKey: Brightness.deviceName
        value: Brightness.pendingPercent / 100
        valueText: Brightness.pendingPercent + "%"
        adjustable: Brightness.controllable
        expandable: root.expandable
        expanded: root.open
        reserveExpandSlot: root.reserveExpandSlot
        onExpandToggled: root.open = !root.open
        onMoved: value => Brightness.setPercent(Math.round(value * 100))
    }

    CollapsibleSection {
        id: _options
        y: root._optionsAbove ? 0 : _slider.height
        width: parent.width
        expanded: root.open
        symmetric: root.symmetricFold

        Column {
            id: _optionColumn
            width: parent.width
            topPadding: root._optionsAbove ? 2 : 0
            bottomPadding: root._optionsAbove ? 0 : 2

            Hairline {
                visible: !root._optionsAbove
                x: 14
                width: parent.width - 28
                color: Theme.menuDivider
            }
            Item { visible: !root._optionsAbove; width: parent.width; height: 1 }

            Repeater {
                id: _deviceRepeater
                // a choice only among several: a lone backlight's fold holds the external displays alone
                model: root._optionsShown && Brightness.devices.length > 1 ? Brightness.deviceChoices : []

                delegate: InlineOptionRow {
                    id: _option
                    required property var modelData
                    readonly property bool active: modelData.value === Brightness.deviceChoice

                    width: _optionColumn.width
                    glyph: modelData.value === "" ? "󰘸" : "󰃟"
                    label: modelData.label
                    status: active ? "Current" : ""
                    selected: active
                    accessiblePrefix: "Brightness display"

                    onTriggered: {
                        ShellSettings.brightnessDevice = modelData.value
                        root.closeInline()
                    }
                }
            }

            Hairline {
                visible: _deviceRepeater.count > 0 && root._externalDisplays.length > 0
                x: 14
                width: parent.width - 28
                color: Theme.menuDivider
            }
            // named above the slider, as Volume's apps are: the value slot is measured for "100%"
            Repeater {
                model: root._optionsShown ? root._externalDisplays : []
                delegate: Column {
                    id: _display
                    required property var modelData
                    width: _optionColumn.width

                    ShellText {
                        x: 14
                        width: Math.max(1, parent.width - 28)
                        topPadding: 6
                        text: _display.modelData.label
                        elide: Text.ElideRight
                        color: Theme.withAlpha(Theme.text, 0.88)
                        font.pixelSize: Settings.fontLabel
                    }
                    QuickSlider {
                        id: _displaySlider
                        width: _display.width
                        glyph: "󰍹"
                        accessibleName: _display.modelData.label + " brightness"
                        wheelKey: "displaybrightness"
                        interactionKey: _display.modelData.key
                        value: DisplayBrightness.levelFor(_display.modelData.key) / 100
                        valueText: Math.round(_displaySlider.shownValue * 100) + "%"
                        // a DDC write takes most of a second: one when the drag ends
                        commitOnRelease: true
                        reserveExpandSlot: true
                        onMoved: value => DisplayBrightness.setPercent(_display.modelData.key, value * 100)
                    }
                }
            }

            Item { visible: root._optionsAbove; width: parent.width; height: 1 }
            Hairline {
                visible: root._optionsAbove
                x: 14
                width: parent.width - 28
                color: Theme.menuDivider
            }
        }
    }
}
