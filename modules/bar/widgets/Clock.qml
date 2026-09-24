import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    property var screen: null
    property bool compact: ShellSettings.barCompact
    property bool barActive: true
    readonly property bool _animatable: root.barActive && !Idle.isIdle
    property real menuAnchorX: 0
    readonly property int _horizontalPadding: Metrics.pillPadFor(compact)

    // a keybind opens with no trigger widget, so the state's fallback x has to stay fresh
    readonly property bool _anchorFallbackBar: !!root.screen && root.screen.name === Monitors.overlayBarName

    function _syncMenuAnchor(): void {
        const pt = root.mapToItem(null, root.width / 2, 0)
        if (!isFinite(pt.x)) return
        root.menuAnchorX = pt.x
        if (root._anchorFallbackBar) CalendarState.anchorX = pt.x
    }
    on_AnchorFallbackBarChanged: root._syncMenuAnchor()
    Connections {
        target: CalendarState
        // mapToItem sees no ancestor geometry, so the cached x is a stale layout pass by now
        function onOpenChanged() {
            if (CalendarState.open && CalendarState.anchorSource === null) root._syncMenuAnchor()
        }
    }

    onXChanged: root._syncMenuAnchor()
    onYChanged: root._syncMenuAnchor()
    onWidthChanged: root._syncMenuAnchor()
    Component.onCompleted: root._syncMenuAnchor()

    readonly property bool mirrored: ShellSettings.barWidgetOrderLeftKeys.indexOf("clock") !== -1

    readonly property bool show: ShellSettings.barShowClock
    property real _showProgress: show ? 1.0 : 0.0
    readonly property bool layoutVisible: show || _showProgress > 0.001
    implicitWidth: (_content.implicitWidth + root._horizontalPadding * 2) * _showProgress
    implicitHeight: _content.implicitHeight
    visible: layoutVisible
    enabled: show
    opacity: _showProgress
    clip: _showProgress < 0.999

    MotionBehavior on _showProgress {
        NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
    }

    readonly property bool _calendarOpen: CalendarState.open
        && (CalendarState.anchorSource === root
            || (CalendarState.anchorSource === null && root._anchorFallbackBar))
    readonly property bool _pressed: _calTap.pressed || _cycleTap.pressed
    readonly property bool _hov: root.barActive && root.show
        && _hover.hovered && ShellSettings.barHoverHighlight
    readonly property color _cSub:   _hov ? Theme.mix(Theme.subtext, Theme.accent, 0.30) : Theme.subtext
    readonly property color _cText:  _hov ? Theme.mix(Theme.text,    Theme.accent, 0.30) : Theme.text
    readonly property color _cFaint: _hov ? Theme.mix(Theme.withAlpha(Theme.text, 0.65), Theme.accent, 0.30)
                                          : Theme.withAlpha(Theme.text, 0.65)
    readonly property color _cSec:   _hov ? Theme.mix(Theme.accent, Theme.text, 0.22)
                                          : Theme.withAlpha(Theme.accent, 0.82)

    HoverHandler {
        id: _hover
        enabled: root.enabled && root.visible && root.barActive
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: {
            root._datePeek = false
            if (hovered) _datePeekDelay.restart()
            else _datePeekDelay.stop()
        }
    }

    property bool _datePeek: false
    readonly property bool _dateRevealed: root._datePeek && _hover.hovered
        && ShellSettings.valuesOnHover && !Idle.isIdle

    Timer {
        id: _datePeekDelay
        interval: 80
        onTriggered: root._datePeek = true
    }

    function _openCalendar(): void {
        root._syncMenuAnchor()
        CalendarState.toggleAt(root.menuAnchorX, root.screen, root)
    }

    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: Metrics.barRowHeight
        radius: Metrics.hoverRadiusFor(height)
        color: root._pressed ? Theme.withAlpha(Theme.accent, 0.18)
            : root._calendarOpen ? Theme.withAlpha(Theme.accent, 0.12)
            : Theme.withAlpha(Theme.mix(Theme.text, Theme.accent, 0.30), 0.07)
        opacity: root._pressed || root._calendarOpen || root._hov ? 1 : 0
        visible: opacity > 0.001
        MotionBehavior on opacity {
            gate: root._animatable
            NumberAnimation { duration: Motion.fast }
        }
        ColorFade on color { gate: root._animatable }
    }

    Row {
        id: _content
        x: root._horizontalPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        layoutDirection: root.mirrored ? Qt.RightToLeft : Qt.LeftToRight

        Item {
            id: _dateSectionClip
            anchors.verticalCenter: parent.verticalCenter
            height:  _dateRow.implicitHeight
            // the day and date ease their own widths; easing their sum again stalls until they settle
            property real _shown: ShellSettings.clockShowDate || root._dateRevealed ? 1 : 0
            MotionBehavior on _shown {NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic } }
            width:   (_dateRow.implicitWidth + Metrics.clockDateGapFor(root.compact)) * _shown
            opacity: _shown
            visible: _shown > 0.001
            clip:    true

            Row {
                id: _dateRow
                anchors.verticalCenter: parent.verticalCenter
                x: root.mirrored ? parent.width - width : 0
                spacing: 0

                CollapsingText {
                    text:     DateTime.cachedDayName
                    color:    root._cSub
                    animate:  root._animatable
                    expanded: !ShellSettings.compactDate && !root.compact
                }
                RollingText {
                    text:    DateTime.cachedDateCore
                    color:   root._cSub
                    animate: root._animatable
                }
            }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            RollingText {
                tabularDigits: true
                reserveText: "00"
                horizontalAlignment: Text.AlignRight
                text:    DateTime.cachedHour
                color:   root._cText
                animate: root._animatable
            }
            RollingText { text: ":"; color: root._cText; animate: root._animatable }
            RollingText {
                tabularDigits: true
                reserveText: "00"
                horizontalAlignment: Text.AlignRight
                text:    DateTime.cachedMinute
                color:   root._cText
                animate: root._animatable
            }
            CollapsingText {
                text:     DateTime.cachedSeconds
                color:    root._cSec
                animate:  root._animatable
                expanded: ShellSettings.showSeconds
                reserveText: ":00"
                tabularDigits: true
            }
            CollapsingText {
                text:     DateTime.cachedAmPm ? " " + DateTime.cachedAmPm : ""
                color:    root._cFaint
                animate:  root._animatable
                expanded: ShellSettings.clock12h
            }
        }
    }

    readonly property string accessibleName: "Clock, " + DateTime.cachedHour + ":" + DateTime.cachedMinute
        + (DateTime.cachedAmPm.length > 0 ? " " + DateTime.cachedAmPm : "")
        + ", " + DateTime.cachedWeekday + " " + DateTime.cachedMonthDay
    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.focusable: root.show
    Accessible.onPressAction: root._openCalendar()

    TapHandler {
        id: _calTap
        enabled: root.show && root.barActive
        gesturePolicy: TapHandler.ReleaseWithinBounds
        acceptedButtons: Qt.LeftButton
        onTapped: root._openCalendar()
    }

    TapHandler {
        id: _cycleTap
        enabled: root.show && root.barActive
        gesturePolicy: TapHandler.ReleaseWithinBounds
        acceptedButtons: Qt.MiddleButton
        onTapped: {
            // a peeked date would hide the step that turns the date off
            root._datePeek = false
            ShellSettings.batch(() => {
                const s = ShellSettings.showSeconds
                const d = ShellSettings.clockShowDate
                if (!s && !d)     { ShellSettings.showSeconds = true }
                else if (s && !d) { ShellSettings.showSeconds = false; ShellSettings.clockShowDate = true }
                else if (!s && d) { ShellSettings.showSeconds = true }
                else              { ShellSettings.showSeconds = false; ShellSettings.clockShowDate = false }
            })
        }
    }
}
