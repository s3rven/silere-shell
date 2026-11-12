pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../config"
import "../../../services"
import "../../common"
import "../controls"

PageShell {
    id: root

    implicitHeight: _search.expanded ? Math.max(root._searchHeldHeight, _search.height,
        _search.searching ? 0 : _detail.height)
        : _detail.height
    property real _searchHeldHeight: 0
    // the outer SettingsPage can be Loader.Ready while its asynchronous section
    // body is still incubating. MenuWindow uses this to avoid sizing to that
    // short-lived header-only state during a tab transition
    readonly property bool contentReady: _detailBody.status === Loader.Ready
        || _detailBody.status === Loader.Error
    readonly property bool contentError: _detailBody.status === Loader.Error
    revealReady: contentReady

    // the arranger scrolls this while a row is dragged past the viewport edge
    property Flickable scroller: root._pageLoader?.scroller ?? null
    // keep the search field in view while results own scrolling. Restore the scroller's original binding when the query clears or this page leaves
    Binding {
        target: root.scroller
        property: "interactive"
        value: false
        when: root.active && _search.searching && root.scroller !== null
        restoreMode: Binding.RestoreBindingOrValue
    }

    property string _shownSection: MenuState.settingsSection
    // assigned once to drop the binding: live, it swaps the section the instant MenuState changes,
    // so the first transition fades out content that was already replaced
    Component.onCompleted: root._shownSection = MenuState.settingsSection
    property bool _awaitingSectionEnter: false
    property int _sectionDirection: 1
    signal sectionSwapped()

    function dismissInline(): bool {
        if (MenuState.settingsSelectOpen) {
            MenuState.closeSettingsSelect()
            return true
        }
        return _search.dismissInline()
    }

    SettingsSearch {
        id: _search
        width: root.width
        y: expanded ? 0 : Math.max(0, (_detailHeader._mainH - toggleHeight) / 2)
        // centred on the title, so its outline lands wherever the title's line height puts it
        readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
        transform: PixelSnap { item: _search; dpr: _search._dpr }
        z: 10
        shown: root.active && MenuState.settingsActive && !root.powerOpen
        onExpanding: {
            root._searchHeldHeight = _detail.height
            MenuState.closeSettingsSelect()
        }
        onSearchingChanged: if (searching) {
            root._searchHeldHeight = Math.max(root._searchHeldHeight, _detail.height)
            MenuState.closeSettingsSelect()
            if (root.scroller) {
                root.scroller.cancelFlick()
                root.scroller.contentY = root.scroller.originY
            }
        }
        onSectionChosen: (section, key) => {
            root._revealSection = section
            root._revealKey = key
            const stay = section === root._shownSection && key !== ""
            MenuState.setSettingsSection(section)
            if (root.scroller && !stay) {
                root.scroller.cancelFlick()
                root.scroller.contentY = root.scroller.originY
            }
            _revealDelay.restart()
        }
    }
    Shortcut {
        sequence: "Ctrl+F"
        context: Qt.ApplicationShortcut
        enabled: _search.shown
        onActivated: {
            if (root.scroller) {
                root.scroller.cancelFlick()
                root.scroller.contentY = root.scroller.originY
            }
            _search.focusSearch()
        }
    }

    property string _revealSection: ""
    property string _revealKey: ""

    // the loader reports Ready before its columns have laid out, so rows still read y 0
    Timer {
        id: _revealDelay
        interval: 60
        onTriggered: root._revealPending()
    }

    function _shownWithin(item, top): bool {
        for (let it = item; it && it !== top; it = it.parent)
            if (!it.visible || it.height < 1 || it.opacity < 0.01) return false
        return true
    }

    function _keyRow(top, key: string): var {
        const stack = [top]
        while (stack.length > 0) {
            const it = stack.pop()
            if (it !== top && it.key === key && it.topRadius !== undefined) return it
            const kids = it.children || []
            for (let i = kids.length - 1; i >= 0; i--) stack.push(kids[i])
        }
        return null
    }

    function revealRowFor(section: string, key: string): string {
        const gates = ShellSettings._sectionGates[section] || []
        for (let i = 0; i < gates.length; i++)
            if (gates[i].hides.indexOf(key) >= 0) return gates[i].master ?? gates[i].any[0].master
        return ""
    }

    function _revealPending(): void {
        const top = _detailBody.item
        if (root._revealKey === "" || root._revealSection !== root._shownSection
                || !root.contentReady || !top || !root.scroller) return
        let key = root._revealKey
        root._revealKey = ""
        let row = root._keyRow(top, key)
        for (let hops = 0; hops < 3 && (!row || !root._shownWithin(row, top)); hops++) {
            key = root.revealRowFor(root._revealSection, key)
            row = key.length > 0 ? root._keyRow(top, key) : null
        }
        if (!row || !root._shownWithin(row, top)) return
        root.scroller.cancelFlick()
        root._revealY = row.mapToItem(root.scroller.contentItem, 0, 0).y - root.scroller.height / 3
        _revealHold.restart()
        root._applyRevealY()
        const flash = _revealFlash.createObject(row, {
            topRadius: row.topRadius, bottomRadius: row.bottomRadius, cardInset: row.cardInset
        })
        if (flash) flash.light()
    }

    // the pane is still growing into the new section, so a target clamped now falls short
    property real _revealY: -1
    function _applyRevealY(): void {
        const s = root.scroller
        if (root._revealY < 0 || !s) return
        if (s.dragging || s.flicking) {
            root._revealY = -1
            return
        }
        const maxY = Math.max(s.originY, s.originY + s.contentHeight - s.height)
        s.contentY = Math.max(s.originY, Math.min(maxY, root._revealY))
    }
    Timer { id: _revealHold; interval: 500; onTriggered: root._revealY = -1 }
    Connections {
        target: root._revealY >= 0 ? root.scroller : null
        function onContentHeightChanged() { root._applyRevealY() }
        function onHeightChanged() { root._applyRevealY() }
        function onDraggingChanged() { root._revealY = -1 }
    }

    Component {
        id: _revealFlash
        RowHoverBg {
            id: _flash
            anchors.fill: parent
            z: -1
            fillColor: Theme.accent
            fillOpacity: 0.14
            function light(): void {
                _flash.active = true
                _hold.start()
            }
            Timer { id: _hold; interval: 1100; onTriggered: { _flash.active = false; _drop.start() } }
            Timer { id: _drop; interval: Motion.hoverOut + 200; onTriggered: _flash.destroy() }
        }
    }

    function _holdBodyHeight(): void {
        _detailBody._heldH = _detailBody.height
    }

    function _settleSection(): void {
        _detailSwap.stop()
        _detailEnter.stop()
        _sectionEnterDefer.stop()
        root._awaitingSectionEnter = false
        const changed = root._shownSection !== MenuState.settingsSection
        if (changed) root._holdBodyHeight()
        root._shownSection = MenuState.settingsSection
        _detail.opacity = 1
        _detail._shift = 0
        _detail._lift = 0
        if (changed) root.sectionSwapped()
    }

    function _pauseSectionVisual(): void {
        _detailSwap.stop()
        _detailEnter.stop()
        _sectionEnterDefer.stop()
        root._awaitingSectionEnter = false
        // keep the current opacity/offset while PageShell fades the whole page; restoring full opacity here produces a flash during a fast tab switch
    }

    onPageHidden: {
        root._revealKey = ""
        root._pauseSectionVisual()
    }
    onPageShown: root._settleSection()
    onPowerOpenChanged: {
        if (root.powerOpen) root._settleSection()
    }

    Connections {
        target: root
        function on_MotionAllowedChanged() {
            if (!root._motionAllowed) root._settleSection()
        }
    }

    readonly property var _sectionComponents: ({
        theme: _secTheme, surface: _secSurface,
        separators: _secSeparators, underline: _secUnderline, clock: _secClock,
        workspaces: _secWorkspaces, media: _secMedia, indicators: _secIndicators,
        widgets: _secWidgets,
        popups: _secPopups, osd: _secOsd, warnings: _secWarnings,
        interface: _secInterface, devices: _secDevices, updates: _secUpdates
    })

    readonly property var _sectionMeta: {
        const m = ({})
        const tree = MenuState.settingsTree
        for (let i = 0; i < tree.length; i++) {
            const it = tree[i]
            if (it.children) {
                for (let j = 0; j < it.children.length; j++) {
                    const c = it.children[j]
                    m[c.section] = {
                        glyph: c.glyph,
                        label: c.label,
                        description: c.description ?? ""
                    }
                }
            } else {
                m[it.section] = {
                    glyph: it.glyph,
                    label: it.label,
                    description: it.description ?? ""
                }
            }
        }
        return m
    }

    Item {
        id: _detail
        width:  root.width
        visible: !_search.searching
        height: _detailHeader.height + _bodyGap + _detailBody.height
        property real _shift: 0
        property real _lift: 0
        transform: Translate { x: _detail._shift; y: _detail._lift }
        // the outgoing controls stay painted for the exit, but must not change settings after the sidebar has selected a different section
        enabled: !_search.searching && root._shownSection === MenuState.settingsSection
            && root.contentReady && !root._awaitingSectionEnter

        readonly property int _bodyGap: 8

        Connections {
            target: MenuState
            function onSettingsSectionChanged() {
                if (MenuState.settingsSection !== root._revealSection) root._revealKey = ""
                if (!root.active || !MenuState.open || root.powerOpen || !root._motionAllowed) {
                    root._settleSection()
                    return
                }
                const sections = MenuState._flatSections
                const from = sections.indexOf(root._shownSection)
                const to = sections.indexOf(MenuState.settingsSection)
                root._sectionDirection = from >= 0 && to >= 0 && to < from ? -1 : 1
                root._awaitingSectionEnter = false
                _sectionEnterDefer.stop()
                _detailEnter.stop()
                // returning before the fade-out completed keeps the existing body and reverses its reveal instead of unloading it again
                if (root._shownSection === MenuState.settingsSection) {
                    _detailSwap.stop()
                    _detailEnter.restart()
                } else if (!_detailSwap.running) {
                    // the swap reads the latest destination when the exit ends. Keep its clock running through successive sidebar clicks
                    _detailSwap.start()
                }
            }
        }

        SequentialAnimation {
            id: _detailSwap
            ParallelAnimation {
                NumberAnimation { target: _detail; property: "opacity"; to: 0.0; duration: Motion.pageOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardAccel }
                NumberAnimation { target: _detail; property: "_shift"; to: -Motion.pageOffset * root._sectionDirection; duration: Motion.pageOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardAccel }
                NumberAnimation { target: _detail; property: "_lift"; to: -Motion.pageLift; duration: Motion.pageOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardAccel }
            }
            ScriptAction {
                script: {
                    root._awaitingSectionEnter = true
                    root._holdBodyHeight()
                    root._shownSection = MenuState.settingsSection
                    _detail._shift = Motion.pageOffset * root._sectionDirection
                    _detail._lift = Motion.pageLift
                    root.sectionSwapped()
                    _sectionEnterDefer.restart()
                }
            }
        }

        function _startSectionEnter(): void {
            if (!root._awaitingSectionEnter || !root.contentReady) return
            root._awaitingSectionEnter = false
            _sectionEnterDefer.stop()
            if (!root.active || !MenuState.open || root.powerOpen || !root._motionAllowed) {
                _detail.opacity = 1
                _detail._shift = 0
                _detail._lift = 0
                return
            }
            _detailEnter.restart()
        }

        // the incubating section still reports the outgoing height, so starting the enter before it is Ready slides content the panel is still resizing under
        Connections {
            target: _detailBody
            function onStatusChanged() {
                if (!root.contentReady) return
                _sectionEnterDefer.restart()
                if (root._revealKey !== "") _revealDelay.restart()
            }
        }

        Timer {
            id: _sectionEnterDefer
            interval: Math.abs(_detailBody.height - _detailBody._heldH) > 64
                ? Motion.ms(55) : 0
            onTriggered: _detail._startSectionEnter()
        }

        ParallelAnimation {
            id: _detailEnter
            NumberAnimation { target: _detail; property: "opacity"; to: 1.0; duration: Motion.pageIn; easing.type: Easing.OutQuad }
            NumberAnimation { target: _detail; property: "_shift"; to: 0.0; duration: Motion.pageIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
            NumberAnimation { target: _detail; property: "_lift"; to: 0.0; duration: Motion.pageIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
        }

        Item {
            id: _detailHeader
            width: parent.width
            readonly property real _mainH: _search.expanded ? _search.fieldHeight
                : Math.max(Metrics.rowHeightFor(32), _hdrText.implicitHeight, _search.toggleHeight)
            // the description hangs below the row, so the row still shares the nav title's line
            readonly property real _textBottom: _hdrDesc.visible ? _hdrDesc.y + _hdrDesc.height : _mainH
            readonly property real _contentBottom: _hdrError.visible
                ? _hdrError.y + _hdrError.height
                : _textBottom
            height: 4 * Math.ceil((_contentBottom + 4) / 4)
            readonly property var _meta: root._sectionMeta[root._shownSection]
                ?? ({ glyph: "", label: "", description: "" })

            // a tinted tile: the page's mark, quieter than the selection outline beside it
            Rectangle {
                id: _hdrIconSlot
                visible: !_search.expanded
                anchors.left: parent.left
                y: Math.round((_detailHeader._mainH - height) / 2)
                width: Metrics.rowHeightFor(28)
                height: width
                radius: Theme.radiusInline
                antialiasing: true
                color: Theme.blend(Theme.menuControl, Theme.accent,
                    ShellSettings.highContrast ? 0.24 : 0.14)

                ShellText {
                    id: _hdrIcon
                    anchors.centerIn: parent
                    text: _detailHeader._meta.glyph
                    color: Theme.mix(Theme.accent, Theme.text, 0.10)
                    font.pixelSize: Settings.fontSize + 2
                }
            }

            Column {
                id: _hdrText
                visible: !_search.expanded
                anchors.left: _hdrIconSlot.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: _search.toggleHeight + 8
                y: Math.round((_detailHeader._mainH - implicitHeight) / 2)
                height: implicitHeight
                spacing: 1

                ShellText {
                    id: _hdrTitle
                    width: parent.width
                    text: _detailHeader._meta.label
                    color: Theme.text
                    font.pixelSize: Settings.fontSize + 4
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }

            ShellText {
                id: _hdrDesc
                visible: !_search.expanded && text.length > 0
                anchors.left: _hdrText.left
                anchors.right: _hdrText.right
                y: Math.round(_hdrText.y + _hdrText.height)
                text: _detailHeader._meta.description
                color: Theme.withAlpha(Theme.subtext, 0.86)
                font.pixelSize: Settings.fontCaption
                elide: Text.ElideRight
            }

            Rectangle {
                id: _hdrError
                visible: ShellSettings.settingsError.length > 0
                x: 0
                y: Metrics.snap4(_detailHeader._textBottom + 8)
                width: parent.width
                height: Metrics.snap4Up(_errorText.implicitHeight + 16)
                radius: Theme.radiusInline
                color: Theme.withAlpha(Theme.warning, 0.08)

                OutlineBorder {
                    radius: _hdrError.radius
                    outlineColor: Theme.withAlpha(Theme.warning, 0.24)
                }

                ShellText {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.top: parent.top
                    anchors.topMargin: 8
                    text: "󰀦"
                    color: Theme.warning
                    font.pixelSize: Settings.fontCaption
                }

                ShellText {
                    id: _errorText
                    anchors.left: parent.left
                    anchors.leftMargin: 30
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.top: parent.top
                    anchors.topMargin: 8
                    text: ShellSettings.settingsError
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    color: Theme.warning
                    font.pixelSize: Settings.fontCaption
                }
            }
        }

        Loader {
            id: _detailBody
            property real _heldH: 0
            y:      _detailHeader.height + _detail._bodyGap
            width:  parent.width
            // the first section built in a session costs ~47ms of shared-control
            // compilation; hold the outgoing height so the pane cannot collapse to 0
            // while the replacement incubates
            height: item ? item.implicitHeight : _heldH
            // yield while building sections even with reduced motion, so input stays responsive
            asynchronous: true
            sourceComponent: root._sectionComponents[root._shownSection] ?? _secTheme
        }

        Component {
            id: _secTheme
            SettingsThemeSection {}
        }

        Component {
            id: _secSurface
            SettingsSurfaceSection {}
        }

        Component {
            id: _secSeparators
            SettingsSeparatorsSection {}
        }

        Component {
            id: _secUnderline
            SettingsUnderlineSection {}
        }

        Component {
            id: _secClock
            SettingsClockSection {}
        }

        Component {
            id: _secWorkspaces
            SettingsWorkspacesSection {}
        }

        Component {
            id: _secMedia
            SettingsMediaSection {}
        }

        Component {
            id: _secIndicators
            SettingsIndicatorsSection {}
        }

        Component {
            id: _secWidgets
            Column {
                width: _detailBody.width
                spacing: 0

                DraggableWidgetList { width: parent.width; scroller: root.scroller }
            }
        }

        Component {
            id: _secPopups
            SettingsPopupsSection {}
        }

        Component {
            id: _secOsd
            SettingsOsdSection {}
        }

        Component {
            id: _secWarnings
            SettingsWarningsSection {}
        }

        Component {
            id: _secInterface
            SettingsInterfaceSection {}
        }

        Component {
            id: _secDevices
            SettingsDevicesSection {}
        }

        Component {
            id: _secUpdates
            Column {
                width: _detailBody.width
                spacing: 0
                SettingsUpdatesSection {
                    animationActive: root.active && root._shownSection === "updates"
                        && !root.powerOpen && !Idle.isIdle
                }
                SettingsMaintenanceSection {
                    firstSection: false
                    animationActive: root.active && root._shownSection === "updates"
                        && !root.powerOpen && !Idle.isIdle
                }
            }
        }
    }
}
