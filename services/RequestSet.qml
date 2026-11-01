import QtQuick

QtObject {
    id: root

    property var _owners: []
    readonly property bool active: root._owners.length > 0

    // a closing view releases its own request, including during a picker handover
    function set(owner, wanted: bool): bool {
        if (!owner) return false
        const index = root._owners.indexOf(owner)
        if (wanted === (index >= 0)) return false
        const next = root._owners.slice()
        if (wanted) next.push(owner)
        else next.splice(index, 1)
        root._owners = next
        return true
    }
}
