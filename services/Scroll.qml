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

    property var _accums: ({})
    property var _timers: ({})
    property var _lastSteps: ({})

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

    function _processDelta(deltaY: real, key: string, threshold: real, maxSteps: int, minStepMs: int): int {
        if (!deltaY) return 0
        const now = Date.now()
        const last = _lastSteps[key] || 0
        const cur = (_accums[key] || 0) + deltaY

        const notches = Math.trunc(cur / threshold)
        if (notches === 0) {
            _accums[key] = cur
            _restartTimer(key)
            return 0
        }

        // Rate limit, preserve accumulator so the notch isn't lost
        if (minStepMs > 0 && last > 0 && now - last < minStepMs) {
            _accums[key] = cur
            _restartTimer(key)
            return 0
        }

        // Only consume from accumulator what we actually emit; clamped overflow
        // stays for the next event instead of being silently dropped
        const emitted = Math.max(-maxSteps, Math.min(maxSteps, notches))
        _accums[key]    = cur - emitted * threshold
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
        let t = _timers[key]
        if (!t) { t = timerComp.createObject(root, { key: key }); _timers[key] = t }
        t.restart()
    }

    Component {
        id: timerComp
        Timer {
            property string key: ""
            interval: root.resetMs; repeat: false
            onTriggered: {
                // Reap every per-key entry, not just the timer — _processDelta
                // reads `_accums[key] || 0`, so a deleted key is equivalent to 0
                // and the maps don't accrue dead entries per control touched.
                delete root._accums[key]
                delete root._lastSteps[key]
                delete root._timers[key]
                destroy()
            }
        }
    }

    Component.onDestruction: {
        for (const key in _timers) {
            if (_timers[key]) _timers[key].destroy()
        }
    }
}
