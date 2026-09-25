pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"

Item {
    id: root

    property bool powerOpen: false
    readonly property bool active: MenuState.settingsActive && !powerOpen
    readonly property bool compact: width < 132

    signal currentPageRetapped()
    signal groupToggled()

    // pinned mode never assigns _expandedGroup, so it stays bound to the selected section's group
    property int _expandedGroup: _groupIndexForSection(MenuState.settingsSection)
    readonly property bool allExpanded: ShellSettings.settingsNavPinned
    property var _collapsed: ({})
    function _isExpanded(index: int): bool {
        return root.allExpanded ? root._collapsed[index] !== true
                                : index === root._expandedGroup
    }
    function _setCollapsed(index: int, on: bool): void {
        const next = {}
        for (const k in root._collapsed) if (root._collapsed[k]) next[k] = true
        if (on) next[index] = true
        else delete next[index]
        root._collapsed = next
    }

    implicitHeight: _navContentHeight()

    readonly property int _navTop:      42
    readonly property int _navBottom:    8
    readonly property int _groupH:      Metrics.rowHeightFor(28)
    readonly property int _groupGap:     6
    readonly property int _childrenPad:  2
    readonly property int _navRowH:     Metrics.rowHeightFor(28)
    readonly property int _navRowGap:    1

    function _leaves(it): var {
        return it.children ? it.children : [it]
    }

    readonly property var _flatLeaves: {
        const out = []
        const tree = MenuState.settingsTree
        for (let g = 0; g < tree.length; g++) {
            const leaves = root._leaves(tree[g])
            for (let j = 0; j < leaves.length; j++)
                out.push({ group: g, row: j, section: leaves[j].section })
        }
        return out
    }
    readonly property int _activeOrdinal: root._flatLeaves.findIndex(
        leaf => leaf.section === MenuState.settingsSection)
    readonly property bool _selectionShown: root._activeOrdinal >= 0
        && root._isExpanded(root._flatLeaves[root._activeOrdinal].group)
    property int _groupItemsVersion: 0

    function _leafTop(ordinal: int): real {
        // a fresh drawer knows its section before the repeater builds that group, so fall back to computed geometry
        void root._groupItemsVersion
        const leaf = root._flatLeaves[ordinal]
        if (!leaf) return root._navTop
        const grp = _groupRepeater.itemAt(leaf.group)
        const groupTop = grp ? _groupColumn.y + grp.y : root._groupY(leaf.group)
        return groupTop + root._groupH + root._childrenPad
            + leaf.row * (root._navRowH + root._navRowGap)
    }
    function _slotTop(slot: real): real {
        const s = Math.max(0, Math.min(root._flatLeaves.length - 1, slot))
        const lo = Math.floor(s)
        const a = root._leafTop(lo)
        return a + (root._leafTop(Math.ceil(s)) - a) * (s - lo)
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

    function _groupModified(it): bool {
        const leaves = root._leaves(it)
        for (let i = 0; i < leaves.length; i++) {
            if (ShellSettings.modifiedSections[leaves[i].section] === true) return true
        }
        return false
    }

    function _groupFinalHeight(index: int, it): real {
        if (!root._isExpanded(index)) return root._groupH
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
        if (!root._isExpanded(groupIndex)) return groupTop
        const leafIndex = root._leafIndexForSection(groupIndex, section)
        if (leafIndex < 0) return groupTop
        return groupTop + root._groupH + root._childrenPad
            + leafIndex * (root._navRowH + root._navRowGap)
    }

    function _revealRange(top: real, bottom: real): void {
        // implicitHeight already caches the same tree calculation for layout.
        const contentH = root.implicitHeight
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

    function _scrollToGroup(index: int): void {
        if (!root.active || index < 0) return
        const tree = MenuState.settingsTree
        if (index >= tree.length) return
        const y = root._groupY(index)
        root._revealRange(y, y + root._groupFinalHeight(index, tree[index]))
    }

    function _settleTo(index: int): void {
        root._settleGroup = index
        _disclosureSettle.restart()
        // implicitHeight is the final math height, so the panel's floor steps
        // instantly while the disclosure animates — the panel needs its own easing
        root.groupToggled()
    }

    function _syncExpansionMode(keepGroupsOpen: bool, section: string): void {
        if (!keepGroupsOpen)
            root._expandedGroup = root._groupIndexForSection(section)
        // the mode changes every group's height at once. Let the panel follow that disclosure and reveal the selected leaf after the rows settle
        root._settleGroup = -1
        _disclosureSettle.restart()
        root.groupToggled()
    }

    function _toggleGroup(index: int): void {
        if (root.allExpanded) {
            const collapsing = root._isExpanded(index)
            root._setCollapsed(index, collapsing)
            root._settleTo(index)
            return
        }
        const opening = root._expandedGroup !== index
        root._expandedGroup = opening ? index : -1
        root._settleTo(opening ? index : -1)

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

    property int _settleGroup: -1
    property int _pendingRevealGroup: -1

    function _queueReveal(index: int): void {
        // Keep an explicit group target once one is queued. Viewport resize
        // notifications continue throughout the outer panel animation; replacing
        // it with the selected-row fallback on every frame caused a second scroll.
        if (index >= 0 || !_resizeSettle.running)
            root._pendingRevealGroup = index
        _resizeSettle.restart()
    }

    Timer {
        id: _disclosureSettle
        interval: Motion.medium
        // Queue the reveal after the disclosure, then let _resizeSettle debounce
        // any remaining outer-panel height frames.
        onTriggered: root._queueReveal(root._settleGroup)
    }

    Timer {
        id: _resizeSettle
        interval: ShellSettings.reduceMotion ? 0 : 50
        onTriggered: {
            const group = root._pendingRevealGroup
            root._pendingRevealGroup = -1
            if (group >= 0) root._scrollToGroup(group)
            else root._scrollToSelection()
        }
    }

    function _selectGroupAndScroll(): void {
        const selectedGroup = root._groupIndexForSection(MenuState.settingsSection)
        // a section can be selected from the page side; never leave it hidden in a collapsed group
        if (root.allExpanded) {
            if (selectedGroup >= 0 && !root._isExpanded(selectedGroup)) {
                root._setCollapsed(selectedGroup, false)
                root._settleTo(selectedGroup)
            } else {
                root._queueReveal(-1)
            }
            return
        }
        if (selectedGroup >= 0 && selectedGroup !== root._expandedGroup) {
            root._expandedGroup = selectedGroup
            root._settleTo(selectedGroup)
        } else {
            root._queueReveal(-1)
        }
    }

    Component.onCompleted: if (root.active) root._queueReveal(-1)
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
    Connections {
        target: ShellSettings
        function onSettingsNavPinnedChanged() {
            root._syncExpansionMode(
                ShellSettings.settingsNavPinned, MenuState.settingsSection)
        }
    }

    ShellFlickable {
        id: _navScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: _content.height
        interactive: contentHeight > height + 1

        onHeightChanged: if (root.active) root._queueReveal(-1)

        MotionBehavior on contentY {
            gate: !_navScroll.moving
            NumberAnimation {
                duration: Motion.normal
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.standard
            }
        }

        Item {
            id: _content
            width: root.width
            height: root.implicitHeight

            Item {
                id: _drawerHeader
                x: 8
                y: 6
                width: Math.max(1, parent.width - 16)
                height: 28

                ShellText {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Settings"
                    color: Theme.withAlpha(Theme.text, 0.88)
                    font.pixelSize: Settings.fontSize
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }

            RailSelection {
                id: _selection
                x: _groupColumn.x + 6
                width: _groupColumn.width - 6
                index: root._activeOrdinal
                rowHeight: root._navRowH
                rowTop: root._slotTop(_selection.slot)
                shown: root.active && root._selectionShown
            }

            Column {
                id: _groupColumn
                x: 6
                y: root._navTop
                width: parent.width - 12
                spacing: root._groupGap

                Repeater {
                    id: _groupRepeater
                    model: MenuState.settingsTree
                    onItemAdded: root._groupItemsVersion++

                    delegate: Item {
                        id: _grp

                        required property int index
                        required property var modelData

                        readonly property var leaves: root._leaves(modelData)
                        readonly property bool expanded: root._isExpanded(index)
                        readonly property bool groupActive: root._groupContainsSection(
                            modelData, MenuState.settingsSection)

                        width: _groupColumn.width
                        height: _grpHeader.height + _leafBox.height

                        Rectangle {
                            id: _grpHeader
                            width: parent.width
                            height: root._groupH
                            radius: Theme.radiusInline
                            antialiasing: true
                            // hover brightens the current group's marking instead of replacing it
                            color: !_grp.groupActive
                                ? (_headerTap.pressed
                                    ? Theme.withAlpha(Theme.accent, 0.12)
                                    : _headerHover.hovered
                                    ? Theme.withAlpha(Theme.text, 0.035) : "transparent")
                                : _grp.expanded
                                    ? (_headerTap.pressed ? Theme.withAlpha(Theme.accent, 0.12)
                                        : _headerHover.hovered
                                        ? Theme.withAlpha(Theme.text, 0.035) : "transparent")
                                    : Theme.mix(Theme.menuControl, Theme.accent,
                                        ShellSettings.highContrast
                                            ? (_headerTap.pressed ? 0.30
                                                : _headerHover.hovered ? 0.24 : 0.16)
                                            : (_headerTap.pressed ? 0.22
                                                : _headerHover.hovered ? 0.17 : 0.10))

                            Accessible.role: Accessible.Button
                            Accessible.name: _grp.modelData.label
                            Accessible.description: _grp.expanded ? "Expanded" : "Collapsed"
                            Accessible.focusable: true
                            Accessible.selected: _grp.groupActive && !_grp.expanded
                            Accessible.onPressAction: root._toggleGroup(_grp.index)

                            HoverHandler {
                                id: _headerHover
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                id: _headerTap
                                onTapped: {
                                    root._toggleGroup(_grp.index)
                                }
                            }

                            ColorFade on color {}

                            // group glyphs repeated their first child's; text headers separate the tiers
                            ShellText {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.right: _groupDot.visible
                                    ? _groupDot.left : _groupChevron.left
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: _grp.modelData.label
                                // collapsed, the header is the only marker the selection has
                                color: !_grp.groupActive
                                    ? Theme.withAlpha(Theme.menuTextMuted,
                                        _headerHover.hovered ? 1.0 : 0.82)
                                    : _grp.expanded
                                        ? Theme.withAlpha(Theme.menuTextMuted,
                                            _headerHover.hovered ? 1.0 : 0.88)
                                        : Theme.withAlpha(Theme.mix(
                                            Theme.text, Theme.accent, 0.22), 0.98)
                                font.pixelSize: Settings.fontCaption
                                font.letterSpacing: 0.65
                                font.weight: Font.DemiBold
                                font.capitalization: Font.AllUppercase
                                elide: Text.ElideRight
                            }

                            // only while collapsed: an expanded group shows its leaves' own dots
                            Rectangle {
                                id: _groupDot
                                visible: ShellSettings.settingsNavDots
                                    && !_grp.expanded && root._groupModified(_grp.modelData)
                                anchors.right: _groupChevron.left
                                anchors.rightMargin: 5
                                anchors.verticalCenter: parent.verticalCenter
                                width: 4; height: 4; radius: 2
                                antialiasing: true
                                color: Theme.withAlpha(Theme.accent, 0.72)
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
                                    _headerHover.hovered ? 0.90
                                    : _grp.expanded ? 0.80 : 0.74)
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

                            Disclosure on height {
                                expanded: _grp.expanded
                                symmetric: !root.allExpanded
                                enterCurve: Motion.standard
                                exitCurve: Motion.standard
                            }

                            Column {
                                id: _leafColumn
                                x: 6
                                y: root._childrenPad
                                width: parent.width - 6
                                spacing: root._navRowGap
                                opacity: _grp.expanded ? 1 : 0

                                MotionBehavior on opacity {
                                    NumberAnimation {
                                        duration: Motion.fast
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: _grp.expanded
                                            ? Motion.standardDecel : Motion.standardAccel
                                    }
                                }

                                Repeater {
                                    id: _leafRepeater
                                    model: _grp.expanded || _leafBox.height > 0.5
                                        ? _grp.leaves : []

                                    delegate: Rectangle {
                                        id: _leaf

                                        required property var modelData
                                        readonly property bool active: MenuState.settingsSection === modelData.section
                                        readonly property string glyph: modelData.glyph ?? ""
                                        readonly property bool showDot: ShellSettings.settingsNavDots
                                            && ShellSettings.modifiedSections[modelData.section] === true
                                        width: _leafColumn.width
                                        height: root._navRowH
                                        radius: Theme.radiusInline
                                        antialiasing: true
                                        // the gliding selection underneath carries the resting fill and outline
                                        color: _leaf.active
                                            ? Theme.withAlpha(Theme.accent,
                                                _leafTap.pressed ? 0.09
                                                    : _leafHover.hovered ? 0.04 : 0)
                                            : _leafTap.pressed
                                                ? Theme.withAlpha(Theme.accent, 0.12)
                                            : _leafHover.hovered
                                                ? Theme.withAlpha(Theme.text, 0.042)
                                                : "transparent"

                                        Accessible.role: Accessible.PageTab
                                        Accessible.name: _leaf.modelData.label
                                        Accessible.focusable: true
                                        Accessible.selected: _leaf.active
                                        Accessible.onPressAction: root._activateSection(
                                            _leaf.modelData.section)

                                        HoverHandler {
                                            id: _leafHover
                                            cursorShape: Qt.PointingHandCursor
                                        }
                                        TapHandler {
                                            id: _leafTap
                                            onTapped: {
                                                root._activateSection(_leaf.modelData.section)
                                            }
                                        }

                                        ColorFade on color {}

                                        ShellText {
                                            id: _leafGlyph
                                            visible: !root.compact
                                            anchors.left: parent.left
                                            anchors.leftMargin: 9
                                            anchors.verticalCenter: parent.verticalCenter
                                            // the rail cap is fixed while the label grows with uiScale, so the
                                            // slot beside it has to give the type its width back
                                            width: Metrics.iconCellFor(Settings.fontLabel)
                                            horizontalAlignment: Text.AlignHCenter
                                            text: _leaf.glyph
                                            color: _leaf.active
                                                ? Theme.mix(Theme.accent, Theme.text, 0.10)
                                                : Theme.withAlpha(Theme.subtext,
                                                    _leafHover.hovered ? 0.92 : 0.76)
                                            font.pixelSize: Settings.fontLabel
                                            ColorFade on color {}
                                        }

                                        // 4px on a 7/5 inset: the rail is a fixed 160 and the dot
                                        // eats the label's budget, which "Notifications" fills
                                        Rectangle {
                                            id: _leafDot
                                            visible: _leaf.showDot
                                            anchors.right: parent.right
                                            anchors.rightMargin: 7
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 4; height: 4; radius: 2
                                            antialiasing: true
                                            color: Theme.withAlpha(Theme.accent,
                                                _leaf.active ? 0.92 : 0.66)
                                            ColorFade on color {}
                                        }

                                        ShellText {
                                            anchors.left: _leafGlyph.visible ? _leafGlyph.right : parent.left
                                            anchors.leftMargin: _leafGlyph.visible ? 7 : 12
                                            anchors.right: _leafDot.visible ? _leafDot.left : parent.right
                                            anchors.rightMargin: _leafDot.visible ? 5 : 6
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: _leaf.modelData.label
                                            elide: Text.ElideRight
                                            color: _leaf.active
                                                ? Theme.text
                                                : Theme.withAlpha(Theme.mix(Theme.subtext, Theme.text, 0.12),
                                                    _leafHover.hovered ? 1.0 : 0.90)
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

    ListEdgeLines {
        anchors.fill: _navScroll
        z: 2
        list: _navScroll
        maxOpacity: 0.72
    }
}
