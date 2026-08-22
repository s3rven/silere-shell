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
    // this is a sibling of the card, so transforms are not inherited. Mirror the card's motion or its shadow visibly lags at the final geometry
    transform: [
        Translate { y: root.card.edgeOffset },
        Scale {
            origin.x: root.card.motionOriginX
            origin.y: root.card.barBottom ? root.height : 0
            xScale: root.card.scaleAmt
            yScale: root.card.scaleAmt
        }
    ]
    sourceComponent: FloatingShadow {
        radius: root.card.radius
        atBottom: root.card.barBottom
    }
}
