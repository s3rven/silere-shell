import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../config"
import "../../services"

// an icon decoded at its device size and drawn on whole device pixels: IconImage's own decode scales a theme icon twice,
// and mipmapping a large one instead takes it out of the texture atlas, a path that SEGVs the render thread
IconImage {
    id: root

    // the logical side the icon is laid out at
    property real side: 16
    readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    // the factor QIcon puts on a theme icon's request
    property real iconScale: IconResolver.screenScale
    // learned once per icon, so a Quickshell that stops scaling theme icons twice still gets a full-size decode
    property bool themeScaled: true
    readonly property int decodeSide: IconResolver.decodeSide(root.source, root.side, root.dpr,
        root.themeScaled ? root.iconScale : 1)

    implicitSize: Metrics.devicePx(root.side, root.dpr)
    backer.sourceSize.width:  root.decodeSide
    backer.sourceSize.height: root.decodeSide
    transform: PixelSnap { item: root; dpr: root.dpr }

    function _learnScale(): void {
        if (root.status === Image.Ready && root.themeScaled && IconResolver.themeScaleMissing(
                root.source, root.backer.implicitWidth, root.side, root.dpr, root.iconScale))
            root.themeScaled = false
    }
    // a synchronous load can finish before this connection exists
    Component.onCompleted: root._learnScale()
    Connections {
        target: root
        function onStatusChanged() { root._learnScale() }
    }
}
