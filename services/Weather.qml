pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "TimeZonePlace.js" as TimeZonePlace

// opt in, and on demand only: the calendar asks when it opens, an answer serves for half
// an hour, and nothing polls in between. Open-Meteo needs no account or key
Singleton {
    id: root

    readonly property bool enabled: ShellSettings.weatherEnabled
    readonly property bool fahrenheit: Qt.locale().measurementSystem === Locale.ImperialUSSystem
    readonly property int maxAgeMs: 30 * 60000
    readonly property int timeoutMs: 10000
    readonly property int maxResponseChars: 65536

    property bool loading: false
    property bool failed: false
    property string failure: ""
    readonly property bool hasData: root._fetchedAt > 0
    property int temperature: 0
    property int high: 0
    property int low: 0
    property int code: -1
    property bool isDay: true
    property string place: ""
    readonly property string unit: root.fahrenheit ? "°F" : "°C"
    readonly property string glyph: root.glyphFor(root.code, root.isDay)
    readonly property string condition: root.conditionFor(root.code)

    property real _fetchedAt: 0
    property string _fetchedFor: ""
    // the time zone's principal city is resolved once per session
    property var _place: null
    property var _xhr: null

    // the WMO codes Open-Meteo reports
    function conditionFor(code: int): string {
        if (code === 0) return "Clear"
        if (code === 1) return "Mostly clear"
        if (code === 2) return "Partly cloudy"
        if (code === 3) return "Overcast"
        if (code === 45 || code === 48) return "Fog"
        if (code >= 51 && code <= 55) return "Drizzle"
        if (code === 56 || code === 57) return "Freezing drizzle"
        if (code === 61 || code === 63) return "Rain"
        if (code === 65) return "Heavy rain"
        if (code === 66 || code === 67) return "Freezing rain"
        if (code >= 71 && code <= 77) return "Snow"
        if (code === 80 || code === 81) return "Showers"
        if (code === 82) return "Heavy showers"
        if (code === 85 || code === 86) return "Snow showers"
        if (code === 95) return "Thunderstorm"
        if (code === 96 || code === 99) return "Thunderstorm, hail"
        return ""
    }

    function glyphFor(code: int, day: bool): string {
        if (code === 0) return day ? "󰖙" : "󰖔"
        if (code === 1 || code === 2) return day ? "󰖕" : "󰼱"
        if (code === 3) return "󰖐"
        if (code === 45 || code === 48) return "󰖑"
        if (code === 56 || code === 57 || code === 66 || code === 67) return "󰙿"
        if (code === 65 || code === 82) return "󰖖"
        if ((code >= 51 && code <= 55) || code === 61 || code === 63
                || code === 80 || code === 81) return "󰖗"
        if (code >= 71 && code <= 77) return "󰖘"
        if (code === 85 || code === 86) return "󰼶"
        if (code === 95) return "󰖓"
        if (code === 96 || code === 99) return "󰙾"
        return ""
    }

    function forecastUrl(lat: real, lon: real, fahrenheit: bool): string {
        // two decimals is about a kilometre: precise enough for weather, no more
        return "https://api.open-meteo.com/v1/forecast?latitude=" + lat.toFixed(2)
            + "&longitude=" + lon.toFixed(2)
            + "&current=temperature_2m,weather_code,is_day"
            + "&daily=temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=auto"
            + (fahrenheit ? "&temperature_unit=fahrenheit" : "")
    }

    // a reading only counts when every field is a real number; a partial answer keeps the last one
    function parseForecast(data): var {
        const current = data?.current
        const daily = data?.daily
        const values = [current?.temperature_2m, current?.weather_code,
            daily?.temperature_2m_max?.[0], daily?.temperature_2m_min?.[0]]
        if (values.some(v => typeof v !== "number" || !isFinite(v))) return null
        return {
            temperature: Math.round(values[0]),
            code: Math.round(values[1]),
            high: Math.round(values[2]),
            low: Math.round(values[3]),
            isDay: current.is_day !== 0
        }
    }

    function _key(nowMs: real): string {
        return root.unit + ":" + Qt.formatDateTime(new Date(nowMs), "yyyy-MM-dd")
    }

    function cacheFresh(fetchedAt: real, fetchedFor: string, nowMs: real): bool {
        const age = nowMs - fetchedAt
        return fetchedAt > 0 && age >= 0 && age < root.maxAgeMs
            && fetchedFor === root._key(nowMs)
    }

    function request(force: bool): void {
        if (!root.enabled || root.loading) return
        if (!force && !root.failed && root.cacheFresh(root._fetchedAt, root._fetchedFor, Date.now())) return
        root.loading = true
        if (root._place) root._fetchForecast()
        else _zoneProc.running = true
    }

    function _fail(reason: string): void {
        root.loading = false
        root.failed = true
        root.failure = reason
    }

    function _get(url: string, done): void {
        const xhr = new XMLHttpRequest()
        root._xhr = xhr
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || root._xhr !== xhr) return
            root._xhr = null
            _deadline.stop()
            let data = null
            if (xhr.status === 200 && xhr.responseText.length <= root.maxResponseChars) {
                try { data = JSON.parse(xhr.responseText) } catch (e) { data = null }
            }
            done(data)
        }
        xhr.open("GET", url)
        xhr.send()
        _deadline.restart()
    }

    function _fetchForecast(): void {
        const place = root._place
        const key = root._key(Date.now())
        root._get(root.forecastUrl(place.lat, place.lon, root.fahrenheit), data => {
            const reading = root.parseForecast(data)
            if (!reading) { root._fail("Can't reach Open-Meteo"); return }
            root.temperature = reading.temperature
            root.code = reading.code
            root.high = reading.high
            root.low = reading.low
            root.isDay = reading.isDay
            root.place = place.name
            root._fetchedFor = key
            root._fetchedAt = Date.now()
            root.failed = false
            root.failure = ""
            root.loading = false
            // a lookup can straddle midnight while the calendar stays open
            if (CalendarState.open && key !== root._key(Date.now()))
                Qt.callLater(root.request, false)
        })
    }

    Timer {
        id: _deadline
        interval: root.timeoutMs
        onTriggered: {
            const xhr = root._xhr
            root._xhr = null
            if (xhr) xhr.abort()
            root._fail("Can't reach Open-Meteo")
        }
    }

    readonly property BoundedProcess _zoneLookup: BoundedProcess {
        id: _zoneProc
        running: false
        timeoutMs: 5000
        command: ["bash", "-c", TimeZonePlace.script]
        stdout: StdioCollector { id: _zoneOut }
        onExited: code => {
            // turning weather off superseded this lookup while it ran
            if (!root.loading) return
            const found = _zoneProc.completedSuccessfully(code)
                ? TimeZonePlace.parseLine(_zoneOut.text) : null
            if (!found) { root._fail("Can't tell where you are from the time zone"); return }
            root._place = { lat: found.lat, lon: found.lon,
                name: TimeZonePlace.placeName(found.zone) }
            root._fetchForecast()
        }
    }

    // an open calendar asks again at once rather than waiting to be reopened
    onEnabledChanged: {
        if (!root.enabled) root._reset()
        else if (CalendarState.open) root.request(false)
    }
    // first referenced by the calendar's row, which can appear while the calendar is already open
    Component.onCompleted: if (root.enabled && CalendarState.open) root.request(false)
    function _reset(): void {
        const xhr = root._xhr
        root._xhr = null
        _deadline.stop()
        if (xhr) xhr.abort()
        root.loading = false
        root.failed = false
        root.failure = ""
        root._fetchedAt = 0
        root._fetchedFor = ""
    }
}
