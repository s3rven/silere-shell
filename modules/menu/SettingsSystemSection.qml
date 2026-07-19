pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../services"

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: 0

    function _fmtSettingValue(v): string {
        if (typeof v === "boolean") return v ? "on" : "off"
        if (typeof v === "number") return String(Math.round(v * 100) / 100)
        const s = String(v)
        return s.length > 0 ? s : "none"
    }

    SectionLabel { label: "HARDWARE"; first: true; visible: Brightness.devices.length > 1 }
    SettingsCard {
        visible: Brightness.devices.length > 1
        SelectRow {
            glyph: "󰃟"; label: "Brightness display"
            currentValue: Brightness.deviceChoice
            model: Brightness.deviceChoices
            onChosen: (v) => ShellSettings.brightnessDevice = v
        }
    }

    SectionLabel { label: "ACCESSIBILITY"; first: Brightness.devices.length <= 1 }
    SettingsCard {
        SelectRow {
            glyph: "󰛖"; label: "Font"
            currentValue: ShellSettings.fontFamily
            model: {
                const m = [{ value: "", label: "JetBrainsMono (default)", fontFamily: "JetBrainsMono Nerd Font" }]
                const fams = FontScan.families
                for (let i = 0; i < fams.length; i++) {
                    const f = fams[i]
                    if (f === "JetBrainsMono Nerd Font") continue
                    m.push({ value: f, label: f.replace(/ Nerd Font( Mono)?$/, ""), fontFamily: f })
                }
                const cur = ShellSettings.fontFamily
                if (cur.length > 0 && m.findIndex(e => e.value === cur) < 0)
                    m.push({ value: cur, label: cur.replace(/ Nerd Font( Mono)?$/, "") + " (not installed)" })
                return m
            }
            onChosen: (v) => ShellSettings.fontFamily = v
        }
        SelectRow {
            glyph: "󰍉"; label: "UI scale"
            currentValue: ShellSettings.uiScale
            model: [
                { value: 0.8,  label: "80%"  },
                { value: 0.9,  label: "90%"  },
                { value: 1.0,  label: "100%" },
                { value: 1.1,  label: "110%" },
                { value: 1.15, label: "115%" }
            ]
            onChosen: (v) => ShellSettings.uiScale = v
        }
        ToggleRow {
            glyph: "󰹑"; label: "High contrast"
            checked: ShellSettings.highContrast
            onToggled: ShellSettings.highContrast = !ShellSettings.highContrast
        }
        ToggleRow {
            glyph: "󱖳"; label: "Reduce motion"
            checked: ShellSettings.reduceMotion
            onToggled: ShellSettings.reduceMotion = !ShellSettings.reduceMotion
        }
    }

    Loader {
        width: parent.width
        active: Quickshell.screens.length > 1
        height: item ? item.implicitHeight : 0
        sourceComponent: Component {
            Column {
                width: parent.width
                SectionLabel { label: "MONITORS" }
                SettingsCard {
                    SelectRow {
                        glyph: "󰍹"; label: "Popups & OSD on"
                        currentValue: ShellSettings.overlayMonitor
                        model: {
                            const t = [{ value: "", label: "Focus" }]
                            const s = Quickshell.screens || []
                            for (let i = 0; i < s.length; i++) {
                                const name = s[i].name
                                t.push({ value: name, label: name })
                            }
                            return t
                        }
                        onChosen: (v) => ShellSettings.overlayMonitor = v
                    }
                    Repeater {
                        model: Quickshell.screens
                        delegate: ToggleRow {
                            required property var modelData
                            glyph: "󰍺"
                            label: "Bar on " + modelData.name
                            checked: Monitors.barEnabled(modelData)
                            onToggled: Monitors.setBarEnabled(modelData.name, !checked)
                        }
                    }
                }
            }
        }
    }

    SectionLabel { label: "CHANGES & RESET" }
    SettingsCard {
        Item {
            id: _modHeader
            property bool open: false
            property real topRadius:    0
            property real bottomRadius: 0
            visible: ShellSettings.modifiedKeys.length > 0
            width: parent ? parent.width : 0
            height: 44

            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: "Changed from defaults, " + ShellSettings.modifiedKeys.length + " settings"
            Accessible.description: open ? "Collapse" : "Expand"
            Keys.onSpacePressed:  e => { if (!e.isAutoRepeat) _modHeader.open = !_modHeader.open; e.accepted = true }
            Keys.onReturnPressed: e => { if (!e.isAutoRepeat) _modHeader.open = !_modHeader.open; e.accepted = true }
            Keys.onEnterPressed:  e => { if (!e.isAutoRepeat) _modHeader.open = !_modHeader.open; e.accepted = true }

            HoverHandler { id: _modHeadHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: _modHeader.open = !_modHeader.open }
            RowHoverBg {
                anchors.fill: parent
                topRadius:    _modHeader.topRadius
                bottomRadius: _modHeader.bottomRadius
                active:       _modHeadHover.hovered || _modHeader.activeFocus
                focusActive:  _modHeader.activeFocus
                fillOpacity:  _modHeader.activeFocus ? 0.13 : 0.08
            }

            Text {
                anchors.left: parent.left; anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                horizontalAlignment: Text.AlignHCenter
                text: "󰏫"
                color: Theme.withAlpha(Theme.subtext, 0.85)
                font.family: Settings.font; font.pixelSize: Settings.iconSize + 2
                renderType: Text.NativeRendering
            }
            Text {
                id: _modHeaderLabel
                anchors.left: parent.left; anchors.leftMargin: 42
                anchors.right: _modSummary.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "Changed from defaults"
                elide: Text.ElideRight
                color: Theme.withAlpha(Theme.text, 0.85)
                font.family: Settings.font; font.pixelSize: Settings.fontSize
                renderType: Text.NativeRendering
            }
            Row {
                id: _modSummary
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(ShellSettings.modifiedKeys.length)
                    color: Theme.withAlpha(Theme.subtext, 0.55)
                    font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
                    renderType: Text.NativeRendering
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰅀"
                    rotation: _modHeader.open ? 180 : 0
                    transformOrigin: Item.Center
                    color: _modHeader.open ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.58)
                    font.family: Settings.font; font.pixelSize: Settings.fontSize
                    renderType: Text.NativeRendering
                    Behavior on rotation { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                }
            }
        }

        CollapsibleSection {
        expanded: _modHeader.open && ShellSettings.modifiedKeys.length > 0
        Repeater {
            model: ShellSettings.modifiedKeys
            delegate: Item {
                id: _modRow
                required property string modelData
                property real topRadius:    0
                property real bottomRadius: 0
                width: parent ? parent.width : 0
                height: 44

                readonly property string pretty: modelData.replace(/([A-Z])/g, " $1").toLowerCase()

                function _reset(): void { ShellSettings.resetKey(_modRow.modelData) }

                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Reset " + pretty + " to default"
                Keys.onSpacePressed:  e => { if (!e.isAutoRepeat) _modRow._reset(); e.accepted = true }
                Keys.onReturnPressed: e => { if (!e.isAutoRepeat) _modRow._reset(); e.accepted = true }
                Keys.onEnterPressed:  e => { if (!e.isAutoRepeat) _modRow._reset(); e.accepted = true }

                HoverHandler { id: _modHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: _modRow._reset() }
                RowHoverBg {
                    anchors.fill: parent
                    topRadius:    _modRow.topRadius
                    bottomRadius: _modRow.bottomRadius
                    active:       _modHover.hovered || _modRow.activeFocus
                    focusActive:  _modRow.activeFocus
                    fillOpacity:  _modRow.activeFocus ? 0.13 : 0.08
                }

                Text {
                    id: _modLabel
                    anchors.left: parent.left; anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, Math.min(implicitWidth,
                        parent.width - _modValue.width - _modResetGlyph.width - 46))
                    text: _modRow.pretty
                    elide: Text.ElideRight
                    color: Theme.withAlpha(Theme.text, 0.85)
                    font.family: Settings.font; font.pixelSize: Settings.fontSize
                    renderType: Text.NativeRendering
                }
                Text {
                    id: _modValue
                    anchors.left: _modLabel.right; anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 130)
                    text: root._fmtSettingValue(ShellSettings[_modRow.modelData])
                    elide: Text.ElideRight
                    color: Theme.withAlpha(Theme.subtext, 0.5)
                    font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
                    renderType: Text.NativeRendering
                }
                Text {
                    id: _modResetGlyph
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰦛"
                    color: (_modHover.hovered || _modRow.activeFocus)
                        ? Theme.withAlpha(Theme.accent, 0.9)
                        : Theme.withAlpha(Theme.subtext, 0.5)
                    font.family: Settings.font; font.pixelSize: Settings.iconSize
                    renderType: Text.NativeRendering
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
            }
        }
        }

        Item {
            id: _resetRow
            width: parent.width; height: 44
            property bool armed: false
            property real topRadius:    0
            property real bottomRadius: 0

            function _activate(): void {
                if (armed) { armed = false; ShellSettings.resetToDefaults() }
                else armed = true
            }

            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: "Reset all settings"
            Accessible.description: armed ? "Activate again to confirm" : ""
            onActiveFocusChanged: if (!activeFocus) armed = false
            Keys.onSpacePressed:  e => { if (!e.isAutoRepeat) _resetRow._activate(); e.accepted = true }
            Keys.onReturnPressed: e => { if (!e.isAutoRepeat) _resetRow._activate(); e.accepted = true }
            Keys.onEnterPressed:  e => { if (!e.isAutoRepeat) _resetRow._activate(); e.accepted = true }

            HoverHandler {
                id: _resetHover
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: if (!hovered) _resetRow.armed = false
            }
            TapHandler { onTapped: _resetRow._activate() }
            RowHoverBg {
                anchors.fill: parent
                topRadius:    _resetRow.topRadius
                bottomRadius: _resetRow.bottomRadius
                active: _resetHover.hovered || _resetRow.armed || _resetRow.activeFocus
                focusActive: _resetRow.activeFocus
                focusColor: _resetRow.armed ? Theme.error : Theme.accent
                fillColor: _resetRow.armed ? Theme.error : Theme.subtext
                fillOpacity: _resetRow.armed ? 0.10 : _resetRow.activeFocus ? 0.13 : 0.08
            }
            Row {
                anchors.left: parent.left; anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    horizontalAlignment: Text.AlignHCenter
                    text: "󰦛"
                    color: _resetRow.armed ? Theme.error : Theme.withAlpha(Theme.subtext, 0.85)
                    font.family: Settings.font; font.pixelSize: Settings.iconSize + 2
                    renderType: Text.NativeRendering
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Reset all settings"
                    color: _resetRow.armed ? Theme.error : Theme.withAlpha(Theme.text, 0.85)
                    font.family: Settings.font; font.pixelSize: Settings.fontSize
                    renderType: Text.NativeRendering
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: _resetRow.armed ? "confirm" : ""
                color: Theme.withAlpha(Theme.error, 0.7)
                font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
                renderType: Text.NativeRendering
            }
        }
    }
}
