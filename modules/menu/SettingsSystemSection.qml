pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: 0

    property int _restoreModifiedIndex: -1

    Timer {
        id: _restoreModifiedFocus
        interval: 0
        onTriggered: {
            if (root._restoreModifiedIndex < 0) return
            if (_modRepeater.count > 0) {
                const i = Math.min(root._restoreModifiedIndex, _modRepeater.count - 1)
                const row = _modRepeater.itemAt(i)
                if (row) row.forceActiveFocus()
            } else {
                _resetRow.forceActiveFocus()
            }
            root._restoreModifiedIndex = -1
        }
    }

    function _fmtSettingValue(v): string {
        if (typeof v === "boolean") return v ? "on" : "off"
        if (typeof v === "number") return String(Math.round(v * 100) / 100)
        const s = String(v)
        return s.length > 0 ? s : "none"
    }

    SectionLabel { label: "CHANGED SETTINGS"; first: true; visible: ShellSettings.modifiedKeys.length > 0 }
    SettingsCard {
        visible: ShellSettings.modifiedKeys.length > 0
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
            Accessible.onPressAction: _modHeader.open = !_modHeader.open
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
                    Behavior on rotation { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
                }
            }
        }

        CollapsibleSection {
            id: _modifiedList
            indent: 8
            expanded: _modHeader.open && ShellSettings.modifiedKeys.length > 0
            Repeater {
                id: _modRepeater
                model: _modHeader.open || _modifiedList.height > 0.5
                    ? ShellSettings.modifiedKeys : []
                delegate: Item {
                    id: _modRow
                    required property int index
                    required property string modelData
                    property real topRadius:    0
                    property real bottomRadius: 0
                    width: parent ? parent.width : 0
                    height: 44

                    readonly property string pretty: modelData.replace(/([A-Z])/g, " $1").toLowerCase()

                    function _reset(): void {
                        if (_modRow.activeFocus) {
                            root._restoreModifiedIndex = _modRow.index
                            _restoreModifiedFocus.restart()
                        }
                        ShellSettings.resetKey(_modRow.modelData)
                    }

                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Reset " + pretty + " to default"
                    Accessible.onPressAction: _modRow._reset()
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
    }

    SectionLabel {
        label: "RESET"
        first: ShellSettings.modifiedKeys.length === 0
    }
    SettingsCard {
        Item {
            id: _resetRow
            width: parent.width; height: 44
            property bool armed: false
            property real topRadius:    0
            property real bottomRadius: 0

            function _disarm(): void {
                armed = false
                _resetArmTimer.stop()
            }
            function _activate(): void {
                if (armed) {
                    _disarm()
                    ShellSettings.resetToDefaults()
                } else {
                    armed = true
                    _resetArmTimer.restart()
                }
            }

            Timer {
                id: _resetArmTimer
                interval: 3000
                onTriggered: _resetRow.armed = false
            }

            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: "Reset all settings"
            Accessible.description: armed ? "Activate again to confirm" : ""
            Accessible.onPressAction: _resetRow._activate()
            onActiveFocusChanged: if (!activeFocus) _disarm()
            Keys.onSpacePressed:  e => { if (!e.isAutoRepeat) _resetRow._activate(); e.accepted = true }
            Keys.onReturnPressed: e => { if (!e.isAutoRepeat) _resetRow._activate(); e.accepted = true }
            Keys.onEnterPressed:  e => { if (!e.isAutoRepeat) _resetRow._activate(); e.accepted = true }

            HoverHandler {
                id: _resetHover
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: if (!hovered) _resetRow._disarm()
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
        HintText {
            text: "Restores appearance, behavior, and layout settings to their built-in defaults."
        }
    }
}
