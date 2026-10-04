pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../services"
import "../common"

PanelWindow {
    id: win

    required property ShellScreen targetScreen
    readonly property var popupCard: card

    readonly property string _output: Compositor.monitorName(win.screen)

    Connections {
        target: Compositor
        function onWorkspaceActivated(output) {
            if (output === win._output && CalendarState.open) CalendarState.close()
        }
    }

    // full screen only to catch the closing click: the compositor recomposites every pixel of a surface Qt redraws, so the card animates in its own narrow window
    screen:        targetScreen
    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "silere-calendar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    visible: CalendarState.open || cardWin.visible
    // layer surfaces stack in map order: mapped after the card, this window would cover it and take its clicks
    property bool _cardMayMap: false
    onVisibleChanged: {
        if (visible) Qt.callLater(() => win._cardMayMap = win.visible)
        else win._cardMayMap = false
    }

    anchors { top: true; left: true; right: true; bottom: true }

    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: CalendarState.open; onActivated: CalendarState.close() }

    OutsideTapGuard {
        id: _tapGuard
        open: CalendarState.open
    }

    Item { id: _fillArea; anchors.fill: parent }
    mask: Region { item: CalendarState.open ? _fillArea : null }
    // an empty region, not none: the silere-calendar layer rule would otherwise blur the whole screen behind this window
    BackgroundEffect.blurRegion: Region { item: null }

    TapHandler {
        id: _dismiss
        enabled: CalendarState.open
        onTapped: {
            if (_tapGuard.ignoring) return
            const p = _dismiss.point.position
            if (p.x < card.x || p.x > card.x + card.width ||
                p.y < card.y || p.y > card.y + card.height)
                CalendarState.close()
        }
    }

    PanelWindow {
        id: cardWin

        // room for the shadow; snapped so a moving anchor rarely reconfigures the surface
        readonly property int _slack: 48
        readonly property real _screenW: win.screen ? win.screen.width : 0
        readonly property int _left: Math.max(0,
            64 * Math.floor((card.placementSpan.x - _slack) / 64))
        readonly property int _right: Math.min(Math.ceil(_screenW),
            64 * Math.ceil((card.placementSpan.y + card.targetWidth + _slack) / 64))

        screen:        win.screen
        color:         "transparent"
        exclusiveZone: -1
        WlrLayershell.namespace: "silere-calendar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: CalendarState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        visible: (CalendarState.open || card.opacity > 0.001) && win._cardMayMap

        anchors { top: true; bottom: true; left: true }
        margins.left: cardWin._left
        implicitWidth: Math.max(1, cardWin._right - cardWin._left)

        // the card alone: anywhere else in the strip has to fall through to the closing window below
        mask: Region {
            item: CalendarState.open ? card : null
            Region { item: _stage; intersection: Intersection.Intersect }
        }
        BackgroundEffect.blurRegion: Region {
            item: card.blurItem
            radius: Math.round(card.radius)
            // a region rebuilds only when one of its own items moves, and the stage carries every card x shift
            Region { item: _stage; intersection: Intersection.Intersect }
        }

        // screen coordinates: the card places itself as it did in a full-screen window
        Item {
            id: _stage
            x: -cardWin._left
            width: cardWin._screenW
            height: parent.height

            PopupShadow { card: card }

            FloatingPopupCard {
                id: card
                win: win
                open: CalendarState.open
                anchorX: CalendarState.effectiveAnchorX
                barBottom: Metrics.barAtBottom

                readonly property int  cell:     Metrics.rowHeightFor(32) + 4
                readonly property int  pad:      14
                readonly property int  weekCol:  ShellSettings.calendarWeekNumbers ? 22 : 0
                readonly property int  gridW:    weekCol + cell * 7
                readonly property int  panelW:   Metrics.snap4Up(gridW + pad * 2)

                property int dispYear:  2000
                property int dispMonth: 0
                property int shownYear:  2000
                property int shownMonth: 0
                property int navDir:     0

                // "today" captured fresh on each open — the card persists, so a readonly `new Date()` binding would freeze at first build and highlight the wrong day forever
                property int    _todayY:      -1
                property int    _todayM:      -1
                property int    _todayD:      -1
                property int    _todayWeek:   -1
                property string todayWeekday: ""

                readonly property int _lead: CalendarState.leadingDays(shownYear, shownMonth)
                readonly property int _daysThis: new Date(shownYear, shownMonth + 1, 0).getDate()
                readonly property int _todayCell:
                    (_todayY === shownYear && _todayM === shownMonth) ? _lead + _todayD - 1 : -1
                readonly property int _rowCount: Math.ceil((_lead + _daysThis) / 7)
                readonly property string monthLabel: Qt.formatDateTime(new Date(shownYear, shownMonth, 1), "MMMM yyyy")

                function _dateForCell(index: int): var {
                    return new Date(card.shownYear, card.shownMonth, index - card._lead + 1)
                }

                function _activateDay(index: int): void {
                    if (!CalendarState.open || _gridSwap.running || index < 0 || index >= card._rowCount * 7) return
                    const date = card._dateForCell(index)
                    if (date.getFullYear() !== card.shownYear || date.getMonth() !== card.shownMonth)
                        card._go(date.getFullYear(), date.getMonth(), index < card._lead ? -1 : 1)
                }

                function _weekForRow(r: int): int {
                    return CalendarState.weekForRow(card.shownYear, card.shownMonth, r)
                }

                function _snapToday(): void {
                    const t = new Date()
                    _todayY = t.getFullYear(); _todayM = t.getMonth(); _todayD = t.getDate()
                    _todayWeek = DateTime.isoWeek(t)
                    todayWeekday = Qt.formatDateTime(t, "dddd")
                    dispYear  = _todayY; dispMonth  = _todayM
                    shownYear = _todayY; shownMonth = _todayM
                    _gridSwap.stop(); _grid.opacity = 1; _grid.xOff = 0
                }
                function _go(y: int, m: int, dir: int): void {
                    navDir = dir
                    dispYear = y; dispMonth = m
                    if (ShellSettings.reduceMotion) { _gridSwap.stop(); shownYear = y; shownMonth = m; _grid.opacity = 1; _grid.xOff = 0; return }
                    _gridSwap.restart()
                }
                function _step(delta: int): void {
                    let m = dispMonth + delta, y = dispYear
                    while (m < 0)  { m += 12; y-- }
                    while (m > 11) { m -= 12; y++ }
                    _go(y, m, delta < 0 ? -1 : 1)
                }
                function _goToday(): void {
                    const t = new Date()
                    const cur = dispYear * 12 + dispMonth
                    const tgt = t.getFullYear() * 12 + t.getMonth()
                    if (tgt === cur) return
                    _go(t.getFullYear(), t.getMonth(), tgt > cur ? 1 : -1)
                }
                Connections {
                    target: CalendarState
                    function onOpenChanged() {
                        if (CalendarState.open) {
                            card._snapToday()
                            card.forceActiveFocus()
                        } else _gridSwap.stop()
                    }
                }
                Connections {
                    target: DateTime
                    function onCachedDateCoreChanged() {
                        if (!CalendarState.open) return
                        const t = DateTime.currentDate
                        card._todayY = t.getFullYear(); card._todayM = t.getMonth(); card._todayD = t.getDate()
                        card._todayWeek = DateTime.isoWeek(t)
                        card.todayWeekday = Qt.formatDateTime(t, "dddd")
                    }
                }
                Component.onCompleted: card._snapToday()

                SequentialAnimation {
                    id: _gridSwap
                    ParallelAnimation {
                        NumberAnimation { target: _grid; property: "opacity"; to: 0;                duration: Motion.pageOut; easing.type: Easing.InCubic }
                        NumberAnimation { target: _grid; property: "xOff";    to: -card.navDir * 14; duration: Motion.pageOut; easing.type: Easing.InCubic }
                    }
                    ScriptAction {
                        script: {
                            card.shownYear = card.dispYear
                            card.shownMonth = card.dispMonth
                            _grid.xOff = card.navDir * 14
                        }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: _grid; property: "opacity"; to: 1; duration: Motion.pageIn; easing.type: Easing.OutCubic }
                        NumberAnimation { target: _grid; property: "xOff";    to: 0; duration: Motion.pageIn; easing.type: Easing.OutQuart }
                    }
                }

                width:  panelW
                height: 4 * Math.ceil((_col.implicitHeight + pad * 2) / 4)
                // a month with a sixth week row resizes the card while it stays open
                MotionBehavior on height {
                    gate: card.geometryMotionReady
                    NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (e) => {
                        const n = Scroll.processControlWheel(e, "calendar")
                        if (n !== 0) card._step(-n)
                    }
                }

                Column {
                    id: _col
                    x: Math.round((card.panelW - card.gridW) / 2); y: card.pad
                    width: card.gridW
                    spacing: 6

                    Item {
                        id: _headerRow
                        width: parent.width
                        height: Metrics.rowHeightFor(36)

                        Item {
                            id: _todayButton
                            // the pill, not the row: a full-width hit area lights the narrow fill from 200px away
                            width: _todayRow.width + 20
                            height: parent.height

                            Accessible.role: Accessible.Button
                            Accessible.name: "Today"
                            Accessible.focusable: true
                            Accessible.onPressAction: card._goToday()

                            HoverHandler { id: _todayH; cursorShape: Qt.PointingHandCursor }
                            TapHandler   { id: _todayTap; onTapped: card._goToday() }

                            Rectangle {
                                id: _todayFill
                                anchors.fill: parent
                                radius: Theme.radiusControl
                                antialiasing: true
                                color: _todayTap.pressed
                                    ? Theme.withAlpha(Theme.accent, 0.13)
                                    : _todayH.hovered
                                        ? Theme.withAlpha(Theme.subtext, 0.12)
                                        : "transparent"
                                ColorFade on color {}
                            }

                            Row {
                                id: _todayRow
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 11

                                ShellText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: card._todayD < 0 ? "" : card._todayD
                                    color: Theme.accent
                                    font.pixelSize: Settings.fontSize + 15; font.weight: Font.DemiBold
                                }
                                ShellText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: card.todayWeekday
                                    color: (_todayH.hovered) ? Theme.text : Theme.withAlpha(Theme.text, 0.9)
                                    font.pixelSize: Settings.fontSize + 1; font.weight: Font.DemiBold
                                    ColorFade on color {}
                                }
                            }
                        }

                        ShellText {
                            anchors.right: parent.right
                            anchors.rightMargin: 2
                            anchors.verticalCenter: parent.verticalCenter
                            visible: ShellSettings.calendarWeekNumbers && card._todayWeek > 0
                            text: "Week " + card._todayWeek
                            color: Theme.withAlpha(Theme.subtext, 0.78)
                            font.pixelSize: Settings.fontCaption
                        }
                    }

                    Hairline {
                        width: parent.width
                        color: Theme.withAlpha(Theme.subtext, Theme.lineAlpha(0.13))
                    }

                    Item {
                        width: parent.width
                        height: 30

                        IconButton {
                            id: _prevButton
                            buttonSize: 26
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "󰅁"
                            accessibleName: "Previous month"
                            onTriggered: card._step(-1)
                        }

                        Item {
                            id: _monthButton
                            anchors.centerIn: parent
                            // the grid it names starts a week column in, so centring on the row leaves it visibly left of the days
                            anchors.horizontalCenterOffset: Math.round(card.weekCol / 2)
                            width: _mLabel.implicitWidth + 16; height: 26
                            Accessible.role: Accessible.Button
                            Accessible.name: "Return to current month"
                            Accessible.focusable: true
                            Accessible.onPressAction: card._goToday()
                            // distinct from the today pill's: two controls reading "Jump to today" are indistinguishable by voice
                            HoverHandler { id: _mH; cursorShape: Qt.PointingHandCursor }
                            TapHandler   { id: _mT; onTapped: card._goToday() }

                            Rectangle {
                                id: _monthFill
                                anchors.fill: parent
                                radius: Theme.radiusControl
                                antialiasing: true
                                color: Theme.buttonFill(Theme.accent, _mH.hovered, _mT.pressed)
                                ColorFade on color {}

                                OutlineBorder {
                                    radius: _monthFill.radius
                                    outlineColor: Theme.buttonLine(
                                        Theme.accent, _mH.hovered, _mT.pressed)
                                    ColorFade on outlineColor {}
                                }
                            }
                            ShellText {
                                id: _mLabel
                                anchors.centerIn: parent
                                text: card.monthLabel
                                color: (_mH.hovered) ? Theme.text : Theme.withAlpha(Theme.text, 0.9)
                                font.pixelSize: Settings.fontSize + 1; font.weight: Font.DemiBold
                                ColorFade on color {}
                            }
                        }

                        IconButton {
                            id: _nextButton
                            buttonSize: 26
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "󰅂"
                            accessibleName: "Next month"
                            onTriggered: card._step(1)
                        }
                    }

                    // the header labels the grid, so it sits nearer to it than to the month row above
                    Item { width: parent.width; height: 3 }

                    Row {
                        width: parent.width
                        Item {
                            visible: ShellSettings.calendarWeekNumbers
                            width: card.weekCol; height: 20
                            ShellText {
                                anchors.centerIn: parent
                                text: "Wk"
                                color: Theme.withAlpha(Theme.subtext, 0.78)
                                font.pixelSize: Settings.fontMicro
                                font.weight: Font.Medium; font.capitalization: Font.AllUppercase
                            }
                        }
                        Repeater {
                            model: 7
                            delegate: Item {
                                id: dayHdr
                                required property int index
                                readonly property int weekday: CalendarState.weekdayAt(index)
                                width: card.cell; height: 20
                                ShellText {
                                    anchors.centerIn: parent
                                    text: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"][dayHdr.weekday]
                                    color: Theme.withAlpha(Theme.subtext, dayHdr.weekday === 0 || dayHdr.weekday === 6 ? 0.78 : 0.92)
                                    font.pixelSize: Settings.fontMicro
                                    font.weight: Font.Medium; font.capitalization: Font.AllUppercase
                                }
                            }
                        }
                    }

                    Item {
                        id: _gridWrap
                        width: parent.width
                        height: card._rowCount * card.cell
                        clip: true

                        Column {
                            id: _weekAxis
                            visible: ShellSettings.calendarWeekNumbers
                            x: 0
                            width: card.weekCol
                            opacity: _grid.opacity
                            Repeater {
                                model: card._rowCount
                                delegate: Item {
                                    id: _weekRow
                                    required property int index
                                    width: card.weekCol
                                    height: card.cell
                                    ShellText {
                                        anchors.centerIn: parent
                                        text: card._weekForRow(_weekRow.index)
                                        color: Theme.withAlpha(Theme.subtext, 0.78)
                                        font.pixelSize: Settings.fontTiny
                                        font.weight: Font.Medium
                                    }
                                }
                            }
                        }

                        Hairline {
                            visible: ShellSettings.calendarWeekNumbers
                            x: card.weekCol - width
                            y: 0
                            vertical: true
                            height: parent.height
                            color: Theme.withAlpha(Theme.subtext, Theme.lineAlpha(0.10))
                        }

                        Grid {
                            id: _grid
                            property real xOff: 0
                            x: card.weekCol + xOff
                            width: card.cell * 7
                            columns: 7
                            // one texture for the whole grid while it slides, not a re-raster per cell
                            layer.enabled: _gridSwap.running && !ShellSettings.reduceMotion

                            Repeater {
                                model: card._rowCount * 7
                                delegate: Item {
                                    id: _dayCell
                                    required property int index

                                    readonly property bool cur:   index >= card._lead && index < card._lead + card._daysThis
                                    readonly property bool today: index === card._todayCell
                                    readonly property int weekday: CalendarState.weekdayAt(index % 7)
                                    readonly property bool weekend: weekday === 0 || weekday === 6
                                    readonly property var date: card._dateForCell(index)
                                    readonly property int dayNum: date.getDate()

                                    width: card.cell; height: card.cell

                                    Accessible.role: _dayCell.cur ? Accessible.StaticText : Accessible.Button
                                    Accessible.name: Qt.formatDateTime(_dayCell.date, "dddd, d MMMM yyyy")
                                    Accessible.description: _dayCell.cur ? ""
                                        : "Show " + Qt.formatDateTime(_dayCell.date, "MMMM yyyy")
                                    Accessible.focusable: !_dayCell.cur && CalendarState.open && !_gridSwap.running
                                    Accessible.onPressAction: card._activateDay(_dayCell.index)

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: card.cell - 4; height: width; radius: width / 2
                                        antialiasing: true
                                        color: _dayCell.today ? Theme.accent
                                            : _dayTap.pressed
                                                ? Theme.withAlpha(Theme.accent, 0.14)
                                            : (_dayH.hovered
                                                ? Theme.withAlpha(Theme.subtext, 0.10)
                                                : "transparent")
                                        ColorFade on color {}

                                        HoverHandler {
                                            id: _dayH
                                            enabled: !_dayCell.cur && CalendarState.open && !_gridSwap.running
                                            cursorShape: Qt.PointingHandCursor
                                        }
                                        TapHandler {
                                            id: _dayTap
                                            enabled: !_dayCell.cur && CalendarState.open && !_gridSwap.running
                                            onTapped: card._activateDay(_dayCell.index)
                                        }
                                        ShellText {
                                            anchors.centerIn: parent
                                            text: _dayCell.dayNum
                                            color: _dayCell.today ? Theme.background
                                                 : _dayCell.cur   ? Theme.withAlpha(Theme.text, _dayCell.weekend ? 0.82 : 0.9)
                                                 :                  Theme.withAlpha(Theme.subtext, 0.64)
                                            font.pixelSize: Settings.fontSize
                                            font.weight: _dayCell.today ? Font.DemiBold : Font.Normal
                                        }

                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
