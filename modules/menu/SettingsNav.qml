pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

// Settings category tree, embedded in MenuWindow's rail (not a free-standing
// card). Drives MenuState.settingsSection; SettingsPage renders the matching
// detail pane. Sits flush on the rail surface — the rail provides fill/dividers.
Item {
    id: root

    property bool powerOpen: false
    readonly property bool active: MenuState.open && MenuState.activeTab === 1 && !powerOpen

    // Full tree height, so the panel can size to fit it (MenuWindow's height floor).
    implicitHeight: _content.height

    readonly property int _navTop:     10
    readonly property int _navGapY:    10   // between groups
    readonly property int _navRowH:    28
    readonly property int _navRowGap:  2    // within a group
    readonly property int _navHdrH:    22
    readonly property int _navStdHdrH: 13   // standalone leaf's divider slot

    // y of a section's row, computed straight from the tree — exact and synchronous,
    // so the sliding marker is right on the first frame (no mapToItem race).
    function _sectionRowY(section: string): real {
        const tree = MenuState.settingsTree
        let y = _navTop
        for (let i = 0; i < tree.length; i++) {
            const it = tree[i]
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

    Shortcut {
        sequences: ["Down"]
        context: Qt.ApplicationShortcut
        enabled: root.active
        onActivated: MenuState.stepSettingsSection(1)
    }
    Shortcut {
        sequences: ["Up"]
        context: Qt.ApplicationShortcut
        enabled: root.active
        onActivated: MenuState.stepSettingsSection(-1)
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: _content.height
        clip: true
        boundsMovement: Flickable.StopAtBounds
        flickDeceleration: 1800
        interactive: contentHeight > height + 1

        Item {
            id: _content
            width: root.width
            height: _navCol.implicitHeight + root._navTop + 10

            // ── Sliding selection ───────────────────────────────────────
            // One accent marker that glides between rows, mod-menu style.
            // Position comes straight from the tree, so it's right on the first
            // frame; _selReady holds motion off until after that frame.
            property bool _selReady: false
            Component.onCompleted: Qt.callLater(function() { _content._selReady = true })

            Item {
                id: _selHighlight
                x: 6
                width: _content.width - 12
                y: root._sectionRowY(MenuState.settingsSection)
                height: root._navRowH

                Behavior on y {
                    enabled: _content._selReady && !ShellSettings.reduceMotion
                    NumberAnimation { duration: Motion.ms(180); easing.type: Easing.OutCubic }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    antialiasing: true
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0;  color: Theme.withAlpha(Theme.accent, 0.18) }
                        GradientStop { position: 0.45; color: Theme.withAlpha(Theme.accent, 0.09) }
                        GradientStop { position: 1.0;  color: Theme.withAlpha(Theme.accent, 0.018) }
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
                    model: MenuState.settingsTree

                    delegate: Column {
                        id: _grp
                        required property var modelData
                        width: parent.width
                        spacing: root._navRowGap

                        readonly property bool isGroup: !!modelData.children
                        readonly property var  _leaves: isGroup ? modelData.children : [modelData]
                        readonly property bool groupActive: {
                            for (let i = 0; i < _leaves.length; i++) {
                                if (_leaves[i].section === MenuState.settingsSection) return true
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
                                readonly property bool   active: MenuState.settingsSection === modelData.section
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
                                TapHandler   { id: _leafTap; onTapped: MenuState.setSettingsSection(_leaf.modelData.section) }
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
    }
}
