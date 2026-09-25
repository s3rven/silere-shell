pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"
import "controls"

Item {
    id: root

    property bool open: false
    property real topRadius:    0
    property real bottomRadius: 0
    property real cardInset:    1
    property real cardLeftBleed: 0
    property bool reserveExpandSlot: false

    property string tab: "output"

    width: parent ? parent.width : 0
    implicitHeight: _slider.height + _options.height
    height: implicitHeight
    readonly property bool _optionsShown: root.open || _options.height > 0.5

    readonly property bool _hasOutputs: Audio.sinkCount > 1
    readonly property bool _hasInput:   Audio.micReady || Audio.sourceCount > 0
    readonly property bool _hasApps:    Audio.playbackCount > 0
    readonly property bool _canExpand:  root._hasOutputs || root._hasInput || root._hasApps

    readonly property var _tabs: {
        const out = []
        if (root._hasOutputs) out.push({ value: "output", label: "Output" })
        if (root._hasInput)   out.push({ value: "input",  label: "Input"  })
        if (root._hasApps)    out.push({ value: "apps",   label: "Apps"   })
        return out
    }

    // the chosen tab can empty out while the section is open: fall back rather than show nothing
    readonly property string _tab: {
        const tabs = root._tabs
        for (let i = 0; i < tabs.length; i++) if (tabs[i].value === root.tab) return root.tab
        return tabs.length > 0 ? tabs[0].value : "output"
    }

    // content swaps at the trough, so the rows do not cross-dissolve through each other
    property string _shownTab: "output"
    property real _tabFade: 1.0
    property real _tabShift: 0
    property int _tabDir: 1
    readonly property bool _tabMotion: Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)

    function _tabIndex(value: string): int {
        const tabs = root._tabs
        for (let i = 0; i < tabs.length; i++) if (tabs[i].value === value) return i
        return 0
    }

    function _settleTab(): void {
        _tabSwap.stop()
        root._shownTab = root._tab
        root._tabFade = 1.0
        root._tabShift = 0
    }

    Component.onCompleted: root._shownTab = root._tab
    on_TabChanged: {
        if (!root._optionsShown || !root._tabMotion) { root._settleTab(); return }
        root._tabDir = root._tabIndex(root._tab) >= root._tabIndex(root._shownTab) ? 1 : -1
        _tabSwap.restart()
    }
    onOpenChanged: if (!root.open) root._settleTab()
    on_TabMotionChanged: if (!root._tabMotion) root._settleTab()

    // the page tokens rather than a local timing: pageIn is pinned at or above the panel resize
    SequentialAnimation {
        id: _tabSwap
        ParallelAnimation {
            NumberAnimation { target: root; property: "_tabFade"; to: 0.0; duration: Motion.pageOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardAccel }
            NumberAnimation { target: root; property: "_tabShift"; to: -Motion.pageOffset * root._tabDir; duration: Motion.pageOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
        }
        ScriptAction {
            script: {
                root._shownTab = root._tab
                root._tabShift = Motion.pageOffset * root._tabDir
            }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "_tabFade"; to: 1.0; duration: Motion.pageIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardDecel }
            NumberAnimation { target: root; property: "_tabShift"; to: 0.0; duration: Motion.pageIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
        }
    }

    function closeInline(): bool {
        if (!root.open) return false
        root.open = false
        return true
    }

    // PipeWire enumerates through states holding one sink and no source, so an open
    // section is only folded once emptiness outlives that; the counts are read live
    // because the derived binding still holds its old value inside the signal
    function _hasChoices(): bool {
        return Audio.sinkCount > 1 || Audio.micReady || Audio.sourceCount > 0
            || Audio.playbackCount > 0
    }

    Timer {
        id: _emptySettle
        interval: 400
        onTriggered: if (!root._hasChoices()) root.closeInline()
    }

    function _closeWhenEmpty(): void {
        if (!root.open || root._hasChoices()) return
        _emptySettle.restart()
    }

    Connections {
        target: Audio
        function onSinkCountChanged()     { root._closeWhenEmpty() }
        function onSourceCountChanged()   { root._closeWhenEmpty() }
        function onPlaybackCountChanged() { root._closeWhenEmpty() }
    }

    QuickSlider {
        id: _slider
        y: 0
        width: parent.width
        topRadius:    root.topRadius
        bottomRadius: root._optionsShown ? 0 : root.bottomRadius
        cardInset:    root.cardInset
        cardLeftBleed: root.cardLeftBleed
        glyph: Audio.icon
        accessibleName: "Volume"
        wheelKey: "volume"
        value: Audio.uiVolume
        valueText: Audio.label
        glyphClickable: true
        expandable: root._canExpand
        expanded: root.open
        reserveExpandSlot: root.reserveExpandSlot
        onGlyphClicked: Audio.toggleMute()
        onExpandToggled: root.open = !root.open
        onMoved: (v) => Audio.setVolume(v)
    }

    CollapsibleSection {
        id: _options
        y: _slider.height
        width: parent.width
        expanded: root.open

        Column {
            id: _optCol
            width: parent.width
            bottomPadding: 2

            Hairline {
                x: 14
                width: parent.width - 28
                color: Theme.menuDivider
            }
            Item { width: parent.width; height: 1 }

            ChoiceChipRow {
                width: _optCol.width
                visible: root._tabs.length > 1
                label: ""
                model: root._tabs
                currentValue: root._tab
                onChosen: (v) => root.tab = v
            }

            // the chips sit outside this: fading them blinks the control the click landed on
            Column {
                id: _tabContent
                width: _optCol.width
                opacity: root._tabFade
                x: root._tabShift

                Repeater {
                    model: root._optionsShown && root._shownTab === "output" ? Audio.sinkModel : []
                    delegate: InlineOptionRow {
                        id: _out
                        required property var modelData
                        readonly property bool active: modelData.value === Audio.sink

                        width: _optCol.width
                        glyph: Audio.deviceClass(modelData.value) === "headset" ? "󰋋" : "󰓃"
                        label: modelData.label
                        status: Audio.feedsNothing(modelData.value) ? "No device"
                            : active ? "Current" : ""
                        selected: active
                        accessiblePrefix: "Output"

                        onTriggered: {
                            Audio.setSink(_out.modelData.value)
                            root.open = false
                        }
                    }
                }

                QuickSlider {
                    width: _optCol.width
                    visible: root._optionsShown && root._shownTab === "input" && Audio.micReady
                    glyph: Audio.micIcon
                    accessibleName: "Microphone"
                    wheelKey: "microphone"
                    value: Audio.micVolume
                    valueText: Audio.micLabel
                    glyphClickable: true
                    reserveExpandSlot: true
                    onGlyphClicked: Audio.toggleMicMute()
                    onMoved: (v) => Audio.setMicVolume(v)
                }

                Repeater {
                    model: root._optionsShown && root._shownTab === "input" ? Audio.sourceModel : []
                    delegate: InlineOptionRow {
                        id: _src
                        required property var modelData
                        readonly property bool active: modelData.value === Audio.source

                        width: _optCol.width
                        glyph: Audio.deviceClass(modelData.value) === "headset" ? "󰋎" : "󰍬"
                        label: modelData.label
                        status: active ? "Current" : ""
                        selected: active
                        accessiblePrefix: "Input"

                        onTriggered: Audio.setSource(_src.modelData.value)
                    }
                }

                // the bar indicator says the microphone is open; this says which app has it
                Repeater {
                    model: root._optionsShown && root._shownTab === "input" ? Audio.captureModel : []
                    delegate: InlineOptionRow {
                        id: _cap
                        required property var modelData

                        width: _optCol.width
                        glyph: Audio.micMuted ? "󰍭" : "󰍬"
                        label: modelData.label
                        status: Audio.micMuted ? "Muted" : "Listening"
                        accentColor: Theme.error
                        highlighted: !Audio.micMuted
                        interactive: false
                    }
                }

                // the value slot is measured for "100%", so the app name cannot live there
                Repeater {
                    model: root._optionsShown && root._shownTab === "apps" ? Audio.playbackModel : []
                    delegate: Column {
                        id: _app
                        required property var modelData
                        readonly property PwVolumeControl ctl: PwVolumeControl { node: _app.modelData.value; capExternal: false }

                        width: _optCol.width

                        ShellText {
                            x: 14
                            width: Math.max(1, parent.width - 28)
                            topPadding: 6
                            text: _app.modelData.label
                            elide: Text.ElideRight
                            // the app is what the row is for; it should not be the faintest thing in it
                            color: Theme.withAlpha(Theme.text, 0.88)
                            font.pixelSize: Settings.fontLabel
                        }

                        QuickSlider {
                            width: _app.width
                            glyph: _app.ctl.muted ? "󰝟" : "󰝚"
                            accessibleName: _app.modelData.label
                            wheelKey: "appvolume"
                            value: _app.ctl.uiVolume
                            valueText: Math.round(_app.ctl.uiVolume * 100) + "%"
                            glyphClickable: true
                            reserveExpandSlot: true
                            onGlyphClicked: _app.ctl.toggleMute()
                            onMoved: (v) => _app.ctl.setVolume(v)
                        }
                    }
                }
            }

            // routing an app to another device is a mixer's job; this is the way out to one
            InlineOptionRow {
                width: _optCol.width
                visible: root._optionsShown && Audio.hasSoundSettings
                glyph: "󰒓"
                label: "Sound settings"
                status: Audio.soundSettingsName
                onTriggered: {
                    Audio.openSoundSettings()
                    root.open = false
                    MenuState.close()
                }
            }
        }
    }
}
