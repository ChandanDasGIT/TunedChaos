pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// Right-click / "⋮" menu for a row in the Queue or in a playlist.
ThemedMenu {
    id: root

    property int row: -1
    property string path
    property bool inQueue: true // false: the row belongs to the viewed playlist
    property bool canRemove: true // false: the list being played from (it can't be changed)

    signal detailsRequested(string path)

    function openFor(row, path) { // at the pointer
        root.row = row
        root.path = path
        popup()
    }
    function openAt(row, path, item, x, y) {
        root.row = row
        root.path = path
        popup(item, x, y)
    }

    Action {
        text: qsTr("Play")
        icon.name: "play"
        onTriggered: root.inQueue ? PlaylistController.playIndex(root.row)
                                  : PlaylistsController.playViewed(root.row)
    }

    Action {
        text: qsTr("Play next")
        icon.name: "next"
        enabled: root.path !== PlayerController.source
        onTriggered: PlaylistsController.playNext([{ path: root.path }])
    }

    Action {
        enabled: !root.inQueue
        text: qsTr("Add to queue")
        icon.name: "plus"
        onTriggered: PlaylistsController.addToQueue([{ path: root.path }])
    }

    AddToPlaylistMenu {
        items: [{ path: root.path }]
    }

    Action {
        text: qsTr("New playlist with this song…")
        icon.name: "listMusic"
        onTriggered: PlaylistsController.requestNewPlaylist([{ path: root.path }])
    }

    Action {
        text: qsTr("Track details")
        icon.name: "info"
        onTriggered: root.detailsRequested(root.path)
    }

    MenuSeparator {
        contentItem: Rectangle {
            implicitHeight: 1
            color: Theme.border
        }
    }

    Action {
        enabled: root.canRemove // (not from the list being played from: it's only for now)
        text: root.inQueue ? qsTr("Remove from queue") : qsTr("Remove from playlist")
        icon.name: "trash"
        onTriggered: root.inQueue ? PlaylistController.removeIndex(root.row)
                                  : PlaylistsController.removeFromViewed(root.row)
    }
}
