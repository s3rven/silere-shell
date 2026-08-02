import QtQuick
import "../../../config"
import "../../common"

Item {
    id: root

    property string glyph:       ""
    property string title:       ""
    property string status:      ""
    property string valueText:   ""
    property color  accentColor: Theme.accent
    property bool   active:       false
    property bool   available:    true
    property bool   showSwitch:   false
    property bool   expandable:   false
    property bool   expanded:     false
    property int    badgeCount:   0

    property real topRadius:    0
    property real bottomRadius: 0
    property real cardInset:    1
    property real cardLeftBleed: 0

    signal activated()
    signal expandToggled()
    signal badgeActivated()

    readonly property bool _canTap: root.enabled && root.available
    readonly property string _accessibleDetail: {
        let detail = root.status.length > 0 ? root.status : root.valueText
        if (root.expandable) {
            const state = root.expanded ? "Expanded" : "Collapsed"
            detail = detail.length > 0 ? detail + ", " + state : state
        }
        return detail
    }

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

    width:          parent ? parent.width : 0
    height:         48
    implicitHeight: height

    opacity: _canTap ? 1.0 : 0.45
    MotionBehavior on opacity {NumberAnimation { duration: Motion.medium } }

    activeFocusOnTab: _canTap
    Accessible.role: root.showSwitch ? Accessible.Switch : Accessible.Button
    Accessible.name: root.title
    Accessible.description: root._accessibleDetail
    Accessible.checked: root.active
    Accessible.onPressAction: root._activate()
    Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }
    Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }
    Keys.onRightPressed: event => {
        if (root._canTap && root.expandable && !root.expanded) {
            root.expandToggled()
            event.accepted = true
        } else {
            event.accepted = false
        }
    }
    Keys.onLeftPressed: event => {
        if (root._canTap && root.expandable && root.expanded) {
            root.expandToggled()
            event.accepted = true
        } else {
            event.accepted = false
        }
    }

    HoverHandler { id: _hover; cursorShape: root._canTap ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler {
        id: _tap
        enabled: root._canTap
        onTapped: (eventPoint, button) => {
            if (!root._insideChevron(eventPoint.position) && !root._insideBadge(eventPoint.position)) root._activate()
        }
    }

    RowHoverBg {
        anchors.fill: parent
        topRadius:    root.topRadius
        bottomRadius: root.bottomRadius
        cardInset:    root.cardInset
        leftBleed:    root.cardLeftBleed
        active:       (_hover.hovered || root.activeFocus) && root._canTap
        // stacking the focus marker on the active one lengthens the pill
        focusActive:  root.activeFocus && root._canTap && !root.active
        fillOpacity:  root.activeFocus ? 0.13 : 0.08
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
            visible: root.badgeCount > 0
            anchors.horizontalCenter: parent.right
            anchors.verticalCenter:   parent.top
            anchors.horizontalCenterOffset: -2
            anchors.verticalCenterOffset:    1
            width:  Math.max(15, _badgeTxt.implicitWidth + 7)
            height: 15
            radius: 7.5
            antialiasing: true
            z: 2
            activeFocusOnTab: visible
            Accessible.role: Accessible.Button
            Accessible.name: "Open missed notifications"
            Accessible.description: root.badgeCount + (root.badgeCount === 1 ? " missed notification" : " missed notifications")
            Accessible.onPressAction: root._activateBadge()

            Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) root._activateBadge(); event.accepted = true }
            Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root._activateBadge(); event.accepted = true }
            Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) root._activateBadge(); event.accepted = true }

            color: (_badgeMouse.containsMouse || activeFocus)
                ? Theme.mix(root.accentColor, Theme.text, 0.10)
                : root.accentColor
            ColorFade on color {}

            OutlineBorder {
                radius: _badge.radius
                outlineWidth: _badge.activeFocus ? 2 : 1
                outlineColor: _badge.activeFocus
                    ? Theme.withAlpha(Theme.text, 0.66)
                    : Theme.mix(Theme.menuCard, root.accentColor, _badgeMouse.containsMouse ? 0.42 : 0.55)
                ColorFade on outlineColor {}
            }

            ShellText {
                id: _badgeTxt
                anchors.centerIn: parent
                text:  root.badgeCount > 99 ? "99+" : root.badgeCount
                color: Theme.background
                font.pixelSize: Settings.fontSize - 4
                font.weight: Font.Bold
            }

            MouseArea {
                id: _badgeMouse
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root._activateBadge()
            }
        }
    }

    Column {
        id: _textCol
        anchors.left:           _iconSlot.right
        anchors.leftMargin:     10
        anchors.right:          _rightSlot.left
        anchors.rightMargin:    8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        ShellText {
            width:          parent.width
            text:           root.title
            color:          root.active ? Theme.text : Theme.withAlpha(Theme.text, 0.85)
            font.pixelSize: Settings.fontSize
            font.weight:    Font.DemiBold
            font.hintingPreference: Font.PreferFullHinting
            elide:          Text.ElideRight
            ColorFade on color {}
        }

        ShellText {
            visible:        root.status.length > 0
            width:          parent.width
            text:           root.status
            color:          root.active ? Theme.mix(root.accentColor, Theme.text, 0.12)
                                        : Theme.withAlpha(Theme.subtext, 0.62)
            font.pixelSize: Math.max(10, Settings.fontSize - 2)
            font.weight:    Font.Medium
            font.hintingPreference: Font.PreferFullHinting
            elide:          Text.ElideRight
            ColorFade on color {}
        }
    }

    Item {
        id: _rightSlot
        anchors.right:          parent.right
        anchors.rightMargin:    12
        anchors.verticalCenter: parent.verticalCenter
        height: 20
        readonly property real _ctrlW: root.showSwitch ? 36
                                     : (root.valueText.length > 0 ? Math.ceil(_valMetrics.advanceWidth) : 0)
        width: (_chevron.visible ? _chevron.width + 8 : 0) + _ctrlW

        TextMetrics { id: _valMetrics; font.family: Settings.font; font.pixelSize: Settings.fontSize - 1; text: root.valueText }

        ToggleSwitch {
            id: _switch
            visible: root.showSwitch
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked:     root.active
            highlighted: _hover.hovered && root._canTap
            focused: root.activeFocus && root._canTap
            pressed: _tap.pressed
            accentColor: root.accentColor
        }

        ShellText {
            visible: !root.showSwitch && root.valueText.length > 0
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            text:           root.valueText
            color:          root.active ? Theme.mix(root.accentColor, Theme.text, 0.18)
                                        : Theme.withAlpha(Theme.text, 0.60)
            font.pixelSize: Settings.fontSize - 1
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
            activeFocusOnTab: root._canTap && root.expandable

            Accessible.role: Accessible.Button
            Accessible.name: root.title + " details"
            Accessible.description: root.expanded ? "Expanded" : "Collapsed"
            Accessible.onPressAction: root._toggleExpanded()

            Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) root._toggleExpanded(); event.accepted = true }
            Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root._toggleExpanded(); event.accepted = true }
            Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) root._toggleExpanded(); event.accepted = true }
            Keys.onEscapePressed: event => {
                if (root.expanded) {
                    root._toggleExpanded()
                    event.accepted = true
                } else {
                    event.accepted = false
                }
            }

            ShellText {
                anchors.centerIn: parent
                text: "󰅀"
                color: (_chevHover.hovered || _chevron.activeFocus) ? Theme.text
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
                anchors.margins: -4
                enabled: root.expandable
                cursorShape: Qt.PointingHandCursor
                onClicked: root._toggleExpanded()
            }
        }
    }
}
