pragma Singleton

import QtQuick
import Quickshell

Singleton {
    function isInside(item, ancestor): bool {
        let current = item
        while (current) {
            if (current === ancestor) return true
            current = current.parent
        }
        return false
    }
}
