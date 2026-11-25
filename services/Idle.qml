pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    readonly property bool isIdle: _monitor.isIdle

    // a lock screen typically covers the session well before the blank stage below, and the
    // simple animation driver paces by wall time, so nothing stops on its own behind it
    readonly property bool isQuiet: _quiet.isIdle || _monitor.isIdle

    IdleMonitor {
        id: _quiet
        // seconds — unbounded per-frame work only; surfaces stay put. Sits on the usual dim
        // stage, since audio alone holds no inhibitor and a freeze on a lit screen is visible
        timeout: 240
        respectInhibitors: true
    }

    IdleMonitor {
        id: _monitor
        timeout: 600              // seconds — aligned with hypridle's screen-blank stage
        respectInhibitors: true
    }

    // a backlight that moves with nobody at the keyboard, or as they come back, is an idle daemon's dim or restore
    readonly property bool unattended: _unattended.isIdle || root._returned.running
    IdleMonitor {
        id: _unattended
        timeout: 30
        respectInhibitors: false
        onIsIdleChanged: if (!isIdle) root._returned.restart()
    }
    readonly property Timer _returned: Timer { interval: 1500 }

    // hands off the keyboard and pointer for a few seconds (reading, listening): a notification card then waits for the
    // next input instead of timing out unseen. Watched only while a card asks, and an inhibitor (a video playing) keeps
    // cards on their usual timer
    readonly property RequestSet _handsOffWatch: RequestSet {}
    function watchHandsOff(owner, wanted: bool): void { root._handsOffWatch.set(owner, wanted) }
    readonly property bool handsOff: _handsOff.enabled && _handsOff.isIdle
    IdleMonitor {
        id: _handsOff
        timeout: 3
        respectInhibitors: true
        enabled: root._handsOffWatch.active
    }

    // session only: a restart or a crash must never leave the screen awake; shell.qml holds the inhibitor
    property bool keepAwake: false
    function toggleKeepAwake(): void { root.setKeepAwake(!root.keepAwake, 0) }

    property real keepAwakeUntil: 0
    readonly property string keepAwakeUntilText: root.keepAwakeUntil > 0
        ? "Until " + DateTime.clockText(new Date(root.keepAwakeUntil)) : ""
    function setKeepAwake(on: bool, until: real): void {
        root.keepAwakeUntil = on ? Math.max(0, until) : 0
        root.keepAwake = on
    }
    // whole minutes: the clock that ends it ticks on the minute
    function keepAwakeFor(nowMs: real, minutes: int): void {
        root.setKeepAwake(true, Math.ceil((nowMs + minutes * 60000) / 60000) * 60000)
    }
    onKeepAwakeChanged: if (!root.keepAwake) root.keepAwakeUntil = 0

    readonly property bool _awakeElapsed: root.keepAwakeUntil > 0
        && DateTime.currentDate.getTime() >= root.keepAwakeUntil
    on_AwakeElapsedChanged: Qt.callLater(root._expireAwake)
    function _expireAwake(): void {
        if (root.keepAwakeUntil > 0 && Date.now() >= root.keepAwakeUntil) root.setKeepAwake(false, 0)
    }
}
