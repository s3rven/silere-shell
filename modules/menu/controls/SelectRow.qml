pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    property string glyph:       ""
    property string label:       ""
    property string key: ""
    property string description: ""
    property var    model:       []
    property var    currentValue: root.key.length > 0 ? ShellSettings[root.key] : undefined
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
    // seven rows and half of the next: a cut row says there is more without any other chrome
    readonly property int _optionsCapH: Metrics.snap4Up(root._optionH * 7.5)
    // 44/56 are the shared single-line and two-line row heights; a select row that sits between toggles must not be the one that breaks the rhythm
    readonly property int _headerH: 4 * Math.ceil(Math.max(
        root._hasDesc ? 56 : 44,
        _headerText.implicitHeight + 12,
        _glyph.implicitHeight + 12,
        root._controlH + 12) / 4)

    // the value pill grows into whatever the label leaves free, keeping 96px for the
    // label itself. A flat 148 cap truncated long values (font and display names)
    // on a wide row while most of the middle sat empty
    readonly property int _leadW: root._hasLead ? 14 + Metrics.glyphSlotWidth + 10 : 14
    readonly property int _pillMaxW: Math.max(92, Metrics.snap4Down(root.width - root._leadW - 10 - 12 - 96))

    signal chosen(var value)

    Connections {
        target: root
        function onChosen(value) {
            if (root.key.length > 0) ShellSettings.setValue(root.key, value)
        }
    }

    property bool _open: false
    // with the bar below, the card grows upward from it: the list opens above so the header stays under the pointer
    readonly property bool _above: Metrics.barAtBottom
    readonly property real _headerY: root._above ? _options.height : 0
    ScrollHold {
        id: _hold
        item: _headerHitArea
        watched: root
    }

    // opening a dropdown has to show the current choice, which may sit below the cap
    function _revealOption(index: int): void {
        if (!_open || _options.count <= 0) return
        const i = Math.max(0, Math.min(_options.count - 1, index))
        _options.forceLayout()
        _options.positionViewAtIndex(i, ListView.Contain)
    }

    function _revealActiveOption(): void {
        root._revealOption(Math.max(0, _options.currentIndex))
    }

    function _setOpen(next: bool): void {
        if (next && !root._canOpen) return
        if (_open === next) {
            if (_open) _revealDefer.restart()
            return
        }
        _revealDefer.stop()
        _typedReset.stop()
        _options.cancelFlick()
        const returnFocus = !next && _options.currentItem && _options.currentItem.activeFocus
        if (next) MenuState.claimSettingsSelect(root)
        else MenuState.releaseSettingsSelect(root)
        root._typed = ""
        if (root._above) _hold.arm()
        _open = next
        if (_open) {
            _options.currentIndex = Math.max(0, root._activeIndex)
            _revealDefer.restart()
        }
        else if (returnFocus && root.enabled && root.visible) root.forceActiveFocus(Qt.TabFocusReason)
    }

    function _toggleOpen(): void {
        root._setOpen(!_open)
    }

    // keys reach the row, so a list opened by pointer takes the row's focus to hear them; that focus draws no ring
    property bool _pointerFocus: false
    onActiveFocusChanged: if (!activeFocus) root._pointerFocus = false

    function _moveTo(index: int): void {
        _options.currentIndex = Math.max(0, Math.min(root._optionCount - 1, index))
        root._revealOption(_options.currentIndex)
    }

    // the font list runs to thousands of rows. Typing lands on the first that starts with the text, or failing that contains it
    property string _typed: ""
    Timer { id: _typedReset; interval: 1000; onTriggered: root._typed = "" }
    function _searchText(text: string): string {
        return text.normalize("NFD").toLowerCase().replace(/[\u0300-\u036F]/g, "")
    }
    function _matchTyped(start: int): void {
        const query = root._searchText(root._typed)
        if (!root._open || query.length === 0 || root._optionCount <= 0) return
        let contains = -1
        for (let step = 0; step < root._optionCount; step++) {
            const i = (Math.max(0, start) + step) % root._optionCount
            const label = root._searchText(String(root.model[i].label ?? ""))
            if (label.startsWith(query)) { root._moveTo(i); return }
            if (contains < 0 && label.indexOf(query) >= 0) contains = i
        }
        if (contains >= 0) root._moveTo(contains)
    }
    function _typeAhead(text: string): void {
        if (!root._open || !root._canOpen || text.length === 0) return
        const previous = root._searchText(root._typed)
        const added = root._searchText(text)
        const cycle = added.length === 1 && previous === added
        root._typed = cycle ? text.toLowerCase() : (root._typed + text.toLowerCase()).slice(0, 256)
        _typedReset.restart()
        root._matchTyped(cycle ? _options.currentIndex + 1 : 0)
    }
    function _backspaceTypeAhead(): void {
        if (!root._open || !root._canOpen || root._typed.length === 0) return
        root._typed = root._typed.slice(0, -1)
        _typedReset.restart()
        root._matchTyped(0)
    }

    Keys.onPressed: event => {
        if (!root._open || (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) return
        const at = _options.currentIndex
        if (event.key === Qt.Key_Home) root._moveTo(0)
        else if (event.key === Qt.Key_End) root._moveTo(root._optionCount - 1)
        else if (event.key === Qt.Key_PageUp) root._moveTo(at - 7)
        else if (event.key === Qt.Key_PageDown) root._moveTo(at + 7)
        else if (event.key === Qt.Key_Backspace && root._typed.length > 0) {
            root._backspaceTypeAhead()
        } else if (event.text.length === 1 && event.text > " " || (event.text === " " && root._typed.length > 0))
            root._typeAhead(event.text)
        else return
        event.accepted = true
    }

    onEnabledChanged: if (!enabled) root._setOpen(false)
    onVisibleChanged: if (!visible) root._setOpen(false)
    on_OptionCountChanged: if (root._optionCount <= 0) root._setOpen(false)
    on_ActiveIndexChanged: if (root._open) {
        _options.currentIndex = Math.max(0, root._activeIndex)
        _revealDefer.restart()
    }
    Component.onDestruction: MenuState.releaseSettingsSelect(root)

    Timer {
        id: _revealDefer
        interval: 0
        onTriggered: {
            root._revealActiveOption()
        }
    }

    readonly property bool _canOpen: root.enabled && root.visible && root._optionCount > 0
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
    opacity: enabled ? 1.0 : Theme.disabledOpacity
    MotionBehavior on opacity {NumberAnimation { duration: Motion.medium } }

    Accessible.role: Accessible.ComboBox
    Accessible.name: root.label
    Accessible.description: root.description.length > 0
        ? root.description + " · Current: " + root._activeLabel
        : "Current: " + root._activeLabel
    Accessible.focusable: root._canOpen
    Accessible.onPressAction: root._toggleOpen()
    KeyboardFocus {
        interactive: root._canOpen
        ringY: root._headerY
        ringHeight: root._headerH
        ringShown: !root._pointerFocus
        spaceIsText: root._typed.length > 0
        listNavigation: true
        customNavigation: true
        onActivated: {
            if (root._open && _options.currentIndex >= 0) {
                const option = root.model[_options.currentIndex]
                if (!option) return
                root.chosen(option.value)
                root._setOpen(false)
            } else {
                root._setOpen(true)
            }
        }
        onNavigated: direction => {
            if (!root._open) {
                root._setOpen(true)
            } else _options.currentIndex = Math.max(0, Math.min(root._optionCount - 1, _options.currentIndex + direction))
            root._revealOption(_options.currentIndex)
        }
    }

    Item {
        id: _headerHitArea
        y: root._headerY
        width: parent.width
        height: root._headerH

        HoverHandler {
            id: _hov
            enabled: root._canOpen
            cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
        TapHandler {
            id: _headerTap
            enabled: root._canOpen
            onTapped: {
                if (!root._open && !root.activeFocus) {
                    root._pointerFocus = true
                    root.forceActiveFocus(Qt.MouseFocusReason)
                }
                root._toggleOpen()
            }
        }
    }

    RowHoverBg {
        y: root._headerY
        width:  parent.width
        height: root._headerH
        topRadius:    root._open && root._above ? 0 : root.topRadius
        bottomRadius: root._open && !root._above ? 0 : root.bottomRadius
        cardInset:    root.cardInset
        leftBleed:    root.cardLeftBleed
        active:       (_hov.hovered) && root.enabled
        pressed:      _headerTap.pressed && root.enabled
    }

    ShellText {
        id: _glyph
        anchors.left:           parent.left; anchors.leftMargin: 14
        anchors.verticalCenter: _header.verticalCenter
        width: root._hasLead ? Metrics.glyphSlotWidth : 0
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
        anchors.top:    parent.top; anchors.topMargin: root._headerY
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
                color: Theme.menuTextDetail
                font.pixelSize: Settings.fontCaption
                lineHeight: 1.1
            }
        }
    }
    Item {
        id: _chevronSlot
        anchors.right:          parent.right; anchors.rightMargin: 12
        anchors.verticalCenter: _header.verticalCenter
        // a 56px row centres the pill 14px down, half a device pixel off at 1.25
        readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
        transform: PixelSnap { item: _chevronSlot; dpr: _chevronSlot._dpr }
        // 4px: a text-sized pill puts its left outline edge between device pixels at 1.25
        width: Math.min(Metrics.snap4Up(Math.max(92, _valText.implicitWidth + 34)), root._pillMaxW)
        height: root._controlH

        Rectangle {
            id: _chevronFill
            anchors.fill: parent
            radius: Theme.radiusField
            antialiasing: true
            color: root._open
                ? Theme.withAlpha(root.accentColor, 0.055)
                : Theme.buttonFill(root.accentColor,
                    _hov.hovered, _headerTap.pressed)
            ColorFade on color {}

            OutlineBorder {
                radius: _chevronFill.radius
                outlineWidth: 1
                outlineColor: root._open
                        ? Theme.controlLineActive(root.accentColor)
                        : Theme.buttonLine(root.accentColor,
                            _hov.hovered, _headerTap.pressed)
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
            text:           root._typed.length > 0 ? root._typed : root._activeLabel
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

    ShellListView {
        id: _options
        anchors.top: parent.top; anchors.topMargin: root._above ? 0 : root._headerH
        anchors.left: parent.left
        anchors.right: parent.right

        // a ListView, not a Repeater: a Repeater loads every installed font even with all but seven rows clipped
        height: root._open ? Math.min(root._optionCount * root._optionH
            + (headerItem ? headerItem.height : 2) + (footerItem ? footerItem.height : 2), root._optionsCapH) : 0
        interactive: contentHeight > height + 1
            && root._open && !_optionsDisclosure.running
        visible: height > 0.5
        cacheBuffer: 0
        reuseItems: true
        model: root._open || height > 0.5 ? root.model : []
        opacity: root._open ? 1.0 : 0.0

        Disclosure on height {
            id: _optionsDisclosure
            onRunningChanged: if (!running && root._open) _revealDefer.restart()
        }
        // position against the growing viewport until the selected row really fits. Stop after the reveal so ordinary list scrolling stays free
        onHeightChanged: if (root._open && _optionsDisclosure.running) _revealDefer.restart()
        MotionBehavior on opacity {
            id: _optFade
            NumberAnimation {
                duration: Motion.fast
                easing.type: _optFade.targetValue > 0.5 ? Easing.OutCubic : Easing.InCubic
            }
        }

        header: Item {
            width: _options.width
            height: root._above ? 2 : _topDivider.implicitHeight + 1
            Hairline {
                id: _topDivider
                visible: !root._above
                x: 14
                width: parent.width - 28
                color: Theme.menuDivider
            }
        }
        footer: Item {
            width: _options.width
            height: root._above ? _bottomDivider.implicitHeight + 1 : 2
            Hairline {
                id: _bottomDivider
                visible: root._above
                anchors.bottom: parent.bottom
                x: 14
                width: parent.width - 28
                color: Theme.menuDivider
            }
        }

        delegate: InlineOptionRow {
            id: _opt
            required property var modelData
            required property int index
            topRadius: root._above && _opt.index === 0 ? root.topRadius : 0
            bottomRadius: !root._above && _opt.index === _options.count - 1 ? root.bottomRadius : 0
            readonly property bool active: root.currentValue === modelData.value
            readonly property string optionFont:
                (modelData.fontFamily !== undefined && modelData.fontFamily !== null
                    && String(modelData.fontFamily).length > 0)
                ? String(modelData.fontFamily) : Settings.font

            width: _options.width
            enabled: root.enabled && root._open
            label: String(modelData.label ?? "")
            accessiblePrefix: root.label
            labelFontFamily: optionFont
            preview: root.optionPreview
            previewValue: modelData.value
            selected: active
            highlighted: root.activeFocus && _options.currentIndex === _opt.index
            accentColor: root.accentColor
            onActiveFocusChanged: if (activeFocus) _options.currentIndex = index

            // closing hands focus back only when a key chose the option; a click left a focus ring around the row
            onTriggered: {
                if (!root.enabled || !root._open) return
                root.chosen(_opt.modelData.value)
                root._setOpen(false)
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
