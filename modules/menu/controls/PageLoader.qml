import QtQuick

// the viewport animates around a stable page layout. Freeze the departing loader too: Loader otherwise resizes its item even over the item's binding
Loader {
    id: root

    required property real layoutWidth
    property bool shown: false
    // a page named inline compiles with the menu; one set as source compiles when its tab is first wanted, and
    // reads these through its parent, set before its bindings run. setSource() with properties leaks per open
    property bool pageActive: false
    property bool powerOpen: false
    property bool animateOnCreate: false
    property bool viewportReady: true
    property Flickable scroller: null
    property int viewportHeight: 0
    property int thumbOutset: 0
    property real scrollOffset: 0
    property real _heldWidth: 0
    property real _heldScroll: 0
    property bool _holdLayout: false

    width: root._holdLayout ? root._heldWidth : root.layoutWidth
    // the shared scroller resets for the incoming page. Compensate only the departing page so its visible rows do not jump back to the top mid-fade
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
