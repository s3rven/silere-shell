import QtQuick
import "../../config"
import "../../services"

Flickable {
    clip: true
    flickDeceleration: Motion.flickDeceleration
    maximumFlickVelocity: Motion.flickVelocity
    // one scroll feel shell-wide: drag stops at the edge, a flick still rebounds
    boundsMovement: Flickable.StopAtBounds
    onContentYChanged: Scroll.notePageMoved()
}
