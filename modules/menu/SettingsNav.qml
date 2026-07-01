pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"

Item {
    id: root

    property bool powerOpen: false
    readonly property bool active: MenuState.open && MenuState.activeTab === 1 && !powerOpen

    // Full tree height, so the panel can size to fit it (MenuWindow's height floor).
    implicitHeight: _content.height

    readonly property int _navTop:     10
    readonly property int _navGapY:    10   // between groups
    readonly property int _navRowH:    30
    readonly property int _navRowGap:  2    // within a group
    readonly property int _navHdrH:    22
    readonly property int _navStdHdrH: 12   // standalone leaf's divider slot

    // synchronous tree walk avoids mapToItem race on first frame
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
        sequences: ["Ctrl+Down"]
        context: Qt.ApplicationShortcut
        enabled: root.active
        onActivated: MenuState.stepSettingsSection(1)
    }
    Shortcut {
        sequences: ["Ctrl+Up"]
        context: Qt.ApplicationShortcut
        enabled: root.active
        onActivated: MenuState.stepSettingsSection(-1)
    }

    Flickable {
        id: _navScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: _content.height
        clip: true
        boundsMovement: Flickable.StopAtBounds
        flickDeceleration: 1800
        maximumFlickVelocity: 2200
        interactive: contentHeight > height + 1

        Item {
            id: _content
            width: root.width
            height: _navCol.implicitHeight + root._navTop + 10

            // ── Sliding selection ───────────────────────────────────────
            // _selReady defers the Behavior one frame so it's correct on open
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
                    NumberAnimation { duration: Motion.ms(155); easing.type: Easing.OutCubic }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    antialiasing: true
                    color: Theme.menuControl
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    antialiasing: true
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.menuControlLine
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: 14
                    radius: 1.5
                    antialiasing: true
                    color: Theme.accent
                }
            }

            Column {
                id: _navCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 9
                anchors.rightMargin: 9
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
                                anchors.leftMargin:     9
                                anchors.bottom:         parent.bottom
                                anchors.bottomMargin:   4
                                text:           _grp.modelData.label
                                color:          _grp.groupActive
                                    ? Theme.withAlpha(Theme.menuTextMuted, 0.90)
                                    : Theme.withAlpha(Theme.menuTextMuted, 0.58)
                                font.family:    Settings.font
                                font.pixelSize: Settings.fontSize - 3
                                font.letterSpacing:  0.5
                                font.weight:    Font.DemiBold
                                font.capitalization: Font.AllUppercase
                                renderType:     Text.NativeRendering
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }
                            Rectangle {
                                visible:              _grp.isGroup
                                anchors.left:         _hdrLabel.right
                                anchors.leftMargin:   8
                                anchors.right:        parent.right
                                anchors.rightMargin:  8
                                anchors.verticalCenter: _hdrLabel.verticalCenter
                                height: 1
                                radius: 0.5
                                color: _grp.groupActive
                                    ? Theme.menuDivider
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
                                property real _shift: active ? 0.5 : (_leafHover.hovered ? 0.5 : 0.0)

                                readonly property color _fg: active
                                    ? Theme.text
                                    : Theme.withAlpha(Theme.mix(Theme.subtext, Theme.text, 0.12), _leafHover.hovered || _leaf.activeFocus ? 0.92 : 0.76)
                                readonly property color _glyphFg: active
                                    ? Theme.mix(Theme.accent, Theme.text, 0.10)
                                    : Theme.withAlpha(Theme.subtext, _leafHover.hovered || _leaf.activeFocus ? 0.76 : 0.56)

                                width: parent.width
                                height: root._navRowH
                                radius: 8
                                antialiasing: true
                                color: ((_leafHover.hovered || _leaf.activeFocus) && !active)
                                    ? Theme.withAlpha(Theme.text, 0.045) : "transparent"
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                                Behavior on _shift {
                                    enabled: !ShellSettings.reduceMotion
                                    NumberAnimation { duration: Motion.ms(105); easing.type: Easing.OutCubic }
                                }

                                activeFocusOnTab: root.active
                                Accessible.role: Accessible.Button
                                Accessible.name: _leaf.modelData.label
                                Keys.onSpacePressed: event => { if (!event.isAutoRepeat) MenuState.setSettingsSection(_leaf.modelData.section); event.accepted = true }
                                Keys.onReturnPressed: event => { if (!event.isAutoRepeat) MenuState.setSettingsSection(_leaf.modelData.section); event.accepted = true }
                                Keys.onEnterPressed: event => { if (!event.isAutoRepeat) MenuState.setSettingsSection(_leaf.modelData.section); event.accepted = true }

                                HoverHandler { id: _leafHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler   { id: _leafTap; onTapped: MenuState.setSettingsSection(_leaf.modelData.section) }
                                scale: _leafTap.pressed ? 0.985 : 1.0
                                transformOrigin: Item.Left
                                Behavior on scale {
                                    enabled: !ShellSettings.reduceMotion
                                    NumberAnimation { duration: Motion.ms(95); easing.type: Easing.OutCubic }
                                }

                                Text {
                                    id: _leafGlyph
                                    anchors.left:           parent.left
                                    anchors.leftMargin:     13
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 19
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
                                    anchors.rightMargin:    9
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: _leaf.modelData.label
                                    elide: Text.ElideRight
                                    color: _leaf._fg
                                    font.family:    Settings.font
                                    font.pixelSize: Settings.fontSize
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

    ListEdgeFade {
        anchors.fill: _navScroll
        visible: _navScroll.interactive
        fadeColor: Theme.menuPane
        list: _navScroll
    }
}
