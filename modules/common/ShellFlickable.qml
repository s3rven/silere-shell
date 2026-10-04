import QtQuick
import "../../config"
import "../../services"

Flickable {
    clip: true
    flickDeceleration: Motion.flickDeceleration
    maximumFlickVelocity: Motion.flickVelocity
    boundsMovement: Flickable.StopAtBounds
    onContentYChanged: Scroll.notePageMoved()
}
