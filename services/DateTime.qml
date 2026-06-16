pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    SystemClock {
        id: clock
        precision: ShellSettings.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    property string _lastDay:       ""
    property string cachedDayName:  ""  // "ddd " — trailing space is the separator
    property string cachedDateCore: ""  // "MMM dd"
    property string cachedTime:     ""  // "HH:mm" or "h:mm"
    property string cachedAmPm:     ""  // " AM" / " PM" in 12h mode, "" in 24h
    property string cachedSeconds:  ""  // ":ss"

    Component.onCompleted: _update()

    Connections {
        target: clock
        function onDateChanged() { root._update() }
    }

    Connections {
        target: ShellSettings
        function onClock12hChanged() { root._update() }
        function onShowSecondsChanged() { root._update() }
    }

    function _update(): void {
        const day = Qt.formatDateTime(clock.date, "yyyyMMdd")
        if (day !== _lastDay) {
            _lastDay        = day
            cachedDayName   = Qt.formatDateTime(clock.date, "ddd ")
            cachedDateCore  = Qt.formatDateTime(clock.date, "MMM dd")
        }
        if (ShellSettings.clock12h) {
            cachedTime  = Qt.formatDateTime(clock.date, "h:mm")
            cachedAmPm  = Qt.formatDateTime(clock.date, " AP")
        } else {
            cachedTime  = Qt.formatDateTime(clock.date, "HH:mm")
            cachedAmPm  = ""
        }
        cachedSeconds = ShellSettings.showSeconds
            ? Qt.formatDateTime(clock.date, ":ss")
            : ""
    }
}
