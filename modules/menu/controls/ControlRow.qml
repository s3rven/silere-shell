import QtQuick
import "../../../config"
import "../../common"

MenuRow {
    id: root

    property string title:       ""
    property string status:      ""
    property string valueText:   ""
    property color  accentColor: Theme.accent
    property bool   active:       false
    property bool   available:    true
    property bool   showSwitch:   false
    property bool   expandable:   false
    property bool   expanded:     false
    property bool   passive:      false
    property int    badgeCount:   0

    rowHovered:     _hover.hovered
    rowInteractive: root._canTap

    signal activated()
    signal expandToggled()
    signal badgeActivated()

    readonly property bool _canTap: !root.passive && root.enabled && root.available
    function _activate(): void {
        if (!_canTap) return
        // animate the knob only on a real user flip, not section-driven re-checks
        if (showSwitch) _switch.armFlipAnimation()
        root.activated()
    }

    function _activateBadge(): void {
        if (root.badgeCount > 0) root.badgeActivated()
    }

    function _toggleExpanded(): void {
        if (root._canTap && root.expandable) root.expandToggled()
    }

    function _insideChevron(pos): bool {
        if (!root.expandable || !_chevron.visible) return false
        const x0 = _rightSlot.x + _chevron.x - 4
        const x1 = _rightSlot.x + _chevron.x + _chevron.width + 4
        return pos.x >= x0 && pos.x <= x1
    }

    function _insideBadge(pos): bool {
        if (root.badgeCount <= 0 || !_badge.visible) return false
        const mapped = _badge.mapFromItem(root, pos.x, pos.y)
        return mapped.x >= -4 && mapped.x <= _badge.width + 4
            && mapped.y >= -4 && mapped.y <= _badge.height + 4
    }

    height:         Metrics.rowHeightFor(48)

    opacity: root.passive ? 1.0 : (_canTap ? 1.0 : 0.45)
    MotionBehavior on opacity {NumberAnimation { duration: Motion.medium } }

    HoverHandler { id: _hover; cursorShape: root._canTap ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler {
        id: _tap
        enabled: root._canTap
        onTapped: (eventPoint) => {
            if (!root._insideChevron(eventPoint.position) && !root._insideBadge(eventPoint.position)) {
                root._activate()
            }
        }
    }

    Item {
        id: _iconSlot
        anchors.left:           parent.left
        anchors.leftMargin:     14
        anchors.verticalCenter: parent.verticalCenter
        width: 18; height: 18

        ShellText {
            id: _glyph
            anchors.centerIn: parent
            text:           root.glyph
            color:          root.active ? Theme.withAlpha(root.accentColor, 0.95)
                                        : Theme.withAlpha(Theme.subtext, 0.85)
            font.pixelSize: Settings.iconSize + 2
            ColorFade on color {}
        }

        Rectangle {
            id: _badge
            opacity: root.badgeCount > 0 ? 1.0 : 0.0
            scale:   root.badgeCount > 0 ? 1.0 : 0.5
            visible: opacity > 0.01
            transformOrigin: Item.Center
            MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }
            MotionBehavior on scale   {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            anchors.horizontalCenter: parent.right
            anchors.verticalCenter:   parent.top
            anchors.horizontalCenterOffset: -2
            anchors.verticalCenterOffset:    1
            width:  Math.max(15, _badgeTxt.implicitWidth + 7)
            height: 15
            radius: 7.5
            antialiasing: true
            z: 2

            color: (_badgeMouse.containsMouse)
                ? Theme.mix(root.accentColor, Theme.text, 0.10)
                : root.accentColor
            ColorFade on color {}

            OutlineBorder {
                radius: _badge.radius
                outlineWidth: 1
                outlineColor: Theme.mix(Theme.menuCard, root.accentColor, _badgeMouse.containsMouse ? 0.42 : 0.55)
                ColorFade on outlineColor {}
            }

            ShellText {
                id: _badgeTxt
                anchors.centerIn: parent
                text:  root.badgeCount > 99 ? "99+" : root.badgeCount
                color: Theme.background
                font.pixelSize: Settings.fontTiny
                font.weight: Font.Bold
            }

            MouseArea {
                id: _badgeMouse
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root._activateBadge()
                }
            }
        }
    }

    Column {
        id: _textCol
        anchors.left:           _iconSlot.right
        anchors.leftMargin:     10
        anchors.right:          _rightSlot.left
        anchors.rightMargin:    10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        ShellText {
            width:          parent.width
            text:           root.title
            color:          root.active ? Theme.text : Theme.withAlpha(Theme.text, 0.85)
            font.pixelSize: Settings.fontSize
            font.weight:    Font.DemiBold
            elide:          Text.ElideRight
            ColorFade on color {}
        }

        ShellText {
            visible:        root.status.length > 0
            width:          parent.width
            text:           root.status
            color:          root.active ? Theme.mix(root.accentColor, Theme.text, 0.12)
                                        : Theme.withAlpha(Theme.subtext, 0.62)
            font.pixelSize: Settings.fontCaption
            font.weight:    Font.Medium
            elide:          Text.ElideRight
            ColorFade on color {}
        }
    }

    Item {
        id: _rightSlot
        anchors.right:          parent.right
        anchors.rightMargin:    12
        anchors.verticalCenter: parent.verticalCenter
        height: root.height
        readonly property real _chevronW: _chevron.visible ? _chevron.width + 8 : 0
        readonly property real _valNatural: Math.ceil(_valMetrics.advanceWidth)
        // the title names the setting and the value only qualifies it, so a long value
        // gives way first: 42 of label inset + 22 of margins + the same 96 label floor
        // SelectRow reserves. Uncapped, the value took its full width and elided the title.
        readonly property real _valMax: Math.max(0, root.width - 160 - _chevronW)
        readonly property real _ctrlW: root.showSwitch ? 36
            : root.valueText.length === 0 ? 0
            : root.width <= 0 ? _valNatural
            : Math.min(_valNatural, _valMax)
        width: _chevronW + _ctrlW

        TextMetrics { id: _valMetrics; font.family: Settings.font; font.pixelSize: Settings.fontLabel; text: root.valueText }

        ToggleSwitch {
            id: _switch
            visible: root.showSwitch
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked:     root.active
            highlighted: _hover.hovered && root._canTap
            pressed: _tap.pressed
            accentColor: root.accentColor
        }

        ShellText {
            visible: !root.showSwitch && root.valueText.length > 0
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            width:          _rightSlot._ctrlW
            horizontalAlignment: Text.AlignRight
            elide:          Text.ElideRight
            text:           root.valueText
            color:          root.active ? Theme.mix(root.accentColor, Theme.text, 0.18)
                                        : Theme.withAlpha(Theme.text, 0.60)
            font.pixelSize: Settings.fontLabel
            font.weight:    Font.Medium
            ColorFade on color {}
        }

        // MouseArea (not TapHandler) so it doesn't fire the row body tap too
        Item {
            id: _chevron
            visible: root.expandable
            width:  visible ? 24 : 0
            height: parent.height
            anchors.right: (root.showSwitch || root.valueText.length > 0) ? undefined : parent.right
            x: (root.showSwitch || root.valueText.length > 0)
                ? parent.width - _rightSlot._ctrlW - 8 - width
                : 0

            ShellText {
                anchors.centerIn: parent
                text: "󰅀"
                color: (_chevHover.hovered) ? Theme.text
                     : Theme.withAlpha(Theme.subtext, root.expanded ? 0.85 : 0.55)
                font.pixelSize: Settings.fontSize
                rotation: root.expanded ? 180 : 0
                transformOrigin: Item.Center
                MotionBehavior on rotation {NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
                ColorFade on color {}
            }

            HoverHandler { id: _chevHover; enabled: root.expandable; cursorShape: Qt.PointingHandCursor }
            MouseArea {
                anchors.fill: parent
                anchors.leftMargin: -4
                anchors.rightMargin: -4
                enabled: root.expandable
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root._toggleExpanded()
                }
            }
        }
    }
}
