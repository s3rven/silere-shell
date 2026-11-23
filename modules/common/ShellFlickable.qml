import QtQuick
import "../../config"
import "../../services"

Flickable {
    clip: true
    flickDeceleration: Motion.flickDeceleration
    maximumFlickVelocity: Motion.flickVelocity
    boundsMovement: Flickable.StopAtBounds
    property bool followFocusOnLayout: false
    onContentYChanged: if (moving) Scroll.notePageMoved()
    // the one ScrollHold allowed to scroll this page
    property QtObject scrollHold: null
    onMovementStarted: releaseScrollHold()

    function releaseScrollHold(): void {
        if (scrollHold) scrollHold.release()
    }

    function scrollToTop(): void {
        // assigning contentY alone leaves a running flick free to move the next page again on its first frame
        releaseScrollHold()
        cancelFlick()
        contentY = originY
    }
}
