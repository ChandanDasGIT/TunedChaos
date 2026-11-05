import QtQuick
import QtQuick.Controls

// A list in Settings whose order you set by dragging: hold a row's grip and move
// it up or down; the other rows slide aside to show where it will land.
// The row's own controls come from `rowContent`, an Item with `property var modelData`
// and `property int index` (set for each row).
Item {
    id: root

    property var model: []
    property Component rowContent
    property real rowHeight: 44
    property real gap: 4
    // Rows from here on can't be dragged and stay where they are (e.g. Settings, always last)
    property int fixedFrom: -1
    readonly property int count: model ? model.length : 0
    readonly property int movable: fixedFrom >= 0 ? Math.min(fixedFrom, count) : count
    readonly property real slot: rowHeight + gap

    signal moved(int from, int to)

    // While a row is dragged: where it came from and where it would land
    property int dragFrom: -1
    property int dragTo: -1

    implicitHeight: count > 0 ? count * slot - gap : 0

    Repeater {
        model: root.model

        delegate: Rectangle {
            id: row

            required property var modelData
            required property int index
            readonly property bool fixed: index >= root.movable
            readonly property bool dragged: root.dragFrom === index
            property real dragY: 0
            // Rows between the dragged one's old and new place move over by one
            readonly property int shift: root.dragFrom < 0 || dragged ? 0
                                       : index > root.dragFrom && index <= root.dragTo ? -1
                                       : index < root.dragFrom && index >= root.dragTo ? 1 : 0

            width: root.width
            height: root.rowHeight
            y: dragged ? dragY : (index + shift) * root.slot
            z: dragged ? 2 : 1
            radius: Theme.radius
            color: dragged ? Qt.tint(Theme.surfaceAlt, Theme.accentSoft) : Theme.fillSoft
            border.width: dragged ? 1 : 0
            border.color: Theme.accent

            Behavior on y {
                enabled: !row.dragged
                NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
            }

            Item {
                id: grip
                width: 34
                height: parent.height
                visible: !row.fixed

                Icon {
                    anchors.centerIn: parent
                    name: "grip"
                    size: 12
                    color: row.dragged ? Theme.accent : Theme.textMuted
                }

                // The press takes over at once, so the page doesn't scroll while dragging.
                MouseArea {
                    property real pressY: 0

                    anchors.fill: parent
                    preventStealing: true
                    cursorShape: row.dragged ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    onPressed: (mouse) => {
                        pressY = mapToItem(root, mouse.x, mouse.y).y
                        row.dragY = row.index * root.slot
                        root.dragTo = row.index
                        root.dragFrom = row.index
                    }
                    onPositionChanged: (mouse) => {
                        if (!row.dragged)
                            return
                        const y = mapToItem(root, mouse.x, mouse.y).y
                        const last = (root.movable - 1) * root.slot
                        row.dragY = Math.max(0, Math.min(last, row.index * root.slot + y - pressY))
                        root.dragTo = Math.max(0, Math.min(root.movable - 1, Math.round(row.dragY / root.slot)))
                    }
                    onReleased: finish()
                    onCanceled: finish()

                    function finish() {
                        if (!row.dragged)
                            return
                        const from = root.dragFrom, to = root.dragTo
                        root.dragFrom = -1
                        root.dragTo = -1
                        if (from !== to)
                            root.moved(from, to)
                    }
                }
            }

            Loader {
                id: content
                anchors.left: grip.right
                anchors.leftMargin: row.fixed ? Theme.padding - grip.width : 0
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                sourceComponent: root.rowContent
            }

            Binding { target: content.item; property: "modelData"; value: row.modelData; when: content.item !== null }
            Binding { target: content.item; property: "index"; value: row.index; when: content.item !== null }
        }
    }
}
