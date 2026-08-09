import QtQuick
import "../../config"

Flickable {
    clip: true
    flickDeceleration: Motion.flickDeceleration
    maximumFlickVelocity: Motion.flickVelocity
}
