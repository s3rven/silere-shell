import QtQuick
import "../../config"
import "../../services"

Flickable {
    clip: true
    flickDeceleration: Motion.flickDeceleration
    maximumFlickVelocity: Motion.flickVelocity
    boundsMovement: Flickable.StopAtBounds
    onContentYChanged: Scroll.notePageMoved()

    function scrollToTop(): void {
        // Assigning contentY alone leaves a running flick free to move the
        // next page again on its first frame.
        cancelFlick()
        contentY = originY
    }
}
