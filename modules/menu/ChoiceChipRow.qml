pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import "../../config"
import "../../services"
import "../common"

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property var    model: []
    property var    currentValue
    property color  accentColor: Theme.accent
    property real   topRadius:    0
    property real   bottomRadius: 0
    property real   cardInset:    1
    property real   cardLeftBleed: 0

    signal chosen(var value)

    readonly property int _optionCount: Math.max(1, root.model.length)
    readonly property real _preferredControlW: Math.min(204,
        Math.max(146, root._optionCount * 54 + (root._optionCount - 1) * 2))
    readonly property real _inlineLabelW:
        Math.max(0, root.width - 12 - root._preferredControlW - 14 - 10)
    readonly property bool _stacked: root.width > 0
        && _labelRow.neededW > root._inlineLabelW

    readonly property int _activeIndex: {
        for (let i = 0; i < root.model.length; i++) {
            if (root.model[i].value === root.currentValue) return i
        }
        return -1
    }

    // no clamping: an arrow key past the edge must not rewrite an off-model value
    function _focusOption(index: int, choose: bool): void {
        if (index < 0 || index >= _optionRepeater.count) return
        const item = _optionRepeater.itemAt(index)
        if (!item) return
        item.forceActiveFocus()
        if (choose && root.enabled && index !== root._activeIndex)
            root.chosen(item.modelData.value)
    }

    width: parent ? parent.width : 0
    height: root._stacked ? 72 : 44
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

    Item {
        id: _labelRow

        x: 14
        y: root._stacked ? 9 : Math.round((root.height - height) / 2)
        width: root._stacked
            ? Math.max(1, root.width - 28)
            : Math.max(1, _choiceGroup.x - x - 10)
        height: Math.max(_glyph.implicitHeight, _label.implicitHeight)
        readonly property real neededW: (root.glyph.length > 0 ? 28 : 0)
            + Math.ceil(_label.implicitWidth)

        Text {
            id: _glyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyph.length > 0
            width: visible ? 18 : 0
            horizontalAlignment: Text.AlignHCenter
            text: root.glyph
            color: Theme.withAlpha(Theme.subtext, 0.82)
            font.family: Settings.font
            font.pixelSize: Settings.iconSize + 2
            renderType: Text.NativeRendering
        }

        Text {
            id: _label
            anchors.left: _glyph.right
            anchors.leftMargin: root.glyph.length > 0 ? 10 : 0
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth,
                Math.max(18, parent.width - anchors.leftMargin - _glyph.width))
            text: root.label
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.withAlpha(Theme.text, 0.88)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize
            renderType: Text.NativeRendering
        }
    }

    Item {
        id: _choiceGroup

        x: root.width - 12 - width
        y: root._stacked
            ? root.height - 9 - height
            : Math.round((root.height - height) / 2)
        width: Math.min(root._preferredControlW, Math.max(1, root.width - 28))
        height: 26

        readonly property real physicalPx: 1 / Math.max(1, Screen.devicePixelRatio)
        readonly property int contentW: Math.max(1,
            Math.floor(width - 2))
        readonly property int cellW: Math.max(1,
            Math.floor(contentW / root._optionCount))
        readonly property int cellRemainder: Math.max(0,
            contentW - cellW * root._optionCount)

        Rectangle {
            anchors.fill: parent
            radius: 7
            antialiasing: true
            color: Theme.mix(Theme.menuControl, Theme.text, 0.012)

            OutlineBorder {
                radius: parent.radius
                outlineColor: Theme.menuControlLine
            }
        }

        Row {
            x: 1
            y: 1
            width: Math.max(1, parent.width - 2)
            height: Math.max(1, parent.height - 2)
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

                    width: _choiceGroup.cellW
                        + (index < _choiceGroup.cellRemainder ? 1 : 0)
                    height: Math.max(1, _choiceGroup.height - 2)

                    Accessible.role: Accessible.RadioButton
                    Accessible.name: root.label + ": " + optionLabel
                    Accessible.checked: active
                    Accessible.onPressAction: {
                        if (root.enabled) root.chosen(modelData.value)
                    }

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
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Home) {
                            root._focusOption(0, true)
                            event.accepted = true
                        } else if (event.key === Qt.Key_End) {
                            root._focusOption(_optionRepeater.count - 1, true)
                            event.accepted = true
                        }
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
                        onTapped: root.chosen(_option.modelData.value)
                    }

                    Rectangle {
                        id: _surface
                        anchors.fill: parent
                        radius: 6
                        antialiasing: true
                        color: _option.active
                            ? Theme.mix(Theme.menuControl, root.accentColor,
                                ShellSettings.neutralTheme ? 0.16 : 0.22)
                            : _tap.pressed
                                ? Theme.withAlpha(Theme.text, 0.070)
                                : _hover.hovered
                                    ? Theme.withAlpha(Theme.text, 0.042)
                                    : "transparent"
                        MotionBehavior on color {
                            ColorAnimation { duration: Motion.fast }
                        }

                        OutlineBorder {
                            radius: _surface.radius
                            outlineWidth: _option.activeFocus ? 2 : 1
                            outlineColor: _option.activeFocus
                                ? Theme.withAlpha(root.accentColor, 0.62)
                                : "transparent"
                        }

                        Row {
                            id: _content
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: _option.optionGlyph.length > 0
                                text: _option.optionGlyph
                                color: _option.active
                                    ? Theme.mix(Theme.text, root.accentColor, 0.12)
                                    : Theme.withAlpha(Theme.subtext,
                                        _hover.hovered ? 0.88 : 0.68)
                                font.family: Settings.font
                                font.pixelSize: Math.max(9, Settings.fontSize - 1)
                                font.weight: Font.Medium
                                renderType: Text.NativeRendering
                                MotionBehavior on color {
                                    ColorAnimation { duration: Motion.fast }
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: _option.optionLabel.length > 0
                                width: Math.min(implicitWidth, Math.max(10,
                                    _option.width - 14
                                        - (_option.optionGlyph.length > 0 ? 18 : 0)))
                                height: 18
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: _option.optionLabel
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: _option.active
                                    ? Theme.mix(Theme.text, root.accentColor,
                                        ShellSettings.highContrast ? 0 : 0.10)
                                    : Theme.withAlpha(Theme.subtext,
                                        _hover.hovered ? 0.90 : 0.72)
                                font.family: Settings.font
                                font.pixelSize: Math.max(9, Settings.fontSize - 1)
                                fontSizeMode: Text.HorizontalFit
                                minimumPixelSize: Math.max(8, Settings.fontSize - 3)
                                font.weight: _option.active
                                    ? Font.DemiBold : Font.Medium
                                renderType: Text.NativeRendering
                                MotionBehavior on color {
                                    ColorAnimation { duration: Motion.fast }
                                }
                            }
                        }

                    }

                    Rectangle {
                        visible: _option.index > 0
                            && !_option.active
                            && _option.index - 1 !== root._activeIndex
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: _choiceGroup.physicalPx
                        height: 14
                        color: Theme.menuControlLine
                    }
                }
            }
        }
    }
}
