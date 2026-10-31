import QtQuick

// native text fields and custom controls share scroll behavior while retaining their own keys
Item {
    id: root

    property Item control: parent
    property Item revealTarget: root.control
    property real revealY: 0
    property real revealHeight: root.revealTarget ? root.revealTarget.height : 0
    visible: false

    function reveal(): void {
        if (!root.enabled || !root.control || !root.control.activeFocus
                || !root.control.enabled || !root.control.visible || !root.revealTarget) return
        for (let viewport = root.revealTarget.parent; viewport; viewport = viewport.parent) {
            if (viewport.contentY === undefined || !viewport.contentItem || viewport.height <= 0) continue
            viewport.cancelFlick()
            const p = root.revealTarget.mapToItem(viewport.contentItem, 0, root.revealY)
            const top = Number(viewport.originY || 0)
            const wanted = p.y < viewport.contentY || root.revealHeight > viewport.height ? p.y
                : p.y + root.revealHeight > viewport.contentY + viewport.height
                    ? p.y + root.revealHeight - viewport.height : viewport.contentY
            viewport.contentY = Math.max(top,
                Math.min(top + Math.max(0, viewport.contentHeight - viewport.height), wanted))
        }
    }

    Connections {
        target: root.control
        function onActiveFocusChanged() { if (root.control.activeFocus) Qt.callLater(root.reveal) }
    }
    onRevealHeightChanged: if (root.control && root.control.activeFocus) Qt.callLater(root.reveal)
}
