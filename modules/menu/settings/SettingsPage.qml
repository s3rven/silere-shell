pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../../common"
import "../controls"

PageShell {
    id: root

    implicitHeight: _detail.height

    property string _shownSection: MenuState.settingsSection
    // assigned once to drop the binding: live, it swaps the section the instant MenuState changes,
    // so the first transition fades out content that was already replaced
    Component.onCompleted: root._shownSection = MenuState.settingsSection
    property bool _awaitingSectionEnter: false
    signal sectionSwapped()

    function _settleSection(): void {
        _detailSwap.stop()
        _detailEnter.stop()
        _sectionEnterDefer.stop()
        root._awaitingSectionEnter = false
        const changed = root._shownSection !== MenuState.settingsSection
        root._shownSection = MenuState.settingsSection
        _detail.opacity = 1
        _detail._shift = 0
        if (changed) root.sectionSwapped()
    }

    onPageHidden: root._settleSection()
    onPowerOpenChanged: {
        if (root.powerOpen) root._settleSection()
    }

    Connections {
        target: ShellSettings
        function onReduceMotionChanged() {
            if (ShellSettings.reduceMotion) root._settleSection()
        }
    }

    readonly property var _sectionComponents: ({
        theme: _secTheme, surface: _secSurface,
        separators: _secSeparators, underline: _secUnderline, clock: _secClock,
        workspaces: _secWorkspaces, media: _secMedia, indicators: _secIndicators,
        widgets: _secWidgets,
        popups: _secPopups, osd: _secOsd, warnings: _secWarnings,
        interface: _secInterface, updates: _secUpdates,
        maintenance: _secMaintenance
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

    // outlives the section component, which is destroyed whenever the user navigates away
    property string _lastUnderlineStyle:
        ShellSettings.underlineGlow ? "glow" : "static"

    Item {
        id: _detail
        width:  root.width
        height: _detailHeader.height + _bodyGap + _detailBody.height
        property real _shift: 0
        transform: Translate { y: _detail._shift }

        readonly property int _bodyGap: 8

        Connections {
            target: MenuState
            function onSettingsSectionChanged() {
                if (!root.active || root.powerOpen || ShellSettings.reduceMotion) {
                    root._settleSection()
                    return
                }
                root._awaitingSectionEnter = false
                _sectionEnterDefer.stop()
                _detailEnter.stop()
                _detailSwap.restart()
            }
        }

        SequentialAnimation {
            id: _detailSwap
            NumberAnimation { target: _detail; property: "opacity"; to: 0.0; duration: Motion.pageOut; easing.type: Easing.InCubic }
            ScriptAction {
                script: {
                    root._awaitingSectionEnter = true
                    root._shownSection = MenuState.settingsSection
                    _detail._shift = Motion.pageOffset
                    root.sectionSwapped()
                    _sectionEnterDefer.restart()
                }
            }
        }

        Timer {
            id: _sectionEnterDefer
            interval: 0
            onTriggered: {
                if (!root._awaitingSectionEnter) return
                root._awaitingSectionEnter = false
                if (!root.active || root.powerOpen || ShellSettings.reduceMotion) {
                    _detail.opacity = 1
                    _detail._shift = 0
                    return
                }
                _detailEnter.restart()
            }
        }

        ParallelAnimation {
            id: _detailEnter
            NumberAnimation { target: _detail; property: "opacity"; to: 1.0; duration: Motion.pageIn; easing.type: Easing.OutCubic }
            NumberAnimation { target: _detail; property: "_shift"; to: 0.0; duration: Motion.pageIn; easing.type: Easing.OutQuart }
        }

        Item {
            id: _detailHeader
            width: parent.width
            readonly property real _mainH: Math.max(30, _hdrText.implicitHeight)
            readonly property real _contentBottom: _hdrError.visible
                ? _mainH + 4 + _hdrError.implicitHeight
                : _mainH
            height: 4 * Math.ceil((_contentBottom + 4) / 4)
            readonly property var _meta: root._sectionMeta[root._shownSection]
                ?? ({ glyph: "", label: "", description: "" })

            Item {
                id: _hdrIconSlot
                anchors.left: parent.left
                anchors.verticalCenter: _hdrText.verticalCenter
                width: 22
                height: 22

                ShellText {
                    id: _hdrIcon
                    anchors.centerIn: parent
                    text: _detailHeader._meta.glyph
                    color: Theme.withAlpha(Theme.accent, 0.82)
                    font.pixelSize: Settings.fontSize + 2
                }
            }

            Column {
                id: _hdrText
                anchors.left: _hdrIconSlot.right
                anchors.leftMargin: 7
                anchors.right: parent.right
                y: Math.round((_detailHeader._mainH - implicitHeight) / 2)
                height: implicitHeight
                spacing: 1

                ShellText {
                    id: _hdrTitle
                    width: parent.width
                    text: _detailHeader._meta.label
                    color: Theme.text
                    font.pixelSize: Settings.fontSize + 3
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Accessible.description: _detailHeader._meta.description
                }

                ShellText {
                    width: parent.width
                    visible: _detailHeader._meta.description.length > 0
                    text: _detailHeader._meta.description
                    color: Theme.withAlpha(Theme.subtext, 0.62)
                    font.pixelSize: Settings.fontCaption
                    elide: Text.ElideRight
                }
            }

            ShellText {
                id: _hdrError
                visible: ShellSettings.settingsError.length > 0
                anchors.left: _hdrText.left
                anchors.right: parent.right
                y: _detailHeader._mainH + 4
                text: ShellSettings.settingsError
                color: Theme.warning
                font.pixelSize: Settings.fontMicro
                elide: Text.ElideRight
                Accessible.role: Accessible.StaticText
                Accessible.name: "Configuration warning: " + text
            }
        }

        Loader {
            id: _detailBody
            y:      _detailHeader.height + _detail._bodyGap
            width:  parent.width
            height: item ? item.implicitHeight : 0
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
            SettingsUnderlineSection {
                lastStyle: root._lastUnderlineStyle
                onStyleRemembered: (style) => root._lastUnderlineStyle = style
            }
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

                DraggableWidgetList { width: parent.width }
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
            id: _secUpdates
            SettingsUpdatesSection {
                animationActive: root.active && root._shownSection === "updates"
                    && !root.powerOpen && !Idle.isIdle
            }
        }

        Component {
            id: _secMaintenance
            SettingsMaintenanceSection {}
        }
    }
}
