import QtQuick
import "../../config"
import "../../services"

ListView {
    id: root

    clip: true
    flickDeceleration: Motion.flickDeceleration
    maximumFlickVelocity: Motion.flickVelocity
    boundsMovement: Flickable.StopAtBounds
    onContentYChanged: Scroll.notePageMoved()
}
