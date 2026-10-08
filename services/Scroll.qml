pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property int  notch: 120
    readonly property int  resetMs: 180
    readonly property int  controlTouchpadNotch: 60
    readonly property real touchpadPixelScale: 8.0
    readonly property int  controlTouchpadMinStepMs: 30
    readonly property real horizontalRejectRatio: 1.25
    readonly property int  pageLatchMs: 400
    readonly property int  sliderRestMs: 300

    property var _accums: Object.create(null)
    property var _expires: Object.create(null)
    property var _lastSteps: Object.create(null)
    property var _directions: Object.create(null)
    // a plain field, so stamping it on every scrolled frame notifies nothing
    readonly property var _page: ({ movedAt: 0 })

    function notePageMoved(): void {
        root._page.movedAt = Date.now()
    }

    // a wheel gesture that is scrolling the page keeps scrolling it when a slider passes under the pointer
    function wheelBelongsToPage(hoveredSince: real): bool {
        const now = Date.now()
        if (now - root._page.movedAt >= root.pageLatchMs
                && now - hoveredSince >= root.sliderRestMs) return false
        root._page.movedAt = now
        return true
    }

    // natural scrolling flips the delta; a level keeps "up means more", as Qt's own sliders do
    function processLevelWheel(event, key: string): int {
        const n = root.processControlWheel(event, key)
        return event && event.inverted ? -n : n
    }

    function processControlWheel(event, key: string): int {
        if (!event) return 0
        const touchpad = _isTouchpad(event)
        const axes = _wheelAxes(event, touchpad)
        if (!axes.y) return 0
        if (Math.abs(axes.x) > Math.abs(axes.y) * horizontalRejectRatio) {
            _accums[key] = 0; _restartTimer(key); return 0
        }
        return _processDelta(
            axes.y, key,
            touchpad ? controlTouchpadNotch : notch,
            touchpad ? 1 : 2,
            touchpad ? controlTouchpadMinStepMs : 0
        )
    }

    // a tray app steps once per Scroll call, so a touchpad's stream of small deltas has to arrive as whole notches
    function processTrayWheel(event, key: string): var {
        if (!event) return { steps: 0, horizontal: false }
        const touchpad = _isTouchpad(event)
        const axes = _wheelAxes(event, touchpad)
        const horizontal = Math.abs(axes.x) > Math.abs(axes.y)
        return {
            steps: _processDelta(
                horizontal ? axes.x : axes.y, key + (horizontal ? ":h" : ":v"),
                touchpad ? controlTouchpadNotch : notch,
                touchpad ? 1 : 2,
                touchpad ? controlTouchpadMinStepMs : 0),
            horizontal: horizontal
        }
    }

    function _processDelta(deltaY: real, key: string, threshold: real, maxSteps: int, minStepMs: int): int {
        if (!deltaY) return 0
        const now = Date.now()
        // A busy event loop can deliver input before the cleanup timer fires.
        // Expired gestures must still start without the previous remainder.
        if (_expires[key] !== undefined && _expires[key] <= now) _forgetKey(key)
        const previous = _accums[key] || 0
        // a complete notch leaves no remainder, so direction must survive separately
        const reversed = (_directions[key] || 0) * deltaY < 0
        _directions[key] = Math.sign(deltaY)
        if (reversed) delete _lastSteps[key]
        const last = reversed ? 0 : (_lastSteps[key] || 0)
        const cur = (reversed ? 0 : previous) + deltaY

        const notches = Math.trunc(cur / threshold)
        if (notches === 0) {
            _accums[key] = cur
            _restartTimer(key)
            return 0
        }

        if (minStepMs > 0 && last > 0 && now - last < minStepMs) {
            _accums[key] = cur
            _restartTimer(key)
            return 0
        }

        const emitted = Math.max(-maxSteps, Math.min(maxSteps, notches))
        // consume the whole burst even when capped; only a fractional notch carries over
        _accums[key]    = cur - notches * threshold
        _lastSteps[key] = now
        _restartTimer(key)
        return emitted
    }

    function _wheelAxes(event, touchpad: bool): var {
        if (touchpad && event.pixelDelta && (event.pixelDelta.y || event.pixelDelta.x))
            return { x: event.pixelDelta.x * touchpadPixelScale, y: event.pixelDelta.y * touchpadPixelScale }
        return { x: event.angleDelta ? event.angleDelta.x : 0, y: event.angleDelta ? event.angleDelta.y : 0 }
    }

    function _isTouchpad(event): bool {
        if (!event || !event.device) return false
        if (event.device.type !== undefined) return event.device.type === PointerDevice.TouchPad
        if (event.device.deviceType !== undefined) return event.device.deviceType === PointerDevice.TouchPad
        const name = event.device.name ? String(event.device.name).toLowerCase() : ""
        return name.includes("touchpad") || name.includes("trackpad")
    }

    function _restartTimer(key: string): void {
        root._expires[key] = Date.now() + root.resetMs
        if (!_cleanup.running) {
            _cleanup.interval = root.resetMs
            _cleanup.start()
        }
    }

    function _forgetKey(key: string): void {
        delete root._accums[key]
        delete root._lastSteps[key]
        delete root._directions[key]
        delete root._expires[key]
    }

    // Return the time until the next expiry; zero means there is no work left.
    function _expireKeys(now: real): int {
        let next = Infinity
        for (const key in root._expires) {
            const expiry = root._expires[key]
            if (expiry <= now) root._forgetKey(key)
            else next = Math.min(next, expiry)
        }
        return isFinite(next) ? Math.max(1, Math.ceil(next - now)) : 0
    }

    Timer {
        id: _cleanup
        onTriggered: {
            const delay = root._expireKeys(Date.now())
            if (delay > 0) {
                interval = delay
                start()
            }
        }
    }
}
