import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph:        ""
    property string label:        ""
    property bool   checked:      false
    property real   topRadius:    0
    property real   bottomRadius: 0
    property bool   available:    true
    property string dependsNote:  ""
    property string badge:        ""   // small tag after the label, e.g. "beta"
    // tag colour by kind: warning for experimental ("beta"), neutral for info ("net")
    readonly property color _badgeColor: badge === "beta" ? Theme.warning : Theme.subtext
    // Matches the enclosing card's border width, keeps the hover fill inside
    // the stroke and aligned with the card's INNER rounded edge.
    property real   cardInset:    1

    signal toggled()

    readonly property bool _canToggle: root.enabled && (root.available || root.checked)
    readonly property bool _showDependsNote: root.dependsNote.length > 0
                                            && (!root.enabled || (!root.available && !root.checked))
    readonly property real _rightSlotW: _showDependsNote
        ? Math.min(_noteText.implicitWidth, Math.max(54, root.width * 0.34))
        : 34

    // 4px multiple: keeps card dividers on whole physical px under
    // fractional scaling.
    width:          parent ? parent.width : 0
    height:         44
    implicitHeight: 44

    opacity: _canToggle ? 1.0 : 0.45
    Behavior on opacity { NumberAnimation { duration: Motion.medium } }

    HoverHandler { id: _hover; cursorShape: root._canToggle ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler {
        enabled: root._canToggle
        onTapped: {
            // Animate the knob only on a real user flip; section switches re-run
            // layout and would otherwise slide every checked knob.
            if (!ShellSettings.reduceMotion) { _knob._animateX = true; _knobDisarm.restart() }
            root.toggled()
        }
    }

    RowHoverBg {
        anchors.fill: parent
        topRadius:    root.topRadius
        bottomRadius: root.bottomRadius
        cardInset:    root.cardInset
        active:       _hover.hovered && root._canToggle
        fillOpacity:  0.08
    }

    Item {
        anchors.left:           parent.left
        anchors.leftMargin:     12
        anchors.right:          _rightSlot.left
        anchors.rightMargin:    8
        anchors.verticalCenter: parent.verticalCenter
        height: 22
        clip: true

        Text {
            id: _glyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            horizontalAlignment: Text.AlignHCenter
            text:           root.glyph
            color:          root.checked
                ? Theme.withAlpha(Theme.accent, 0.9)
                : Theme.withAlpha(Theme.subtext, 0.85)
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize + 1
            renderType:     Text.NativeRendering
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        Text {
            id: _label
            anchors.left:           _glyph.right
            anchors.leftMargin:     8
            anchors.right:          _badge.visible ? _badge.left : parent.right
            anchors.rightMargin:    _badge.visible ? 8 : 0
            anchors.verticalCenter: parent.verticalCenter
            text:           root.label
            textFormat:     Text.PlainText
            elide:          Text.ElideRight
            color:          root.checked
                ? Theme.text
                : Theme.withAlpha(Theme.text, 0.85)
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize
            renderType:     Text.NativeRendering
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        // tag after the label (e.g. "beta", "net"), coloured by kind
        Rectangle {
            id: _badge
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.badge.length > 0
            width:  _badgeText.implicitWidth + 10
            height: _badgeText.implicitHeight + 4
            radius: 4
            antialiasing: true
            color: Theme.withAlpha(root._badgeColor, 0.08)
            border.width: 1
            border.color: Theme.withAlpha(root._badgeColor, 0.32)
            Text {
                id: _badgeText
                anchors.centerIn: parent
                text:           root.badge
                color:          Theme.withAlpha(root._badgeColor, 0.85)
                font.family:    Settings.font
                font.pixelSize: Settings.fontSize - 4
                font.weight:    Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing:  0
                renderType:     Text.NativeRendering
            }
        }
    }

    Item {
        id: _rightSlot
        anchors.right:          parent.right
        anchors.rightMargin:    12
        anchors.verticalCenter: parent.verticalCenter
        width: root._rightSlotW
        height: 18

        Rectangle {
            id: _toggle
            anchors.fill: parent
            visible: !root._showDependsNote
            radius: 9; antialiasing: true
            color: root.checked
                ? Theme.mix(Theme.menuControl, Theme.accent, 0.38)
                : Theme.menuControl
            border.width: 1
            border.color: root.checked
                ? Theme.mix(Theme.menuCard, Theme.accent, 0.62)
                : Theme.menuControlLine
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on border.color { ColorAnimation { duration: Motion.fast } }

            Rectangle {
                id: _knob
                anchors.verticalCenter: parent.verticalCenter
                width: 14; height: 14; radius: 7
                antialiasing: true
                x:     root.checked ? parent.width - width - 2 : 2
                color: root.checked ? Theme.accent : Theme.mix(Theme.subtext, Theme.accent, 0.16)

                // Stretch into a capsule while travelling, settle back round.
                property real _stretch: 1.0
                // Armed by the tap above; the disarm timer clears it once the
                // spring has settled, so only deliberate flips animate the slide.
                property bool _animateX: false
                transform: Scale {
                    origin.x: _knob.width  / 2
                    origin.y: _knob.height / 2
                    xScale: _knob._stretch
                    yScale: 1.0
                }

                Timer { id: _knobDisarm; interval: Motion.fast + Motion.medium + 80; onTriggered: _knob._animateX = false }

                Behavior on x     { enabled: _knob._animateX && !ShellSettings.reduceMotion; SpringAnimation { spring: 10; damping: 0.88; epsilon: 0.5 } }
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Connections {
                    target: root
                    function onCheckedChanged() {
                        if (ShellSettings.reduceMotion) { _knob._stretch = 1.0; return }
                        if (!_knob._animateX) { _knob._stretch = 1.0; return }
                        _knobStretch.restart()
                    }
                }
                Connections {
                    target: ShellSettings
                    function onReduceMotionChanged() {
                        if (ShellSettings.reduceMotion) { _knobStretch.stop(); _knob._stretch = 1.0 }
                    }
                }
                SequentialAnimation {
                    id: _knobStretch
                    NumberAnimation { target: _knob; property: "_stretch"; to: 1.22; duration: Motion.fast;   easing.type: Easing.OutQuad }
                    NumberAnimation { target: _knob; property: "_stretch"; to: 1.0;  duration: Motion.medium; easing.type: Easing.OutCubic }
                }
            }
        }

        Text {
            id: _noteText
            visible: root._showDependsNote
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: root.dependsNote
            elide: Text.ElideRight
            color: Theme.withAlpha(Theme.subtext, 0.40)
            font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
            renderType: Text.NativeRendering
        }
    }
}
