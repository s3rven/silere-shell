import QtQuick
import "../../services"

Item {
    id: root

    required property bool open
    property bool ignoring: false

    // a bar-position flip re-places the popup under the pointer; swallow the tap that lands mid-move
    Connections {
        target: ShellSettings
        function onBarPositionChanged() {
            if (!root.open) return
            root.ignoring = true
            _guard.restart()
        }
    }

    Timer {
        id: _guard
        interval: 250
        repeat: false
        onTriggered: root.ignoring = false
    }

    onOpenChanged: {
        if (root.open) return
        _guard.stop()
        root.ignoring = false
    }
}
