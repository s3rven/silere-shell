pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"

FittedPopupWindow {
    id: win

    targetScreen: CalendarState.surfaceScreen
    open: CalendarState.open
    layerNamespace: "silere-calendar"
    popupCard: card
    onDismissed: CalendarState.close()
    onEscapePressed: CalendarState.close()

    PopupShadow { card: card }

    FloatingPopupCard {
        id: card
        win: win
        open: CalendarState.open
        anchorX: CalendarState.effectiveAnchorX
        barBottom: Metrics.barAtBottom

        readonly property int  cell:     Metrics.rowHeightFor(32) + 4
        // a short screen (768p at 2x) lowers the weeks on the 4px grid rather than run the card off its edge
        readonly property real _gridRoom: winH - _edgeY - 8 - pad * 2 - _gridWrap.y
            - (_weather.visible ? _col.spacing + _weather.height : 0)
        readonly property int  rowH:     Math.max(Metrics.snap4Up(Settings.fontSize * 1.5),
            Math.min(cell, Metrics.snap4Down(_gridRoom / _rowCount)))
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
        // six weeks for every month, as GtkCalendar and GNOME Shell do: a four or five week month resized the card,
        // which under a bottom bar moved the arrows out from under the pointer
        readonly property int _rowCount: 6
        // the target month, not the drawn one: fast scrolling keeps the grid mid-swap, and the label must not freeze with it
        readonly property string monthLabel: Qt.formatDateTime(new Date(dispYear, dispMonth, 1), "MMMM yyyy")
        // standalone, not the "MMMM" format form: some locales decline the month inside a date
        readonly property string monthName: Qt.locale().standaloneMonthName(dispMonth, Locale.LongFormat)
        readonly property bool onTodayMonth: dispYear === _todayY && dispMonth === _todayM
        readonly property string todayCaption: _todayM < 0 ? ""
            : Qt.locale().standaloneMonthName(_todayM, Locale.LongFormat)
                + (ShellSettings.calendarWeekNumbers && _todayWeek > 0 ? " · Week " + _todayWeek : "")

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
            if (!CalendarState.open) return
            navDir = dir
            dispYear = y; dispMonth = m
            if (ShellSettings.reduceMotion) { card._settleMonth(); return }
            // a restart per wheel notch never reaches the swap; a running one takes the latest month at its midpoint
            if (!_gridSwap.running) _gridSwap.restart()
        }
        function _settleMonth(): void {
            _gridSwap.stop()
            shownYear = dispYear
            shownMonth = dispMonth
            _grid.opacity = 1
            _grid.xOff = 0
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
                    card._requestWeather()
                } else _gridSwap.stop()
            }
        }
        Connections {
            target: ShellSettings
            function onReduceMotionChanged(): void {
                if (ShellSettings.reduceMotion) card._settleMonth()
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
                card._requestWeather()
            }
        }
        // the popup loads on its first open, after that open edge has passed: it takes the keys here instead
        Component.onCompleted: {
            card._snapToday()
            if (CalendarState.open) card.forceActiveFocus()
            card._requestWeather()
        }
        function _requestWeather(): void {
            if (ShellSettings.weatherEnabled) Weather.request(false)
        }

        SequentialAnimation {
            id: _gridSwap
            onFinished: if (CalendarState.open && (card.shownYear !== card.dispYear
                    || card.shownMonth !== card.dispMonth)) _gridSwap.restart()
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
        height: _heightGlide.value
        SmoothGlide {
            id: _heightGlide
            target: 4 * Math.ceil((_col.implicitHeight + card.pad * 2) / 4)
            gate: card.geometryMotionReady
            duration: Motion.normal
        }

        // the date-grid convention: Page Up and Page Down turn the month from wherever focus sits in the card
        function _pageKey(key: int): bool {
            if (key !== Qt.Key_PageUp && key !== Qt.Key_PageDown) return false
            card._step(key === Qt.Key_PageUp ? -1 : 1)
            return true
        }
        Keys.onPressed: (e) => { e.accepted = card._pageKey(e.key) }

        WheelHandler {
            enabled: CalendarState.open
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
                width: parent.width
                height: Metrics.rowHeightFor(48)

                Item {
                    id: _todayButton
                    // the pill hangs into the margin so the numeral, not the fill, lines up with the grid;
                    // and it is the pill, not the row: a full-width hit area lights the narrow fill from 200px away
                    x: -8
                    width: _todayContent.width + 16
                    height: parent.height

                    Accessible.role: Accessible.Button
                    Accessible.name: "Today"
                    Accessible.focusable: CalendarState.open
                    Accessible.onPressAction: card._goToday()
                    KeyboardFocus { interactive: control ? control.Accessible.focusable : false; listNavigation: true; onActivated: { if (control) control.Accessible.pressAction() } }
                    // pointer feedback only once there is a month to return from
                    HoverHandler { id: _todayH; enabled: CalendarState.open && !card.onTodayMonth; cursorShape: Qt.PointingHandCursor }
                    TapHandler   { id: _todayTap; enabled: CalendarState.open && !card.onTodayMonth; onTapped: card._goToday() }

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusControl
                        antialiasing: true
                        color: _todayTap.pressed ? Theme.withAlpha(Theme.accent, 0.13)
                            : _todayH.hovered ? Theme.withAlpha(Theme.subtext, 0.12)
                            : "transparent"
                        ColorFade on color {}
                    }

                    Row {
                        id: _todayContent
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 11

                        ShellText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: card._todayD < 0 ? "" : card._todayD
                            color: Theme.accent
                            font.pixelSize: Settings.fontSize + 15; font.weight: Font.DemiBold
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            ShellText {
                                text: card.todayWeekday
                                color: _todayH.hovered ? Theme.text : Theme.withAlpha(Theme.text, 0.9)
                                font.pixelSize: Settings.fontSize + 1; font.weight: Font.DemiBold
                                ColorFade on color {}
                            }
                            ShellText {
                                text: card.todayCaption
                                color: Theme.withAlpha(Theme.subtext, 0.78)
                                font.pixelSize: Settings.fontCaption
                            }
                        }
                    }
                }
            }

            Hairline {
                width: parent.width
                color: Theme.withAlpha(Theme.subtext, Theme.lineAlpha(0.13))
            }

            Item {
                width: parent.width
                height: Metrics.rowHeightFor(34)

                IconButton {
                    id: _prevButton
                    enabled: CalendarState.open
                    buttonSize: Metrics.rowHeightFor(28)
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
                    width: _monthRow.width + 20
                    height: Metrics.rowHeightFor(28)

                    Accessible.role: Accessible.Button
                    Accessible.name: "Return to current month"
                    Accessible.description: "Showing " + card.monthLabel
                    Accessible.focusable: CalendarState.open
                    Accessible.onPressAction: card._goToday()
                    KeyboardFocus { interactive: control ? control.Accessible.focusable : false; listNavigation: true; onActivated: { if (control) control.Accessible.pressAction() } }
                    HoverHandler { id: _mH; enabled: CalendarState.open && !card.onTodayMonth; cursorShape: Qt.PointingHandCursor }
                    TapHandler   { id: _mT; enabled: CalendarState.open && !card.onTodayMonth; onTapped: card._goToday() }

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusControl
                        antialiasing: true
                        color: _mT.pressed ? Theme.withAlpha(Theme.accent, 0.13)
                            : _mH.hovered ? Theme.withAlpha(Theme.subtext, 0.12)
                            : "transparent"
                        ColorFade on color {}
                    }

                    Row {
                        id: _monthRow
                        anchors.centerIn: parent
                        spacing: 6

                        ShellText {
                            id: _mLabel
                            anchors.baseline: _yLabel.baseline
                            // a long localized name gives way to the arrows rather than running under them
                            width: Math.max(0, Math.min(implicitWidth,
                                _monthButton.parent.width - _prevButton.width - _nextButton.width
                                    - card.weekCol - 44 - _monthRow.spacing - _yLabel.implicitWidth))
                            elide: Text.ElideRight
                            text: card.monthName
                            color: _mH.hovered ? Theme.text : Theme.withAlpha(Theme.text, 0.9)
                            font.pixelSize: Settings.fontSize + 1; font.weight: Font.DemiBold
                            ColorFade on color {}
                        }
                        ShellText {
                            id: _yLabel
                            text: Qt.formatDateTime(new Date(card.dispYear, card.dispMonth, 1), "yyyy")
                            color: Theme.withAlpha(Theme.subtext, 0.78)
                            font.pixelSize: Settings.fontSize + 1
                        }
                    }
                }

                IconButton {
                    id: _nextButton
                    enabled: CalendarState.open
                    buttonSize: Metrics.rowHeightFor(28)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "󰅂"
                    accessibleName: "Next month"
                    onTriggered: card._step(1)
                }
            }

            // the header labels the grid, so it sits nearer to it than to the month row above
            Item { width: parent.width; height: 2 }

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
                        readonly property bool weekend: CalendarState.isWeekend(dayHdr.weekday)
                        width: card.cell; height: 20
                        Accessible.role: Accessible.StaticText
                        Accessible.name: Qt.locale().standaloneDayName(dayHdr.weekday, Locale.LongFormat)
                        ShellText {
                            anchors.centerIn: parent
                            width: parent.width - 4
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: CalendarState.weekdayLabelFor(dayHdr.weekday, Qt.locale())
                            color: Theme.withAlpha(Theme.subtext, dayHdr.weekend ? 0.78 : 0.92)
                            font.pixelSize: Settings.fontMicro
                            font.weight: Font.Medium; font.capitalization: Font.AllUppercase
                        }
                    }
                }
            }

            Item {
                id: _gridWrap
                width: parent.width
                height: card._rowCount * card.rowH
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
                            height: card.rowH
                            ShellText {
                                anchors.centerIn: parent
                                text: card._weekForRow(_weekRow.index)
                                color: _weekRow.index === Math.floor(card._todayCell / 7)
                                    ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.78)
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
                            readonly property bool weekend: CalendarState.isWeekend(weekday)
                            readonly property var date: card._dateForCell(index)
                            readonly property int dayNum: date.getDate()

                            width: card.cell; height: card.rowH

                            Accessible.role: _dayCell.cur ? Accessible.StaticText : Accessible.Button
                            Accessible.name: Qt.formatDateTime(_dayCell.date, "dddd, d MMMM yyyy")
                            Accessible.description: _dayCell.cur ? ""
                                : "Show " + Qt.formatDateTime(_dayCell.date, "MMMM yyyy")
                            Accessible.focusable: !_dayCell.cur && CalendarState.open && !_gridSwap.running
                            Accessible.onPressAction: card._activateDay(_dayCell.index)
                            KeyboardFocus { interactive: control ? control.Accessible.focusable : false; listNavigation: true; onActivated: { if (control) control.Accessible.pressAction() } }

                            Rectangle {
                                anchors.centerIn: parent
                                width: card.rowH - 4; height: width; radius: Theme.radiusInline
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
                                         : _dayCell.cur   ? (_dayCell.weekend ? Theme.withAlpha(Theme.subtext, 0.86) : Theme.withAlpha(Theme.text, 0.9))
                                         :                  Theme.withAlpha(Theme.subtext, 0.64)
                                    font.pixelSize: Settings.fontSize
                                    font.weight: _dayCell.today ? Font.DemiBold : Font.Normal
                                }

                            }
                        }
                    }
                }
            }

            // today's weather once it arrives: the grid never waits on the network, and the card's height glide brings the row in
            Item {
                id: _weather
                readonly property bool shown: ShellSettings.weatherEnabled
                    && (Weather.hasData || Weather.failed)
                readonly property bool retry: _weather.shown && Weather.failed && !Weather.loading
                visible: _weather.shown
                width: parent.width
                height: _weather.shown ? Metrics.rowHeightFor(38) : 0

                Accessible.role: _weather.retry ? Accessible.Button : Accessible.StaticText
                Accessible.name: !_weather.shown ? ""
                    : Weather.hasData ? "Weather in " + Weather.place + ", " + Weather.temperature
                        + Weather.unit + ", " + Weather.condition + ", high " + Weather.high
                        + ", low " + Weather.low + (Weather.failed
                            ? ". Previous reading. " + (Weather.loading ? "Updating" : Weather.failure + ". Retry") : "")
                    : Weather.loading ? "Updating weather"
                    : "Weather unavailable, " + Weather.failure + ". Retry"
                Accessible.focusable: _weather.retry && CalendarState.open
                Accessible.onPressAction: if (_weather.retry) Weather.request(true)
                KeyboardFocus { interactive: control ? control.Accessible.focusable : false; listNavigation: true; onActivated: { if (control) control.Accessible.pressAction() } }

                HoverHandler { id: _weatherH; enabled: _weather.retry; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: _weather.retry; onTapped: Weather.request(true) }

                Hairline {
                    width: parent.width
                    color: Theme.withAlpha(Theme.subtext, Theme.lineAlpha(0.13))
                }

                // off means the service is never created; a binding below would otherwise instantiate it
                Loader {
                    id: _weatherBody
                    y: 4
                    width: parent.width
                    height: parent.height - 4
                    active: ShellSettings.weatherEnabled
                    sourceComponent: Item {
                        ShellText {
                            id: _weatherGlyph
                            x: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: Weather.hasData && Weather.glyph.length > 0 ? Weather.glyph : "󰖐"
                            color: Weather.hasData ? Theme.withAlpha(Theme.text, 0.86)
                                : Theme.withAlpha(Theme.subtext, 0.64)
                            font.pixelSize: Settings.fontSize + 5
                        }

                        ShellText {
                            id: _weatherTemp
                            anchors.left: _weatherGlyph.right
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Weather.hasData
                            text: Weather.temperature + "°"
                            color: Theme.text
                            font.pixelSize: Settings.fontSize + 2
                            font.weight: Font.DemiBold
                        }

                        ShellText {
                            id: _weatherRange
                            anchors.right: parent.right
                            anchors.rightMargin: 2
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Weather.hasData
                            text: "H " + Weather.high + "°  L " + Weather.low + "°"
                            color: Theme.withAlpha(Theme.subtext, 0.86)
                            font.pixelSize: Settings.fontCaption
                        }

                        ShellText {
                            anchors.left: _weatherTemp.visible ? _weatherTemp.right : _weatherGlyph.right
                            anchors.leftMargin: 8
                            anchors.right: _weatherRange.visible ? _weatherRange.left : parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: Weather.loading && Weather.failed ? "Updating…"
                                : Weather.hasData && Weather.failed ? "Update failed · Retry"
                                : Weather.hasData
                                ? (Weather.place.length > 0 ? Weather.condition + " · " + Weather.place : Weather.condition)
                                : Weather.failure
                            color: _weatherH.hovered ? Theme.withAlpha(Theme.text, 0.92)
                                : Weather.failed && !Weather.loading ? Theme.warning
                                : Theme.withAlpha(Theme.subtext, 0.86)
                            font.pixelSize: Settings.fontCaption
                            elide: Text.ElideRight
                            ColorFade on color {}
                        }
                    }
                }
            }
        }
    }
}
