pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"

Item {
    id: root

    property bool powerOpen: false
    readonly property bool active: MenuState.open && MenuState.activeTab === 1 && !powerOpen

    // Final (post-animation) tree height, so the panel floor moves once per
    // section change instead of chasing the collapse animation frame by frame.
    implicitHeight: _navContentHeight()

    readonly property int _navTop:     8
    readonly property int _navGapY:    8    // between groups
    readonly property int _navRowH:    30
    readonly property int _navRowGap:  2    // within a group
    readonly property int _navHdrH:    20
    readonly property int _navStdHdrH: 12   // standalone leaf's divider slot

    // accordion: only the group holding the active section shows its rows, so
    // the nav stays short and the panel can hug the detail content
    function _groupExpanded(it): bool {
        if (!it.children) return true
        for (let i = 0; i < it.children.length; i++) {
            if (it.children[i].section === MenuState.settingsSection) return true
        }
        return false
    }

    function _groupHeight(it): real {
        const isGroup = !!it.children
        const hdr = isGroup ? _navHdrH : _navStdHdrH
        const leaves = isGroup ? it.children : [it]
        return hdr + (root._groupExpanded(it) ? leaves.length * (_navRowH + _navRowGap) : 0)
    }

    function _navContentHeight(): real {
        const tree = MenuState.settingsTree
        let h = _navTop
        for (let i = 0; i < tree.length; i++) {
            if (i > 0) h += _navGapY
            h += root._groupHeight(tree[i])
        }
        return h + 10
    }

    // synchronous tree walk avoids mapToItem race on first frame
    function _sectionRowY(section: string): real {
        const tree = MenuState.settingsTree
        let y = _navTop
        for (let i = 0; i < tree.length; i++) {
            const it = tree[i]
            if (i > 0) y += _navGapY
            const isGroup = !!it.children
            const hdr = isGroup ? _navHdrH : _navStdHdrH
            const leaves = isGroup ? it.children : [it]
            for (let j = 0; j < leaves.length; j++) {
                if (leaves[j].section === section)
                    return y + hdr + j * _navRowH + (j + 1) * _navRowGap
            }
            y += root._groupHeight(it)
        }
        return _navTop
    }

    // clamp against the final tree height, not the animating contentHeight —
    // a mid-collapse clamp can leave the view resting out of bounds
    function _scrollToSelection(): void {
        const contentH = root._navContentHeight()
        const viewH = _navScroll.height
        if (contentH <= viewH + 1) { _navScroll.contentY = 0; return }
        const rowY = _sectionRowY(MenuState.settingsSection)
        const margin = 8
        const maxY = Math.max(0, contentH - viewH)
        let target = _navScroll.contentY
        if (rowY - margin < target) target = rowY - margin
        else if (rowY + _navRowH + margin > target + viewH) target = rowY + _navRowH + margin - viewH
        _navScroll.contentY = Math.max(0, Math.min(maxY, target))
    }

    function _focusSelection(): void {
        for (let i = 0; i < _groupRepeater.count; i++) {
            const group = _groupRepeater.itemAt(i)
            if (group && group.focusSection(MenuState.settingsSection)) return
        }
    }

    function _stepSelection(delta: int): void {
        const before = MenuState.settingsSection
        MenuState.stepSettingsSection(delta)
        if (before !== MenuState.settingsSection) _selectionFocus.restart()
    }

    Timer {
        id: _selectionFocus
        interval: 0
        onTriggered: root._focusSelection()
    }

    onActiveChanged: if (active) Qt.callLater(_scrollToSelection)
    Connections {
        target: MenuState
        function onSettingsSectionChanged() { root._scrollToSelection() }
    }

    Shortcut {
        sequences: ["Ctrl+Down"]
        context: Qt.ApplicationShortcut
        enabled: root.active
        onActivated: root._stepSelection(1)
    }
    Shortcut {
        sequences: ["Ctrl+Up"]
        context: Qt.ApplicationShortcut
        enabled: root.active
        onActivated: root._stepSelection(-1)
    }

    Flickable {
        id: _navScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: _content.height
        clip: true
        boundsMovement: Flickable.StopAtBounds
        flickDeceleration: 1800
        maximumFlickVelocity: 2200
        interactive: contentHeight > height + 1

        // callLater coalesces the per-frame calls while the panel height animates
        onHeightChanged: Qt.callLater(root._scrollToSelection)

        // only animates programmatic scroll-to-selection, never the user's own drag/flick
        Behavior on contentY {
            enabled: !ShellSettings.reduceMotion && !_navScroll.moving
            NumberAnimation { duration: Motion.ms(160); easing.type: Easing.OutCubic }
        }

        Item {
            id: _content
            width: root.width
            height: _navCol.implicitHeight + root._navTop + 10

            // _selReady defers the Behavior one frame so it's correct on open
            property bool _selReady: false
            Component.onCompleted: Qt.callLater(function() { _content._selReady = true })

            Item {
                id: _selHighlight
                x: 6
                width: _content.width - 12
                y: root._sectionRowY(MenuState.settingsSection)
                height: root._navRowH

                Behavior on y {
                    enabled: _content._selReady && !ShellSettings.reduceMotion
                    NumberAnimation { duration: Motion.ms(155); easing.type: Easing.OutCubic }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    antialiasing: true
                    color: Theme.menuControl
                    border.width: 1
                    border.color: Theme.menuControlLine
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: 14
                    radius: 1.5
                    antialiasing: true
                    color: Theme.accent
                }
            }

            Column {
                id: _navCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                anchors.top: parent.top
                anchors.topMargin: root._navTop
                spacing: root._navGapY

                Repeater {
                    id: _groupRepeater
                    model: MenuState.settingsTree

                    delegate: Item {
                        id: _grp
                        required property var modelData
                        width: parent.width
                        height: _grpHdr.height + _leafBox.height

                        readonly property bool isGroup: !!modelData.children
                        readonly property var  _leaves: isGroup ? modelData.children : [modelData]
                        readonly property bool groupActive: {
                            for (let i = 0; i < _leaves.length; i++) {
                                if (_leaves[i].section === MenuState.settingsSection) return true
                            }
                            return false
                        }
                        readonly property bool expanded: !isGroup || groupActive

                        function focusSection(section: string): bool {
                            for (let i = 0; i < _leafRepeater.count; i++) {
                                const leaf = _leafRepeater.itemAt(i)
                                if (leaf && leaf.modelData.section === section) {
                                    leaf.forceActiveFocus()
                                    return true
                                }
                            }
                            return false
                        }

                        Item {
                            id: _grpHdr
                            width: parent.width
                            height: _grp.isGroup ? root._navHdrH : root._navStdHdrH

                            // a collapsed header is a button that jumps to the group's first section
                            function _open(): void {
                                if (_grp.isGroup && !_grp.groupActive)
                                    MenuState.setSettingsSection(_grp._leaves[0].section)
                            }
                            activeFocusOnTab: root.active && _grp.isGroup && !_grp.groupActive
                            Accessible.role: _grp.isGroup ? Accessible.Button : Accessible.NoRole
                            Accessible.name: _grp.isGroup ? _grp.modelData.label + " settings group" : ""
                            Accessible.description: _grp.expanded ? "Expanded" : "Expand"
                            Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) _grpHdr._open(); event.accepted = true }
                            Keys.onReturnPressed: event => { if (!event.isAutoRepeat) _grpHdr._open(); event.accepted = true }
                            Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) _grpHdr._open(); event.accepted = true }
                            HoverHandler {
                                id: _hdrHover
                                enabled: _grp.isGroup && !_grp.groupActive
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler { onTapped: _grpHdr._open() }

                            Text {
                                id: _hdrLabel
                                visible:                _grp.isGroup
                                anchors.left:           parent.left
                                anchors.leftMargin:     9
                                anchors.bottom:         parent.bottom
                                anchors.bottomMargin:   4
                                text:           _grp.modelData.label
                                color:          _grp.groupActive
                                    ? Theme.withAlpha(Theme.menuTextMuted, 0.90)
                                    : Theme.withAlpha(Theme.menuTextMuted,
                                          _hdrHover.hovered || _grpHdr.activeFocus ? 0.86 : 0.58)
                                font.family:    Settings.font
                                font.pixelSize: Settings.fontSize - 3
                                font.letterSpacing:  0.5
                                font.weight:    Font.DemiBold
                                font.capitalization: Font.AllUppercase
                                renderType:     Text.NativeRendering
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }
                            Rectangle {
                                visible:              _grp.isGroup
                                anchors.left:         _hdrLabel.right
                                anchors.leftMargin:   8
                                anchors.right:        _hdrChevron.left
                                anchors.rightMargin:  6
                                anchors.verticalCenter: _hdrLabel.verticalCenter
                                height: 1
                                radius: 0.5
                                color: _grp.groupActive
                                    ? Theme.menuDivider
                                    : Theme.withAlpha(Theme.subtext, 0.10)
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }
                            Text {
                                id: _hdrChevron
                                visible: _grp.isGroup
                                anchors.right:        parent.right
                                anchors.rightMargin:  8
                                anchors.verticalCenter: _hdrLabel.verticalCenter
                                text: "󰅂"
                                rotation: _grp.expanded ? 90 : 0
                                transformOrigin: Item.Center
                                color: Theme.withAlpha(Theme.subtext,
                                    _hdrHover.hovered || _grpHdr.activeFocus ? 0.72 : 0.38)
                                font.family:    Settings.font
                                font.pixelSize: Settings.fontSize - 2
                                renderType:     Text.NativeRendering
                                Behavior on rotation {
                                    enabled: !ShellSettings.reduceMotion
                                    NumberAnimation { duration: Motion.ms(155); easing.type: Easing.OutCubic }
                                }
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }
                        }

                        Item {
                            id: _leafBox
                            anchors.top: _grpHdr.bottom
                            width: parent.width
                            height: _grp.expanded ? _leafCol.height : 0
                            visible: height > 0
                            // a standing clip node breaks batching; only clip mid-animation
                            clip: height < _leafCol.height
                            Behavior on height {
                                enabled: !ShellSettings.reduceMotion
                                NumberAnimation { duration: Motion.ms(155); easing.type: Easing.OutCubic }
                            }

                            Column {
                                id: _leafCol
                                width: parent.width
                                topPadding: root._navRowGap
                                spacing: root._navRowGap

                                Repeater {
                                    id: _leafRepeater
                                    model: _grp._leaves

                                    delegate: Rectangle {
                                        id: _leaf
                                        required property var modelData
                                        readonly property bool   active: MenuState.settingsSection === modelData.section
                                        readonly property string glyph:  modelData.glyph ?? ""
                                        // whole pixels only: a fractional shift blurs native-rendered text
                                        property real _shift: (active || _leafHover.hovered) ? 1 : 0

                                        readonly property color _fg: active
                                            ? Theme.text
                                            : Theme.withAlpha(Theme.mix(Theme.subtext, Theme.text, 0.12), _leafHover.hovered || _leaf.activeFocus ? 0.92 : 0.76)
                                        readonly property color _glyphFg: active
                                            ? Theme.mix(Theme.accent, Theme.text, 0.10)
                                            : Theme.withAlpha(Theme.subtext, _leafHover.hovered || _leaf.activeFocus ? 0.76 : 0.56)

                                        width: parent.width
                                        height: root._navRowH
                                        radius: 8
                                        antialiasing: true
                                        color: ((_leafHover.hovered || _leaf.activeFocus) && !active)
                                            ? Theme.withAlpha(Theme.text, 0.045) : "transparent"
                                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                                        Behavior on _shift {
                                            enabled: !ShellSettings.reduceMotion
                                            NumberAnimation { duration: Motion.ms(105); easing.type: Easing.OutCubic }
                                        }

                                        activeFocusOnTab: root.active && _grp.expanded
                                        Accessible.role: Accessible.Button
                                        Accessible.name: _leaf.modelData.label
                                        Keys.onSpacePressed: event => { if (!event.isAutoRepeat) MenuState.setSettingsSection(_leaf.modelData.section); event.accepted = true }
                                        Keys.onReturnPressed: event => { if (!event.isAutoRepeat) MenuState.setSettingsSection(_leaf.modelData.section); event.accepted = true }
                                        Keys.onEnterPressed: event => { if (!event.isAutoRepeat) MenuState.setSettingsSection(_leaf.modelData.section); event.accepted = true }
                                        Keys.onUpPressed: event => { root._stepSelection(-1); event.accepted = true }
                                        Keys.onDownPressed: event => { root._stepSelection(1); event.accepted = true }

                                        HoverHandler { id: _leafHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler   { id: _leafTap; onTapped: MenuState.setSettingsSection(_leaf.modelData.section) }
                                        scale: _leafTap.pressed ? 0.985 : 1.0
                                        transformOrigin: Item.Left
                                        Behavior on scale {
                                            enabled: !ShellSettings.reduceMotion
                                            NumberAnimation { duration: Motion.ms(95); easing.type: Easing.OutCubic }
                                        }

                                        Text {
                                            id: _leafGlyph
                                            anchors.left:           parent.left
                                            anchors.leftMargin:     13
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 19
                                            horizontalAlignment: Text.AlignHCenter
                                            text:  _leaf.glyph
                                            color: _leaf._glyphFg
                                            font.family:    Settings.font
                                            font.pixelSize: Settings.fontSize
                                            renderType:     Text.NativeRendering
                                            transform: Translate { x: Math.round(_leaf._shift) }
                                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                                        }

                                        Text {
                                            anchors.left:           _leafGlyph.right
                                            anchors.leftMargin:     9
                                            anchors.right:          parent.right
                                            anchors.rightMargin:    9
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: _leaf.modelData.label
                                            elide: Text.ElideRight
                                            color: _leaf._fg
                                            font.family:    Settings.font
                                            font.pixelSize: Settings.fontSize
                                            font.weight:    _leaf.active ? Font.DemiBold : Font.Normal
                                            renderType:     Text.NativeRendering
                                            transform: Translate { x: Math.round(_leaf._shift) }
                                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ListEdgeFade {
        anchors.fill: _navScroll
        visible: _navScroll.interactive
        fadeColor: Theme.menuPane
        list: _navScroll
    }
}
