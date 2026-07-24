pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

PageShell {
    id: root

    implicitHeight: _detail.height
    enterFade: 145; exitFade: 110

    // lags behind MenuState.settingsSection during the swap; detail pane renders whichever section this points at
    property string _shownSection: MenuState.settingsSection

    readonly property var _sectionComponents: ({
        theme: _secTheme, nightlight: _secNightLight, surface: _secSurface,
        separators: _secSeparators, underline: _secUnderline, clock: _secClock,
        workspaces: _secWorkspaces, media: _secMedia, indicators: _secIndicators,
        widgets: _secWidgets,
        popups: _secPopups, osd: _secOsd, warnings: _secWarnings,
        updates: _secUpdates, system: _secSystem
    })

    // section id → { glyph, label, group, description, index }, for the detail-pane header
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

        readonly property int _bodyGap: 8

        Connections {
            target: MenuState
            function onSettingsSectionChanged() {
                if (ShellSettings.reduceMotion) {
                    root._shownSection = MenuState.settingsSection
                    _detail.opacity = 1
                    return
                }
                if (!_detailSwap.running) _detailSwap.restart()
            }
        }

        SequentialAnimation {
            id: _detailSwap
            NumberAnimation { target: _detail; property: "opacity"; to: 0.0; duration: Motion.ms(55); easing.type: Easing.InCubic }
            ScriptAction    { script: root._shownSection = MenuState.settingsSection }
            NumberAnimation { target: _detail; property: "opacity"; to: 1.0; duration: Motion.ms(105); easing.type: Easing.OutCubic }
            ScriptAction { script: if (root._shownSection !== MenuState.settingsSection) _detailSwapAgain.restart() }
        }
        Timer {
            id: _detailSwapAgain
            interval: 0
            onTriggered: if (!ShellSettings.reduceMotion && root._shownSection !== MenuState.settingsSection) _detailSwap.restart()
        }

        Item {
            id: _detailHeader
            width: parent.width
            height: 58
            readonly property var _meta: root._sectionMeta[root._shownSection]
                ?? ({ glyph: "", label: "", group: "Settings", description: "", index: 0 })

            Text {
                id: _hdrPath
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 1
                text: _detailHeader._meta.group
                color: Theme.withAlpha(Theme.accent, 0.76)
                font.family: Settings.font
                font.pixelSize: Math.max(8, Settings.fontSize - 3)
                font.letterSpacing: 0.55
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                renderType: Text.NativeRendering
                elide: Text.ElideRight
            }
            Item {
                id: _hdrIconSlot
                anchors.left: parent.left
                anchors.top: _hdrPath.bottom
                anchors.topMargin: 6
                width: 22
                height: 34

                Text {
                    anchors.centerIn: parent
                    text: _detailHeader._meta.glyph
                    color: Theme.withAlpha(Theme.accent, 0.82)
                    font.family: Settings.font
                    font.pixelSize: Settings.fontSize + 2
                    renderType: Text.NativeRendering
                }
            }
            Text {
                id: _hdrTitle
                anchors.left: _hdrIconSlot.right
                anchors.leftMargin: 7
                anchors.right: parent.right
                anchors.top: _hdrIconSlot.top
                anchors.topMargin: -1
                text: _detailHeader._meta.label
                color: Theme.text
                font.family: Settings.font
                font.pixelSize: Settings.fontSize + 3
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
                elide: Text.ElideRight
            }
            Text {
                anchors.left: _hdrTitle.left
                anchors.right: parent.right
                anchors.top: _hdrTitle.bottom
                anchors.topMargin: 2
                text: _detailHeader._meta.description
                color: Theme.withAlpha(Theme.subtext, 0.58)
                font.family: Settings.font
                font.pixelSize: Math.max(8, Settings.fontSize - 2)
                renderType: Text.NativeRendering
                elide: Text.ElideRight
            }
        }

        // one loader for all sections: only the visible one exists, swapped while the pane sits at opacity 0
        Loader {
            id: _detailBody
            y:      _detailHeader.height + _detail._bodyGap
            width:  parent.width
            height: item ? item.implicitHeight : 0
            sourceComponent: root._sectionComponents[root._shownSection] ?? _secSystem

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
            id: _secSystem
            SettingsSystemSection {}
        }

        Component {
            id: _secUpdates
            SettingsUpdatesSection {
                animationActive: root.active && root._shownSection === "updates"
                    && !root.powerOpen && !Idle.isIdle
            }
        }
        }   // _detailBody
    }
}
