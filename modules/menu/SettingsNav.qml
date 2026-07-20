pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"

Item {
    id: root

    property bool powerOpen: false
    readonly property bool active: MenuState.open && MenuState.activeTab === 1 && !powerOpen
    readonly property bool compact: width < 132

    signal currentPageRetapped()

    // The open category is separate from the selected page: users can inspect
    // another category without the detail pane jumping to its first entry.
    property int _expandedGroup: _groupIndexForSection(MenuState.settingsSection)

    // Final tree height, so the popup floor does not follow every frame of a
    // disclosure animation.
    implicitHeight: _navContentHeight()

    readonly property int _navTop:       8
    readonly property int _navBottom:    8
    readonly property int _groupH:      30
    readonly property int _groupGap:     3
    readonly property int _childrenPad:  4
    readonly property int _navRowH:     30
    readonly property int _navRowGap:    2

    function _leaves(it): var {
        return it.children ? it.children : [it]
    }

    function _groupIndexForSection(section: string): int {
        const tree = MenuState.settingsTree
        for (let i = 0; i < tree.length; i++) {
            const leaves = root._leaves(tree[i])
            for (let j = 0; j < leaves.length; j++) {
                if (leaves[j].section === section) return i
            }
        }
        return -1
    }

    function _leafIndexForSection(groupIndex: int, section: string): int {
        const tree = MenuState.settingsTree
        if (groupIndex < 0 || groupIndex >= tree.length) return -1
        const leaves = root._leaves(tree[groupIndex])
        for (let i = 0; i < leaves.length; i++) {
            if (leaves[i].section === section) return i
        }
        return -1
    }

    function _groupContainsSection(it, section: string): bool {
        const leaves = root._leaves(it)
        for (let i = 0; i < leaves.length; i++) {
            if (leaves[i].section === section) return true
        }
        return false
    }

    function _groupFinalHeight(index: int, it): real {
        if (index !== root._expandedGroup) return root._groupH
        const leaves = root._leaves(it)
        return root._groupH + root._childrenPad * 2
            + leaves.length * root._navRowH
            + Math.max(0, leaves.length - 1) * root._navRowGap
    }

    function _groupY(index: int): real {
        const tree = MenuState.settingsTree
        let y = root._navTop
        for (let i = 0; i < index; i++)
            y += root._groupFinalHeight(i, tree[i]) + root._groupGap
        return y
    }

    function _navContentHeight(): real {
        const tree = MenuState.settingsTree
        let h = root._navTop
        for (let i = 0; i < tree.length; i++) {
            if (i > 0) h += root._groupGap
            h += root._groupFinalHeight(i, tree[i])
        }
        return h + root._navBottom
    }

    function _sectionRowY(section: string): real {
        const groupIndex = root._groupIndexForSection(section)
        const leafIndex = root._leafIndexForSection(groupIndex, section)
        if (groupIndex < 0 || leafIndex < 0) return root._navTop
        return root._groupY(groupIndex) + root._groupH + root._childrenPad
            + leafIndex * (root._navRowH + root._navRowGap)
    }

    function _revealRange(top: real, bottom: real): void {
        const contentH = root._navContentHeight()
        const viewH = _navScroll.height
        if (contentH <= viewH + 1) {
            _navScroll.contentY = 0
            return
        }

        const margin = 7
        const maxY = Math.max(0, contentH - viewH)
        let target = _navScroll.contentY
        // If the disclosed category is taller than the viewport, keep its
        // header visible instead of bottom-aligning it out of view.
        if (bottom - top > viewH - margin * 2) target = top - margin
        else if (top - margin < target) target = top - margin
        else if (bottom + margin > target + viewH)
            target = bottom + margin - viewH
        _navScroll.contentY = Math.max(0, Math.min(maxY, target))
    }

    function _scrollToSelection(): void {
        const y = root._sectionRowY(MenuState.settingsSection)
        root._revealRange(y, y + root._navRowH)
    }

    function _scrollToExpandedGroup(): void {
        if (root._expandedGroup < 0) return
        const tree = MenuState.settingsTree
        const y = root._groupY(root._expandedGroup)
        root._revealRange(y, y + root._groupFinalHeight(root._expandedGroup,
                                                        tree[root._expandedGroup]))
    }

    function _toggleGroup(index: int): void {
        const oldGroup = root._expandedGroup >= 0
            ? _groupRepeater.itemAt(root._expandedGroup) : null
        const restoreFocus = oldGroup && oldGroup.hasFocusedItem()
        root._expandedGroup = root._expandedGroup === index ? -1 : index
        _disclosureSettle.restart()
        if (restoreFocus) Qt.callLater(function() { root._focusGroupHeader(index) })
    }

    function _activateSection(section: string): void {
        if (MenuState.settingsSection === section) {
            root.currentPageRetapped()
            return
        }
        MenuState.setSettingsSection(section)
    }

    function _focusGroupHeader(index: int): void {
        if (index < 0 || index >= _groupRepeater.count) return
        const group = _groupRepeater.itemAt(index)
        if (group) group.focusHeader()
    }

    function _moveFromHeader(groupIndex: int, delta: int): void {
        const group = _groupRepeater.itemAt(groupIndex)
        if (delta > 0 && group && group.expanded && group.focusLeaf(0)) return

        const next = groupIndex + (delta < 0 ? -1 : 1)
        if (next < 0 || next >= _groupRepeater.count) return
        const nextGroup = _groupRepeater.itemAt(next)
        if (!nextGroup) return
        if (delta < 0 && nextGroup.expanded && nextGroup.focusLastLeaf()) return
        nextGroup.focusHeader()
    }

    function _moveFromLeaf(groupIndex: int, leafIndex: int, delta: int): void {
        const group = _groupRepeater.itemAt(groupIndex)
        if (!group) return
        const nextLeaf = leafIndex + delta
        if (nextLeaf >= 0 && nextLeaf < group.leaves.length) {
            group.focusLeaf(nextLeaf)
            return
        }
        if (delta < 0) group.focusHeader()
        else root._focusGroupHeader(groupIndex + 1)
    }

    Timer {
        id: _disclosureSettle
        interval: ShellSettings.reduceMotion ? 0 : Motion.ms(155)
        onTriggered: root._scrollToExpandedGroup()
    }

    Timer {
        id: _resizeSettle
        interval: ShellSettings.reduceMotion ? 0 : 50
        onTriggered: root._scrollToSelection()
    }

    Component.onCompleted: Qt.callLater(root._scrollToSelection)
    onActiveChanged: {
        if (!active) return
        const selectedGroup = root._groupIndexForSection(MenuState.settingsSection)
        if (selectedGroup >= 0) root._expandedGroup = selectedGroup
        Qt.callLater(root._scrollToSelection)
    }

    Connections {
        target: MenuState
        function onSettingsSectionChanged() {
            const selectedGroup = root._groupIndexForSection(MenuState.settingsSection)
            if (selectedGroup >= 0) root._expandedGroup = selectedGroup
            Qt.callLater(root._scrollToSelection)
        }
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

        onHeightChanged: _resizeSettle.restart()

        Behavior on contentY {
            enabled: !ShellSettings.reduceMotion && !_navScroll.moving
            NumberAnimation { duration: Motion.ms(155); easing.type: Easing.OutCubic }
        }

        Item {
            id: _content
            width: root.width
            height: root._navContentHeight()

            Column {
                id: _groupColumn
                x: 7
                y: root._navTop
                width: parent.width - 14
                spacing: root._groupGap

                Repeater {
                    id: _groupRepeater
                    model: MenuState.settingsTree

                    delegate: Item {
                        id: _grp

                        required property int index
                        required property var modelData

                        readonly property var leaves: root._leaves(modelData)
                        readonly property bool expanded: root._expandedGroup === index
                        readonly property bool groupActive: root._groupContainsSection(
                            modelData, MenuState.settingsSection)

                        width: _groupColumn.width
                        height: _grpHeader.height + _leafBox.height

                        function focusHeader(): void {
                            _grpHeader.forceActiveFocus()
                        }

                        function focusLeaf(index: int): bool {
                            if (!_grp.expanded || index < 0 || index >= _leafRepeater.count)
                                return false
                            const leaf = _leafRepeater.itemAt(index)
                            if (!leaf) return false
                            leaf.forceActiveFocus()
                            return true
                        }

                        function focusLastLeaf(): bool {
                            return _grp.focusLeaf(_leafRepeater.count - 1)
                        }

                        function hasFocusedItem(): bool {
                            if (_grpHeader.activeFocus) return true
                            for (let i = 0; i < _leafRepeater.count; i++) {
                                const leaf = _leafRepeater.itemAt(i)
                                if (leaf && leaf.activeFocus) return true
                            }
                            return false
                        }

                        Rectangle {
                            id: _grpHeader
                            width: parent.width
                            height: root._groupH
                            radius: 7
                            antialiasing: true
                            color: activeFocus
                                ? Theme.withAlpha(Theme.accent, 0.065)
                                : _headerHover.hovered
                                    ? Theme.withAlpha(Theme.text, 0.035)
                                    : _grp.expanded
                                        ? Theme.withAlpha(Theme.text, 0.022)
                                        : "transparent"
                            border.width: activeFocus ? 1 : 0
                            border.color: Theme.withAlpha(Theme.accent, 0.30)
                            scale: _headerTap.pressed ? 0.985 : 1.0
                            transformOrigin: Item.Left

                            activeFocusOnTab: root.active
                            Accessible.role: Accessible.Button
                            Accessible.name: _grp.modelData.label + " settings category"
                            Accessible.description: _grp.expanded
                                ? "Expanded, activate to collapse"
                                : (_grp.groupActive
                                    ? "Collapsed, contains the current page"
                                    : "Collapsed, activate to expand")

                            Keys.onSpacePressed: event => {
                                if (!event.isAutoRepeat) root._toggleGroup(_grp.index)
                                event.accepted = true
                            }
                            Keys.onReturnPressed: event => {
                                if (!event.isAutoRepeat) root._toggleGroup(_grp.index)
                                event.accepted = true
                            }
                            Keys.onEnterPressed: event => {
                                if (!event.isAutoRepeat) root._toggleGroup(_grp.index)
                                event.accepted = true
                            }
                            Keys.onLeftPressed: event => {
                                if (_grp.expanded) root._toggleGroup(_grp.index)
                                event.accepted = true
                            }
                            Keys.onRightPressed: event => {
                                if (!_grp.expanded) root._toggleGroup(_grp.index)
                                event.accepted = true
                            }
                            Keys.onUpPressed: event => {
                                root._moveFromHeader(_grp.index, -1)
                                event.accepted = true
                            }
                            Keys.onDownPressed: event => {
                                root._moveFromHeader(_grp.index, 1)
                                event.accepted = true
                            }

                            HoverHandler {
                                id: _headerHover
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                id: _headerTap
                                onTapped: root._toggleGroup(_grp.index)
                            }

                            Behavior on color {
                                enabled: !ShellSettings.reduceMotion
                                ColorAnimation { duration: Motion.fast }
                            }
                            Behavior on scale {
                                enabled: !ShellSettings.reduceMotion
                                NumberAnimation { duration: Motion.ms(90); easing.type: Easing.OutCubic }
                            }

                            Rectangle {
                                visible: _grp.groupActive && !_grp.expanded
                                anchors.left: parent.left
                                anchors.leftMargin: 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 2
                                height: 13
                                radius: 1
                                antialiasing: true
                                color: Theme.accent
                            }

                            Text {
                                id: _groupGlyph
                                visible: !root.compact
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                horizontalAlignment: Text.AlignHCenter
                                text: _grp.modelData.glyph ?? ""
                                color: _grp.groupActive || _grp.expanded
                                    ? Theme.mix(Theme.accent, Theme.text, 0.08)
                                    : Theme.withAlpha(Theme.menuTextMuted,
                                        _headerHover.hovered || _grpHeader.activeFocus ? 0.84 : 0.60)
                                font.family: Settings.font
                                font.pixelSize: Settings.fontSize
                                renderType: Text.NativeRendering
                            }

                            Text {
                                anchors.left: _groupGlyph.visible ? _groupGlyph.right : parent.left
                                anchors.leftMargin: _groupGlyph.visible ? 8 : 10
                                anchors.right: _groupChevron.left
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: _grp.modelData.label
                                color: _grp.groupActive || _grp.expanded
                                    ? Theme.text
                                    : Theme.withAlpha(Theme.menuTextMuted,
                                        _headerHover.hovered || _grpHeader.activeFocus ? 0.94 : 0.76)
                                font.family: Settings.font
                                font.pixelSize: Settings.fontSize - 1
                                font.weight: _grp.groupActive || _grp.expanded
                                    ? Font.DemiBold : Font.Normal
                                renderType: Text.NativeRendering
                                elide: Text.ElideRight
                            }

                            Text {
                                id: _groupChevron
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰅂"
                                rotation: _grp.expanded ? 90 : 0
                                transformOrigin: Item.Center
                                color: Theme.withAlpha(_grp.expanded ? Theme.accent : Theme.subtext,
                                    _headerHover.hovered || _grpHeader.activeFocus ? 0.78 : 0.44)
                                font.family: Settings.font
                                font.pixelSize: Settings.fontSize - 2
                                renderType: Text.NativeRendering

                                Behavior on rotation {
                                    enabled: !ShellSettings.reduceMotion
                                    NumberAnimation { duration: Motion.ms(145); easing.type: Easing.OutCubic }
                                }
                                Behavior on color {
                                    enabled: !ShellSettings.reduceMotion
                                    ColorAnimation { duration: Motion.fast }
                                }
                            }
                        }

                        Item {
                            id: _leafBox
                            anchors.top: _grpHeader.bottom
                            width: parent.width
                            height: _grp.expanded
                                ? _leafColumn.implicitHeight + root._childrenPad * 2
                                : 0
                            visible: height > 0
                            clip: height < _leafColumn.implicitHeight + root._childrenPad * 2

                            Behavior on height {
                                enabled: !ShellSettings.reduceMotion
                                NumberAnimation { duration: Motion.ms(150); easing.type: Easing.OutCubic }
                            }

                            Rectangle {
                                // Keep the tree guide beside the child rows;
                                // the old position ran through their glyphs.
                                x: 5
                                y: 1
                                width: 1
                                height: Math.max(0, parent.height - 2)
                                color: Theme.withAlpha(Theme.subtext, 0.10)
                            }

                            Column {
                                id: _leafColumn
                                x: 6
                                y: root._childrenPad
                                width: parent.width - 6
                                spacing: root._navRowGap

                                Repeater {
                                    id: _leafRepeater
                                    model: _grp.leaves

                                    delegate: Rectangle {
                                        id: _leaf

                                        required property int index
                                        required property var modelData
                                        readonly property bool active: MenuState.settingsSection === modelData.section
                                        readonly property string glyph: modelData.glyph ?? ""
                                        property real _shift: active || _leafHover.hovered ? 1 : 0

                                        width: _leafColumn.width
                                        height: root._navRowH
                                        radius: 8
                                        antialiasing: true
                                        color: active
                                            ? Theme.menuControl
                                            : _leafHover.hovered || activeFocus
                                                ? Theme.withAlpha(Theme.text, 0.042)
                                                : "transparent"
                                        border.width: active || activeFocus ? 1 : 0
                                        border.color: active
                                            ? Theme.menuControlLine
                                            : Theme.withAlpha(Theme.accent, 0.28)
                                        scale: _leafTap.pressed ? 0.985 : 1.0
                                        transformOrigin: Item.Left

                                        activeFocusOnTab: root.active && _grp.expanded
                                        Accessible.role: Accessible.Button
                                        Accessible.name: _leaf.modelData.label
                                        Accessible.description: _leaf.modelData.description ?? ""
                                        Accessible.selectable: true
                                        Accessible.selected: active

                                        Keys.onSpacePressed: event => {
                                            if (!event.isAutoRepeat)
                                                root._activateSection(_leaf.modelData.section)
                                            event.accepted = true
                                        }
                                        Keys.onReturnPressed: event => {
                                            if (!event.isAutoRepeat)
                                                root._activateSection(_leaf.modelData.section)
                                            event.accepted = true
                                        }
                                        Keys.onEnterPressed: event => {
                                            if (!event.isAutoRepeat)
                                                root._activateSection(_leaf.modelData.section)
                                            event.accepted = true
                                        }
                                        Keys.onLeftPressed: event => {
                                            root._toggleGroup(_grp.index)
                                            _grpHeader.forceActiveFocus()
                                            event.accepted = true
                                        }
                                        Keys.onUpPressed: event => {
                                            root._moveFromLeaf(_grp.index, _leaf.index, -1)
                                            event.accepted = true
                                        }
                                        Keys.onDownPressed: event => {
                                            root._moveFromLeaf(_grp.index, _leaf.index, 1)
                                            event.accepted = true
                                        }

                                        HoverHandler {
                                            id: _leafHover
                                            cursorShape: Qt.PointingHandCursor
                                        }
                                        TapHandler {
                                            id: _leafTap
                                            onTapped: root._activateSection(_leaf.modelData.section)
                                        }

                                        Behavior on color {
                                            enabled: !ShellSettings.reduceMotion
                                            ColorAnimation { duration: Motion.fast }
                                        }
                                        Behavior on scale {
                                            enabled: !ShellSettings.reduceMotion
                                            NumberAnimation { duration: Motion.ms(90); easing.type: Easing.OutCubic }
                                        }
                                        Behavior on _shift {
                                            enabled: !ShellSettings.reduceMotion
                                            NumberAnimation { duration: Motion.ms(100); easing.type: Easing.OutCubic }
                                        }

                                        Rectangle {
                                            visible: _leaf.active
                                            anchors.left: parent.left
                                            anchors.leftMargin: 5
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 3
                                            height: 14
                                            radius: 1.5
                                            antialiasing: true
                                            color: Theme.accent
                                        }

                                        Text {
                                            id: _leafGlyph
                                            visible: !root.compact
                                            anchors.left: parent.left
                                            anchors.leftMargin: 11
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 18
                                            horizontalAlignment: Text.AlignHCenter
                                            text: _leaf.glyph
                                            color: _leaf.active
                                                ? Theme.mix(Theme.accent, Theme.text, 0.10)
                                                : Theme.withAlpha(Theme.subtext,
                                                    _leafHover.hovered || _leaf.activeFocus ? 0.78 : 0.55)
                                            font.family: Settings.font
                                            font.pixelSize: Settings.fontSize
                                            renderType: Text.NativeRendering
                                            transform: Translate { x: Math.round(_leaf._shift) }

                                            Behavior on color {
                                                enabled: !ShellSettings.reduceMotion
                                                ColorAnimation { duration: Motion.fast }
                                            }
                                        }

                                        Text {
                                            anchors.left: _leafGlyph.visible ? _leafGlyph.right : parent.left
                                            anchors.leftMargin: _leafGlyph.visible ? 8 : 12
                                            anchors.right: parent.right
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: _leaf.modelData.label
                                            elide: Text.ElideRight
                                            color: _leaf.active
                                                ? Theme.text
                                                : Theme.withAlpha(Theme.mix(Theme.subtext, Theme.text, 0.12),
                                                    _leafHover.hovered || _leaf.activeFocus ? 0.92 : 0.76)
                                            font.family: Settings.font
                                            font.pixelSize: Settings.fontSize
                                            font.weight: _leaf.active ? Font.DemiBold : Font.Normal
                                            renderType: Text.NativeRendering
                                            transform: Translate { x: Math.round(_leaf._shift) }

                                            Behavior on color {
                                                enabled: !ShellSettings.reduceMotion
                                                ColorAnimation { duration: Motion.fast }
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
    }

    ListEdgeFade {
        anchors.fill: _navScroll
        visible: _navScroll.interactive
        fadeColor: Theme.menuPane
        list: _navScroll
    }
}
