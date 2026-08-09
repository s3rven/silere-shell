import QtQuick
import "../../config"

ListView {
    clip: true
    flickDeceleration: Motion.flickDeceleration
    maximumFlickVelocity: Motion.flickVelocity
}
