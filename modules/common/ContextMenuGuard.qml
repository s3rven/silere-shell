import QtQuick

// claims right presses nothing else takes. Qt 6.11+ synthesizes a context menu event for an
// unclaimed one, reads window position (0,0) as "no position", and maps it through the active
// focus item, which a layer surface without keyboard focus does not have: a segfault that takes
// the shell down from one right click in a corner (QTBUG-146671, unfixed as of 6.12). A window
// with input at its origin needs this at its root; widgets above it still get their right clicks
TapHandler {
    acceptedButtons: Qt.RightButton
}
