pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"

Item {
    id: root

    property bool powerOpen: false
    property bool navigationVisible: true
    readonly property bool active: MenuState.settingsActive
        && navigationVisible && !powerOpen
    readonly property bool compact: width < 132

    signal currentPageRetapped()

    property int _expandedGroup: _groupIndexForSection(MenuState.settingsSection)

    implicitHeight: _navContentHeight()

    readonly property int _navTop:      10
    readonly property int _navBottom:    8
    readonly property int _groupH:      27
    readonly property int _groupGap:     1
    readonly property int _childrenPad:  2
    readonly property int _navRowH:     27
    readonly property int _navRowGap:    1

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
        if (groupIndex < 0) return root._navTop
        const groupTop = root._groupY(groupIndex)
        if (groupIndex !== root._expandedGroup) return groupTop
        const leafIndex = root._leafIndexForSection(groupIndex, section)
        if (leafIndex < 0) return groupTop
        return groupTop + root._groupH + root._childrenPad
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
        if (bottom - top > viewH - margin * 2) target = top - margin
        else if (top - margin < target) target = top - margin
        else if (bottom + margin > target + viewH)
            target = bottom + margin - viewH
        _navScroll.contentY = Math.max(0, Math.min(maxY, target))
    }

    function _scrollToSelection(): void {
        if (!root.active) return
        const y = root._sectionRowY(MenuState.settingsSection)
        root._revealRange(y, y + root._navRowH)
    }

    function _scrollToExpandedGroup(): void {
        if (!root.active || root._expandedGroup < 0) return
        const tree = MenuState.settingsTree
        const y = root._groupY(root._expandedGroup)
        root._revealRange(y, y + root._groupFinalHeight(root._expandedGroup,
                                                        tree[root._expandedGroup]))
    }

    function _toggleGroup(index: int): void {
        const oldGroup = root._expandedGroup >= 0
            ? _groupRepeater.itemAt(root._expandedGroup) : null
        const restoreFocus = oldGroup && oldGroup.hasFocusedItem()
        const opening = root._expandedGroup !== index
        // move focus before collapsing destroys the focused leaf, or Qt rejects the activeFocusOnTab change
        if (restoreFocus) root._focusGroupHeader(index)
        root._expandedGroup = opening ? index : -1
        _disclosureSettle.restart()

        if (opening) {
            const group = MenuState.settingsTree[index]
            const leaves = root._leaves(group)
            if (leaves.length > 0 && !root._groupContainsSection(group, MenuState.settingsSection))
                root._activateSection(leaves[0].section)
        }
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

        const count = _groupRepeater.count
        if (count === 0) return
        const next = (groupIndex + (delta < 0 ? -1 : 1) + count) % count
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
        else if (_groupRepeater.count > 0)
            root._focusGroupHeader((groupIndex + 1) % _groupRepeater.count)
    }

    Timer {
        id: _disclosureSettle
        interval: Motion.medium
        onTriggered: root._scrollToExpandedGroup()
    }

    Timer {
        id: _resizeSettle
        interval: ShellSettings.reduceMotion ? 0 : 50
        onTriggered: root._scrollToSelection()
    }

    function _selectGroupAndScroll(): void {
        const selectedGroup = root._groupIndexForSection(MenuState.settingsSection)
        if (selectedGroup >= 0 && selectedGroup !== root._expandedGroup) {
            root._expandedGroup = selectedGroup
            _disclosureSettle.restart()
        } else {
            Qt.callLater(root._scrollToSelection)
        }
    }

    Component.onCompleted: {
        if (root.active) Qt.callLater(root._scrollToSelection)
    }
    onActiveChanged: {
        if (!active) {
            _disclosureSettle.stop()
            _resizeSettle.stop()
            return
        }
        root._selectGroupAndScroll()
    }

    Connections {
        target: MenuState
        function onSettingsSectionChanged() {
            if (root.active) root._selectGroupAndScroll()
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
        interactive: _navSettle.overflows

        onHeightChanged: if (root.active) _resizeSettle.restart()

        MotionBehavior on contentY {
            gate: !_navScroll.moving
            NumberAnimation { duration: Motion.medium; easing.type: Easing.OutQuart }
        }

        Item {
            id: _content
            width: root.width
            height: root.implicitHeight

            Column {
                id: _groupColumn
                x: 6
                y: root._navTop
                width: parent.width - 12
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
                            radius: Theme.radiusInline
                            antialiasing: true
                            color: activeFocus
                                ? Theme.withAlpha(Theme.accent, 0.065)
                                : _headerHover.hovered
                                    ? Theme.withAlpha(Theme.text, 0.035)
                                    : _grp.expanded
                                        ? Theme.withAlpha(Theme.accent, 0.035)
                                    : (_grp.groupActive && !_grp.expanded)
                                        ? Theme.mix(Theme.menuControl, Theme.accent,
                                            ShellSettings.highContrast ? 0.16 : 0.10)
                                        : "transparent"
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: _grp.modelData.label + " settings category"
                            Accessible.description: _grp.expanded
                                ? "Expanded, activate to collapse"
                                : (_grp.groupActive
                                    ? "Collapsed, contains the current page"
                                    : "Collapsed, activate to expand")
                            Accessible.onPressAction: root._toggleGroup(_grp.index)

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
                                onTapped: {
                                    _grpHeader.forceActiveFocus()
                                    root._toggleGroup(_grp.index)
                                }
                            }

                            ColorFade on color {}

                            OutlineBorder {
                                radius: _grpHeader.radius
                                outlineColor: _grpHeader.activeFocus
                                    ? Theme.withAlpha(Theme.accent, Theme.focusRingSoftAlpha)
                                    : "transparent"
                            }

                            ShellText {
                                id: _groupGlyph
                                visible: !root.compact
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                horizontalAlignment: Text.AlignHCenter
                                text: _grp.modelData.glyph ?? ""
                                color: _grp.groupActive && !_grp.expanded
                                    ? Theme.mix(Theme.accent, Theme.text, 0.08)
                                    : Theme.withAlpha(Theme.menuTextMuted,
                                        _headerHover.hovered || _grpHeader.activeFocus || _grp.expanded ? 0.84 : 0.64)
                                font.pixelSize: Settings.fontSize
                            }

                            ShellText {
                                anchors.left: _groupGlyph.visible ? _groupGlyph.right : parent.left
                                anchors.leftMargin: _groupGlyph.visible ? 8 : 10
                                anchors.right: _groupChevron.left
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: _grp.modelData.label
                                color: _grp.groupActive && !_grp.expanded
                                    ? Theme.text
                                    : Theme.withAlpha(Theme.menuTextMuted,
                                        _headerHover.hovered || _grpHeader.activeFocus || _grp.expanded ? 0.94 : 0.80)
                                font.pixelSize: Settings.fontCaption
                                font.weight: _grp.groupActive || _grp.expanded
                                    ? Font.DemiBold : Font.Normal
                                font.letterSpacing: 0.35
                                font.capitalization: Font.AllUppercase
                                elide: Text.ElideRight
                            }

                            ShellText {
                                id: _groupChevron
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰅂"
                                rotation: _grp.expanded ? 90 : 0
                                transformOrigin: Item.Center
                                color: Theme.withAlpha(Theme.subtext,
                                    _headerHover.hovered || _grpHeader.activeFocus ? 0.78
                                    : _grp.expanded ? 0.62 : 0.44)
                                font.pixelSize: Settings.fontCaption

                                Disclosure on rotation { expanded: _grp.expanded }
                                ColorFade on color {}
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

                            Disclosure on height { expanded: _grp.expanded }

                            Column {
                                id: _leafColumn
                                x: 6
                                y: root._childrenPad
                                width: parent.width - 6
                                spacing: root._navRowGap
                                property real _shift: _grp.expanded ? 0 : -4
                                opacity: _grp.expanded ? 1 : 0
                                transform: Translate { y: _leafColumn._shift }

                                MotionBehavior on opacity {
                                    NumberAnimation {
                                        duration: Motion.fast
                                        easing.type: _grp.expanded ? Easing.OutCubic : Easing.InCubic
                                    }
                                }
                                Disclosure on _shift { expanded: _grp.expanded }

                                Repeater {
                                    id: _leafRepeater
                                    model: _grp.expanded || _leafBox.height > 0.5
                                        ? _grp.leaves : []

                                    delegate: Rectangle {
                                        id: _leaf

                                        required property int index
                                        required property var modelData
                                        readonly property bool active: MenuState.settingsSection === modelData.section
                                        readonly property string glyph: modelData.glyph ?? ""
                                        width: _leafColumn.width
                                        height: root._navRowH
                                        radius: Theme.radiusInline
                                        antialiasing: true
                                        color: active
                                            ? Theme.mix(Theme.menuControl, Theme.accent,
                                                ShellSettings.highContrast ? 0.18 : 0.13)
                                            : _leafHover.hovered || activeFocus
                                                ? Theme.withAlpha(Theme.text, 0.042)
                                                : "transparent"

                                        activeFocusOnTab: _grp.expanded
                                        Accessible.role: Accessible.Button
                                        Accessible.name: _leaf.modelData.label
                                        Accessible.description: _leaf.modelData.description ?? ""
                                        Accessible.selectable: true
                                        Accessible.selected: active
                                        Accessible.onPressAction: root._activateSection(_leaf.modelData.section)

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
                                            onTapped: {
                                                _leaf.forceActiveFocus()
                                                root._activateSection(_leaf.modelData.section)
                                            }
                                        }

                                        ColorFade on color {}

                                        OutlineBorder {
                                            radius: _leaf.radius
                                            outlineColor: _leaf.activeFocus
                                                ? Theme.withAlpha(Theme.accent, Theme.focusRingSoftAlpha)
                                                : "transparent"
                                        }

                                        ShellText {
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
                                                    _leafHover.hovered || _leaf.activeFocus ? 0.72 : 0.46)
                                            font.pixelSize: Settings.fontLabel
                                            ColorFade on color {}
                                        }

                                        ShellText {
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
                                            font.pixelSize: Settings.fontLabel
                                            font.weight: _leaf.active ? Font.DemiBold : Font.Normal
                                            ColorFade on color {}
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

    ScrollSettle {
        id: _navSettle
        list: _navScroll
        armed: root.active
    }

    ListEdgeLines {
        anchors.fill: _navScroll
        visible: _navSettle.ready
        list: _navScroll
    }
}
