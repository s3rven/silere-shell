import QtQuick
import "../services"

// carries the reduce-motion gate so no call site can forget it
Behavior {
    enabled: !ShellSettings.reduceMotion
}
