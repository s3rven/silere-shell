pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property var    model: []
    property var    currentValue
    property color  accentColor: Theme.accent
    // value → color overrides for swatches that track live state; keeps the model array static so delegates don't rebuild per change
    property var    liveSwatches: ({})
    // Card-edge rounding for the hover fill — set on the first/last row of a card
    // so the fill rounds only where the card itself does (see RowHoverBg).
    property real   topRadius:    0
    property real   bottomRadius: 0
    property real   cardInset:    1
    // auto-stack when the inline form won't fit; positioned via x/y not flipped anchors so the switch is glitch-free.
    // gauged off the *natural* inline width, not live width — segment widths depend on _stacked, so live width would close a binding loop
    readonly property bool _stacked: width > 0 && _segContainer._maxNatW > 0
        && _labelRow.implicitWidth + _segContainer._naturalW + 40 > width

    signal chosen(var value)

    // 4px multiples: keep card dividers on whole physical px under fractional scaling
    width:  parent ? parent.width : 0
    height: _stacked ? 80 : 44
    opacity: enabled ? 1.0 : 0.45
    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium } }

    readonly property int _activeIndex: {
        for (let i = 0; i < model.length; i++) {
            if (model[i].value === currentValue) return i
        }
        return -1
    }

    // one tab stop for the row: entering lands on the active chip, ←/→ move, Space/Enter pick (Item not FocusScope, so it only fires when the row gets Tab focus)
    activeFocusOnTab: enabled
    onActiveFocusChanged: {
        if (activeFocus && _segRepeater.count > 0) {
            const it = _segRepeater.itemAt(Math.max(0, _activeIndex))
            if (it) it.forceActiveFocus()
        }
    }

    HoverHandler { id: _rowHover; enabled: root.enabled }
    RowHoverBg {
        anchors.fill: parent
        topRadius:    root.topRadius
        bottomRadius: root.bottomRadius
        cardInset:    root.cardInset
        active:       (_rowHover.hovered || root.activeFocus) && root.enabled
        fillOpacity:  0.08
    }

    Item {
        id: _labelRow
        x: 14
        y: root._stacked ? 10 : (root.height - height) / 2
        width: root._stacked ? root.width - 26 : Math.max(0, _segContainer.x - x - 10)
        implicitWidth: (root.glyph.length > 0 ? 28 : 0) + _label.implicitWidth
        implicitHeight: Math.max(_glyph.implicitHeight, _label.implicitHeight)
        height: Math.max(_glyph.implicitHeight, _label.implicitHeight)
        clip: true

        Text {
            id: _glyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyph.length > 0
            width: visible ? 18 : 0
            horizontalAlignment: Text.AlignHCenter
            text:           root.glyph
            color:          Theme.withAlpha(Theme.subtext, 0.85)
            font.family:    Settings.font
            font.pixelSize: Settings.iconSize + 2
            renderType:     Text.NativeRendering
        }
        Text {
            id: _label
            anchors.left:           _glyph.right
            anchors.leftMargin:     root.glyph.length > 0 ? 10 : 0
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            text:           root.label
            textFormat:     Text.PlainText
            elide:          Text.ElideRight
            color:          Theme.withAlpha(Theme.text, 0.85)
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize
            renderType:     Text.NativeRendering
        }
    }

    Rectangle {
        id: _segContainer
        // right-hugged in both modes — stacking moves the control down a line, it never inflates it
        x: root.width - 12 - width
        y: root._stacked ? (_labelRow.y + _labelRow.height + 11) : (root.height - height) / 2
        height:       32
        width:        Math.min(Math.max(1, root.width - 26), _segRow.implicitWidth + 8)
        radius:       Theme.radiusControl
        antialiasing: true
        color:        Theme.mix(Theme.menuControl, Theme.text,
            root.activeFocus ? 0.055 : (_rowHover.hovered ? 0.035 : 0.012))
        border.width: 1
        border.color: root.activeFocus ? Theme.withAlpha(root.accentColor, 0.42)
                    : _rowHover.hovered ? Theme.menuControlLineHot : Theme.menuControlLine

        Behavior on color { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.fast } }

        // bumped when delegates are (re)created: itemAt() returns null while the Repeater populates;
        // without this the binding caches that null and the indicator stays hidden until the first click re-evals
        property int _rev: 0
        readonly property Item _activeSeg: {
            _segContainer._rev
            if (root._activeIndex < 0 || _segRepeater.count <= root._activeIndex) return null
            return _segRepeater.itemAt(root._activeIndex)
        }

        property bool _animReady: false
        Component.onCompleted: Qt.callLater(function() {
            _segContainer._animReady = true
            _segContainer._recalcNat()
        })

        // equal-width segments: each takes the widest segment's natural width so the control reads as one tidy switch, not ragged chips.
        // recomputed imperatively (not a binding over itemAt()) so a late-settling segment can't strand a stale max
        property real _maxNatW: 0
        function _recalcNat() {
            let m = 0
            for (let i = 0; i < _segRepeater.count; i++) {
                const it = _segRepeater.itemAt(i)
                if (it) m = Math.max(m, it.natW)
            }
            _maxNatW = m
        }
        // Natural inline width of the whole control (drives the stack decision).
        readonly property real _naturalW: _maxNatW * root.model.length + 8
        // space-starved cap only: stacked cells stay natural-width unless even that overflows the row
        readonly property real _fullCellW: Math.max(1, Math.floor((root.width - 34) / Math.max(1, root.model.length)))
        readonly property real _cellW: root._stacked ? Math.min(_fullCellW, _maxNatW) : _maxNatW

        Rectangle {
            id: _indicator
            x:      _segContainer._activeSeg ? _segContainer._activeSeg.x + _segRow.x + 1 : 3
            y:      3
            width:  _segContainer._activeSeg ? _segContainer._activeSeg.width : 0
            height: parent.height - 6
            // concentric with the track: outer radius minus the 3px inset
            radius:       Theme.radiusControl - 3
            antialiasing: true
            opacity:      _segContainer._activeSeg ? 1.0 : 0.0
            visible:      opacity > 0.001

            color:        Theme.mix(Theme.menuControl, root.accentColor, ShellSettings.neutralTheme ? 0.26 : 0.38)
            border.width: 1
            border.color: ShellSettings.neutralTheme
                ? Theme.withAlpha(root.accentColor, 0.56)
                : Theme.mix(Theme.menuCard, root.accentColor, 0.66)

            Behavior on x        { enabled: _segContainer._animReady && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.width; easing.type: Easing.OutQuart } }
            Behavior on width    { enabled: _segContainer._animReady && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.width; easing.type: Easing.OutQuart } }
            Behavior on opacity  { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast } }
            Behavior on color        { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.fast } }
            Behavior on border.color { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.fast } }
        }

        Row {
            id: _segRow
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Repeater {
                id: _segRepeater
                model: root.model
                onItemAdded:   { _segContainer._rev++; _segContainer._recalcNat() }
                onItemRemoved: { _segContainer._rev++; _segContainer._recalcNat() }

                delegate: Item {
                    id: _seg
                    required property var modelData
                    required property int index

                    readonly property bool   active:   index === root._activeIndex
                    readonly property string segGlyph: (modelData.glyph !== undefined && modelData.glyph !== null)
                        ? String(modelData.glyph) : ""
                    readonly property string segBadge: (modelData.badge !== undefined && modelData.badge !== null)
                        ? String(modelData.badge) : ""
                    readonly property bool segHasSwatch: root.liveSwatches[modelData.value] !== undefined
                        || (modelData.color !== undefined && modelData.color !== null && String(modelData.color).length > 0)
                    readonly property color segSwatchColor: {
                        const live = root.liveSwatches[modelData.value]
                        return live !== undefined ? live : (segHasSwatch ? modelData.color : "transparent")
                    }

                    // natural content width; the container maxes these to size every segment equally — never shrink below it or text clips
                    readonly property real natW: Math.ceil(_content.implicitWidth) + 18
                    onNatWChanged: _segContainer._recalcNat()

                    width:  root._stacked ? _segContainer._cellW : Math.max(natW, _segContainer._cellW)
                    height: 30
                    clip: true

                    Accessible.role: Accessible.RadioButton
                    Accessible.name: root.label + ": " + String(_seg.modelData.label ?? "")
                    Accessible.checked: _seg.active
                    Keys.onSpacePressed: event => { if (!event.isAutoRepeat && root.enabled) root.chosen(_seg.modelData.value); event.accepted = true }
                    Keys.onReturnPressed: event => { if (!event.isAutoRepeat && root.enabled) root.chosen(_seg.modelData.value); event.accepted = true }
                    Keys.onEnterPressed: event => { if (!event.isAutoRepeat && root.enabled) root.chosen(_seg.modelData.value); event.accepted = true }
                    Keys.onLeftPressed: event => {
                        const it = _segRepeater.itemAt(_seg.index - 1)
                        if (it) it.forceActiveFocus()
                        event.accepted = true
                    }
                    Keys.onRightPressed: event => {
                        const it = _segRepeater.itemAt(_seg.index + 1)
                        if (it) it.forceActiveFocus()
                        event.accepted = true
                    }

                    HoverHandler {
                        id: _hover
                        enabled: root.enabled
                        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                    TapHandler {
                        id: _tap
                        enabled: root.enabled
                        onTapped: root.chosen(_seg.modelData.value)
                    }

                    // hover/focus preview: a faded ghost of the selection thumb, as if it had moved here
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Theme.radiusControl - 3
                        antialiasing: true
                        color: Theme.mix(Theme.menuControl, root.accentColor, ShellSettings.neutralTheme ? 0.26 : 0.38)
                        border.width: 1
                        border.color: ShellSettings.neutralTheme
                            ? Theme.withAlpha(root.accentColor, 0.56)
                            : Theme.mix(Theme.menuCard, root.accentColor, 0.66)
                        opacity: _seg.active ? 0.0 : (_seg.activeFocus ? 0.55 : (_hover.hovered ? 0.35 : 0.0))
                        Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
                    }

                    // keyboard focus on the already-active segment: ring the real thumb
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Theme.radiusControl - 3
                        antialiasing: true
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.withAlpha(root.accentColor, 0.72)
                        opacity: (_seg.active && _seg.activeFocus) ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    }

                    scale: _tap.pressed ? 0.97 : 1.0
                    transformOrigin: Item.Center
                    Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

                    Row {
                        id: _content
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible:        _seg.segGlyph.length > 0
                            text:           _seg.segGlyph
                            color:          _seg.active
                                ? Theme.mix(Theme.text, root.accentColor, ShellSettings.highContrast ? 0.0 : 0.10)
                                : (_hover.hovered ? Theme.withAlpha(Theme.text, 0.88) : Theme.withAlpha(Theme.subtext, 0.68))
                            font.family:    Settings.font
                            font.pixelSize: Math.max(9, Settings.fontSize - 1)
                            font.weight:    Font.Medium
                            renderType:     Text.NativeRendering
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible:        _seg.segHasSwatch
                            width:          visible ? 12 : 0
                            height:         visible ? 12 : 0
                            radius:         4
                            antialiasing:   true
                            color:          _seg.segSwatchColor
                            border.width:   1
                            border.color:   _seg.active
                                ? Theme.withAlpha(Theme.text, 0.42)
                                : (_hover.hovered ? Theme.withAlpha(Theme.text, 0.30) : Theme.withAlpha(Theme.subtext, 0.22))
                            Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible:        _seg.modelData.label.length > 0
                            text:           _seg.modelData.label
                            textFormat:     Text.PlainText
                            // cap against the static space budget, not _seg.width — natW feeds cell width,
                            // so a live-width cap loops layout (width → natW → cellW → width) and polishes every frame
                            width: root._stacked
                                ? Math.min(implicitWidth, Math.max(18, _segContainer._fullCellW - 18
                                    - (_seg.segGlyph.length > 0 ? 18 : 0)
                                    - (_seg.segHasSwatch ? 16 : 0)
                                    - (_seg.segBadge.length > 0 ? 28 : 0)))
                                : implicitWidth
                            elide:          Text.ElideRight
                            color:          _seg.active
                                ? Theme.mix(Theme.text, root.accentColor, ShellSettings.highContrast ? 0.0 : 0.10)
                                : (_hover.hovered ? Theme.withAlpha(Theme.text, 0.88) : Theme.withAlpha(Theme.subtext, 0.68))
                            font.family:    Settings.font
                            font.pixelSize: Math.max(9, Settings.fontSize - 1)
                            font.weight:    _seg.active ? Font.DemiBold : Font.Medium
                            renderType:     Text.NativeRendering
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: _seg.segBadge.length > 0
                            width: visible ? _segBadgeText.implicitWidth + 8 : 0
                            height: visible ? _segBadgeText.implicitHeight + 2 : 0
                            radius: 3
                            antialiasing: true
                            color: Theme.withAlpha(Theme.warning, 0.08)
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.warning, 0.32)

                            Text {
                                id: _segBadgeText
                                anchors.centerIn: parent
                                text: _seg.segBadge
                                color: Theme.withAlpha(Theme.warning, 0.85)
                                font.family: Settings.font
                                font.pixelSize: Settings.fontSize - 5
                                font.weight: Font.DemiBold
                                font.capitalization: Font.AllUppercase
                                renderType: Text.NativeRendering
                            }
                        }
                    }
                }
            }
        }
    }
}
