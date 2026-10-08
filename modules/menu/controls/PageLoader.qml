import QtQuick

// The viewport animates around a stable page layout. Freeze the departing
// loader too: Loader otherwise resizes its item even over the item's binding.
Loader {
    id: root

    required property real layoutWidth
    property bool shown: false
    property real scrollOffset: 0
    property real _heldWidth: 0
    property real _heldScroll: 0
    property bool _holdLayout: false

    width: root._holdLayout ? root._heldWidth : root.layoutWidth
    // The shared scroller resets for the incoming page. Compensate only the
    // departing page so its visible rows do not jump back to the top mid-fade.
    y: root._holdLayout ? root.scrollOffset - root._heldScroll : 0

    function holdLayout(): void {
        root._heldWidth = root.width
        root._heldScroll = root.scrollOffset - root.y
        root._holdLayout = true
    }

    onShownChanged: {
        if (root.shown) root._holdLayout = false
        else if (!root._holdLayout) root.holdLayout()
    }
    Component.onCompleted: if (!root.shown) root.holdLayout()
}
