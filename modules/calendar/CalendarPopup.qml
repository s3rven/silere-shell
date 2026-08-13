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

    readonly property string _output: Compositor.monitorName(win.screen)

    Connections {
        target: Compositor
        function onWorkspaceActivated(output) {
            if (output === win._output && CalendarState.open) CalendarState.close()
        }
    }

    screen:        targetScreen
    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "silere-calendar"
    WlrLayershell.keyboardFocus: CalendarState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: CalendarState.open || card.opacity > 0.001

    anchors { top: true; left: true; right: true; bottom: true }

    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: CalendarState.open; onActivated: CalendarState.close() }

    OutsideTapGuard {
        id: _tapGuard
        open: CalendarState.open
    }

    Item { id: _fillArea; anchors.fill: parent }
    mask: Region { item: CalendarState.open ? _fillArea : null }

    TapHandler {
        id: _dismiss
        enabled: CalendarState.open && card.scaleAmt > 0.95
        onTapped: {
            if (_tapGuard.ignoring) return
            const p = _dismiss.point.position
            if (p.x < card.x || p.x > card.x + card.width ||
                p.y < card.y || p.y > card.y + card.height)
                CalendarState.close()
        }
    }

    PopupShadow { card: card }

    FloatingPopupCard {
        id: card
        win: win
        open: CalendarState.open
        anchorX: CalendarState.effectiveAnchorX
        barBottom: Metrics.barAtBottom

        readonly property int  cell:     34
        readonly property int  pad:      14
        readonly property int  weekCol:  22
        readonly property int  panelW:   weekCol + cell * 7 + pad * 2

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

        readonly property int _firstJs:  new Date(shownYear, shownMonth, 1).getDay()
        readonly property int _lead:     (_firstJs + 6) % 7
        readonly property int _daysThis: new Date(shownYear, shownMonth + 1, 0).getDate()
        readonly property int _daysPrev: new Date(shownYear, shownMonth,     0).getDate()
        readonly property int _todayCell:
            (_todayY === shownYear && _todayM === shownMonth) ? _lead + _todayD - 1 : -1
        readonly property int _rowCount: Math.ceil((_lead + _daysThis) / 7)
        readonly property string monthLabel: Qt.formatDateTime(new Date(shownYear, shownMonth, 1), "MMMM yyyy")

        function _weekForRow(r: int): int {
            return DateTime.isoWeek(new Date(card.shownYear, card.shownMonth, 1 - card._lead + r * 7))
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
                const t = new Date()
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


        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (e) => {
                const n = Scroll.processControlWheel(e, "calendar")
                if (n !== 0) card._step(-n)
            }
        }

        Column {
            id: _col
            x: card.pad; y: card.pad
            width: card.panelW - card.pad * 2
            spacing: 6

            Item {
                id: _todayButton
                // the pill, not the row: a full-width hit area lights the narrow fill from 200px away
                width: _todayRow.width + 20
                height: Metrics.rowHeightFor(40)

                HoverHandler { id: _todayH; cursorShape: Qt.PointingHandCursor }
                TapHandler   { onTapped: card._goToday() }

                Rectangle {
                    id: _todayFill
                    anchors.fill: parent
                    radius: Theme.radiusControl
                    antialiasing: true
                    color: _todayH.hovered ? Theme.withAlpha(Theme.subtext, 0.12) : "transparent"
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
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        ShellText {
                            text: card.todayWeekday
                            color: (_todayH.hovered) ? Theme.text : Theme.withAlpha(Theme.text, 0.9)
                            font.pixelSize: Settings.fontSize + 1; font.weight: Font.DemiBold
                            ColorFade on color {}
                        }
                        ShellText {
                            visible: card._todayWeek > 0
                            text: "Week " + card._todayWeek
                            color: Theme.withAlpha(Theme.subtext, 0.45)
                            font.pixelSize: Settings.fontCaption
                        }
                    }
                }
            }

            Rectangle {
                id: _persistenceError
                visible: CalendarState.persistenceError.length > 0
                width: parent.width
                height: visible ? Math.max(34, _persistenceErrorText.implicitHeight + 14) : 0
                radius: Theme.radiusControl
                antialiasing: true
                color: Theme.withAlpha(Theme.warning, 0.10)
                border.width: 1
                border.color: Theme.withAlpha(Theme.warning, 0.34)

                ShellText {
                    id: _persistenceErrorText
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: CalendarState.persistenceError
                    color: Theme.warning
                    font.pixelSize: Settings.fontCaption
                    wrapMode: Text.WordWrap
                }

                MotionBehavior on height {
                    NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
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
                    onTriggered: card._step(-1)
                }

                Item {
                    id: _monthButton
                    anchors.centerIn: parent
                    width: _mLabel.implicitWidth + 16; height: 26
                    // distinct from the today pill's: two controls reading "Jump to today" are indistinguishable by voice
                    HoverHandler { id: _mH; cursorShape: Qt.PointingHandCursor }
                    TapHandler   { onTapped: card._goToday() }

                    Rectangle {
                        id: _monthFill
                        anchors.fill: parent
                        radius: Theme.radiusControl
                        antialiasing: true
                        color: _mH.hovered ? Theme.withAlpha(Theme.subtext, 0.12) : "transparent"
                        ColorFade on color {}
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
                    onTriggered: card._step(1)
                }
            }

            Row {
                width: parent.width
                Item {
                    width: card.weekCol; height: 22
                    ShellText {
                        anchors.centerIn: parent
                        text: "Wk"
                        color: Theme.withAlpha(Theme.subtext, 0.30)
                        font.pixelSize: Settings.fontTiny
                        font.weight: Font.Medium; font.capitalization: Font.AllUppercase
                    }
                }
                Repeater {
                    model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                    delegate: Item {
                        id: dayHdr
                        required property int index
                        required property string modelData
                        width: card.cell; height: 22
                        ShellText {
                            anchors.centerIn: parent
                            text: dayHdr.modelData
                            color: Theme.withAlpha(Theme.subtext, dayHdr.index >= 5 ? 0.4 : 0.6)
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
                MotionBehavior on height {
                    NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
                }

                Column {
                    id: _weekAxis
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
                                color: Theme.withAlpha(Theme.subtext, 0.38)
                                font.pixelSize: Settings.fontTiny
                                font.weight: Font.Medium
                            }
                        }
                    }
                }

                Hairline {
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
                    // layer only during the slide so translated NativeRendering text stays crisp
                    layer.enabled: _gridSwap.running && !ShellSettings.reduceMotion

                    Repeater {
                        model: card._rowCount * 7
                        delegate: Item {
                            id: _dayCell
                            required property int index

                            readonly property bool cur:   index >= card._lead && index < card._lead + card._daysThis
                            readonly property bool today: index === card._todayCell
                            readonly property bool weekend: index % 7 >= 5
                            readonly property bool marked: cur
                                && CalendarState.marks[CalendarState.markKey(card.shownYear, card.shownMonth, dayNum)] === true
                            readonly property int  dayNum:
                                  index < card._lead                  ? card._daysPrev - card._lead + 1 + index
                                : index < card._lead + card._daysThis ? index - card._lead + 1
                                :                                       index - card._lead - card._daysThis + 1

                            width: card.cell; height: card.cell

                            Rectangle {
                                anchors.centerIn: parent
                                width: 30; height: 30; radius: 15
                                antialiasing: true
                                color: _dayCell.today ? Theme.accent
                                     : (_dayH.hovered && _dayCell.cur ? Theme.withAlpha(Theme.subtext, 0.10) : "transparent")
                                ColorFade on color {}

                                HoverHandler { id: _dayH; enabled: _dayCell.cur; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    enabled: _dayCell.cur
                                    onTapped: CalendarState.toggleMark(card.shownYear, card.shownMonth, _dayCell.dayNum)
                                }

                                ShellText {
                                    anchors.centerIn: parent
                                    text: _dayCell.dayNum
                                    color: _dayCell.today ? Theme.background
                                         : _dayCell.cur   ? Theme.withAlpha(Theme.text, _dayCell.weekend ? 0.68 : 0.9)
                                         :                  Theme.withAlpha(Theme.subtext, 0.3)
                                    font.pixelSize: Settings.fontSize
                                    font.weight: _dayCell.today ? Font.DemiBold : Font.Normal
                                }

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom; anchors.bottomMargin: 3
                                    width: 4; height: 4; radius: 2
                                    antialiasing: true
                                    color: _dayCell.today ? Theme.background : Theme.accent
                                    opacity: _dayCell.marked ? 1 : 0
                                    scale:   _dayCell.marked ? 1 : 0.3
                                    MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }
                                    MotionBehavior on scale   {NumberAnimation { duration: Motion.ms(125); easing.type: Easing.OutCubic } }
                                }

                            }
                        }
                    }
                }
            }
        }
    }
}
