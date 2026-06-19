import QtQuick
import Quickshell
import Quickshell.Io
import "../../config"
import "../../services"

Item {
    id: root

    required property bool active
    required property bool powerOpen

    signal categoryChanged()

    width: parent ? parent.width : 0
    implicitHeight: _page.implicitHeight
    enabled: root.active && !root.powerOpen
    visible: opacity > 0.001
    transformOrigin: Item.Center

    property bool _entering: false
    layer.enabled: _entering && !ShellSettings.reduceMotion

    Component.onCompleted: opacity = root.active ? 1.0 : 0.0

    onActiveChanged: {
        if (root.active) {
            _exit.stop()
            if (root.opacity < 0.001) root.scale = 0.985
            _enter.restart()
        } else {
            _enter.stop()
            _exit.restart()
        }
    }

    ParallelAnimation {
        id: _enter
        onStarted: root._entering = true
        onStopped: root._entering = false
        NumberAnimation { target: root; property: "opacity"; to: 1.0; duration: Motion.ms(145); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "scale";   to: 1.0; duration: Motion.ms(165); easing.type: Easing.OutQuart }
    }

    SequentialAnimation {
        id: _exit
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: Motion.ms(110); easing.type: Easing.InCubic }
        ScriptAction { script: { root.scale = 1.0 } }
    }

    function _hex2(v) {
        const s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16)
        return s.length < 2 ? "0" + s : s
    }

    readonly property int _navW:     146
    readonly property int _navGap:   16
    readonly property int _contentW: Math.max(0, width - _navW - _navGap)

    // Sidebar metrics — shared by the layout below AND the arithmetic that places
    // the sliding selection, so the two can't drift. (The marker used to read its
    // row via mapToItem in Component.onCompleted, which raced the async page load /
    // open animation and sometimes landed on the group header instead of Theme.)
    readonly property int _navTop:     10
    readonly property int _navGapY:    10   // between groups
    readonly property int _navRowH:    28
    readonly property int _navRowGap:  2    // within a group
    readonly property int _navHdrH:    22
    readonly property int _navStdHdrH: 13   // standalone leaf's divider slot (System)

    // y of a section's row inside _nav, computed straight from the tree — exact and
    // synchronous, no dependency on layout having settled.
    function _sectionRowY(section: string): real {
        let y = _navTop
        for (let i = 0; i < _tree.length; i++) {
            const it = _tree[i]
            if (i > 0) y += _navGapY
            const isGroup = !!it.children
            const hdr = isGroup ? _navHdrH : _navStdHdrH
            const leaves = isGroup ? it.children : [it]
            for (let j = 0; j < leaves.length; j++) {
                if (leaves[j].section === section)
                    return y + hdr + j * _navRowH + (j + 1) * _navRowGap
            }
            y += hdr + leaves.length * (_navRowH + _navRowGap)
        }
        return _navTop
    }

    property string _section:      "theme"
    property string _shownSection: "theme"

    function _setSection(s) {
        if (s === _section) return
        _section = s
        root.categoryChanged()
    }

    readonly property var _tree: [
        { glyph: "󰉦", label: "Appearance", children: [
            { glyph: "󰉦", label: "Theme",       section: "theme"      },
            { glyph: "󱖲", label: "Motion",      section: "motion"     },
            { glyph: "󰖙", label: "Night Light", section: "nightlight" }
        ]},
        { glyph: "󰕮", label: "Bar", children: [
            { glyph: "󰍹", label: "Surface",    section: "surface"    },
            { glyph: "󰻂", label: "Separators", section: "separators" },
            { glyph: "󰍴", label: "Underline",  section: "underline"  }
        ]},
        { glyph: "󰀻", label: "Widgets", children: [
            { glyph: "󰅐", label: "Clock",      section: "clock"      },
            { glyph: "󰕰", label: "Workspaces", section: "workspaces" },
            { glyph: "󰝚", label: "Media",      section: "media"      },
            { glyph: "󰈈", label: "Indicators", section: "indicators" }
        ]},
        { glyph: "󰂚", label: "Notifications", children: [
            { glyph: "󰂚", label: "Popups",   section: "popups"   },
            { glyph: "󱀅", label: "OSD",      section: "osd"      },
            { glyph: "󰀦", label: "Warnings", section: "warnings" }
        ]},
        { glyph: "󰒓", label: "System", children: [
            { glyph: "󰒓", label: "General", section: "system"  },
            { glyph: "󰚰", label: "Updates", section: "updates" }
        ]}
    ]

    readonly property var _flatSections: {
        const out = []
        for (let i = 0; i < _tree.length; i++) {
            const it = _tree[i]
            if (it.children) for (let j = 0; j < it.children.length; j++) out.push(it.children[j].section)
            else out.push(it.section)
        }
        return out
    }

    // section id → { glyph, label, group }, for the detail-pane page header.
    readonly property var _sectionMeta: {
        const m = ({})
        for (let i = 0; i < _tree.length; i++) {
            const it = _tree[i]
            if (it.children) {
                for (let j = 0; j < it.children.length; j++) {
                    const c = it.children[j]
                    m[c.section] = { glyph: c.glyph, label: c.label, group: it.label }
                }
            } else {
                m[it.section] = { glyph: it.glyph, label: it.label, group: "" }
            }
        }
        return m
    }

    function _stepSection(delta: int): void {
        const idx = _flatSections.indexOf(_section)
        if (idx < 0) return
        const next = Math.max(0, Math.min(_flatSections.length - 1, idx + delta))
        if (next !== idx) _setSection(_flatSections[next])
    }

    Shortcut {
        sequences: ["Down"]
        context: Qt.ApplicationShortcut
        enabled: root.active && !root.powerOpen && MenuState.open
        onActivated: root._stepSection(1)
    }
    Shortcut {
        sequences: ["Up"]
        context: Qt.ApplicationShortcut
        enabled: root.active && !root.powerOpen && MenuState.open
        onActivated: root._stepSection(-1)
    }

    readonly property string _battAlertMode: {
        const o = ShellSettings.osdBatteryWarn
        const g = ShellSettings.underlineBattGlow && ShellSettings.underlineGlow
        return o && g ? "both" : o ? "osd" : g ? "glow" : "off"
    }
    function _setBattAlert(v) {
        ShellSettings.osdBatteryWarn = (v === "osd" || v === "both")
        ShellSettings.underlineBattGlow = (v === "glow" || v === "both")
    }

    readonly property string _tempAlertMode: {
        const o = ShellSettings.osdTempWarn
        const g = ShellSettings.underlineTempGlow && ShellSettings.underlineGlow
        return o && g ? "both" : o ? "osd" : g ? "glow" : "off"
    }
    function _setTempAlert(v) {
        ShellSettings.osdTempWarn = (v === "osd" || v === "both")
        ShellSettings.underlineTempGlow = (v === "glow" || v === "both")
    }

    readonly property var _alertChipModel: ShellSettings.underlineGlow
        ? [
            { value: "off",  label: "Off"  },
            { value: "osd",  label: "OSD"  },
            { value: "glow", label: "Glow" },
            { value: "both", label: "Both" }
        ]
        : [
            { value: "off", label: "Off" },
            { value: "osd", label: "OSD" }
          ]

    readonly property string _underlineScreenshotStyle:
        !ShellSettings.underlineScreenshotGlow ? "off"
        : ShellSettings.screenshotGlowSweep ? "sweep"
        : "flash"

    function _setUnderlineScreenshotStyle(style) {
        ShellSettings.underlineScreenshotGlow = style !== "off"
        ShellSettings.screenshotGlowSweep = style === "sweep"
        if (style !== "off") {
            ShellSettings.screenshotGlowStrength = style === "sweep" ? 1.1 : 1.0
            ShellSettings.screenshotGlowDuration = style === "sweep" ? 800 : 650
        }
    }

    readonly property bool _underlineEnabled:
        ShellSettings.barBorderVisible || ShellSettings.underlineGlow
    property string _lastUnderlineStyle:
        ShellSettings.barBorderVisible && !ShellSettings.underlineGlow ? "static" : "glow"
    readonly property string _underlineStyle:
        ShellSettings.underlineGlow ? "glow" : "static"

    function _setUnderlineEnabled(enabled) {
        if (!enabled) {
            root._lastUnderlineStyle = root._underlineStyle
            ShellSettings.barBorderVisible = false
            ShellSettings.underlineGlow = false
            return
        }
        root._setUnderlineStyle(root._lastUnderlineStyle)
    }

    function _setUnderlineStyle(style) {
        root._lastUnderlineStyle = style
        ShellSettings.barBorderVisible = style === "static"
        ShellSettings.underlineGlow = style === "glow"
        if (style === "glow" && !ShellSettings.underlineIdleGlow
                && !ShellSettings.underlineNotifGlow
                && !ShellSettings.underlineBattGlow
                && !ShellSettings.underlineNetGlow
                && !ShellSettings.underlineTempGlow
                && !ShellSettings.underlineScreenshotGlow) {
            ShellSettings.underlineNotifGlow = true
            ShellSettings.underlineNetGlow = true
        }
    }

    readonly property string _underlineBrightness: {
        const v = ShellSettings.underlineGlow
            ? ShellSettings.glowStrength : ShellSettings.barLineStrength
        return v < 0.9 ? "soft" : v > 1.2 ? "bright" : "normal"
    }

    function _setUnderlineBrightness(level) {
        const n = level === "soft" ? 0.7 : level === "bright" ? 1.4 : 1.0
        if (ShellSettings.underlineGlow) {
            ShellSettings.glowStrength = n
            ShellSettings.activeGlowStrength = level === "soft" ? 0.65 : level === "bright" ? 1.0 : 0.85
        } else {
            ShellSettings.barLineStrength = n
        }
    }

    Row {
        id: _page
        width: parent.width
        spacing: root._navGap

        // ── Side-nav tree ──────────────────────────────────────────────────
        Item {
            id: _nav
            width: root._navW
            implicitHeight: _navCol.implicitHeight + 20
            height: implicitHeight

            Rectangle {
                anchors.fill: parent
                radius: 11
                antialiasing: true
                color: Theme.mix(Theme.menuSidebar, Theme.background, 0.08)
                border.width: 0
            }

            // ── Sliding selection ───────────────────────────────────────────
            // One accent marker that glides between rows instead of a static box,
            // mod-menu style. Position is computed from the tree (see _sectionRowY),
            // so it's correct on the very first frame; _selReady just holds motion
            // off until after that frame so the first paint snaps. Sits under
            // the rows (declared before _navCol) so row text/icons paint on top.
            readonly property real _selY: root._sectionRowY(root._section)
            property bool _selReady: false
            Component.onCompleted: Qt.callLater(function() { _nav._selReady = true })

            Item {
                id: _selHighlight
                x: 6
                width: _nav.width - 12
                y: _nav._selY
                height: root._navRowH
                visible: true

                Behavior on y {
                    enabled: _nav._selReady && !ShellSettings.reduceMotion
                    NumberAnimation { duration: Motion.ms(180); easing.type: Easing.OutCubic }
                }

                // Quiet active wash: enough structure for keyboard navigation without
                // turning every row into a boxed control.
                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    antialiasing: true
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Theme.withAlpha(Theme.accent, 0.18) }
                        GradientStop { position: 0.45; color: Theme.withAlpha(Theme.accent, 0.09) }
                        GradientStop { position: 1.0; color: Theme.withAlpha(Theme.accent, 0.018) }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 1
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: 15
                    radius: 1
                    antialiasing: true
                    color: Theme.withAlpha(Theme.accent, 0.82)
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    antialiasing: true
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.accent, 0.34)
                }

            }

            Column {
                id: _navCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.top: parent.top
                anchors.topMargin: root._navTop
                spacing: root._navGapY

                Repeater {
                    model: root._tree

                    delegate: Column {
                        id: _grp
                        required property var modelData
                        width: parent.width
                        spacing: root._navRowGap

                        readonly property bool isGroup: !!modelData.children
                        readonly property var  _leaves: isGroup ? modelData.children : [modelData]
                        readonly property bool groupActive: {
                            for (let i = 0; i < _leaves.length; i++) {
                                if (_leaves[i].section === root._section) return true
                            }
                            return false
                        }

                        Item {
                            width: parent.width
                            height: _grp.isGroup ? root._navHdrH : root._navStdHdrH

                            Text {
                                id: _hdrLabel
                                visible:                _grp.isGroup
                                anchors.left:           parent.left
                                anchors.leftMargin:     10
                                anchors.bottom:         parent.bottom
                                anchors.bottomMargin:   5
                                text:           _grp.modelData.label
                                color:          _grp.groupActive
                                    ? Theme.withAlpha(Theme.mix(Theme.accent, Theme.text, 0.34), 0.88)
                                    : Theme.withAlpha(Theme.mix(Theme.accent, Theme.subtext, 0.28), 0.66)
                                font.family:    Settings.font
                                font.pixelSize: Settings.fontSize - 3
                                font.letterSpacing:  0
                                font.weight:    Font.DemiBold
                                font.capitalization: Font.AllUppercase
                                renderType:     Text.NativeRendering
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }
                            Rectangle {
                                visible:              _grp.isGroup
                                anchors.left:         _hdrLabel.right
                                anchors.leftMargin:   9
                                anchors.right:        parent.right
                                anchors.rightMargin:  9
                                anchors.verticalCenter: _hdrLabel.verticalCenter
                                height: 1
                                radius: 0.5
                                color: _grp.groupActive
                                    ? Theme.withAlpha(Theme.accent, 0.30)
                                    : Theme.withAlpha(Theme.subtext, 0.10)
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }
                        }

                        Repeater {
                            model: _grp._leaves

                            delegate: Rectangle {
                                id: _leaf
                                required property var modelData
                                readonly property bool   active: root._section === modelData.section
                                readonly property string glyph:  modelData.glyph ?? ""
                                property real _shift: active ? 1.5 : (_leafHover.hovered ? 1.0 : 0.0)

                                readonly property color _fg: active
                                    ? Theme.text
                                    : Theme.withAlpha(Theme.mix(Theme.subtext, Theme.text, 0.10), _leafHover.hovered ? 0.86 : 0.62)
                                readonly property color _glyphFg: active
                                    ? Theme.accent
                                    : Theme.withAlpha(Theme.subtext, _leafHover.hovered ? 0.68 : 0.42)

                                width: parent.width
                                height: root._navRowH
                                radius: 7
                                antialiasing: true
                                color: (_leafHover.hovered && !active)
                                    ? Theme.withAlpha(Theme.menuHover, 0.055) : "transparent"
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                                Behavior on _shift {
                                    enabled: !ShellSettings.reduceMotion
                                    NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic }
                                }

                                HoverHandler { id: _leafHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler   { id: _leafTap; onTapped: root._setSection(_leaf.modelData.section) }
                                scale: _leafTap.pressed ? 0.98 : 1.0
                                transformOrigin: Item.Left
                                Behavior on scale {
                                    enabled: !ShellSettings.reduceMotion
                                    NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic }
                                }

                                Text {
                                    id: _leafGlyph
                                    anchors.left:           parent.left
                                    anchors.leftMargin:     12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 18
                                    horizontalAlignment: Text.AlignHCenter
                                    text:  _leaf.glyph
                                    color: _leaf._glyphFg
                                    font.family:    Settings.font
                                    font.pixelSize: Settings.fontSize
                                    renderType:     Text.NativeRendering
                                    transform: Translate { x: _leaf._shift }
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                                }

                                Text {
                                    anchors.left:           _leafGlyph.right
                                    anchors.leftMargin:     9
                                    anchors.right:          parent.right
                                    anchors.rightMargin:    10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: _leaf.modelData.label
                                    elide: Text.ElideRight
                                    color: _leaf._fg
                                    font.family:    Settings.font
                                    font.pixelSize: Settings.fontSize - 1
                                    font.weight:    _leaf.active ? Font.DemiBold : Font.Normal
                                    renderType:     Text.NativeRendering
                                    transform: Translate { x: _leaf._shift }
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Detail pane ────────────────────────────────────────────────────
        Item {
            id: _detail
            width:  root._contentW
            height: _detailHeader.height + _detailBody.height

            // Height of whichever section is currently shown in the body.
            readonly property real _bodyH:
                    root._shownSection === "theme"      ? _secTheme.height
                  : root._shownSection === "motion"     ? _secMotion.height
                  : root._shownSection === "nightlight" ? _secNightLight.height
                  : root._shownSection === "surface"    ? _secSurface.height
                  : root._shownSection === "separators" ? _secSeparators.height
                  : root._shownSection === "underline"  ? _secUnderline.height
                  : root._shownSection === "clock"      ? _secClock.height
                  : root._shownSection === "workspaces" ? _secWorkspaces.height
                  : root._shownSection === "media"      ? _secMedia.height
                  : root._shownSection === "indicators" ? _secIndicators.height
                  : root._shownSection === "popups"     ? _secPopups.height
                  : root._shownSection === "osd"        ? _secOsd.height
                  : root._shownSection === "warnings"   ? _secWarnings.height
                  : root._shownSection === "updates"    ? _secUpdates.height
                  :                                       _secSystem.height

            property real _slide: 0
            transform: Translate { y: _detail._slide }

            Connections {
                target: root
                function onCategoryChanged() {
                    if (ShellSettings.reduceMotion) {
                        root._shownSection = root._section
                        _detail.opacity = 1
                        _detail._slide = 0
                        return
                    }
                    if (!_detailSwap.running) _detailSwap.restart()
                }
            }

            SequentialAnimation {
                id: _detailSwap
                NumberAnimation { target: _detail; property: "opacity"; to: 0.0; duration: Motion.ms(60); easing.type: Easing.InCubic }
                ScriptAction    { script: { root._shownSection = root._section; _detail._slide = 8 } }
                ParallelAnimation {
                    NumberAnimation { target: _detail; property: "opacity"; to: 1.0; duration: Motion.ms(120); easing.type: Easing.OutCubic }
                    NumberAnimation { target: _detail; property: "_slide";  to: 0.0; duration: Motion.ms(120); easing.type: Easing.OutQuart }
                }
                ScriptAction { script: if (root._shownSection !== root._section) _detailSwapAgain.restart() }
            }
            Timer {
                id: _detailSwapAgain
                interval: 0
                onTriggered: if (!ShellSettings.reduceMotion && root._shownSection !== root._section) _detailSwap.restart()
            }

            Item {
                id: _detailHeader
                width: parent.width
                // 4px multiple: the body sits at this height, so an off-grid value
                // would push every card (and its first divider) onto a half physical
                // pixel at 1.25x and double the hairlines. 16 (tabContent.y) + 44 = 60.
                height: 44
                readonly property var _meta: root._sectionMeta[root._shownSection]
                                            ?? ({ glyph: "", label: "", group: "" })

                // Icon chip — the section glyph in a small accent-tinted tile, a
                // focal point for the page (mod-menu style) and a touch more
                // "designed" than a bare glyph.
                Rectangle {
                    id: _hdrIconChip
                    anchors.left:           parent.left
                    anchors.leftMargin:     2
                    anchors.verticalCenter: _hdrTitleBlock.verticalCenter
                    width:  34
                    height: 34
                    radius: 10
                    antialiasing: true
                    // Subtle vertical lift so the chip reads as a raised tile, not a
                    // flat tint — brighter accent at the top edge, settling darker.
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.withAlpha(Theme.accent, 0.16) }
                        GradientStop { position: 1.0; color: Theme.withAlpha(Theme.accent, 0.09) }
                    }
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.accent, 0.24)
                    Text {
                        anchors.centerIn: parent
                        text:           _detailHeader._meta.glyph
                        color:          Theme.accent
                        font.family:    Settings.font
                        font.pixelSize: Settings.fontSize + 4
                        renderType:     Text.NativeRendering
                    }
                }
                Column {
                    id: _hdrTitleBlock
                    anchors.left:                 _hdrIconChip.right
                    anchors.leftMargin:           11
                    // Vertically centred above the hairline so a title with no group
                    // breadcrumb (System) sits balanced, same as the two-line pages.
                    anchors.verticalCenter:       parent.verticalCenter
                    anchors.verticalCenterOffset: -3
                    spacing: 2

                    Text {
                        visible: text.length > 0
                        // Accent-leaning so the breadcrumb ties into the panel's accent
                        // system (same family as the sidebar group headers), not a flat
                        // grey caption floating above the title.
                        text:           (_detailHeader._meta.group || "").toUpperCase()
                        color:          Theme.withAlpha(Theme.mix(Theme.subtext, Theme.accent, 0.40), 0.58)
                        font.family:    Settings.font
                        font.pixelSize: Settings.fontSize - 4
                        font.letterSpacing: 0
                        font.weight:    Font.DemiBold
                        renderType:     Text.NativeRendering
                    }
                    Text {
                        id: _hdrTitle
                        text:           _detailHeader._meta.label
                        color:          Theme.text
                        font.family:    Settings.font
                        font.pixelSize: Settings.fontSize + 4
                        font.weight:    Font.DemiBold
                        renderType:     Text.NativeRendering
                    }
                }
                // Full-width baseline rule. (No accent segment — its width tracked
                // each title, so it read as uneven section to section.)
                Rectangle {
                    anchors.left:         parent.left
                    anchors.right:        parent.right
                    anchors.rightMargin:  2
                    anchors.bottom:       parent.bottom
                    anchors.bottomMargin: 4
                    height: 1
                    color:  Theme.withAlpha(Theme.subtext, 0.10)
                }
            }

            Item {
                id: _detailBody
                y:      _detailHeader.height
                width:  parent.width
                height: _detail._bodyH

            // ── APPEARANCE · Theme ──────────────────────────────────────
            Column {
                id: _secTheme
                width: parent.width
                spacing: 0
                visible: root._shownSection === "theme"

                property bool _showNeutralContent: false
                property bool _showMatuContent:    false
                Component.onCompleted: {
                    _secTheme._showNeutralContent = ShellSettings.neutralTheme
                    _secTheme._showMatuContent    = !ShellSettings.neutralTheme
                }
                Connections {
                    target: ShellSettings
                    function onNeutralThemeChanged() {
                        if (ShellSettings.reduceMotion) {
                            _secTheme._showNeutralContent = ShellSettings.neutralTheme
                            _secTheme._showMatuContent    = !ShellSettings.neutralTheme
                            return
                        }
                        if (ShellSettings.neutralTheme) {
                            _themeOpenMatuTimer.stop()
                            _secTheme._showMatuContent    = false
                            _themeOpenNeutralTimer.interval = Motion.fast + 20
                            _themeOpenNeutralTimer.restart()
                        } else {
                            _themeOpenNeutralTimer.stop()
                            _secTheme._showNeutralContent = false
                            _themeOpenMatuTimer.interval = Motion.fast + 20
                            _themeOpenMatuTimer.restart()
                        }
                    }
                }
                Timer { id: _themeOpenNeutralTimer; interval: Motion.fast + 20; onTriggered: _secTheme._showNeutralContent = true }
                Timer { id: _themeOpenMatuTimer;    interval: Motion.fast + 20; onTriggered: _secTheme._showMatuContent    = true }

                SettingsCard {
                    ToggleRow {
                        glyph: "󰉦"; label: "Neutral theme"
                        checked: ShellSettings.neutralTheme
                        onToggled: ShellSettings.neutralTheme = !ShellSettings.neutralTheme
                        topRadius: 10
                        // Always square: the accent picker expands below when neutral
                        // is on, the matugen showcase when it's off — so this toggle is
                        // never the card's bottom edge.
                        bottomRadius: 0
                    }

                    CollapsibleSection {
                        expanded: _secTheme._showNeutralContent

                        Item {
                            id: _accentPicker
                            width: parent.width
                            height: 140

                            readonly property real _accentL: 0.70
                            function _accentForHS(h, s) {
                                const c = Qt.hsla(h, s, _accentL, 1.0)
                                return "#" + _hex2(c.r) + _hex2(c.g) + _hex2(c.b)
                            }
                            function _accentForHue(h) { return _accentForHS(h, 0.72) }
                            readonly property color _curColor: ShellSettings.neutralAccentAuto ? MatugenTheme.accent : ShellSettings.neutralAccent
                            readonly property real  _curHue:   _curColor.hslHue < 0 ? 0 : _curColor.hslHue
                            readonly property real  _curSat:   isNaN(_curColor.hslSaturation) ? 0.72 : _curColor.hslSaturation

                            readonly property var _accents: [
                                { color: "#c0c8f0", name: "Lavender" },
                                { color: "#7aa2f7", name: "Blue"     },
                                { color: "#bb9af7", name: "Purple"   },
                                { color: "#73c7b5", name: "Teal"     },
                                { color: "#9ece6a", name: "Green"    },
                                { color: "#f7768e", name: "Rose"     },
                                { color: "#e0af68", name: "Amber"    }
                            ]

                            property string _hoverName: ""
                            // exact applied accent (matugen's when auto), for a precise readout
                            readonly property string _curHex: ShellSettings.neutralAccentAuto
                                ? ("#" + _hex2(MatugenTheme.accent.r) + _hex2(MatugenTheme.accent.g) + _hex2(MatugenTheme.accent.b)).toUpperCase()
                                : ShellSettings.neutralAccent.toUpperCase()
                            readonly property string _activeName: {
                                if (ShellSettings.neutralAccentAuto) return "Auto  ·  " + _curHex
                                for (let i = 0; i < _accents.length; i++)
                                    if (_accents[i].color === ShellSettings.neutralAccent) return _accents[i].name + "  ·  " + _curHex
                                return _curHex
                            }
                            readonly property string _shownName: _hoverName.length > 0 ? _hoverName : _activeName

                            // Header — glyph + label at the left like every other row,
                            // live readout at the right (mirrors SliderRow's value), so
                            // the picker reads as a labelled control instead of swatches
                            // floating under the divider.
                            Row {
                                id: _pickerHead
                                anchors.top:        parent.top;  anchors.topMargin:  13
                                anchors.left:       parent.left; anchors.leftMargin: 12
                                spacing: 8
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text:           "󰈊"
                                    color:          Theme.withAlpha(Theme.subtext, 0.85)
                                    font.family:    Settings.font
                                    font.pixelSize: Settings.fontSize + 1
                                    renderType:     Text.NativeRendering
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text:           "Accent"
                                    color:          Theme.withAlpha(Theme.text, 0.85)
                                    font.family:    Settings.font
                                    font.pixelSize: Settings.fontSize
                                    renderType:     Text.NativeRendering
                                }
                            }
                            Text {
                                anchors.right:          parent.right; anchors.rightMargin: 12
                                anchors.left:           _pickerHead.right; anchors.leftMargin: 8
                                anchors.verticalCenter: _pickerHead.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text:           _accentPicker._shownName
                                color:          Theme.withAlpha(Theme.subtext, 0.7)
                                font.family:    Settings.font
                                font.pixelSize: Settings.fontSize - 2
                                renderType:     Text.NativeRendering
                                elide:          Text.ElideRight
                            }

                            Row {
                                id: _swatchRow
                                anchors.top:        parent.top
                                anchors.topMargin:  44
                                anchors.left:       parent.left;  anchors.leftMargin:  12
                                anchors.right:      parent.right; anchors.rightMargin: 12
                                height: 32
                                spacing: Math.max(4, (width - 8 * 26) / 7)

                                AccentSwatch {
                                    chipColor: MatugenTheme.accent
                                    name:      "Auto"
                                    active:    ShellSettings.neutralAccentAuto
                                    onPicked:  ShellSettings.neutralAccentAuto = true
                                    onHoverChanged: (n, h) => _accentPicker._hoverName =
                                        h ? n : (_accentPicker._hoverName === n ? "" : _accentPicker._hoverName)

                                    Grid {
                                        anchors.centerIn: parent
                                        columns: 2; spacing: 2
                                        Repeater {
                                            model: 4
                                            Rectangle { width: 4; height: 4; radius: 2; color: Qt.rgba(0,0,0,0.35) }
                                        }
                                    }
                                }

                                Repeater {
                                    model: _accentPicker._accents
                                    delegate: AccentSwatch {
                                        id: _sw
                                        required property var modelData
                                        chipColor: modelData.color
                                        name:      modelData.name
                                        active:    !ShellSettings.neutralAccentAuto && ShellSettings.neutralAccent === modelData.color
                                        onPicked:  { ShellSettings.neutralAccentAuto = false; ShellSettings.neutralAccent = modelData.color }
                                        onHoverChanged: (n, h) => _accentPicker._hoverName =
                                            h ? n : (_accentPicker._hoverName === n ? "" : _accentPicker._hoverName)

                                        // Centre dot — only on the selected swatch.
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 8; height: 8; radius: 4
                                            antialiasing: true
                                            color: Qt.rgba(0, 0, 0, 0.55)
                                            opacity: _sw.active ? 1 : 0
                                            scale:   _sw.active ? 1 : 0.3
                                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                                            Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(125); easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }
                            }

                            Item {
                                id: _hueStrip
                                anchors.top:       _swatchRow.bottom; anchors.topMargin: 14
                                anchors.left:      parent.left;  anchors.leftMargin:  12
                                anchors.right:     parent.right; anchors.rightMargin: 12
                                height: 14
                                opacity: ShellSettings.neutralAccentAuto ? 0.4 : 1.0
                                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                                Rectangle {
                                    anchors.fill: parent; radius: height / 2; antialiasing: true
                                    border.width: 1; border.color: Theme.withAlpha(Theme.subtext, 0.18)
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.000; color: _accentPicker._accentForHue(0.000) }
                                        GradientStop { position: 0.167; color: _accentPicker._accentForHue(0.167) }
                                        GradientStop { position: 0.333; color: _accentPicker._accentForHue(0.333) }
                                        GradientStop { position: 0.500; color: _accentPicker._accentForHue(0.500) }
                                        GradientStop { position: 0.667; color: _accentPicker._accentForHue(0.667) }
                                        GradientStop { position: 0.833; color: _accentPicker._accentForHue(0.833) }
                                        GradientStop { position: 1.000; color: _accentPicker._accentForHue(1.000) }
                                    }
                                }
                                Rectangle {
                                    id: _hueThumb
                                    width: 16; height: 16; radius: 8; antialiasing: true
                                    y: (parent.height - height) / 2
                                    x: Math.round(_accentPicker._curHue * (_hueStrip.width - width))
                                    color: _accentPicker._curColor
                                    border.width: 2; border.color: Theme.text
                                    scale: _hueMa.pressed ? 1.18 : (_hueMa.containsMouse ? 1.08 : 1.0); transformOrigin: Item.Center
                                    Behavior on x     { enabled: !_hueMa.pressed && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                                    Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    id: _hueMa
                                    anchors.fill: parent; anchors.topMargin: -8; anchors.bottomMargin: -8
                                    cursorShape: Qt.PointingHandCursor; preventStealing: true; hoverEnabled: true
                                    function _set(mx) {
                                        const t = _hueThumb.width
                                        const h = Math.max(0, Math.min(1, (mx - t / 2) / Math.max(1, width - t)))
                                        ShellSettings.neutralAccentAuto = false
                                        ShellSettings.neutralAccent = _accentPicker._accentForHS(h, _accentPicker._curSat)
                                    }
                                    onPressed:         (m) => _set(m.x)
                                    onPositionChanged: (m) => { if (pressed) _set(m.x) }
                                }
                            }

                            Item {
                                id: _satStrip
                                anchors.top:       _hueStrip.bottom; anchors.topMargin: 10
                                anchors.left:      parent.left;  anchors.leftMargin:  12
                                anchors.right:     parent.right; anchors.rightMargin: 12
                                height: 14
                                opacity: ShellSettings.neutralAccentAuto ? 0.4 : 1.0
                                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                                Rectangle {
                                    anchors.fill: parent; radius: height / 2; antialiasing: true
                                    border.width: 1; border.color: Theme.withAlpha(Theme.subtext, 0.18)
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: _accentPicker._accentForHS(_accentPicker._curHue, 0.0) }
                                        GradientStop { position: 1.0; color: _accentPicker._accentForHS(_accentPicker._curHue, 1.0) }
                                    }
                                }
                                Rectangle {
                                    id: _satThumb
                                    width: 16; height: 16; radius: 8; antialiasing: true
                                    y: (parent.height - height) / 2
                                    x: Math.round(_accentPicker._curSat * (_satStrip.width - width))
                                    color: _accentPicker._curColor
                                    border.width: 2; border.color: Theme.text
                                    scale: _satMa.pressed ? 1.18 : (_satMa.containsMouse ? 1.08 : 1.0); transformOrigin: Item.Center
                                    Behavior on x     { enabled: !_satMa.pressed && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                                    Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    id: _satMa
                                    anchors.fill: parent; anchors.topMargin: -8; anchors.bottomMargin: -8
                                    cursorShape: Qt.PointingHandCursor; preventStealing: true; hoverEnabled: true
                                    function _set(mx) {
                                        const t = _satThumb.width
                                        const s = Math.max(0.12, Math.min(1, (mx - t / 2) / Math.max(1, width - t)))
                                        ShellSettings.neutralAccentAuto = false
                                        ShellSettings.neutralAccent = _accentPicker._accentForHS(_accentPicker._curHue, s)
                                    }
                                    onPressed:         (m) => _set(m.x)
                                    onPositionChanged: (m) => { if (pressed) _set(m.x) }
                                }
                            }
                        }
                    }
                    CollapsibleSection {
                        expanded: _secTheme._showNeutralContent
                        ChoiceChipRow {
                            glyph: "󰃞"; label: "Background"
                            currentValue: ShellSettings.baseTone
                            model: [
                                { value: "charcoal", label: "Charcoal" },
                                { value: "black",    label: "Black"    }
                            ]
                            onChosen: (v) => ShellSettings.baseTone = v
                        }
                    }

                    // Neutral off → the shell themes from matugen. Show the live
                    // palette as proof it's working; if matugen isn't installed
                    // these are the bundled fallback tones, called out as such.
                    CollapsibleSection {
                        expanded: _secTheme._showMatuContent

                        Item {
                            id: _matuShowcase
                            width: parent.width
                            // Top padding (13, matching the accent picker header) lifts
                            // the content clear of the divider above; the trailing 14
                            // balances it below.
                            implicitHeight: _matuCol.y + _matuCol.implicitHeight + 14
                            height: implicitHeight

                            function _hex(c) { return ("#" + _hex2(c.r) + _hex2(c.g) + _hex2(c.b)).toUpperCase() }

                            readonly property var _swatches: [
                                { c: MatugenTheme.accent,     n: "Accent"  },
                                { c: MatugenTheme.background, n: "Base"    },
                                { c: MatugenTheme.surface,    n: "Surface" },
                                { c: MatugenTheme.text,       n: "Text"    },
                                { c: MatugenTheme.error,      n: "Error"   },
                                { c: MatugenTheme.warning,    n: "Warning" },
                                { c: MatugenTheme.success,    n: "Success" }
                            ]

                            property string _hoverLabel: ""
                            readonly property string _source:  SystemTools.hasMatugen ? "Matugen" : "Fallback"
                            // Top-right readout: a hovered swatch's name·hex, else the source.
                            readonly property string _readout: _hoverLabel.length > 0 ? _hoverLabel : _source
                            readonly property string _caption: SystemTools.hasMatugen
                                ? "Matched to your wallpaper"
                                : "matugen not installed"

                            // Header — glyph + label left, live readout right, so the
                            // showcase reads as the same kind of labelled control as the
                            // accent picker on the neutral-theme side.
                            Row {
                                id: _matuHead
                                anchors.top:  parent.top;  anchors.topMargin:  13
                                anchors.left: parent.left; anchors.leftMargin: 12
                                spacing: 8
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text:           "󰏘"
                                    color:          Theme.withAlpha(Theme.subtext, 0.85)
                                    font.family:    Settings.font
                                    font.pixelSize: Settings.fontSize + 1
                                    renderType:     Text.NativeRendering
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text:           "Palette"
                                    color:          Theme.withAlpha(Theme.text, 0.85)
                                    font.family:    Settings.font
                                    font.pixelSize: Settings.fontSize
                                    renderType:     Text.NativeRendering
                                }
                            }
                            Text {
                                anchors.right:          parent.right; anchors.rightMargin: 12
                                anchors.left:           _matuHead.right; anchors.leftMargin: 8
                                anchors.verticalCenter: _matuHead.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text:           _matuShowcase._readout
                                color:          Theme.withAlpha(Theme.subtext, 0.7)
                                font.family:    Settings.font
                                font.pixelSize: Settings.fontSize - 2
                                renderType:     Text.NativeRendering
                                elide:          Text.ElideRight
                            }

                            Column {
                                id: _matuCol
                                anchors.left:  parent.left;  anchors.leftMargin:  12
                                anchors.right: parent.right; anchors.rightMargin: 12
                                anchors.top:   _matuHead.bottom; anchors.topMargin: 14
                                spacing: 10

                                Row {
                                    width: parent.width
                                    height: 30
                                    spacing: Math.max(4, (width - 7 * 28) / 6)

                                    Repeater {
                                        model: _matuShowcase._swatches
                                        delegate: Rectangle {
                                            id: _msw
                                            required property var modelData
                                            required property int index
                                            readonly property bool _isAccent: index === 0
                                            readonly property string _label: modelData.n + "  ·  " + _matuShowcase._hex(modelData.c)
                                            width: 28; height: 30; radius: 8
                                            antialiasing: true
                                            color: modelData.c
                                            // Accent keeps a brighter rim so the headline colour
                                            // reads first; any swatch brightens on hover.
                                            border.width: 1
                                            border.color: _mswHover.hovered
                                                ? Theme.withAlpha(Theme.text, 0.7)
                                                : (_isAccent ? Theme.withAlpha(Theme.text, 0.5)
                                                             : Theme.withAlpha(Theme.subtext, 0.28))
                                            Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                                            scale: _mswHover.hovered ? 1.08 : 1.0
                                            transformOrigin: Item.Center
                                            Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic } }
                                            HoverHandler {
                                                id: _mswHover
                                                cursorShape: Qt.PointingHandCursor
                                                onHoveredChanged: _matuShowcase._hoverLabel =
                                                    hovered ? _msw._label
                                                            : (_matuShowcase._hoverLabel === _msw._label ? "" : _matuShowcase._hoverLabel)
                                            }
                                        }
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text:           _matuShowcase._caption
                                    color:          Theme.withAlpha(Theme.subtext, 0.55)
                                    font.family:    Settings.font
                                    font.pixelSize: Settings.fontSize - 2
                                    renderType:     Text.NativeRendering
                                    elide:          Text.ElideRight
                                }

                                Text {
                                    visible: !SystemTools.hasMatugen
                                    width: parent.width
                                    text:           "Install matugen and set a wallpaper to colour the shell from it."
                                    color:          Theme.withAlpha(Theme.subtext, 0.45)
                                    font.family:    Settings.font
                                    font.pixelSize: Settings.fontSize - 3
                                    renderType:     Text.NativeRendering
                                    wrapMode:       Text.WordWrap
                                }
                            }
                        }
                    }
                }
            }

            // ── BAR · Surface ──────────────────────────────────────────
            Column {
                id: _secSurface
                width: parent.width
                spacing: 0
                visible: root._shownSection === "surface"

                SettingsCard {
                    ChoiceChipRow {
                        glyph: "󰍹"; label: "Position"
                        currentValue: ShellSettings.barPosition
                        model: [
                            { value: "top",    label: "Top"    },
                            { value: "bottom", label: "Bottom" }
                        ]
                        onChosen: (v) => ShellSettings.barPosition = v
                        topRadius: 10
                    }
                    ChoiceChipRow {
                        glyph: "󰲏"; label: "Height"
                        currentValue: ShellSettings.barHeight
                        model: [
                            { value: 28, label: "Compact" },
                            { value: 36, label: "Normal"  },
                            { value: 44, label: "Tall"    }
                        ]
                        onChosen: (v) => ShellSettings.barHeight = v
                    }
                    SliderRow {
                        glyph: "󰗌"; label: "Opacity"
                        value: ShellSettings.barOpacity
                        min: 0.4; max: 1.0; step: 0.02
                        displayValue: Math.round(ShellSettings.barOpacity * 100) + "%"
                        onChanged: (v) => ShellSettings.barOpacity = v
                        bottomRadius: 10
                    }
                }

                SectionLabel { label: "FLOATING" }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰖲"; label: "Floating bar"; badge: "beta"
                        checked: ShellSettings.barFloating
                        onToggled: ShellSettings.barFloating = !ShellSettings.barFloating
                        topRadius: 10
                        bottomRadius: ShellSettings.barFloating ? 0 : 10
                    }
                    CollapsibleSection {
                        expanded: ShellSettings.barFloating
                        SliderRow {
                            glyph: "󰁌"; label: "Width"
                            value: ShellSettings.barWidth
                            min: 0.5; max: 1.0; step: 0.02
                            displayValue: Math.round(ShellSettings.barWidth * 100) + "%"
                            onChanged: (v) => ShellSettings.barWidth = v
                        }
                        ChoiceChipRow {
                            glyph: "󰀁"; label: "Shape"
                            currentValue: ShellSettings.barCornerStyle
                            model: [
                                { value: "flat",  label: "Flat"  },
                                { value: "round", label: "Round" }
                            ]
                            onChosen: (v) => ShellSettings.barCornerStyle = v
                        }
                        CollapsibleSection {
                            expanded: ShellSettings.barCornerStyle === "round"
                            SliderRow {
                                glyph: "󱓻"; label: "Roundness"
                                value: ShellSettings.barRadius
                                min: 2; max: 28; step: 1
                                displayValue: ShellSettings.barRadius + "px"
                                onChanged: (v) => ShellSettings.barRadius = Math.round(v)
                            }
                        }
                        ToggleRow {
                            glyph: "󰘷"; label: "Drop shadow"
                            checked: ShellSettings.barShadow
                            onToggled: ShellSettings.barShadow = !ShellSettings.barShadow
                            bottomRadius: ShellSettings.barShadow ? 0 : 10
                        }
                        CollapsibleSection {
                            expanded: ShellSettings.barShadow
                            SliderRow {
                                glyph: "󰔏"; label: "Shadow depth"
                                value: ShellSettings.barShadowStrength
                                min: 0.3; max: 2.0; step: 0.1
                                displayValue: Math.round(ShellSettings.barShadowStrength * 100) + "%"
                                onChanged: (v) => ShellSettings.barShadowStrength = v
                                bottomRadius: 10
                            }
                        }
                    }
                }
            }

            // ── APPEARANCE · Night Light ────────────────────────────────
            Column {
                id: _secNightLight
                width: parent.width
                spacing: 0
                visible: root._shownSection === "nightlight"

                SettingsCard {
                    visible: NightLight.toolAvailable
                    ToggleRow {
                        glyph: "󰖙"; label: "Follow sun position"
                        checked: ShellSettings.nightLightAuto
                        onToggled: ShellSettings.nightLightAuto = !ShellSettings.nightLightAuto
                        topRadius: 10; bottomRadius: 0
                    }
                    SliderRow {
                        glyph: "󰖚"; label: "Color temperature"
                        enabled: !ShellSettings.nightLightAuto
                        value: ShellSettings.nightLightTemp
                        min: 1000; max: 6500; step: 100
                        displayValue: ShellSettings.nightLightTemp + "K"
                                    + (ShellSettings.nightLightAuto ? "  ·  auto " + NightLight.locationLabel : "")
                        onChanged: (v) => { if (!ShellSettings.nightLightAuto) ShellSettings.nightLightTemp = v }
                        topRadius: 0; bottomRadius: 10
                    }
                }
                HintText {
                    visible: !NightLight.toolAvailable
                    text: "hyprsunset is not installed."
                }
            }

            // ── APPEARANCE · Motion ─────────────────────────────────────
            Column {
                id: _secMotion
                width: parent.width
                spacing: 0
                visible: root._shownSection === "motion"

                SettingsCard {
                    ToggleRow {
                        glyph: "󱖳"; label: "Reduce motion"
                        checked: ShellSettings.reduceMotion
                        onToggled: ShellSettings.reduceMotion = !ShellSettings.reduceMotion
                        topRadius: 10
                        bottomRadius: ShellSettings.reduceMotion ? 10 : 0
                    }
                    CollapsibleSection {
                        expanded: !ShellSettings.reduceMotion
                        SliderRow {
                            glyph: "󰣿"; label: "Animation speed"
                            value: ShellSettings.animSpeed
                            min: 0.5; max: 2.0; step: 0.1
                            displayValue: ShellSettings.animSpeed.toFixed(1) + "×"
                            onChanged: (v) => ShellSettings.animSpeed = v
                            bottomRadius: 10
                        }
                    }
                }

            }

            // ── SYSTEM ──────────────────────────────────────────────────
            Column {
                id: _secSystem
                width: parent.width
                spacing: 0
                visible: root._shownSection === "system"

                SectionLabel { label: "INTERFACE"; first: true }
                SettingsCard {
                    ChoiceChipRow {
                        glyph: "󰍉"; label: "UI scale"
                        currentValue: ShellSettings.uiScale
                        model: [
                            { value: 0.8, label: "80%"  },
                            { value: 0.9, label: "90%"  },
                            { value: 1.0, label: "100%" }
                        ]
                        onChosen: (v) => ShellSettings.uiScale = v
                        topRadius: 10; bottomRadius: 10
                    }
                }

                SectionLabel { label: "MONITORS"; visible: Quickshell.screens.length > 1 }
                SettingsCard {
                    visible: Quickshell.screens.length > 1
                    ChoiceChipRow {
                        glyph: "󰍹"; label: "Popups & OSD on"
                        currentValue: ShellSettings.overlayMonitor
                        model: {
                            const t = [{ value: "", label: "Focus" }]
                            const s = Quickshell.screens || []
                            for (let i = 0; i < s.length; i++) {
                                const name = s[i].name
                                t.push({ value: name, label: name.length > 12 ? name.slice(0, 9) + "..." : name })
                            }
                            return t
                        }
                        onChosen: (v) => ShellSettings.overlayMonitor = v
                        topRadius: 10
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
                    HintText { text: "Pick which screens get a bar, and where notifications and the volume/brightness OSD appear." }
                }

                Item { width: 1; height: 12 }
                SettingsCard {
                    Item {
                        id: _resetRow
                        width: parent.width; height: 44
                        property bool armed: false
                        HoverHandler {
                            id: _resetHover
                            cursorShape: Qt.PointingHandCursor
                            onHoveredChanged: if (!hovered) _resetRow.armed = false
                        }
                        TapHandler {
                            onTapped: {
                                if (_resetRow.armed) { _resetRow.armed = false; ShellSettings.resetToDefaults() }
                                else { _resetRow.armed = true }
                            }
                        }
                        RowHoverBg {
                            anchors.fill: parent
                            topRadius: 10; bottomRadius: 10
                            active: _resetHover.hovered || _resetRow.armed
                            fillColor: _resetRow.armed ? Theme.error : Theme.subtext
                            fillOpacity: _resetRow.armed ? 0.10 : 0.08
                        }
                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰦛"
                                color: _resetRow.armed ? Theme.error : Theme.withAlpha(Theme.subtext, 0.85)
                                font.family: Settings.font; font.pixelSize: Settings.fontSize + 1
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
                            text: _resetRow.armed ? "tap to confirm" : ""
                            color: Theme.withAlpha(Theme.error, 0.7)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }

            // ── SYSTEM · Updates ────────────────────────────────────────
            Column {
                id: _secUpdates
                width: parent.width
                spacing: 0
                visible: root._shownSection === "updates"

                SectionLabel { label: "SILERE"; first: true }
                SettingsCard {
                    Item {
                        width: parent.width; height: 44
                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                id: _silereIcon
                                anchors.verticalCenter: parent.verticalCenter
                                text: ShellUpdate.pending ? "󰚰" : "󰄬"
                                color: ShellUpdate.lastCheckError.length > 0 || ShellUpdate.lastApplyError.length > 0
                                    ? Theme.warning
                                    : ShellUpdate.pending ? Theme.accent : Theme.withAlpha(Theme.success, 0.9)
                                font.family: Settings.font; font.pixelSize: Settings.fontSize + 1
                                renderType: Text.NativeRendering
                                transformOrigin: Item.Center
                                scale: 1.0

                                Behavior on color { ColorAnimation { duration: Motion.color } }

                                // Spring pop when landing on "Up to date"
                                SequentialAnimation {
                                    id: _silerePopAnim
                                    NumberAnimation {
                                        target: _silereIcon; property: "scale"
                                        to: 1.30; duration: Motion.fast; easing.type: Easing.OutQuad
                                    }
                                    NumberAnimation {
                                        target: _silereIcon; property: "scale"
                                        to: 1.0;  duration: Motion.slow; easing.type: Easing.OutBack
                                    }
                                }

                                Connections {
                                    target: ShellUpdate
                                    function onCheckingChanged() {
                                        if (ShellUpdate.checking) return
                                        if (!ShellUpdate.pending
                                                && ShellUpdate.lastCheckError.length === 0
                                                && !ShellSettings.reduceMotion) {
                                            _silerePopAnim.restart()
                                        }
                                    }
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: ShellUpdate.statusText
                                color: Theme.withAlpha(Theme.text, 0.85)
                                font.family: Settings.font; font.pixelSize: Settings.fontSize
                                renderType: Text.NativeRendering
                            }
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: ShellUpdate.currentVersion.length > 0 ? "#" + ShellUpdate.currentVersion : ""
                            color: Theme.withAlpha(Theme.subtext, 0.55)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
                            renderType: Text.NativeRendering
                        }
                    }
                    HintText {
                        visible: ShellUpdate.pending || ShellUpdate.lastCheckError.length > 0 || ShellUpdate.lastApplyError.length > 0
                        text: ShellUpdate.lastApplyError.length > 0 ? ShellUpdate.lastApplyError
                            : ShellUpdate.lastCheckError.length > 0 ? ShellUpdate.lastCheckError
                            : ShellUpdate.summary
                    }
                }

                SectionLabel { label: "PACKAGES" }
                SettingsCard {
                    Item {
                        width: parent.width; height: 44
                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Updates.icon
                                color: Updates.lastFailed ? Theme.warning : Theme.withAlpha(Theme.subtext, 0.85)
                                font.family: Settings.font; font.pixelSize: Settings.fontSize + 1
                                renderType: Text.NativeRendering
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Packages"
                                color: Theme.withAlpha(Theme.text, 0.85)
                                font.family: Settings.font; font.pixelSize: Settings.fontSize
                                renderType: Text.NativeRendering
                            }
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: Updates.managerLabel
                            color: Theme.withAlpha(Theme.subtext, 0.55)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
                            renderType: Text.NativeRendering
                        }
                    }
                    Item {
                        property bool suppressDividerAbove: true
                        width: parent.width; height: 32
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 38
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Last checked · " + Updates.lastCheckTime
                            color: Theme.withAlpha(Theme.subtext, 0.42)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
                            renderType: Text.NativeRendering
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: Updates.statusText
                            color: Updates.lastFailed ? Theme.warning : Theme.withAlpha(Theme.subtext, 0.50)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
                            renderType: Text.NativeRendering
                        }
                    }
                    HintText {
                        visible: Updates.lastFailed && Updates.lastError.length > 0
                        text: Updates.lastError
                    }
                }

                SectionLabel { label: "CONTROLS" }
                SettingsCard {
                    Item {
                        id: _checkRow
                        width: parent.width; height: 44
                        opacity: ShellUpdate.checking ? 0.45 : 1.0
                        Behavior on opacity { NumberAnimation { duration: Motion.medium } }
                        HoverHandler { id: _checkHover; cursorShape: ShellUpdate.checking ? Qt.ArrowCursor : Qt.PointingHandCursor }
                        TapHandler { enabled: !ShellUpdate.checking; onTapped: ShellUpdate.check() }
                        RowHoverBg {
                            anchors.fill: parent
                            topRadius: 10; bottomRadius: 0
                            active: _checkHover.hovered && !ShellUpdate.checking
                            fillOpacity: 0.08
                        }
                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰓦"
                                color: Theme.withAlpha(Theme.subtext, 0.85)
                                font.family: Settings.font; font.pixelSize: Settings.fontSize + 1
                                renderType: Text.NativeRendering
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: ShellUpdate.checking ? "Checking..." : "Check Silere"
                                color: Theme.withAlpha(Theme.text, 0.85)
                                font.family: Settings.font; font.pixelSize: Settings.fontSize
                                renderType: Text.NativeRendering
                            }
                        }
                    }
                    Item {
                        id: _applyRow
                        visible: ShellUpdate.pending
                        width: parent.width; height: visible ? 44 : 0
                        opacity: ShellUpdate.applying ? 0.45 : 1.0
                        Behavior on opacity { NumberAnimation { duration: Motion.medium } }
                        HoverHandler { id: _applyHover; cursorShape: ShellUpdate.applying ? Qt.ArrowCursor : Qt.PointingHandCursor }
                        TapHandler { enabled: !ShellUpdate.applying; onTapped: ShellUpdate.apply() }
                        RowHoverBg {
                            anchors.fill: parent
                            bottomRadius: 0
                            active: _applyHover.hovered && !ShellUpdate.applying
                            fillColor: Theme.accent; fillOpacity: 0.10
                        }
                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰅢"
                                color: Theme.accent
                                font.family: Settings.font; font.pixelSize: Settings.fontSize + 1
                                renderType: Text.NativeRendering
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: ShellUpdate.applying ? "Updating…" : "Install update"
                                color: Theme.accent
                                font.family: Settings.font; font.pixelSize: Settings.fontSize
                                font.weight: Font.DemiBold
                                renderType: Text.NativeRendering
                            }
                        }
                    }
                    Item {
                        id: _packageCheckRow
                        width: parent.width; height: 44
                        readonly property bool canCheck: ShellSettings.updatesWidget && Updates.supported && !Updates.isChecking
                        opacity: _packageCheckRow.canCheck ? 1.0 : 0.45
                        Behavior on opacity { NumberAnimation { duration: Motion.medium } }
                        HoverHandler { id: _packageCheckHover; cursorShape: _packageCheckRow.canCheck ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler { enabled: _packageCheckRow.canCheck; onTapped: Updates.refresh() }
                        RowHoverBg {
                            anchors.fill: parent
                            bottomRadius: 10
                            active: _packageCheckHover.hovered && _packageCheckRow.canCheck
                            fillOpacity: 0.08
                        }
                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰓦"
                                color: Theme.withAlpha(Theme.subtext, 0.85)
                                font.family: Settings.font; font.pixelSize: Settings.fontSize + 1
                                renderType: Text.NativeRendering
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Updates.isChecking ? "Checking packages..." : "Check packages"
                                color: Theme.withAlpha(Theme.text, 0.85)
                                font.family: Settings.font; font.pixelSize: Settings.fontSize
                                renderType: Text.NativeRendering
                            }
                        }
                    }
                }

                Item { width: 1; height: 8 }

                SettingsCard {
                    ToggleRow {
                        glyph: "󰚰"; label: "Package update badge"
                        checked: ShellSettings.updatesWidget
                        onToggled: ShellSettings.updatesWidget = !ShellSettings.updatesWidget
                        available: !SystemTools.ready || Updates.supported
                        dependsNote: "No package manager"
                        topRadius: 10; bottomRadius: 0
                    }
                    ToggleRow {
                        glyph: "󰥔"; label: "Notify me about updates"
                        checked: ShellUpdate.timerEnabled
                        enabled: !ShellUpdate.timerBusy
                        available: ShellUpdate.timerSupported
                        dependsNote: ShellUpdate.timerBusy ? "Working" : (!SystemTools.ready ? "Checking" : "No systemd")
                        topRadius: 0; bottomRadius: 0
                        onToggled: ShellUpdate.setTimerEnabled(!ShellUpdate.timerEnabled)
                    }
                    HintText { text: "Shows a bar badge when Silere has an update. Nothing installs until you press Install update." }
                }
            }

            // ── BAR · Separators ───────────────────────────────────────
            Column {
                id: _secSeparators
                width: parent.width
                spacing: 0
                visible: root._shownSection === "separators"

                SectionLabel { label: "STYLE"; first: true }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰡍"; label: "Dense bar"; badge: "beta"
                        checked: ShellSettings.barCompact
                        onToggled: ShellSettings.barCompact = !ShellSettings.barCompact
                        topRadius: 10
                    }
                    ChoiceChipRow {
                        glyph: "󰻂"; label: "Separator"
                        currentValue: ShellSettings.dotStyle
                        model: [
                            { value: "·",    label: "·" },
                            { value: "•",    label: "•" },
                            { value: "◦",    label: "◦" },
                            { value: "|",    label: "|" },
                            { value: "line", label: "│" }
                        ]
                        onChosen: (v) => ShellSettings.dotStyle = v
                    }
                    ChoiceChipRow {
                        glyph: "󰤼"; label: "Spacing"
                        currentValue: ShellSettings.barSpacing
                        model: [
                            { value: 8,  label: "Tight"  },
                            { value: 11, label: "Normal" },
                            { value: 15, label: "Loose"  }
                        ]
                        onChosen: (v) => ShellSettings.barSpacing = v
                        bottomRadius: 10
                    }
                }

                SectionLabel { label: "APPEARANCE" }
                SettingsCard {
                    SliderRow {
                        glyph: ShellSettings.dotStyle === "line" ? "│" : ShellSettings.dotStyle
                        glyphColor: Theme.withAlpha(Theme.text, Math.max(0.35, ShellSettings.dotOpacity))
                        label: "Separator opacity"
                        value: ShellSettings.dotOpacity
                        min: 0.10; max: 1.0; step: 0.05
                        displayValue: Math.round(ShellSettings.dotOpacity * 100) + "%"
                        onChanged: (v) => ShellSettings.dotOpacity = v
                        topRadius: 10; bottomRadius: 10
                    }
                }
            }

            // ── WIDGETS · Indicators ────────────────────────────────────
            Column {
                id: _secIndicators
                width: parent.width
                spacing: 0
                visible: root._shownSection === "indicators"

                SectionLabel { label: "WINDOW"; first: true }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰦩"; label: "Window title"
                        checked: ShellSettings.showWindowTitle
                        onToggled: ShellSettings.showWindowTitle = !ShellSettings.showWindowTitle
                        topRadius: 10
                        bottomRadius: ShellSettings.showWindowTitle ? 0 : 10
                    }
                    CollapsibleSection {
                        expanded: ShellSettings.showWindowTitle
                        ToggleRow {
                            glyph: "󰀻"; label: "App name"
                            checked: ShellSettings.showWindowTitleApp
                            onToggled: ShellSettings.showWindowTitleApp = !ShellSettings.showWindowTitleApp
                        }
                        SliderRow {
                            glyph: "󰦩"; label: "Title opacity"
                            value: ShellSettings.windowTitleOpacity
                            min: 0.2; max: 1.0; step: 0.05
                            displayValue: Math.round(ShellSettings.windowTitleOpacity * 100) + "%"
                            onChanged: (v) => ShellSettings.windowTitleOpacity = v
                            bottomRadius: 10
                        }
                    }
                }

                SectionLabel { label: "NETWORK" }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰓅"; label: "Network speed"
                        checked: ShellSettings.networkTrafficStats
                        onToggled: ShellSettings.networkTrafficStats = !ShellSettings.networkTrafficStats
                        available: Network.toolAvailable
                        dependsNote: "NetworkManager missing"
                        topRadius: 10
                    }
                    CollapsibleSection {
                        expanded: ShellSettings.networkTrafficStats
                        ToggleRow {
                            glyph: "󰐃"; label: "Always show speed"
                            checked: ShellSettings.networkSpeedInline
                            onToggled: ShellSettings.networkSpeedInline = !ShellSettings.networkSpeedInline
                        }
                    }
                    ToggleRow {
                        glyph: "󰦝"; label: "Show connection under VPN"
                        checked: ShellSettings.netVpnShowLink
                        onToggled: ShellSettings.netVpnShowLink = !ShellSettings.netVpnShowLink
                        available: Network.toolAvailable
                        dependsNote: "NetworkManager missing"
                        bottomRadius: 10
                    }
                }

                SectionLabel { label: "DISPLAY" }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰈈"; label: "Show values on hover"
                        checked: ShellSettings.valuesOnHover
                        onToggled: ShellSettings.valuesOnHover = !ShellSettings.valuesOnHover
                        topRadius: 10
                    }
                    HintText { text: "Hides volume, brightness, and battery values at rest; hover to reveal." }
                }

                SectionLabel { label: "OPTIONAL WIDGETS" }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰂄"; label: "Hide when charging or full"
                        checked: ShellSettings.batteryAutoHide
                        onToggled: ShellSettings.batteryAutoHide = !ShellSettings.batteryAutoHide
                        available: Battery.available
                        dependsNote: "No battery"
                        topRadius: 10
                    }
                    ToggleRow {
                        glyph: "󰇘"; label: "System tray"
                        checked: ShellSettings.trayWidget
                        onToggled: ShellSettings.trayWidget = !ShellSettings.trayWidget
                    }
                    ToggleRow {
                        glyph: "󰚰"; label: "Package update count"
                        checked: ShellSettings.updatesWidget
                        onToggled: ShellSettings.updatesWidget = !ShellSettings.updatesWidget
                        available: !SystemTools.ready || Updates.supported
                        dependsNote: "No package manager"
                        bottomRadius: 10
                    }
                }
            }

            // ── WIDGETS · Clock ─────────────────────────────────────────
            Column {
                id: _secClock
                width: parent.width
                spacing: 0
                visible: root._shownSection === "clock"

                SectionLabel { label: "FORMAT"; first: true }
                SettingsCard {
                    ChoiceChipRow {
                        glyph: "󰃭"; label: "Date"
                        currentValue: !ShellSettings.clockShowDate ? "off"
                                      : ShellSettings.compactDate ? "compact" : "normal"
                        model: [
                            { value: "off",     label: "Off"     },
                            { value: "normal",  label: "Normal"  },
                            { value: "compact", label: "Compact" }
                        ]
                        onChosen: (v) => {
                            ShellSettings.clockShowDate = v !== "off"
                            ShellSettings.compactDate   = v === "compact"
                        }
                        topRadius: 10
                    }
                    ChoiceChipRow {
                        glyph: "󰔟"; label: "Time"
                        currentValue: ShellSettings.clock12h ? "12h" : "24h"
                        model: [
                            { value: "24h", label: "24h" },
                            { value: "12h", label: "12h" }
                        ]
                        onChosen: (v) => ShellSettings.clock12h = v === "12h"
                    }
                    ChoiceChipRow {
                        glyph: "󱑂"; label: "Seconds"
                        currentValue: ShellSettings.showSeconds ? "on" : "off"
                        model: [
                            { value: "off", label: "Off" },
                            { value: "on",  label: "On"  }
                        ]
                        onChosen: (v) => ShellSettings.showSeconds = v === "on"
                        bottomRadius: 10
                    }
                }
            }

            // ── WIDGETS · Workspaces ────────────────────────────────────
            Column {
                id: _secWorkspaces
                width: parent.width
                spacing: 0
                visible: root._shownSection === "workspaces"

                SectionLabel { label: "BEHAVIOR"; first: true }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰗘"; label: "Slide animation"
                        checked: ShellSettings.workspaceShift
                        onToggled: ShellSettings.workspaceShift = !ShellSettings.workspaceShift
                        topRadius: 10
                    }
                    ToggleRow {
                        glyph: "󱕒"; label: "Scroll to switch"
                        checked: ShellSettings.wsScrollSwitch
                        onToggled: ShellSettings.wsScrollSwitch = !ShellSettings.wsScrollSwitch
                    }
                    ToggleRow {
                        glyph: "󰂟"; label: "Notification pulse"
                        checked: ShellSettings.wsNotifPulse
                        onToggled: ShellSettings.wsNotifPulse = !ShellSettings.wsNotifPulse
                        bottomRadius: 10
                    }
                }

                SectionLabel { label: "LABELS" }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰎠"; label: "Show numbers"
                        checked: ShellSettings.wsShowNumbers
                        onToggled: ShellSettings.wsShowNumbers = !ShellSettings.wsShowNumbers
                        topRadius: 10
                        bottomRadius: ShellSettings.wsShowNumbers ? 0 : 10
                    }
                    CollapsibleSection {
                        expanded: ShellSettings.wsShowNumbers
                        ToggleRow {
                            glyph: "󰮚"; label: "Roman numerals"
                            checked: ShellSettings.wsRomanNumerals
                            onToggled: ShellSettings.wsRomanNumerals = !ShellSettings.wsRomanNumerals
                            bottomRadius: 10
                        }
                    }
                }

                SectionLabel { label: "DISPLAY" }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰀻"; label: "Show app icons"; badge: "beta"
                        checked: ShellSettings.wsShowAppIcons
                        onToggled: ShellSettings.wsShowAppIcons = !ShellSettings.wsShowAppIcons
                        topRadius: 10
                    }
                    CollapsibleSection {
                        expanded: ShellSettings.wsShowAppIcons
                        SliderRow {
                            glyph: "󰋩"; label: "Icon opacity"
                            value: ShellSettings.wsIconOpacity
                            min: 0.3; max: 1.0; step: 0.05
                            displayValue: Math.round(ShellSettings.wsIconOpacity * 100) + "%"
                            onChanged: (v) => ShellSettings.wsIconOpacity = v
                        }
                        SliderRow {
                            glyph: "󰍉"; label: "Icon size"
                            value: ShellSettings.wsIconSize
                            min: 12; max: 20; step: 1
                            displayValue: ShellSettings.wsIconSize + "px"
                            onChanged: (v) => ShellSettings.wsIconSize = v
                        }
                    }
                    SliderRow {
                        glyph: "󰕰"; label: "Visible workspaces"
                        value: ShellSettings.wsMinVisible
                        min: 1; max: 10; step: 1
                        displayValue: ShellSettings.wsMinVisible
                        onChanged: (v) => ShellSettings.wsMinVisible = v
                        bottomRadius: 10
                    }
                }
            }

            // ── WIDGETS · Media ─────────────────────────────────────────
            Column {
                id: _secMedia
                width: parent.width
                spacing: 0
                visible: root._shownSection === "media"

                SectionLabel { label: "DISPLAY"; first: true }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰎇"; label: "Show artist + title"
                        checked: ShellSettings.mediaWidgetFormat === "artist-title"
                        onToggled: ShellSettings.mediaWidgetFormat = (ShellSettings.mediaWidgetFormat === "artist-title" ? "title" : "artist-title")
                        topRadius: 10
                        bottomRadius: 10
                    }
                }

                SectionLabel { label: "VISUALIZER" }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰱐"; label: "Audio visualizer"; badge: "beta"
                        checked: ShellSettings.mediaProgress
                        onToggled: ShellSettings.mediaProgress = !ShellSettings.mediaProgress
                        topRadius: 10
                        available: SystemTools.hasCava && SystemTools.hasCavaConfig
                        dependsNote: SystemTools.hasCava ? "cava config missing" : "cava missing"
                        bottomRadius: ShellSettings.mediaProgress && SystemTools.hasCava && SystemTools.hasCavaConfig ? 0 : 10
                    }
                    CollapsibleSection {
                        expanded: ShellSettings.mediaProgress && SystemTools.hasCava && SystemTools.hasCavaConfig
                        HintText { text: "Uses more CPU while music is playing. Stops automatically when idle." }
                    }
                }
            }

            // ── BAR · Underline ─────────────────────────────────────────
            Column {
                id: _secUnderline
                width: parent.width
                spacing: 0
                visible: root._shownSection === "underline"

                SectionLabel { label: "UNDERLINE"; first: true }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰍴"; label: "Show underline"
                        checked: root._underlineEnabled
                        onToggled: root._setUnderlineEnabled(!root._underlineEnabled)
                        topRadius: 10
                        bottomRadius: 10
                    }
                }

                CollapsibleSection {
                    expanded: root._underlineEnabled
                    Column {
                        width: parent.width
                        SectionLabel { label: "STYLE" }
                        SettingsCard {
                            ChoiceChipRow {
                                glyph: "󰒓"; label: "Style"
                                currentValue: root._underlineStyle
                                model: [
                                    { value: "static", label: "Static" },
                                    { value: "glow",   label: "Glow" }
                                ]
                                onChosen: (v) => root._setUnderlineStyle(v)
                                topRadius: 10
                            }
                            ChoiceChipRow {
                                glyph: "󰃠"
                                label: ShellSettings.underlineGlow ? "Glow intensity" : "Line intensity"
                                currentValue: root._underlineBrightness
                                model: [
                                    { value: "soft",   label: "Low" },
                                    { value: "normal", label: "Medium" },
                                    { value: "bright", label: "High" }
                                ]
                                onChosen: (v) => root._setUnderlineBrightness(v)
                                bottomRadius: 10
                            }
                        }
                    }
                }

                CollapsibleSection {
                    expanded: ShellSettings.underlineGlow
                    Column {
                        width: parent.width
                        SectionLabel { label: "GLOW FEEDBACK" }
                        SettingsCard {
                            ToggleRow {
                                glyph: "󰊠"; label: "Always visible"
                                checked: ShellSettings.underlineIdleGlow
                                onToggled: ShellSettings.underlineIdleGlow = !ShellSettings.underlineIdleGlow
                                topRadius: 10
                            }
                            ToggleRow {
                                glyph: "󰂚"; label: "Notifications"
                                checked: ShellSettings.underlineNotifGlow
                                onToggled: ShellSettings.underlineNotifGlow = !ShellSettings.underlineNotifGlow
                            }
                            ToggleRow {
                                glyph: "󰤭"; label: "Network disconnect"
                                checked: ShellSettings.underlineNetGlow
                                onToggled: ShellSettings.underlineNetGlow = !ShellSettings.underlineNetGlow
                            }
                            ChoiceChipRow {
                                glyph: "󰄀"; label: "Screenshots"
                                rowEnabled: SystemTools.hasInotifywait
                                currentValue: root._underlineScreenshotStyle
                                model: [
                                    { value: "off",   label: "Off" },
                                    { value: "flash", label: "Flash" },
                                    { value: "sweep", label: "Sweep" }
                                ]
                                onChosen: (v) => root._setUnderlineScreenshotStyle(v)
                                bottomRadius: 10
                            }
                            HintText {
                                visible: !SystemTools.hasInotifywait
                                text: "Screenshot feedback needs inotify-tools."
                            }
                        }
                    }
                }
            }

            // ── NOTIFICATIONS · Popups ──────────────────────────────────
            Column {
                id: _secPopups
                width: parent.width
                spacing: 0
                visible: root._shownSection === "popups"

                SectionLabel { label: "ENABLE"; first: true }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰂚"; label: "Popup notifications"
                        checked: ShellSettings.notifPopupEnabled
                        onToggled: ShellSettings.notifPopupEnabled = !ShellSettings.notifPopupEnabled
                        topRadius: 10
                    }
                    ToggleRow {
                        glyph: "󰊓"; label: "Silence in fullscreen"
                        checked: ShellSettings.notifFullscreenSilence
                        onToggled: ShellSettings.notifFullscreenSilence = !ShellSettings.notifFullscreenSilence
                        bottomRadius: 10
                    }
                }

                SectionLabel { label: "DISPLAY" }
                SettingsCard {
                    ChoiceChipRow {
                        glyph: "󰔛"; label: "Dismiss after"
                        rowEnabled: ShellSettings.notifPopupEnabled
                        currentValue: ShellSettings.notifDefaultTimeout
                        model: [
                            { value: 3000,  label: "3s"  },
                            { value: 5000,  label: "5s"  },
                            { value: 10000, label: "10s" },
                            { value: 15000, label: "15s" }
                        ]
                        onChosen: (v) => ShellSettings.notifDefaultTimeout = v
                        topRadius: 10
                    }
                    ChoiceChipRow {
                        glyph: "󰍹"; label: "Position"
                        rowEnabled: ShellSettings.notifPopupEnabled
                        currentValue: ShellSettings.notifPosition
                        model: [
                            { value: "top-left",   label: "Left"   },
                            { value: "top-center", label: "Center" },
                            { value: "top-right",  label: "Right"  }
                        ]
                        onChosen: (v) => ShellSettings.notifPosition = v
                    }
                    ChoiceChipRow {
                        glyph: "󰽘"; label: "Max shown"
                        rowEnabled: ShellSettings.notifPopupEnabled
                        currentValue: ShellSettings.notifMaxVisible
                        model: [
                            { value: 3, label: "3"   },
                            { value: 5, label: "5"   },
                            { value: 0, label: "All" }
                        ]
                        onChosen: (v) => ShellSettings.notifMaxVisible = v
                        bottomRadius: 10
                    }
                }

                SectionLabel { label: "ALERTS" }
                SettingsCard {
                    ChoiceChipRow {
                        glyph: "󰀦"; label: "Alert duration"
                        rowEnabled: ShellSettings.notifPopupEnabled
                        currentValue: ShellSettings.sysAlertTimeout
                        model: [
                            { value: 5000,  label: "5s"   },
                            { value: 10000, label: "10s"  },
                            { value: 20000, label: "20s"  },
                            { value: 0,     label: "Stay" }
                        ]
                        onChosen: (v) => ShellSettings.sysAlertTimeout = v
                        topRadius: 10; bottomRadius: 10
                    }
                }
            }

            // ── NOTIFICATIONS · OSD ─────────────────────────────────────
            Column {
                id: _secOsd
                width: parent.width
                spacing: 0
                visible: root._shownSection === "osd"

                SectionLabel { label: "GENERAL"; first: true }
                SettingsCard {
                    ToggleRow {
                        glyph: "󱀅"; label: "Show OSD"
                        checked: ShellSettings.osdEnabled
                        onToggled: ShellSettings.osdEnabled = !ShellSettings.osdEnabled
                        topRadius: 10
                    }
                    // Mode: floating pill vs bar-inline. Drives which sub-options apply.
                    ToggleRow {
                        glyph: "󰀱"; label: "Show in bar"; badge: "beta"
                        enabled: ShellSettings.osdEnabled
                        checked: ShellSettings.osdBarIntegrated
                        onToggled: ShellSettings.osdBarIntegrated = !ShellSettings.osdBarIntegrated
                    }
                    ChoiceChipRow {
                        glyph: "󰔛"; label: "Dismiss after"
                        rowEnabled: ShellSettings.osdEnabled
                        currentValue: ShellSettings.osdTimeout
                        model: [
                            { value: 1000, label: "1s" },
                            { value: 2000, label: "2s" },
                            { value: 3000, label: "3s" },
                            { value: 5000, label: "5s" }
                        ]
                        onChosen: (v) => ShellSettings.osdTimeout = v
                    }
                    ChoiceChipRow {
                        glyph: "󰒓"; label: "Show for"
                        rowEnabled: ShellSettings.osdEnabled
                        currentValue: ShellSettings.osdKindFilter
                        model: [
                            { value: "both",       glyph: "󰓎", label: "Both" },
                            { value: "volume",     glyph: "󰕾", label: "Vol"  },
                            { value: "brightness", glyph: "󰃟", label: "Brt"  }
                        ]
                        onChosen: (v) => ShellSettings.osdKindFilter = v
                        bottomRadius: 10
                    }
                }

                SectionLabel { label: "EXTRAS" }
                SettingsCard {
                    ToggleRow {
                        glyph: "󰓎"; label: "Volume shimmer"
                        enabled: ShellSettings.osdEnabled && !ShellSettings.osdBarIntegrated
                        checked: ShellSettings.osdShimmer
                        onToggled: ShellSettings.osdShimmer = !ShellSettings.osdShimmer
                        // only when bar mode is the blocker; OSD-off just dims like its neighbours
                        dependsNote: ShellSettings.osdEnabled ? "Pill only" : ""
                        topRadius: 10
                    }
                    ToggleRow {
                        glyph: "󰕾"; label: "Loud volume tint"
                        enabled: ShellSettings.osdEnabled
                        checked: ShellSettings.osdVolumeTint
                        onToggled: ShellSettings.osdVolumeTint = !ShellSettings.osdVolumeTint
                    }
                    ToggleRow {
                        glyph: "󰂄"; label: "Fully-charged alert"
                        enabled: ShellSettings.osdEnabled && Battery.available
                        checked: ShellSettings.osdChargedNotify
                        onToggled: ShellSettings.osdChargedNotify = !ShellSettings.osdChargedNotify
                        bottomRadius: 10
                    }
                }
            }

            // ── NOTIFICATIONS · Warnings ────────────────────────────────
            Column {
                id: _secWarnings
                width: parent.width
                spacing: 0
                visible: root._shownSection === "warnings"

                SectionLabel { label: "BATTERY"; first: true }
                SettingsCard {
                    ChoiceChipRow {
                        glyph: "󱟢"; label: "Low battery alert"
                        currentValue: root._battAlertMode
                        model: root._alertChipModel
                        onChosen: (v) => root._setBattAlert(v)
                        topRadius: 10
                        bottomRadius: root._battAlertMode === "off" ? 10 : 0
                    }
                    CollapsibleSection {
                        expanded: root._battAlertMode !== "off"
                        SliderRow {
                            glyph: "󱟢"; label: "Alert below"
                            value: ShellSettings.batteryLowThreshold
                            min: 5; max: 50; step: 5
                            displayValue: ShellSettings.batteryLowThreshold + "%"
                            onChanged: (v) => ShellSettings.batteryLowThreshold = v
                            glyphColor: Battery.critical ? Theme.error : (Battery.low ? Theme.warning : Theme.withAlpha(Theme.subtext, 0.85))
                        }
                        HintText { text: "Escalates to critical at " + Math.max(5, Math.round(ShellSettings.batteryLowThreshold / 2)) + "%." }
                    }
                }

                SectionLabel { label: "CPU TEMPERATURE" }
                SettingsCard {
                    ChoiceChipRow {
                        glyph: "󰔏"; label: "High temp alert"
                        currentValue: root._tempAlertMode
                        model: root._alertChipModel
                        onChosen: (v) => root._setTempAlert(v)
                        topRadius: 10
                        bottomRadius: root._tempAlertMode === "off" ? 10 : 0
                    }
                    CollapsibleSection {
                        expanded: root._tempAlertMode !== "off"
                        SliderRow {
                            glyph: "󰔏"; label: "Alert above"
                            value: ShellSettings.tempHotThreshold
                            min: 70; max: 105; step: 5
                            displayValue: ShellSettings.tempHotThreshold + "°"
                            onChanged: (v) => ShellSettings.tempHotThreshold = v
                            glyphColor: CpuTemp.critical ? Theme.error : (CpuTemp.hot ? Theme.warning : Theme.withAlpha(Theme.subtext, 0.85))
                        }
                        HintText { text: "Escalates to critical at " + (ShellSettings.tempHotThreshold + 8) + "°." }
                    }
                }
            }
            }   // _detailBody
        }
    }
}
