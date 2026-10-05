pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../config"
import "../../../services"
import "../../common"

MenuRow {
    id: root

    property string label: ""
    property string key: ""
    property var    model: []
    property var    currentValue: root.key.length > 0 ? ShellSettings[root.key] : undefined
    property color  accentColor: Theme.accent

    rowHovered:     _rowHover.hovered
    rowInteractive: root.enabled

    signal chosen(var value)

    Connections {
        target: root
        function onChosen(value) {
            if (root.key.length > 0) ShellSettings.setValue(root.key, value)
        }
    }

    readonly property int _optionCount: Math.max(1, root.model.length)
    readonly property int _controlH: Metrics.rowHeightFor(28)
    // floor matches ToggleRow: every single-line settings row shares one height,
    // and the two-line rows (slider with a track, toggle with a description) share 56
    readonly property int _inlineH: 4 * Math.ceil(Math.max(44,
        _labelRow.height + 12, _choiceGroup.height + 12) / 4)
    readonly property int _stackedH: 4 * Math.ceil(Math.max(56,
        6 + _labelRow.height + 4 + _choiceGroup.height + 6) / 4)
    readonly property int _chipGap: 5
    // detached chips size to the widest option so every chip in a row matches, instead of splitting a fixed track into equal cells
    FontMetrics {
        id: _chipFm
        font.family: Settings.font
        font.pixelSize: Settings.fontLabel
        font.weight: Font.DemiBold
    }
    readonly property real _widestOptionW: {
        // advanceWidth() is a call, so it registers no dependency; reading the font does
        void _chipFm.font.pixelSize
        let w = 0
        for (let i = 0; i < root.model.length; i++) {
            const o = root.model[i]
            let cw = _chipFm.advanceWidth(String(o.label ?? ""))
            if (o.glyph !== undefined && o.glyph !== null
                    && String(o.glyph).length > 0) cw += 18
            w = Math.max(w, cw)
        }
        return w
    }
    readonly property int _chipW: Math.max(44, Math.ceil(root._widestOptionW) + 22)
    // with nothing in the label column the row is a standalone control, not a setting:
    // holding it to the right cap leaves the gutter it would have used as dead space
    readonly property bool _headless: root.label.length === 0 && root.glyph.length === 0
    readonly property real _preferredControlW: root._headless
        ? Math.max(1, root.width - 28)
        : root._chipW * root._optionCount + root._chipGap * (root._optionCount - 1)
    readonly property real _inlineLabelW:
        Math.max(0, root.width - 12 - root._preferredControlW - 14 - 10)
    readonly property bool _stacked: root.width > 0
        && _labelRow.neededW > root._inlineLabelW

    readonly property int _activeIndex: root.model.findIndex(o => o.value === root.currentValue)
    // separate row and column coordinates keep the selection inside a wrapped group
    readonly property real _selectionColumn: _columnGlide.value
    readonly property real _selectionRow: _rowGlide.value
    SpringGlide { id: _columnGlide; target: Math.max(0, root._activeIndex) % _choiceGroup.columns }
    SpringGlide { id: _rowGlide; target: Math.floor(Math.max(0, root._activeIndex) / _choiceGroup.columns) }

    height: root._stacked ? root._stackedH : root._inlineH
    // the settings pane width animates when the nav rail expands, and crossing the
    // stacking threshold mid-glide would pop this row 20px while everything else eases
    MotionBehavior on height {
        NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
    }
    opacity: root.enabled ? 1.0 : Theme.disabledOpacity

    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.medium }
    }

    HoverHandler { id: _rowHover; enabled: root.enabled }

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
        height: rows * root._controlH + (rows - 1) * root._chipGap

        readonly property int columns: {
            const fit = Math.max(1, Math.min(root._optionCount,
                Math.floor((width + root._chipGap) / (root._chipW + root._chipGap))))
            return Math.ceil(root._optionCount / Math.ceil(root._optionCount / fit))
        }
        readonly property int rows: Math.ceil(root._optionCount / columns)

        readonly property int _gapTotal: root._chipGap * (columns - 1)
        readonly property int contentW: Math.max(1,
            Math.floor(width) - _gapTotal)
        readonly property int cellW: Math.max(1,
            Math.floor(contentW / columns))
        readonly property int cellRemainder: Math.max(0,
            contentW - cellW * columns)

        Grid {
            anchors.fill: parent
            columns: _choiceGroup.columns
            spacing: root._chipGap

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
                        + (index % _choiceGroup.columns < _choiceGroup.cellRemainder ? 1 : 0)
                    height: root._controlH

                    Accessible.role: Accessible.RadioButton
                    Accessible.name: root.label.length > 0
                        ? root.label + ": " + _option.optionLabel
                        : _option.optionLabel
                    Accessible.focusable: root.enabled
                    Accessible.checkable: true
                    Accessible.checked: _option.active
                    Accessible.onPressAction: if (root.enabled)
                        root.chosen(_option.modelData.value)
                    Accessible.onToggleAction: if (root.enabled && !_option.active)
                        root.chosen(_option.modelData.value)

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
                            root.chosen(_option.modelData.value)
                        }
                    }

                    Rectangle {
                        id: _surface
                        anchors.fill: parent
                        radius: Theme.radiusField
                        antialiasing: true
                        readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                        transform: PixelScale {
                            item: _surface
                            dpr: _surface._dpr
                            factor: _tap.pressed ? Motion.pressScale
                                : _hover.hovered ? Motion.hoverScale : 1.0
                        }
                        // the gliding selection carries the selected look, so this only adds hover and press
                        color: _option.active
                            ? (_tap.pressed
                                ? Theme.withAlpha(root.accentColor, 0.075)
                                : _hover.hovered
                                    ? Theme.withAlpha(root.accentColor, 0.035)
                                    : "transparent")
                            : Theme.buttonFill(root.accentColor,
                                _hover.hovered, _tap.pressed)
                        ColorFade on color {}

                        OutlineBorder {
                            radius: _surface.radius
                            outlineWidth: 1
                            outlineColor: _option.active
                                    ? "transparent"
                                    : Theme.buttonLine(root.accentColor,
                                        _hover.hovered, _tap.pressed)
                            ColorFade on outlineColor {}
                        }
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
                            font.weight: _option.active
                                ? Font.DemiBold : Font.Medium
                            ColorFade on color {}
                        }
                    }

                }
            }
        }

        Rectangle {
            id: _selection
            readonly property int _column: Math.round(root._selectionColumn)
            x: root._selectionColumn * (_choiceGroup.cellW + root._chipGap)
                + Math.min(root._selectionColumn, _choiceGroup.cellRemainder)
            y: root._selectionRow * (root._controlH + root._chipGap)
            width: _choiceGroup.cellW + (_column < _choiceGroup.cellRemainder ? 1 : 0)
            height: root._controlH
            radius: Theme.radiusField
            antialiasing: true
            visible: root._activeIndex >= 0
            color: Theme.withAlpha(root.accentColor, 0.055)

            OutlineBorder {
                radius: _selection.radius
                outlineWidth: 1
                outlineColor: Theme.controlLineActive(root.accentColor)
                ColorFade on outlineColor {}
            }
        }
    }
}
