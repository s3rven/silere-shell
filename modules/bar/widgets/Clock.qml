import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    property var screen: null
    property bool compact: ShellSettings.barCompact
    property bool barActive: true
    readonly property bool _canInteract: root.enabled && root.visible && root.show && root.barActive && !Idle.isIdle
    readonly property bool _animatable: root.visible && root.barActive && !Idle.isIdle
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
    // reordering widgets or moving the bar rebuilds this clock under an open calendar, and the anchor it held drops:
    // the new one takes it back, as the workspace strip does for the menu. Unclaimed, the calendar closed 150 ms later
    function _reclaimCalendarAnchor(): void {
        if (!CalendarState.open || CalendarState.anchorSource !== null || !root.screen) return
        const target = CalendarState.triggerScreen
        if (target ? target.name === root.screen.name : root._anchorFallbackBar) CalendarState.adoptAnchor(root)
    }
    Connections {
        target: CalendarState
        // mapToItem sees no ancestor geometry, so the cached x is a stale layout pass by now
        function onOpenChanged() {
            if (CalendarState.open && CalendarState.anchorSource === null) root._syncMenuAnchor()
        }
        function onAnchorSourceChanged() { root._reclaimCalendarAnchor() }
    }

    // a resize is read before the zone lays out around it, so a centred clock gaining or losing its
    // date put the open calendar half that width off. While it is open only afterAnimating measures,
    // once the frame is laid out
    onXChanged: if (!root._calendarOpen) root._syncMenuAnchor()
    onYChanged: if (!root._calendarOpen) root._syncMenuAnchor()
    onWidthChanged: if (!root._calendarOpen) root._syncMenuAnchor()
    Component.onCompleted: {
        root._syncMenuAnchor()
        root._reclaimCalendarAnchor()
    }
    Connections {
        target: root.Window.window
        enabled: root._calendarOpen
        function onAfterAnimating() { root._syncMenuAnchor() }
    }

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

    // both switches before Weather is read: off, the service and its lookups are never created.
    // a failed refresh leaves the bar blank: the old reading has no room here to say it is old
    readonly property string _weather: ShellSettings.weatherEnabled && ShellSettings.clockShowWeather
        && Weather.hasData && !Weather.failed ? Weather.glyph + " " + Weather.temperature + "°" : ""

    readonly property bool _calendarOpen: CalendarState.open
        && (CalendarState.anchorSource === root
            || (CalendarState.anchorSource === null && root._anchorFallbackBar))
    readonly property bool _pressed: _calTap.pressed || _cycleTap.pressed
    readonly property bool _missed: Notifications.missedShown > 0
    readonly property bool _hov: root.barActive && root.show
        && _hover.hovered && ShellSettings.barHoverHighlight
    readonly property color _cSub:   _hov ? Theme.mix(Theme.barSubtext, Theme.barAccent, 0.30) : Theme.barSubtext
    readonly property color _cText:  _hov ? Theme.mix(Theme.barText,    Theme.barAccent, 0.30) : Theme.barText
    readonly property color _cFaint: _hov ? Theme.mix(Theme.withAlpha(Theme.barText, 0.65), Theme.barAccent, 0.30)
                                          : Theme.withAlpha(Theme.barText, 0.65)
    readonly property color _cSec:   _hov ? Theme.mix(Theme.barAccent, Theme.barText, 0.22)
                                          : Theme.withAlpha(Theme.barAccent, 0.82)

    HoverHandler {
        id: _hover
        enabled: root._canInteract
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: {
            if (hovered) {
                if (!root._datePeek) _datePeekDelay.restart()
            } else {
                _datePeekDelay.stop()
                if (!root.holdOpen) root._datePeek = false
            }
        }
    }

    // the pointer is still over the clock's bar zone, so a revealed date waits for it to leave, as the pills' details do
    property bool holdOpen: false
    onHoldOpenChanged: if (!holdOpen && !_hover.hovered) root._datePeek = false
    property bool _datePeek: false
    readonly property bool _dateRevealed: root._datePeek && (_hover.hovered || root.holdOpen)
        && ShellSettings.valuesOnHover && root._canInteract

    on_CanInteractChanged: if (!root._canInteract) {
        _datePeekDelay.stop()
        root._datePeek = false
    }

    Timer {
        id: _datePeekDelay
        interval: 80
        onTriggered: root._datePeek = true
    }

    function _openCalendar(): void {
        if (!root._canInteract) return
        root._syncMenuAnchor()
        CalendarState.toggleAt(root.menuAnchorX, root.screen, root)
    }

    HoverCap {
        hot: root._hov
        pressed: root._pressed
        selected: root._calendarOpen
        gate: root._animatable
    }

    Row {
        id: _content
        x: root._horizontalPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        layoutDirection: root.mirrored ? Qt.RightToLeft : Qt.LeftToRight

        // the space sits on the side facing the date, which flips with the row
        CollapsingText {
            text:     root._weather.length === 0 ? ""
                : root.mirrored ? " " + root._weather : root._weather + " "
            color:    root._cSub
            animate:  root._animatable
            expanded: root._weather.length > 0
        }

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

            // red is for a screen another app is capturing; a mode the user chose stays quiet
            CollapsingText {
                text:     "󱒃 "
                color:    Theme.barError
                animate:  root._animatable
                expanded: Compositor.screenSharing
            }
            CollapsingText {
                text:     "󰐨 "
                color:    root._cSub
                animate:  root._animatable
                expanded: Notifications.presentationMode && !Compositor.screenSharing
            }
            CollapsingText {
                text:     "󰅶 "
                color:    root._cSub
                animate:  root._animatable
                expanded: Idle.keepAwake && !Notifications.presentationMode
            }
            CollapsingText {
                // Do Not Disturb's bell while popups are held back; once they are not, a badged one for what came meanwhile
                text:     root._missed && !Notifications.silencingActive ? "󱅫 " : "󰂛 "
                color:    root._missed ? Theme.barAccentMark : root._cSub
                animate:  root._animatable
                expanded: Notifications.effectiveDnd || root._missed
            }
            RollingText {
                tabularDigits: true
                // the 12-hour clock writes 1-9 unpadded; a two-digit reserve left a blank digit before them
                reserveText: ShellSettings.clock12h ? "0" : "00"
                horizontalAlignment: Text.AlignRight
                text:    DateTime.cachedHour
                color:   root._cText
                animate: root._animatable
            }
            // figures, so it takes their "case" colon: the font's own sits on the x-height, a pixel under the digits' middle
            RollingText { text: ":"; tabularDigits: true; color: root._cText; animate: root._animatable }
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
        + (root._weather.length > 0 ? ", " + Weather.temperature + Weather.unit + " " + Weather.condition : "")
        + (Compositor.screenSharing ? ", Sharing screen" : "")
        + (Notifications.presentationMode ? ", Presentation Mode" : "")
        + (Idle.keepAwake ? ", Keep Awake" : "")
        + (Notifications.effectiveDnd ? ", Do Not Disturb" : "")
        + (Notifications.dndUntil > 0 ? " until " + DateTime.clockText(new Date(Notifications.dndUntil)) : "")
        + (!root._missed ? "" : Notifications.missedShown === 1 ? ", 1 missed notification"
            : ", " + Notifications.missedShown + " missed notifications")
    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.focusable: root._canInteract
    Accessible.onPressAction: root._openCalendar()
    KeyboardFocus { ringY: Metrics.barWidgetReach; ringHeight: height - 2 * Metrics.barWidgetReach; interactive: control ? control.Accessible.focusable : false; listNavigation: true; onActivated: { if (control) control.Accessible.pressAction() } }

    TapHandler {
        id: _calTap
        enabled: root._canInteract
        gesturePolicy: TapHandler.ReleaseWithinBounds
        acceptedButtons: Qt.LeftButton
        onTapped: root._openCalendar()
    }

    TapHandler {
        id: _cycleTap
        enabled: root._canInteract
        gesturePolicy: TapHandler.ReleaseWithinBounds
        acceptedButtons: Qt.MiddleButton
        onTapped: {
            if (!root._canInteract) return
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
