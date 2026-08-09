pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property var    model: []
    property var    currentValue
    property color  accentColor: Theme.accent

    property real topRadius:    0
    property real bottomRadius: 0
    property real cardInset:    1
    property real cardLeftBleed: 0

    signal chosen(var value)

    readonly property int _optionCount: Math.max(1, root.model.length)
    readonly property int _controlH: 4 * Math.ceil(
        Math.max(28, Settings.capHeight + 12) / 4)
    readonly property int _inlineH: 4 * Math.ceil(Math.max(40,
        _labelRow.height + 12, root._controlH + 12) / 4)
    readonly property int _stackedH: 4 * Math.ceil(Math.max(56,
        6 + _labelRow.height + 4 + root._controlH + 6) / 4)
    readonly property real _preferredControlW: Math.min(208,
        Math.max(144, root._optionCount * 60))
    readonly property real _inlineLabelW:
        Math.max(0, root.width - 12 - root._preferredControlW - 14 - 10)
    readonly property bool _stacked: root.width > 0
        && _labelRow.neededW > root._inlineLabelW

    readonly property int _activeIndex: root.model.findIndex(o => o.value === root.currentValue)

    function _focusOption(index: int, choose: bool): void {
        const count = _optionRepeater.count
        if (count <= 0) return
        const wrapped = ((index % count) + count) % count
        const item = _optionRepeater.itemAt(wrapped)
        if (!item) return
        item.forceActiveFocus()
        if (choose && root.enabled && wrapped !== root._activeIndex)
            root.chosen(item.modelData.value)
    }

    width: parent ? parent.width : 0
    height: root._stacked ? root._stackedH : root._inlineH
    implicitHeight: height
    opacity: root.enabled ? 1.0 : 0.45

    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.medium }
    }

    activeFocusOnTab: root.enabled
    onActiveFocusChanged: {
        if (!activeFocus || _optionRepeater.count <= 0) return
        const item = _optionRepeater.itemAt(Math.max(0, root._activeIndex))
        if (item) item.forceActiveFocus()
    }

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
        id: _labelRow

        x: 14
        y: root._stacked ? 6 : Math.round((root.height - height) / 2)
        width: root._stacked
            ? Math.max(1, root.width - 28)
            : Math.max(1, _choiceGroup.x - x - 10)
        height: Math.max(_glyph.implicitHeight, _label.implicitHeight)
        readonly property real neededW: (root.glyph.length > 0 ? 28 : 0)
            + Math.ceil(_label.implicitWidth)

        ShellText {
            id: _glyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyph.length > 0
            width: visible ? 18 : 0
            horizontalAlignment: Text.AlignHCenter
            text: root.glyph
            color: Theme.withAlpha(Theme.subtext, 0.82)
            font.pixelSize: Settings.iconSize + 2
        }

        ShellText {
            id: _label
            anchors.left: _glyph.right
            anchors.leftMargin: root.glyph.length > 0 ? 10 : 0
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth,
                Math.max(18, parent.width - anchors.leftMargin - _glyph.width))
            text: root.label
            elide: Text.ElideRight
            color: Theme.withAlpha(Theme.text, 0.88)
            font.pixelSize: Settings.fontSize
        }
    }

    Item {
        id: _choiceGroup

        x: root.width - 12 - width
        y: root._stacked
            ? root.height - 6 - height
            : Math.round((root.height - height) / 2)
        width: Math.min(root._preferredControlW, Math.max(1, root.width - 28))
        height: root._controlH

        readonly property int contentW: Math.max(1,
            Math.floor(width))
        readonly property int cellW: Math.max(1,
            Math.floor(contentW / root._optionCount))
        readonly property int cellRemainder: Math.max(0,
            contentW - cellW * root._optionCount)

        Rectangle {
            id: _groupTrack
            anchors.fill: parent
            radius: Theme.radiusField
            antialiasing: true
            color: Theme.mix(Theme.menuCard, Theme.text, 0.028)

            OutlineBorder {
                radius: _groupTrack.radius
                outlineColor: Theme.menuControlLine
                ColorFade on outlineColor {}
            }
        }

        Row {
            anchors.fill: parent
            spacing: 0

            Repeater {
                id: _optionRepeater
                model: root.model

                delegate: Item {
                    id: _option

                    required property var modelData
                    required property int index

                    readonly property bool active: index === root._activeIndex
                    readonly property string optionLabel:
                        String(modelData.label ?? "")
                    readonly property string optionGlyph:
                        modelData.glyph === undefined || modelData.glyph === null
                            ? "" : String(modelData.glyph)

                    FocusVisual { id: _optionFocusVisual; target: _option }

                    width: _choiceGroup.cellW
                        + (index < _choiceGroup.cellRemainder ? 1 : 0)
                    height: _choiceGroup.height

                    Accessible.role: Accessible.RadioButton
                    Accessible.name: root.label + ": " + optionLabel
                    Accessible.checked: active
                    Accessible.onPressAction: {
                        if (root.enabled) root.chosen(modelData.value)
                    }
                    Keys.onPressed: _optionFocusVisual.noteKeyboardInput()

                    Keys.onSpacePressed: event => {
                        if (!event.isAutoRepeat && root.enabled)
                            root.chosen(modelData.value)
                        event.accepted = true
                    }
                    Keys.onReturnPressed: event => {
                        if (!event.isAutoRepeat && root.enabled)
                            root.chosen(modelData.value)
                        event.accepted = true
                    }
                    Keys.onEnterPressed: event => {
                        if (!event.isAutoRepeat && root.enabled)
                            root.chosen(modelData.value)
                        event.accepted = true
                    }
                    Keys.onLeftPressed: event => {
                        root._focusOption(index - 1, true)
                        event.accepted = true
                    }
                    Keys.onRightPressed: event => {
                        root._focusOption(index + 1, true)
                        event.accepted = true
                    }
                    Keys.onUpPressed: event => {
                        root._focusOption(index - 1, true)
                        event.accepted = true
                    }
                    Keys.onDownPressed: event => {
                        root._focusOption(index + 1, true)
                        event.accepted = true
                    }
                    HoverHandler {
                        id: _hover
                        enabled: root.enabled
                        cursorShape: root.enabled
                            ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                    TapHandler {
                        id: _tap
                        enabled: root.enabled
                        onTapped: {
                            _optionFocusVisual.takePointerFocus()
                            root.chosen(_option.modelData.value)
                        }
                    }

                    Rectangle {
                        id: _surface
                        anchors.fill: parent
                        topLeftRadius: _option.index === 0 ? Theme.radiusField : 0
                        bottomLeftRadius: topLeftRadius
                        topRightRadius: _option.index === root._optionCount - 1
                            ? Theme.radiusField : 0
                        bottomRightRadius: topRightRadius
                        antialiasing: true
                        color: _option.active
                            ? Theme.withAlpha(root.accentColor,
                                _tap.pressed ? 0.24
                                    : _hover.hovered ? 0.21
                                    : ShellSettings.neutralTheme ? 0.16 : 0.19)
                            : _tap.pressed
                                ? Theme.withAlpha(Theme.text, 0.09)
                                : _optionFocusVisual.active
                                    ? Theme.withAlpha(root.accentColor, 0.10)
                                : _hover.hovered
                                    ? Theme.withAlpha(Theme.text, 0.050)
                                    : "transparent"
                        ColorFade on color {}

                        OutlineBorder {
                            topLeftRadius: _surface.topLeftRadius
                            topRightRadius: _surface.topRightRadius
                            bottomLeftRadius: _surface.bottomLeftRadius
                            bottomRightRadius: _surface.bottomRightRadius
                            outlineWidth: _optionFocusVisual.active ? 2 : 1
                            outlineColor: _optionFocusVisual.active
                                ? Theme.withAlpha(root.accentColor, Theme.focusRingAlpha)
                                : _option.active
                                    ? Theme.withAlpha(root.accentColor, Theme.lineAlpha(0.15))
                                    : _hover.hovered
                                        ? Theme.withAlpha(Theme.text, Theme.lineAlpha(0.09))
                                        : "transparent"
                            ColorFade on outlineColor {}
                        }

                        Row {
                            id: _content
                            anchors.centerIn: parent
                            spacing: 4

                            ShellText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: _option.optionGlyph.length > 0
                                text: _option.optionGlyph
                                color: _option.active
                                    ? Theme.mix(Theme.text, root.accentColor, 0.24)
                                    : Theme.withAlpha(Theme.subtext,
                                        _hover.hovered ? 0.88 : 0.68)
                                font.pixelSize: Settings.fontLabel
                                font.weight: Font.Medium
                                ColorFade on color {}
                            }

                            ShellText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: _option.optionLabel.length > 0
                                width: Math.min(implicitWidth, Math.max(10,
                                    _option.width - 14
                                        - (_option.optionGlyph.length > 0 ? 18 : 0)))
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: _option.optionLabel
                                elide: Text.ElideRight
                                color: _option.active
                                    ? Theme.mix(Theme.text, root.accentColor,
                                        ShellSettings.highContrast ? 0 : 0.22)
                                    : Theme.withAlpha(Theme.subtext,
                                        _hover.hovered ? 0.90 : 0.72)
                                font.pixelSize: Settings.fontLabel
                                fontSizeMode: Text.HorizontalFit
                                minimumPixelSize: Settings.fontCaption
                                font.weight: _option.active
                                    ? Font.DemiBold : Font.Medium
                                ColorFade on color {}
                            }
                        }

                    }

                    Hairline {
                        vertical: true
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: Math.max(0, parent.height - 12)
                        color: Theme.menuDivider
                        opacity: _option.index < root._optionCount - 1
                            && !_option.active
                            && root._activeIndex !== _option.index + 1 ? 1 : 0
                        visible: opacity > 0.001
                        MotionBehavior on opacity {
                            NumberAnimation { duration: Motion.fast }
                        }
                    }
                }
            }
        }
    }
}
