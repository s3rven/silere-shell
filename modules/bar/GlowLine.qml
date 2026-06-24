import QtQuick

// One horizontal underline strip: transparent ends, mid stops fanning out from a
// moving centre peak. Shared by every glow line so the gradient lives in one place;
// callers set their own geometry, opacity and clamp bounds.
Rectangle {
    property color peak
    property color edge
    property real  center: 0.5
    property real  spread: 0.28
    property real  loClamp: 0.02
    property real  hiClamp: 0.98

    height: 1
    antialiasing: false

    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: Math.max(loClamp, center - spread); color: edge }
        GradientStop { position: center; color: peak }
        GradientStop { position: Math.min(hiClamp, center + spread); color: edge }
        GradientStop { position: 1.0; color: "transparent" }
    }
}
