pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../../common"
import "../controls"

PageShell {
    id: root

    implicitHeight: _detail.height
    enterFade: 145; exitFade: 110

    property string _shownSection: MenuState.settingsSection
    property int _sectionDir: 1

    function _settleSection(): void {
        _detailSwap.stop()
        root._shownSection = MenuState.settingsSection
        _detail.opacity = 1
        _detail._shift = 0
    }

    onPageHidden: root._settleSection()
    onPowerOpenChanged: {
        if (root.powerOpen) root._settleSection()
    }

    readonly property var _sectionComponents: ({
        theme: _secTheme, nightlight: _secNightLight, surface: _secSurface,
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
        let index = 0
        for (let i = 0; i < tree.length; i++) {
            const it = tree[i]
            if (it.children) {
                for (let j = 0; j < it.children.length; j++) {
                    const c = it.children[j]
                    m[c.section] = {
                        glyph: c.glyph,
                        label: c.label,
                        group: it.label,
                        description: c.description ?? "",
                        index: index++
                    }
                }
            } else {
                m[it.section] = {
                    glyph: it.glyph,
                    label: it.label,
                    group: "Settings",
                    description: it.description ?? "",
                    index: index++
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
        transform: Translate { x: _detail._shift }

        readonly property int _bodyGap: 8

        Connections {
            target: MenuState
            function onSettingsSectionChanged() {
                if (!root.active || root.powerOpen || ShellSettings.reduceMotion) {
                    root._settleSection()
                    return
                }
                const current = root._sectionMeta[root._shownSection]?.index ?? 0
                const next = root._sectionMeta[MenuState.settingsSection]?.index ?? current
                root._sectionDir = next < current ? -1 : 1
                _detailSwap.restart()
            }
        }

        SequentialAnimation {
            id: _detailSwap
            ParallelAnimation {
                NumberAnimation { target: _detail; property: "opacity"; to: 0.0; duration: Motion.pageOut; easing.type: Easing.InCubic }
                NumberAnimation { target: _detail; property: "_shift"; to: -root._sectionDir * 6; duration: Motion.pageOut; easing.type: Easing.InCubic }
            }
            ScriptAction {
                script: {
                    root._shownSection = MenuState.settingsSection
                    _detail._shift = root._sectionDir * Motion.pageOffset
                }
            }
            ParallelAnimation {
                NumberAnimation { target: _detail; property: "opacity"; to: 1.0; duration: Motion.pageIn; easing.type: Easing.OutCubic }
                NumberAnimation { target: _detail; property: "_shift"; to: 0.0; duration: Motion.pageIn; easing.type: Easing.OutQuart }
            }
        }

        Item {
            id: _detailHeader
            width: parent.width
            // derive from text metrics: reading the anchored children's y fed parent.height back into the anchor solver and looped
            readonly property real _iconTop: 1 + _hdrPath.implicitHeight + 6
            readonly property real _titleTop: _iconTop - 1
            readonly property real _descriptionBottom: _titleTop
                + _hdrTitle.implicitHeight + 2 + _hdrDescription.implicitHeight
            readonly property real _mainBottom: Math.max(
                _iconTop + Math.max(34, _hdrIcon.implicitHeight + 6),
                _descriptionBottom)
            readonly property real _contentBottom: _hdrError.visible
                ? _descriptionBottom + 4 + _hdrError.implicitHeight
                : _mainBottom
            height: 4 * Math.ceil((_contentBottom + 4) / 4)
            readonly property var _meta: root._sectionMeta[root._shownSection]
                ?? ({ glyph: "", label: "", group: "Settings", description: "", index: 0 })

            ShellText {
                id: _hdrPath
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 1
                text: _detailHeader._meta.group
                color: Theme.withAlpha(Theme.accent, 0.76)
                font.pixelSize: Math.max(8, Settings.fontSize - 3)
                font.letterSpacing: 0.55
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                elide: Text.ElideRight
            }
            Item {
                id: _hdrIconSlot
                anchors.left: parent.left
                anchors.top: _hdrPath.bottom
                anchors.topMargin: 6
                width: 22
                height: Math.max(34, _hdrIcon.implicitHeight + 6)

                ShellText {
                    id: _hdrIcon
                    anchors.centerIn: parent
                    text: _detailHeader._meta.glyph
                    color: Theme.withAlpha(Theme.accent, 0.82)
                    font.pixelSize: Settings.fontSize + 2
                }
            }
            ShellText {
                id: _hdrTitle
                anchors.left: _hdrIconSlot.right
                anchors.leftMargin: 7
                anchors.right: parent.right
                anchors.top: _hdrIconSlot.top
                anchors.topMargin: -1
                text: _detailHeader._meta.label
                color: Theme.text
                font.pixelSize: Settings.fontSize + 3
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            ShellText {
                id: _hdrDescription
                anchors.left: _hdrTitle.left
                anchors.right: parent.right
                anchors.top: _hdrTitle.bottom
                anchors.topMargin: 2
                text: _detailHeader._meta.description
                color: Theme.withAlpha(Theme.subtext, 0.58)
                font.pixelSize: Math.max(8, Settings.fontSize - 2)
                elide: Text.ElideRight
            }
            ShellText {
                id: _hdrError
                visible: ShellSettings.settingsError.length > 0
                anchors.left: _hdrTitle.left
                anchors.right: parent.right
                anchors.top: _hdrDescription.bottom
                anchors.topMargin: 4
                text: ShellSettings.settingsError
                color: Theme.warning
                font.pixelSize: Math.max(8, Settings.fontSize - 3)
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
            id: _secNightLight
            SettingsNightLightSection {}
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
