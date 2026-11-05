pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Playlist panel: header bar, column header and track list (or an empty-state hint).
// With acceptsDrops, songs dragged from the Library or YouTube can be dropped
// into the list shown (the Queue or a playlist), at the spot under the pointer.
Rectangle {
    id: root

    property bool showPinButton: false
    property bool pinned: false
    property bool showCloseButton: false
    property bool acceptsDrops: false

    // Dragged songs would go before this row (-1: not over the panel).
    readonly property int dropRow: dropHint.over ? rowAt(SongDrag.scenePos, list.contentY, list.count) : -1

    // The row a drop at `scenePos` goes before (contentY / count: so bindings follow them).
    function rowAt(scenePos, contentY, count) {
        if (count === 0 || !list.visible)
            return 0
        const y = list.contentItem.mapFromItem(null, scenePos.x, scenePos.y).y
        const index = list.indexAt(list.width / 2, y)
        if (index < 0)
            return y < list.originY ? 0 : count
        const item = list.itemAtIndex(index)
        return item && y > item.y + item.height / 2 ? index + 1 : index
    }

    // Column geometry shared by header and rows. Title takes the remaining space;
    // Artist - Album gives way on narrow screens so the title stays readable.
    readonly property real indicatorWidth: 70 // grab handle + cover
    readonly property real availableWidth: width - 8 - 12 // scrollbar + rounded-row insets
    readonly property real trackWidth: SettingsController.trackWidth
    readonly property real durationWidth: SettingsController.durationWidth
    readonly property real artistAlbumWidth: Math.min(
        SettingsController.artistAlbumWidth,
        Math.max(60, (availableWidth - indicatorWidth - trackWidth - durationWidth) * 0.5))
    readonly property real titleWidth: Math.max(
        0, availableWidth - indicatorWidth - trackWidth - durationWidth - artistAlbumWidth)

    // The Queue, or the named playlist chosen in the Playlists menu.
    readonly property bool viewingQueue: PlaylistsController.viewedId === ""
    // Back / Esc: from a playlist to the Queue (false: the Queue already).
    readonly property bool canGoBack: !viewingQueue
    function back() {
        if (viewingQueue)
            return false
        PlaylistsController.view("")
        return true
    }
    readonly property int shownCount: viewingQueue ? PlaylistController.count : PlaylistsController.viewedCount

    signal pinToggled()
    signal closeRequested()
    signal detailsRequested(string path)
    signal importM3uRequested()
    signal exportM3uRequested(string id, string name) // id "" = the Queue

    // Switching between the Queue and a playlist: the new list slides in
    // sideways (playlists from the right, the Queue from the left) and fades in.
    property string shownViewId
    property real switchShift: 0
    property real switchFade: 1

    Component.onCompleted: shownViewId = PlaylistsController.viewedId

    Connections {
        target: PlaylistsController
        function onViewChanged() {
            if (PlaylistsController.viewedId === root.shownViewId)
                return // same list, only its contents changed
            switchAnimation.direction = PlaylistsController.viewedId === "" ? -1 : 1
            root.shownViewId = PlaylistsController.viewedId
            switchAnimation.restart()
        }
    }

    ParallelAnimation {
        id: switchAnimation
        property real direction: 1
        NumberAnimation {
            target: root; property: "switchShift"
            from: 40 * switchAnimation.direction; to: 0
            duration: Theme.animSlow; easing.type: Theme.easingPanel
        }
        NumberAnimation { target: root; property: "switchFade"; from: 0; to: 1; duration: Theme.anim }
    }

    color: Theme.panelShade // softens the cover tint behind it
    radius: Theme.radiusCard
    border.color: Theme.border

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 1 // inside the border
        anchors.bottomMargin: 6 // scrolling rows stay clear of the rounded corners
        spacing: 0

        // Header bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.headerHeight
            color: Theme.fillSoft
            topLeftRadius: Theme.radiusCard - 1
            topRightRadius: Theme.radiusCard - 1

            // Narrow panels: the icon buttons keep their room; the playlist name
            // shrinks (cut with "…") and the summary chip goes first.
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacing
                anchors.rightMargin: Theme.spacing
                spacing: Theme.spacing

                // Tabs: the Queue, and the playlists menu next to it
                PillButton {
                    iconName: "listMusic"
                    iconSize: 11
                    text: qsTr("Queue")
                    implicitHeight: 32
                    active: root.viewingQueue
                    onClicked: PlaylistsController.view("")
                }

                PillButton {
                    id: playlistsButton

                    // Viewing a playlist: its name. Otherwise the playlist playing ("pinned"), if
                    // any, or the YouTube Mix / album playing.
                    readonly property string playingName: PlaylistController.contextTitle !== ""
                                                          ? PlaylistController.contextTitle
                                                          : PlaylistsController.playingFromName
                    readonly property bool showsPlaying: root.viewingQueue && (PlaylistsController.playingFromId !== ""
                                                                               || PlaylistController.contextTitle !== "")
                    readonly property string label: !root.viewingQueue ? PlaylistsController.viewedName
                                                  : showsPlaying ? playingName
                                                  : qsTr("Playlists")

                    // icon, gaps, chevron and padding around the name
                    readonly property real chrome: 10 + 6 + 6 + 9 + 28

                    Layout.fillWidth: true
                    Layout.minimumWidth: chrome + 24
                    Layout.maximumWidth: implicitWidth
                    implicitHeight: 32
                    implicitWidth: chrome + Math.min(playlistsLabel.implicitWidth, 240)
                    active: !root.viewingQueue
                    ToolTip.visible: hovered && showsPlaying
                    ToolTip.text: qsTr("Playing from “%1”").arg(playingName)
                    onClicked: playlistsMenu.popup(playlistsButton, 0, playlistsButton.height + 4)

                    contentItem: Item {
                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: playlistsButton.showsPlaying ? "play" : "listMusic"
                                size: 10
                                color: playlistsButton.iconColor
                            }

                            Label {
                                id: playlistsLabel
                                textFormat: Text.PlainText
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, Math.min(implicitWidth, playlistsButton.width - playlistsButton.chrome)) // long names are cut with "…"
                                text: playlistsButton.label
                                color: playlistsButton.iconColor
                                font.pixelSize: Theme.fontSize
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "chevronDown"
                                size: 9
                                color: playlistsButton.iconColor
                            }
                        }
                    }
                }

                // "12 tracks · 45 min left" (queue) / "12 tracks · 45 min" (a playlist)
                Rectangle {
                    id: summaryChip

                    readonly property real currentLeft: PlayerController.hasTrack && PlaylistController.currentIndex >= 0
                                                        ? Math.max(0, PlayerController.duration - PlayerController.position) : 0

                    Layout.maximumWidth: 200
                    implicitWidth: summary.implicitWidth + 16
                    implicitHeight: summary.implicitHeight + 6
                    radius: height / 2
                    color: Theme.fill
                    // Only with room to spare next to the name
                    visible: root.shownCount > 0 && !clearButton.confirming && root.width > 470
                             && root.width > playlistsButton.implicitWidth + 360

                    Label {
                        id: summary
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, summaryChip.width - 16)
                        text: (root.shownCount === 1 ? qsTr("1 track") : qsTr("%1 tracks").arg(root.shownCount)) + "  ·  "
                              + (!root.viewingQueue ? Util.formatLongDuration(PlaylistsController.viewedDurationMs)
                                 : summaryChip.currentLeft > 0
                                 ? qsTr("%1 left").arg(Util.formatLongDuration(PlaylistController.queueUpcomingMs + summaryChip.currentLeft))
                                 : Util.formatLongDuration(PlaylistController.queueUpcomingMs))
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }
                }

                Item { Layout.fillWidth: true }

                // Clear playlist: needs a second click within 3 s.
                Label {
                    textFormat: Text.PlainText
                    visible: clearButton.confirming
                    text: qsTr("Clear all?")
                    color: Theme.error
                    font.pixelSize: Theme.fontSizeSmall
                }

                ControlButton {
                    id: clearButton

                    property bool confirming: false

                    visible: root.viewingQueue && PlaylistController.count > 0
                    iconName: "trash"
                    iconSize: 13
                    iconColor: confirming ? Theme.error : Theme.textMuted
                    ToolTip.visible: hovered && !confirming
                    ToolTip.text: qsTr("Clear queue")
                    onClicked: {
                        if (confirming) {
                            confirming = false
                            PlaylistController.clear()
                        } else {
                            confirming = true
                            confirmTimer.restart()
                        }
                    }

                    Timer {
                        id: confirmTimer
                        interval: 3000
                        onTriggered: clearButton.confirming = false
                    }
                }

                ControlButton {
                    visible: root.showPinButton
                    iconName: "thumbtack"
                    iconSize: 14
                    active: root.pinned
                    iconColor: root.pinned ? Theme.accent : Theme.textMuted
                    rotation: root.pinned ? 0 : 45 // the button is round, so turning it turns the pin

                    Behavior on rotation { NumberAnimation { duration: Theme.anim; easing.type: Theme.easing } }

                    ToolTip.visible: hovered
                    ToolTip.text: root.pinned ? qsTr("Unpin playlist") : qsTr("Pin playlist")
                    onClicked: root.pinToggled()
                }

                ControlButton {
                    visible: root.showCloseButton
                    iconName: "close"
                    iconSize: 13
                    iconColor: Theme.textMuted
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Close")
                    onClicked: root.closeRequested()
                }
            }
        }

        // Playlists menu: choose one to view; new / rename / delete
        ThemedMenu {
            id: playlistsMenu
            objectName: "playlistsMenu"

            Instantiator {
                model: PlaylistsController.playlists

                delegate: Action {
                    required property var modelData

                    text: modelData.name + "  (" + modelData.count + ")"
                    icon.name: modelData.id === PlaylistsController.playingFromId ? "play" : "listMusic"
                    onTriggered: PlaylistsController.view(modelData.id)
                }

                onObjectAdded: (index, object) => playlistsMenu.insertAction(index, object)
                onObjectRemoved: (index, object) => playlistsMenu.removeAction(object)
            }

            // The list being played from (an album, a Mix...), first: present only while one plays
            Instantiator {
                id: playingEntry
                model: PlaylistController.contextTitle !== "" ? 1 : 0

                delegate: Action {
                    text: qsTr("Playing: %1").arg(PlaylistController.contextTitle)
                    icon.name: "play"
                    onTriggered: PlaylistsController.view(PlaylistsController.playingListId)
                }

                onObjectAdded: (index, object) => playlistsMenu.insertAction(0, object)
                onObjectRemoved: (index, object) => playlistsMenu.removeAction(object)
            }

            // "No playlists yet": present only while there are none
            Instantiator {
                model: PlaylistsController.playlists.length === 0 ? 1 : 0

                delegate: Action {
                    enabled: false
                    text: qsTr("No playlists yet")
                    icon.name: "info"
                }

                onObjectAdded: (index, object) => playlistsMenu.insertAction(playingEntry.count, object)
                onObjectRemoved: (index, object) => playlistsMenu.removeAction(object)
            }

            MenuSeparator {
                contentItem: Rectangle {
                    implicitHeight: 1
                    color: Theme.border
                }
            }

            Action {
                text: qsTr("New playlist…")
                icon.name: "plus"
                onTriggered: PlaylistsController.requestNewPlaylist([])
            }

            Action {
                text: qsTr("Import M3U playlist…")
                icon.name: "download"
                onTriggered: root.importM3uRequested()
            }

            Action {
                enabled: PlaylistsController.viewedEditable
                text: root.viewingQueue ? qsTr("Export the Queue as M3U…")
                                        : qsTr("Export “%1” as M3U…").arg(PlaylistsController.viewedName)
                icon.name: "link"
                onTriggered: root.exportM3uRequested(root.viewingQueue ? "" : PlaylistsController.viewedId,
                                                     root.viewingQueue ? qsTr("Queue") : PlaylistsController.viewedName)
            }

            Action {
                enabled: !root.viewingQueue && PlaylistsController.viewedEditable
                text: root.viewingQueue ? qsTr("Rename…") : qsTr("Rename “%1”…").arg(PlaylistsController.viewedName)
                icon.name: "settings"
                onTriggered: PlaylistsController.requestRename(PlaylistsController.viewedId)
            }

            Action {
                enabled: !root.viewingQueue && PlaylistsController.viewedEditable
                text: root.viewingQueue ? qsTr("Delete…") : qsTr("Delete “%1”…").arg(PlaylistsController.viewedName)
                icon.name: "trash"
                onTriggered: PlaylistsController.requestDelete(PlaylistsController.viewedId)
            }
        }

        PlaylistHeader {
            Layout.fillWidth: true
            visible: root.shownCount > 0
            opacity: root.switchFade
            transform: Translate { x: root.switchShift }
            sortable: root.viewingQueue
            indicatorWidth: root.indicatorWidth
            titleWidth: root.titleWidth
            artistAlbumWidth: root.artistAlbumWidth
            trackWidth: root.trackWidth
            durationWidth: root.durationWidth

            onResizeRequested: (key, width) => {
                const w = Math.round(width)
                if (key === "artistAlbum")
                    SettingsController.artistAlbumWidth = w
                else if (key === "track")
                    SettingsController.trackWidth = w
                else if (key === "duration")
                    SettingsController.durationWidth = w
            }
        }

        ListView {
            id: list
            populate: ListPopulate {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.shownCount > 0
            clip: true
            opacity: root.switchFade
            transform: Translate { x: root.switchShift }
            model: root.viewingQueue ? PlaylistController.model : PlaylistsController.viewModel
            currentIndex: -1 // selection; the playing track is PlaylistController.currentIndex
            property int openSwipeRow: -1 // row whose Delete button is revealed
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: Theme.flickDeceleration
            maximumFlickVelocity: Theme.flickVelocity
            synchronousDrag: true
            keyNavigationEnabled: true
            highlightMoveDuration: Theme.anim
            ScrollBar.vertical: ScrollBar {}

            // Rows slide in when added, fade out when removed, glide when displaced.
            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.anim }
                NumberAnimation { property: "x"; from: -24; to: 0; duration: Theme.anim; easing.type: Theme.easing }
            }
            remove: Transition {
                NumberAnimation { property: "opacity"; to: 0; duration: Theme.anim }
                NumberAnimation { property: "x"; to: 40; duration: Theme.anim; easing.type: Easing.InCubic }
            }
            displaced: Transition {
                NumberAnimation { properties: "x,y"; duration: Theme.anim; easing.type: Theme.easing }
                // finish any interrupted add animation
                NumberAnimation { property: "opacity"; to: 1; duration: Theme.anim }
            }

            Keys.onDeletePressed: {
                if (currentIndex < 0)
                    return
                if (root.viewingQueue)
                    PlaylistController.removeIndex(currentIndex)
                else
                    PlaylistsController.removeFromViewed(currentIndex)
            }
            Keys.onReturnPressed: {
                if (currentIndex < 0)
                    return
                if (root.viewingQueue)
                    PlaylistController.playIndex(currentIndex)
                else
                    PlaylistsController.playViewed(currentIndex)
            }

            delegate: PlaylistRow {
                id: row
                width: ListView.view.width
                selected: ListView.isCurrentItem
                indicatorWidth: root.indicatorWidth
                titleWidth: root.titleWidth
                artistAlbumWidth: root.artistAlbumWidth
                trackWidth: root.trackWidth
                durationWidth: root.durationWidth
                onClicked: {
                    list.currentIndex = row.index
                    list.forceActiveFocus() // so Delete / Enter reach the list
                }
                onActivated: row.isCurrent ? PlayerController.togglePlayPause()
                           : root.viewingQueue ? PlaylistController.playIndex(row.index)
                                               : PlaylistsController.playViewed(row.index)
                onContextMenuRequested: contextMenu.openFor(row.index, row.path)
                // Placed in the list, not the row: the row may scroll away or be removed meanwhile.
                onMenuButtonClicked: (x, y) => {
                    const pos = row.mapToItem(list, x, y)
                    contextMenu.openAt(row.index, row.path, list, pos.x, pos.y)
                }
                menuOpen: contextMenu.opened && contextMenu.row === row.index
                openRowIndex: list.openSwipeRow
                list: list
                rowCount: list.count
                editable: root.viewingQueue || PlaylistsController.viewedEditable
                onMoveRequested: (from, to) => root.viewingQueue ? PlaylistController.moveIndex(from, to)
                                                                 : PlaylistsController.moveInViewed(from, to)
                onSwipeOpened: list.openSwipeRow = row.index
                onDeleteRequested: {
                    list.openSwipeRow = -1
                    if (root.viewingQueue)
                        PlaylistController.removeIndex(row.index)
                    else
                        PlaylistsController.removeFromViewed(row.index)
                }
            }

            // Where dragged songs would be dropped
            Rectangle {
                readonly property Item neighbour: root.dropRow < 0 || list.count === 0 ? null
                                                  : list.itemAtIndex(Math.min(root.dropRow, list.count - 1))
                visible: neighbour !== null
                z: 20
                x: 10
                width: list.width - 20
                height: 3
                radius: 1.5
                color: Theme.accent
                y: neighbour ? (root.dropRow < list.count ? neighbour.y : neighbour.y + neighbour.height) - 1.5 : 0
            }

            // Scrolls while dragged songs are held near the top / bottom edge.
            Timer {
                interval: 16
                repeat: true
                running: root.dropRow >= 0 && list.contentHeight > list.height
                onTriggered: {
                    const pointer = list.mapFromItem(null, SongDrag.scenePos.x, SongDrag.scenePos.y).y
                    const edge = 44
                    let step = 0
                    if (pointer < edge)
                        step = -Math.ceil((edge - pointer) / 4)
                    else if (pointer > list.height - edge)
                        step = Math.ceil((pointer - (list.height - edge)) / 4)
                    if (step !== 0)
                        list.contentY = Math.max(list.originY, Math.min(list.originY + list.contentHeight - list.height,
                                                                       list.contentY + step))
                }
            }

            PlaylistContextMenu {
                id: contextMenu
                inQueue: root.viewingQueue
                canRemove: root.viewingQueue || PlaylistsController.viewedEditable
                onDetailsRequested: (path) => root.detailsRequested(path)
            }
        }

        // Empty state
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.shownCount === 0
            opacity: visible ? 1 : 0

            Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }

            Column {
                anchors.centerIn: parent
                width: parent.width - 4 * Theme.padding
                spacing: Theme.spacing
                opacity: root.switchFade
                transform: Translate { x: root.switchShift }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 76
                    height: 76
                    radius: 38
                    color: Theme.accentSoft

                    Icon {
                        anchors.centerIn: parent
                        name: root.viewingQueue ? "folderOpen" : "listMusic"
                        size: 28
                        color: Theme.accent
                    }
                }

                Item { width: 1; height: 4 }

                Label {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: root.viewingQueue ? qsTr("Your queue is empty") : qsTr("This playlist is empty")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                Label {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: root.viewingQueue
                          ? qsTr("Drop a folder of music anywhere in the window. It's scanned and sorted for you, and starts playing.")
                          : qsTr("Add songs with right-click → Add to playlist in the Queue, or the ⋮ menu of YouTube songs.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }

    }

    // Songs dragged from the Library or YouTube. An empty list says where they
    // go; otherwise a line between the rows shows the spot.
    DropHint {
        id: dropHint
        accepts: root.acceptsDrops
        radius: root.radius
        showLabel: root.shownCount === 0
        text: root.viewingQueue ? qsTr("Drop to add to the Queue")
                                : qsTr("Drop to add to “%1”").arg(PlaylistsController.viewedName)
        onDropped: SongDrag.deliver(PlaylistsController.viewedId, root.dropRow)
    }
}
