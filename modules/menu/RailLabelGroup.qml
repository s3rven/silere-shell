import QtQuick

QtObject {
    id: root

    property bool warm: false

    readonly property Timer _cooldown: Timer {
        interval: 380
        onTriggered: root.warm = false
    }

    function engage(): void {
        _cooldown.stop()
        root.warm = true
    }

    function release(): void {
        if (root.warm) _cooldown.restart()
    }
}
