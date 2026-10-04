import QtQuick

// a bitmap between device pixels is blended across two of them at 1.25; every ancestor's x and y is read here, so any reflow re-snaps it
Translate {
    id: root

    required property Item item
    // QsWindow resolves only on an Item, so the snapped item passes its window's ratio in
    property real dpr: 1

    readonly property point _offset: {
        let sx = 0, sy = 0
        for (let it = root.item; it; it = it.parent) { sx += it.x; sy += it.y }
        const d = root.dpr
        return Qt.point((Math.round(sx * d) - sx * d) / d, (Math.round(sy * d) - sy * d) / d)
    }

    x: root._offset.x
    y: root._offset.y
}
