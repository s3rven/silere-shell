pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    property string glyph:       ""
    property string label:       ""
    property string description: ""
    property var    model:       []
    property var    currentValue
    property color  accentColor: Theme.accent
    // one component serves the header and every option; each reads its subject off its own Loader
    property Component optionPreview: null
    property string fallbackLabel: currentValue === undefined || currentValue === null
        ? "" : String(currentValue)
    property real   topRadius:    0
    property real   bottomRadius: 0
    property real   cardInset:    1
    property real   cardLeftBleed: 0
    readonly property bool _hasDesc: description.length > 0
    readonly property bool _hasLead: glyph.length > 0 || optionPreview !== null
    readonly property int _controlH: Metrics.rowHeightFor(28)
    readonly property int _optionH: Metrics.rowHeightFor(32)
    readonly property int _optionsCapH: Math.min(224, root._optionH * 7)
    // 44/56 are the shared single-line and two-line row heights; a select row that
    // sits between toggles must not be the one that breaks the rhythm
    readonly property int _headerH: 4 * Math.ceil(Math.max(
        root._hasDesc ? 56 : 44,
        _headerText.implicitHeight + 12,
        _glyph.implicitHeight + 12,
        root._controlH + 12) / 4)

    // The value pill grows into whatever the label leaves free, keeping 96px for the
    // label itself. A flat 148 cap truncated long values (font and display names)
    // on a wide row while most of the middle sat empty.
    readonly property int _leadW: root._hasLead ? 14 + 18 + 10 : 14
    readonly property int _pillMaxW: Math.max(92, root.width - root._leadW - 10 - 12 - 96)

    signal chosen(var value)

    property bool _open: false

    // opening a dropdown has to show the current choice, which may sit below the cap
    function _revealOption(index: int): void {
        if (!_open || _optRepeater.count <= 0) return
        const i = Math.max(0, Math.min(_optRepeater.count - 1, index))
        const item = _optRepeater.itemAt(i)
        if (item) {
            const viewportH = Math.min(_optCol.implicitHeight, root._optionsCapH)
            if (item.y < _options.contentY + 4)
                _options.contentY = Math.max(0, item.y - 4)
            else if (item.y + item.height > _options.contentY + viewportH - 4)
                _options.contentY = Math.min(
                    Math.max(0, _options.contentHeight - viewportH),
                    item.y + item.height - viewportH + 4)
        }
    }

    function _revealActiveOption(): void {
        root._revealOption(Math.max(0, _activeIndex))
    }

    function _setOpen(next: bool): void {
        if (next && (!root.enabled || root._optionCount <= 0)) return
        if (_open === next) {
            if (_open) _revealDefer.restart()
            return
        }
        _revealDefer.stop()
        _open = next
        if (_open) _revealDefer.restart()
    }

    function _toggleOpen(): void {
        root._setOpen(!_open)
    }

    onEnabledChanged: if (!enabled) root._setOpen(false)

    Timer {
        id: _revealDefer
        interval: 0
        onTriggered: {
            root._revealActiveOption()
        }
    }

    readonly property int _optionCount: model && model.length !== undefined
        ? model.length : 0
    readonly property int _activeIndex: model && model.findIndex
        ? model.findIndex(o => o.value === currentValue) : -1
    readonly property string _activeLabel: _activeIndex >= 0
        ? model[_activeIndex].label : fallbackLabel
    readonly property string _activeFont: {
        if (_activeIndex < 0) return Settings.font
        const f = model[_activeIndex].fontFamily
        return (f !== undefined && f !== null && String(f).length > 0) ? String(f) : Settings.font
    }

    width:  parent ? parent.width : 0
    height: _headerH + _options.height
    implicitHeight: height
    opacity: enabled ? 1.0 : 0.45
    MotionBehavior on opacity {NumberAnimation { duration: Motion.medium } }

    Item {
        id: _headerHitArea
        width: parent.width
        height: root._headerH

        HoverHandler {
            id: _hov
            enabled: root.enabled
            cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
        TapHandler {
            id: _headerTap
            enabled: root.enabled
            onTapped: root._toggleOpen()
        }
    }

    RowHoverBg {
        width:  parent.width
        height: root._headerH
        topRadius:    root.topRadius
        bottomRadius: root._open ? 0 : root.bottomRadius
        cardInset:    root.cardInset
        leftBleed:    root.cardLeftBleed
        active:       (_hov.hovered) && root.enabled
    }

    ShellText {
        id: _glyph
        anchors.left:           parent.left; anchors.leftMargin: 14
        anchors.verticalCenter: _header.verticalCenter
        width: root._hasLead ? 18 : 0
        visible: root.optionPreview === null
        horizontalAlignment: Text.AlignHCenter
        text:           root.glyph
        color:          Theme.withAlpha(Theme.subtext, 0.85)
        font.pixelSize: Settings.iconSize + 2
    }

    Loader {
        anchors.left: _glyph.left
        anchors.verticalCenter: _glyph.verticalCenter
        width: _glyph.width
        height: root._controlH
        active: root.optionPreview !== null
        sourceComponent: root.optionPreview
        readonly property var optionValue: root.currentValue
    }
    Item {
        id: _header
        anchors.top:    parent.top
        anchors.left:   _glyph.right; anchors.leftMargin: root._hasLead ? 10 : 0
        anchors.right:  _chevronSlot.left; anchors.rightMargin: 10
        height: root._headerH
        Column {
            id: _headerText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            ShellText {
                id: _label
                width: parent.width
                text: root.label
                elide: Text.ElideRight
                color: Theme.withAlpha(Theme.text, 0.85)
                font.pixelSize: Settings.fontSize
            }
            ShellText {
                visible: root._hasDesc
                width: parent.width
                text: root.description
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Theme.withAlpha(Theme.subtext, 0.52)
                font.pixelSize: Settings.fontCaption
                lineHeight: 1.1
            }
        }
    }
    Item {
        id: _chevronSlot
        anchors.right:          parent.right; anchors.rightMargin: 12
        anchors.verticalCenter: _header.verticalCenter
        width: Math.min(Math.max(92, _valText.implicitWidth + 34), root._pillMaxW)
        height: root._controlH

        Rectangle {
            id: _chevronFill
            anchors.fill: parent
            radius: Theme.radiusField
            antialiasing: true
            color: root._open
                ? Theme.withAlpha(root.accentColor, 0.055)
                : _headerTap.pressed
                    ? Theme.withAlpha(Theme.text, 0.065)
                    : _hov.hovered
                        ? Theme.withAlpha(Theme.text, 0.030)
                        : "transparent"
            ColorFade on color {}

            OutlineBorder {
                radius: _chevronFill.radius
                outlineWidth: 1
                outlineColor: root._open
                        ? Theme.controlLineActive(root.accentColor)
                        : _hov.hovered
                            ? Theme.menuControlLineHot
                            : Theme.menuControlLine
                ColorFade on outlineColor {}
            }
        }

        ShellText {
            id: _valText
            anchors.left:           parent.left
            anchors.leftMargin:     9
            anchors.right:          parent.right
            anchors.rightMargin:    21
            anchors.verticalCenter: parent.verticalCenter
            text:           root._activeLabel
            elide:          Text.ElideRight
            color: root._open ? Theme.mix(Theme.text, root.accentColor,
                    ShellSettings.highContrast ? 0 : 0.10)
                : Theme.withAlpha(Theme.text, _hov.hovered ? 0.90 : 0.78)
            font.family:    root._activeFont
            font.pixelSize: Settings.fontLabel
            font.weight:    root._open ? Font.DemiBold : Font.Medium
            ColorFade on color {}
        }
        ShellText {
            anchors.right:          parent.right
            anchors.rightMargin:    7
            anchors.verticalCenter: parent.verticalCenter
            text:    "󰅀"
            rotation: root._open ? 180 : 0
            transformOrigin: Item.Center
            color: root._open ? root.accentColor
                : Theme.withAlpha(Theme.subtext, _hov.hovered ? 0.86 : 0.66)
            font.pixelSize: Settings.fontSize
            MotionBehavior on rotation {NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
            ColorFade on color {}
        }
    }

    ShellFlickable {
        id: _options
        anchors.top:  parent.top; anchors.topMargin: root._headerH
        anchors.left: parent.left
        anchors.right: parent.right

        height: root._open
            ? Math.min(_optCol.implicitHeight, root._optionsCapH)
            : 0
        contentWidth: width
        contentHeight: _optCol.implicitHeight
        interactive: contentHeight > height + 1
        visible: height > 0.5

        Disclosure on height { expanded: root._open }

        Column {
            id: _optCol
            width: parent.width
            y: 0
            opacity: root._open ? 1.0 : 0.0
            bottomPadding: 2

            Hairline {
                x: 14
                width: parent.width - 28
                color: Theme.menuDivider
            }
            Item { width: parent.width; height: 1 }

            MotionBehavior on opacity {
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: root._open ? Easing.OutCubic : Easing.InCubic
                }
            }

            Repeater {
                id: _optRepeater
                model: root._open || _options.height > 0.5 ? root.model : []
                delegate: InlineOptionRow {
                    id: _opt
                    required property var modelData
                    required property int index
                    readonly property bool active: root.currentValue === modelData.value
                    readonly property string optionFont:
                        (modelData.fontFamily !== undefined && modelData.fontFamily !== null
                            && String(modelData.fontFamily).length > 0)
                        ? String(modelData.fontFamily) : Settings.font

                    width: _optCol.width
                    label: String(modelData.label ?? "")
                    labelFontFamily: optionFont
                    preview: root.optionPreview
                    previewValue: modelData.value
                    selected: active
                    ghost: true
                    accentColor: root.accentColor

                    onTriggered: {
                        root.chosen(_opt.modelData.value)
                        root._setOpen(false)
                    }
                }
            }
        }
    }

    MenuScrollThumb {
        list: _options
        shown: root._open
        trackInset: 4
        rightInset: 3
        minimumLength: 18
        color: Theme.subtext
        idleOpacity: 0.34
        movingOpacity: 0.56
    }
}
