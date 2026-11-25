pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// the keyboard verbs dunstctl and makoctl give the popups on screen: dismiss the newest, dismiss them all, or act on the
// newest as a click on it would. The popup window does the work, so each card leaves through the exit a click plays and
// counts as dismissed by you, not expired
Singleton {
    id: root

    readonly property bool armed: true
    // the popup window while it exists; with none there is no card to act on
    property var surface: null

    function run(verb: string): string {
        const win = root.surface
        if (!win) return "no notification on screen"
        const done = verb === "dismissAll" ? win.keyDismissAll()
            : verb === "invoke" ? win.keyInvokeNewest()
            : win.keyDismissNewest()
        return done ? "ok" : "no notification on screen"
    }

    // newest: the id dismiss and invoke would act on now, 0 with no card up; a notification only just sent is counted
    // in shown before its card is up, so a script that wants that one waits for it here
    function statusText(): string {
        const card = root.surface ? root.surface.newestCard() : null
        return JSON.stringify({ shown: Notifications.activeCount, missed: Notifications.missedShown,
            dnd: Notifications.effectiveDnd, silenced: Notifications.silencingActive,
            newest: card && card.notification ? card.notification.id : 0 })
    }

    IpcHandler {
        target: "notifications"

        function dismiss(): string { return root.run("dismiss") }
        function dismissAll(): string { return root.run("dismissAll") }
        function invoke(): string { return root.run("invoke") }
        function status(): string { return root.statusText() }
    }
}
