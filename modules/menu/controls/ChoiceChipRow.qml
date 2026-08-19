pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

MenuRow {
    id: root

    property string label: ""
    property var    model: []
    property var    currentValue
    property color  accentColor: Theme.accent

    rowHovered:     _rowHover.hovered
    rowInteractive: root.enabled

    signal chosen(var value)

    readonly property int _optionCount: Math.max(1, root.model.length)
    readonly property int _controlH: Metrics.rowHeightFor(28)
    // floor matches ToggleRow: every single-line settings row shares one height,
    // and the two-line rows (slider with a track, toggle with a description) share 56
    readonly property int _inlineH: 4 * Math.ceil(Math.max(44,
        _labelRow.height + 12, root._controlH + 12) / 4)
    readonly property int _stackedH: 4 * Math.ceil(Math.max(56,
        6 + _labelRow.height + 4 + root._controlH + 6) / 4)
    readonly property int _chipGap: 5
    // detached chips size to the widest option so every chip in a row matches,
    // instead of splitting a fixed track into equal cells
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
    readonly property real _preferredControlW: Math.min(236,
        root._chipW * root._optionCount + root._chipGap * (root._optionCount - 1))
    readonly property real _inlineLabelW:
        Math.max(0, root.width - 12 - root._preferredControlW - 14 - 10)
    readonly property bool _stacked: root.width > 0
        && _labelRow.neededW > root._inlineLabelW

    readonly property int _activeIndex: root.model.findIndex(o => o.value === root.currentValue)

    height: root._stacked ? root._stackedH : root._inlineH
    // the settings pane width animates when the nav rail expands, and crossing the
    // stacking threshold mid-glide would pop this row 20px while everything else eases
    MotionBehavior on height {
        NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
    }
    opacity: root.enabled ? 1.0 : 0.45

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
        height: root._controlH

        readonly property int _gapTotal: root._chipGap * (root._optionCount - 1)
        readonly property int contentW: Math.max(1,
            Math.floor(width) - _gapTotal)
        readonly property int cellW: Math.max(1,
            Math.floor(contentW / root._optionCount))
        readonly property int cellRemainder: Math.max(0,
            contentW - cellW * root._optionCount)

        Row {
            anchors.fill: parent
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
                        + (index < _choiceGroup.cellRemainder ? 1 : 0)
                    height: _choiceGroup.height

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
                        scale: _tap.pressed ? Motion.pressScale
                            : _hover.hovered ? Motion.hoverScale : 1.0
                        transformOrigin: Item.Center
                        // ghost: the selected chip carries only its accent outline, so the
                        // resting fill belongs to the unselected ones
                        color: _option.active
                            ? (_tap.pressed
                                ? Theme.withAlpha(root.accentColor, 0.13)
                                : _hover.hovered
                                    ? Theme.withAlpha(root.accentColor, 0.09)
                                    : Theme.withAlpha(root.accentColor, 0.055))
                            : _tap.pressed
                                ? Theme.withAlpha(Theme.text, 0.09)
                                : _hover.hovered
                                    ? Theme.withAlpha(Theme.text, 0.055)
                                    : Theme.withAlpha(Theme.text, 0.028)
                        ColorFade on color {}
                        MotionBehavior on scale {
                            NumberAnimation {
                                duration: _tap.pressed ? Motion.press
                                    : _hover.hovered ? Motion.hoverIn : Motion.hoverOut
                                easing.type: Easing.OutCubic
                            }
                        }

                        OutlineBorder {
                            radius: _surface.radius
                            outlineWidth: 1
                            outlineColor: _option.active
                                    ? Theme.controlLineActive(root.accentColor)
                                    : _hover.hovered
                                        ? Theme.withAlpha(root.accentColor,
                                            ShellSettings.highContrast ? 0.38 : 0.22)
                                        : Theme.menuControlLine
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
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: Settings.fontCaption
                            font.weight: _option.active
                                ? Font.DemiBold : Font.Medium
                            ColorFade on color {}
                        }
                    }

                }
            }
        }
    }
}
