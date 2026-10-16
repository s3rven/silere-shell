pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../../common"
import "../controls"

Column {
    id: root

    property bool shown: true
    property bool expanded: false
    property alias query: _input.text
    readonly property bool searching: root.expanded && root.query.trim().length > 0
    readonly property bool _canSearch: root.shown && root.enabled && root.visible
    readonly property var results: root.searching && root._canSearch
        ? MenuState.searchSettings(root.query) : []
    readonly property int fieldHeight: Metrics.rowHeightFor(36)
    readonly property int toggleHeight: Metrics.rowHeightFor(28)
    readonly property string resultSummary: root.results.length === 1 ? "1 section · Enter to open"
        : root.results.length + " sections" + (root.results.length > 4 ? " · Scroll for more" : "")
    property bool _hintReady: false
    signal expanding()
    signal sectionChosen(string section, string key)

    width: parent ? parent.width : 0
    spacing: root.searching ? 8 : 0

    function clearQuery(): void {
        root.query = ""
        _input.focus = false
    }
    function focusSearch(): void {
        if (!root._canSearch) return
        root._expand()
        _input.forceActiveFocus()
        _input.selectAll()
    }
    function _expand(): void {
        if (root.expanded) return
        root.expanding()
        root.expanded = true
    }
    function closeSearch(): void {
        root.expanded = false
        root.clearQuery()
    }
    function dismissInline(): bool {
        if (!root.expanded) return false
        root.closeSearch()
        return true
    }
    function choose(section: string): void {
        const row = root._canSearch ? root.results.find(r => r.section === section) : undefined
        if (!row) return
        const key = row.key || ""
        root.closeSearch()
        root.sectionChosen(section, key)
    }
    function submit(): void {
        if (root._canSearch && root.results.length === 1) root.choose(root.results[0].section)
    }
    onShownChanged: if (!shown) root.closeSearch()
    onEnabledChanged: if (!enabled) root.closeSearch()
    onVisibleChanged: if (!visible) root.closeSearch()
    onExpandedChanged: if (!expanded) root.clearQuery()
    onQueryChanged: {
        _results.cancelFlick()
        if (root.query.trim().length > 0 && root._canSearch) root._expand()
    }
    Connections {
        target: MenuState
        function onSettingsSectionRequested() { root.closeSearch() }
    }

    Item {
        id: _toolbar
        width: root.width
        height: root.expanded ? root.fieldHeight : root.toggleHeight
        IconButton {
            id: _toggle
            z: 2
            anchors.right: parent.right
            visible: !root.expanded
            enabled: root._canSearch
            buttonSize: root.toggleHeight
            glyph: "󰍉"
            accessibleName: "Search settings"
            Accessible.description: "Open settings search (Ctrl+F)"
            onTriggered: root.focusSearch()
            HoverHandler {
                id: _hintHover
                enabled: root._canSearch && !root.expanded
                onHoveredChanged: {
                    root._hintReady = false
                    if (hovered) _hintDelay.restart()
                    else _hintDelay.stop()
                }
            }
            Timer { id: _hintDelay; interval: 500; onTriggered: root._hintReady = _hintHover.hovered }
            // the rail's label pill, dropped below instead of beside
            Rectangle {
                id: _hint
                readonly property bool _show: root._hintReady && _hintHover.hovered && root._canSearch && !root.expanded
                anchors.top: parent.bottom
                anchors.topMargin: 5
                anchors.right: parent.right
                width: Math.min(root.width, _hintLabel.implicitWidth + 18)
                height: 22
                radius: Theme.radiusInline
                antialiasing: true
                color: Theme.menuCardSolid
                opacity: _show ? 1.0 : 0.0
                scale: _show ? 1.0 : 0.96
                transformOrigin: Item.TopRight
                property real _slide: _show ? 0 : -3
                transform: Translate { y: _hint._slide }
                visible: opacity > 0.01
                z: 20
                MotionBehavior on opacity {
                    id: _hintFade
                    NumberAnimation { duration: _hintFade.targetValue > 0.5 ? Motion.fast : Motion.instant; easing.type: Easing.OutCubic }
                }
                MotionBehavior on scale {
                    id: _hintScale
                    NumberAnimation { duration: _hintScale.targetValue >= 1 ? Motion.fast : Motion.instant; easing.type: Easing.OutCubic }
                }
                MotionBehavior on _slide {
                    id: _hintSlide
                    NumberAnimation { duration: _hintSlide.targetValue >= 0 ? Motion.fast : Motion.instant; easing.type: Easing.OutCubic }
                }
                OutlineBorder { radius: _hint.radius; outlineColor: Theme.menuCardBorder }
                ShellText {
                    id: _hintLabel
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, Math.max(0, parent.width - 18))
                    text: "Search settings · Ctrl+F"
                    color: Theme.withAlpha(Theme.text, 0.78)
                    font.pixelSize: Settings.fontLabel
                    elide: Text.ElideRight
                }
            }
        }
        Item {
            id: _fieldViewport
            anchors.right: parent.right
            width: root.expanded ? root.width : root.toggleHeight
            height: parent.height
            visible: root.expanded || width > root.toggleHeight + 0.5
            enabled: root.expanded
            MotionBehavior on width {
                gate: root.shown && root.visible
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }
            // the capsule grows out of the round toggle, so its leading edge stays round through the reveal
            Rectangle {
                id: _fieldFace
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: root.expanded ? root.fieldHeight : root.toggleHeight
                radius: height / 2
                antialiasing: true
                color: Theme.menuControl
                MotionBehavior on height {
                    gate: root.shown && root.visible
                    NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
                }
                OutlineBorder {
                    radius: _fieldFace.radius
                    outlineWidth: 1
                    outlineColor: _input.activeFocus
                        ? Theme.withAlpha(Theme.accent, Theme.focusRingSoftAlpha) : Theme.menuControlLine
                    ColorFade on outlineColor {}
                }
            }
            // rides the leading edge: the toggle's glyph slides into place instead of being uncovered
            ShellText {
                x: (Math.min(parent.width, root.fieldHeight) - implicitWidth) / 2
                anchors.verticalCenter: parent.verticalCenter
                text: "󰍉"
                color: _input.activeFocus ? Theme.accent : Theme.menuTextDetail
                font.pixelSize: Settings.fontSize + 2
                ColorFade on color {}
            }
            Item {
                id: _fieldClip
                // starts past the glyph so the text slides out from behind it
                x: Math.min(parent.width, root.fieldHeight) - 4
                width: Math.max(0, parent.width - x)
                height: parent.height
                clip: true
                Item {
                    id: _field
                    // input and actions keep their full geometry from the first frame, including rapid typing after opening; only the reveal moves
                    x: _fieldViewport.width - width - _fieldClip.x
                    width: root.width
                    height: parent.height
                    TextInput {
                        id: _input
                        x: root.fieldHeight - 2
                        width: Math.max(0, (_clear.visible ? _clear.x : _close.x) - x - 4)
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.expanded
                        enabled: root._canSearch && root.expanded
                        maximumLength: 256
                        selectByMouse: true
                        clip: true
                        color: Theme.text
                        selectionColor: Theme.withAlpha(Theme.accent, 0.4)
                        font.family: Settings.font
                        font.pixelSize: Settings.fontSize
                        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        Accessible.name: "Search settings"
                        Accessible.description: root.searching ? root.resultSummary : "Search by feature name or setting key"
                        onAccepted: root.submit()
                        Keys.onEscapePressed: event => {
                            event.accepted = root.dismissInline()
                            if (!event.accepted) _input.focus = false
                        }
                        ShellText {
                            anchors.fill: parent
                            visible: _input.text.length === 0
                            text: "Find a setting…"
                            color: Theme.menuTextDetail
                            font.pixelSize: Settings.fontSize
                            elide: Text.ElideRight
                        }
                    }
                    IconButton {
                        id: _clear
                        anchors.right: _close.left
                        anchors.rightMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.searching
                        enabled: root._canSearch
                        buttonSize: root.toggleHeight
                        glyph: "󰅖"
                        accessibleName: "Clear settings query"
                        onTriggered: { root.clearQuery(); root.focusSearch() }
                    }
                    IconButton {
                        id: _close
                        anchors.right: parent.right
                        anchors.rightMargin: (root.fieldHeight - root.toggleHeight) / 2
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.expanded
                        buttonSize: root.toggleHeight
                        glyph: "󰅃"
                        accessibleName: "Close settings search"
                        onTriggered: root.closeSearch()
                    }
                }
            }
        }
    }

    ShellText {
        visible: root.searching && root.results.length > 0
        width: parent.width
        text: root.resultSummary
        color: Theme.menuTextDetail
        font.pixelSize: Settings.fontCaption
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
    }

    Rectangle {
        visible: root.searching && root.results.length === 0
        width: parent.width
        height: _emptyHint.implicitHeight + 28
        radius: Theme.radiusCard
        color: Theme.menuCard
        OutlineBorder { radius: parent.radius; outlineColor: Theme.menuCardBorder }
        ShellText {
            id: _emptyHint
            x: 14; y: 14
            width: Math.max(0, parent.width - 28)
            text: "No matching settings. Try a feature name."
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            color: Theme.menuTextDetail
            font.pixelSize: Settings.fontCaption
        }
    }

    Rectangle {
        width: parent.width
        height: Math.min(_results.count, 4) * Metrics.rowHeightFor(48) + 8
        visible: root.searching && _results.count > 0
        radius: Theme.radiusCard
        color: Theme.menuCard
        OutlineBorder { radius: parent.radius; outlineColor: Theme.menuCardBorder; z: 2 }
        // inset by the gap between card and row radius so each hover pill sits concentric in the card
        ShellListView {
            id: _results
            x: 4; y: 4
            width: Math.max(0, parent.width - 8)
            height: Math.max(0, parent.height - 8)
            model: root.results
            interactive: contentHeight > height
            delegate: ControlRow {
                required property var modelData
                width: _results.width
                topRadius: Theme.radiusInline
                bottomRadius: Theme.radiusInline
                cardInset: 0
                glyph: modelData.glyph
                title: modelData.label
                status: modelData.keyLabel.length > 0
                    ? modelData.group + " · " + modelData.keyLabel : modelData.group
                active: modelData.section === MenuState.settingsSection
                valueText: active ? "Current" : ""
                Accessible.description: status + (active ? " · Current section" : "")
                enabled: root._canSearch
                onActivated: root.choose(modelData.section)
            }
        }
        ListEdgeLines { x: 14; y: _results.y; width: Math.max(0, parent.width - 28); height: _results.height; list: _results }
    }
}
