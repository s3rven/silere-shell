pragma ComponentBehavior: Bound

import QtQuick
import "../../services"

Loader {
    id: root

    required property FloatingPopupCard card

    active: (card.open || card.opacity > 0.001) && ShellSettings.barShadow
    anchors.fill: card
    opacity: card.opacity
    z: -1
    sourceComponent: FloatingShadow {
        radius: root.card.radius
        atBottom: root.card.barBottom
    }
}
