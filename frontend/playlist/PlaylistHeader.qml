pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// Column headers: click to sort (again to reverse); drag a divider to resize
// the column to its right. Column geometry is shared with PlaylistRow.
Rectangle {
    id: root

    required property real indicatorWidth
    required property real titleWidth
    required property real artistAlbumWidth
    required property real trackWidth
    required property real durationWidth
    property bool sortable: true // false for saved playlists: they keep their own order

    // key: "artistAlbum" | "track" | "duration"
    signal resizeRequested(string key, real width)

    implicitHeight: 30
    color: "transparent"

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.border
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 6 // same inset as the rounded rows

        Item {
            width: root.indicatorWidth
            height: parent.height
        }

        HeaderCell {
            width: root.titleWidth
            label: qsTr("Title")
            column: PlaylistController.Title
        }

        HeaderCell {
            width: root.artistAlbumWidth
            label: qsTr("Artist - Album")
            column: PlaylistController.ArtistAlbum
            resizeKey: "artistAlbum"
        }

        HeaderCell {
            width: root.trackWidth
            label: qsTr("Track")
            column: PlaylistController.Track
            alignRight: true
            resizeKey: "track"
        }

        HeaderCell {
            width: root.durationWidth
            label: qsTr("Time")
            column: PlaylistController.Duration
            alignRight: true
            resizeKey: "duration"
        }
    }

    component HeaderCell: Item {
        id: cell

        required property string label
        required property int column
        property bool alignRight: false
        property string resizeKey: "" // non-empty: divider on the left edge resizes this column

        readonly property bool active: root.sortable && PlaylistController.sortColumn === column

        height: parent ? parent.height : 0
        clip: false

        MouseArea {
            id: sortArea
            anchors.fill: parent
            hoverEnabled: root.sortable
            enabled: root.sortable
            cursorShape: Qt.PointingHandCursor
            onClicked: PlaylistController.sortBy(cell.column)
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: cell.alignRight ? undefined : parent.left
            anchors.right: cell.alignRight ? parent.right : undefined
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            spacing: 4
            layoutDirection: cell.alignRight ? Qt.RightToLeft : Qt.LeftToRight
            width: Math.min(implicitWidth, cell.width - 12)
            clip: true

            Label {
                textFormat: Text.PlainText
                text: cell.label
                color: cell.active || sortArea.containsMouse ? Theme.text : Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
                font.bold: cell.active
                elide: Text.ElideRight

                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }

            Icon {
                name: "sortUp"
                size: 10
                color: Theme.accent
                height: parent.height
                visible: scale > 0
                scale: cell.active ? 1 : 0
                rotation: PlaylistController.sortDescending ? 180 : 0

                Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Theme.easingBack } }
                Behavior on rotation { NumberAnimation { duration: Theme.anim; easing.type: Theme.easing } }
            }
        }

        // Divider + resize handle on the left edge
        Rectangle {
            visible: cell.resizeKey !== ""
            x: 0
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: parent.height * 0.5
            color: resizeArea.containsMouse || resizeArea.pressed ? Theme.accent : Theme.border
        }

        MouseArea {
            id: resizeArea

            property real startX: 0
            property real startWidth: 0

            visible: cell.resizeKey !== ""
            x: -width / 2
            width: 10
            height: parent.height
            hoverEnabled: true
            cursorShape: Qt.SplitHCursor
            preventStealing: true

            onPressed: (mouse) => {
                startX = mapToItem(root, mouse.x, 0).x
                startWidth = cell.width
            }
            onPositionChanged: (mouse) => {
                if (pressed)
                    root.resizeRequested(cell.resizeKey, startWidth - (mapToItem(root, mouse.x, 0).x - startX))
            }
        }
    }
}
