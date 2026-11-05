import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Library > Hosted library: sign in to a music server (Jellyfin), then its
// songs, albums, artists and playlists (HostedController).
Item {
    id: root

    property int tab: HostedController.SongsTab
    readonly property var tabLists: [HostedController.songs, HostedController.albums,
                                     HostedController.artists, HostedController.genres,
                                     HostedController.playlists, HostedController.folderEntries]
    readonly property bool letters: HostedController.letterTabs[tab] === true
    readonly property bool inFolders: tab === HostedController.FoldersTab
    // The tabs in the order shown (their numbers stay: sorts and views are kept by them)
    readonly property var tabOrder: [0, 1, 5, 2, 3, 4]
    // Each tab as a list or a grid of tiles (Settings: library.view.hosted.<tab>)
    readonly property var viewKeys: ["hosted.songs", "hosted.albums", "hosted.artists", "hosted.genres",
                                     "hosted.playlists", "hosted.folders"]
    readonly property bool grid: SettingsController.libraryViews[viewKeys[tab]] === true
    readonly property var shownList: tabLists[tab]
    readonly property int folderSongCount: HostedController.folderEntries.filter(e => e.kind === "song").length

    // Back: out of an album / artist / playlist, or up one folder (false: nothing to go back from)
    function back() {
        if (letterGrid.visible) {
            letterGrid.visible = false
            return true
        }
        if (HostedController.detailOpen) {
            HostedController.closeDetail()
            return true
        }
        return inFolders && HostedController.folderUp()
    }

    onVisibleChanged: if (visible) HostedController.load(tab)
    onTabChanged: {
        letterGrid.visible = false
        HostedController.closeDetail()
        HostedController.load(tab)
    }
    Connections {
        target: HostedController
        function onAccountChanged() { if (root.visible) HostedController.load(root.tab) }
    }

    // ---------------------------------------------------------------- signing in
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padding
        visible: !HostedController.signedIn
        spacing: Theme.spacing

        Label {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Connect your Jellyfin server")
            color: Theme.text
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.DemiBold
        }

        Label {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Its songs play here like your own. Your password is only used to sign in; it isn't kept.")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize
            wrapMode: Text.WordWrap
        }

        FormField {
            id: serverField
            placeholderText: qsTr("Server address, e.g. http://192.168.1.10:8096")
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            onAccepted: userField.forceActiveFocus()
        }

        FormField {
            id: userField
            placeholderText: qsTr("User name")
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            onAccepted: passwordField.forceActiveFocus()
        }

        FormField {
            id: passwordField
            placeholderText: qsTr("Password")
            echoMode: TextInput.Password
            onAccepted: signInButton.clicked()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: HostedController.busy ? qsTr("Connecting…") : HostedController.error
                color: HostedController.busy ? Theme.textMuted : Theme.error
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            PillButton {
                id: signInButton
                filled: true
                text: qsTr("Sign in")
                implicitHeight: 36
                enabled: !HostedController.busy && serverField.text.trim() !== "" && userField.text.trim() !== ""
                onClicked: {
                    HostedController.signIn(serverField.text.trim(), userField.text.trim(), passwordField.text)
                    passwordField.text = ""
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    // ---------------------------------------------------------------- signed in
    ColumnLayout {
        anchors.fill: parent
        visible: HostedController.signedIn
        spacing: 0

        TabRow {
            Layout.fillWidth: true
            Layout.margins: Theme.padding
            Layout.bottomMargin: 4
            current: root.tabOrder.indexOf(root.tab)
            tabs: [
                { icon: "music", label: qsTr("Songs") },
                { icon: "compactDisc", label: qsTr("Albums") },
                { icon: "folder", label: qsTr("Folders") },
                { icon: "user", label: qsTr("Artists") },
                { icon: "music", label: qsTr("Genres") },
                { icon: "listMusic", label: qsTr("Playlists") }
            ]
            onTabPicked: (index) => root.tab = root.tabOrder[index]
        }

        // Search (in Folders: where it is), then list / grid and sort
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.padding
            Layout.rightMargin: Theme.padding
            Layout.bottomMargin: Theme.spacing
            visible: !HostedController.detailOpen
            spacing: Theme.spacing

            FormField {
                visible: !root.inFolders
                pill: true
                placeholderText: qsTr("Search your server")
                text: HostedController.search
                leftPadding: 40
                inputMethodHints: Qt.ImhNoPredictiveText
                onTextEdited: HostedController.search = text

                Icon {
                    anchors.left: parent.left
                    anchors.leftMargin: 15
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 12
                    color: Theme.textMuted
                }
            }

            // Folders: up one, the path (a part opens that folder), play everything under it
            PillButton {
                visible: root.inFolders
                iconName: "back"
                iconSize: 12
                implicitWidth: 36
                implicitHeight: 36
                enabled: HostedController.folderCrumbs.length > 0
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Up one folder")
                onClicked: HostedController.folderUp()
            }

            ListView {
                id: crumbs
                visible: root.inFolders
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                orientation: ListView.Horizontal
                clip: true
                spacing: 0
                boundsBehavior: Flickable.StopAtBounds
                model: [{ id: "", name: qsTr("Libraries") }].concat(HostedController.folderCrumbs)
                // The deepest part stays in view (once the parts have their sizes)
                onContentWidthChanged: contentX = Math.max(0, contentWidth - width)
                onWidthChanged: contentX = Math.max(0, contentWidth - width)

                delegate: Row {
                    id: crumb
                    required property var modelData
                    required property int index
                    height: crumbs.height

                    Icon {
                        visible: crumb.index > 0
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevronRight"
                        size: 9
                        color: Theme.textDim
                    }

                    PillButton {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitHeight: 30
                        sidePadding: 10
                        transparentIdle: true
                        iconName: crumb.index === 0 ? "home" : ""
                        iconSize: 11
                        active: crumb.index === crumbs.count - 1
                        text: crumb.modelData.name
                        onClicked: if (!active) HostedController.openCrumb(crumb.index - 1)
                    }
                }
            }

            PillButton {
                visible: root.inFolders && HostedController.folderCrumbs.length > 0
                filled: true
                iconName: "play"
                iconSize: 11
                implicitWidth: 36
                implicitHeight: 36
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Play all (subfolders too)")
                onClicked: HostedController.playFolder()
            }

            ControlButton {
                iconName: root.grid ? "list" : "grid"
                iconSize: 14
                iconColor: Theme.textMuted
                ToolTip.visible: hovered
                ToolTip.text: root.grid ? qsTr("Show as a list") : qsTr("Show as a grid")
                onClicked: SettingsController.setGridView(root.viewKeys[root.tab], !root.grid)
            }

            ControlButton {
                id: sortButton
                iconName: "sortList"
                iconSize: 14
                readonly property string sort: SettingsController.hostedSorts[root.tab]
                active: sort !== "name"
                iconColor: active ? Theme.accent : Theme.textMuted
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Sort")
                onClicked: sortMenu.popup(sortButton, 0, sortButton.height)
            }
        }

        Label {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            Layout.leftMargin: Theme.padding
            Layout.rightMargin: Theme.padding
            Layout.bottomMargin: Theme.spacing
            visible: HostedController.error !== ""
            text: HostedController.error
            color: Theme.error
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
        }

        // The tab's list or grid ("Loading…" floats over it: nothing moves)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !HostedController.detailOpen

            Rectangle {
                z: 10
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 6
                width: loadingLabel.implicitWidth + 28
                height: 30
                radius: 15
                color: Theme.surfaceAlt
                border.color: Theme.border
                opacity: HostedController.busy ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Theme.anim } }

                Label {
                    id: loadingLabel
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: qsTr("Loading…")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

        // Songs, the list of albums / artists / playlists, or a folder's folders and songs
        ListView {
            id: list
            anchors.fill: parent
            anchors.leftMargin: Theme.spacing
            anchors.rightMargin: Theme.spacing
            visible: !root.grid
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: Theme.flickDeceleration
            maximumFlickVelocity: Theme.flickVelocity
            model: root.tabLists[root.tab]
            ScrollBar.vertical: ScrollBar {}

            delegate: Column {
                id: entry

                required property var modelData
                required property int index

                width: ListView.view.width

                // The first of its letter: the letter's header above it
                LetterHeader {
                    width: parent.width
                    visible: root.letters && (entry.index === 0
                                              || list.model[entry.index - 1].letter !== entry.modelData.letter)
                    letter: entry.modelData.letter || ""
                    onTapped: {
                        letterGrid.starts = HostedController.letterStarts(root.tab)
                        letterGrid.visible = true
                    }
                }

                HostedRow {
                    readonly property var modelData: entry.modelData
                    readonly property int index: entry.index

                    // A song: on the Songs tab, or in a folder (after its folders)
                    readonly property bool song: root.tab === HostedController.SongsTab || modelData.kind === "song"
                    readonly property int songIndex: root.inFolders ? index - (list.count - root.folderSongCount) : index

                    width: parent.width
                    thumbnail: modelData.kind === "folder" && !SettingsController.folderCovers ? "" : modelData.thumbnail || ""
                    icon: modelData.kind === "folder" ? "folder" : song ? "music" : "compactDisc"
                    title: song ? modelData.title : modelData.name
                    subtitle: song ? [modelData.artist, modelData.album].filter(s => s).join("  ·  ") : modelData.subtitle
                    duration: song ? modelData.durationMs : -1
                    playing: song && modelData.path === PlayerController.source
                    onTapped: {
                        if (modelData.kind === "folder")
                            HostedController.openFolder(modelData.id, modelData.name)
                        else if (song)
                            HostedController.play(root.inFolders ? HostedController.FolderList : HostedController.SongsList,
                                                  songIndex)
                        else
                            HostedController.open(root.tab, modelData.id, modelData.name, modelData.thumbnail)
                    }
                    onQueueRequested: HostedController.addToQueue(root.inFolders ? HostedController.FolderList
                                                                                 : HostedController.SongsList, songIndex)
                    favorite: song && modelData.favorite === true
                    onFavoriteToggled: HostedController.setFavorite(root.inFolders ? HostedController.FolderList
                                                                                   : HostedController.SongsList,
                                                                    songIndex, !favorite)
                    onMenuRequested: (button) => songMenu.show(button, root.inFolders ? HostedController.FolderList
                                                                                      : HostedController.SongsList, songIndex,
                                                               favorite)
                }
            }
        }

        // The same as a grid of tiles
        TileGrid {
            id: tileGrid
            anchors.fill: parent
            anchors.leftMargin: Theme.spacing
            anchors.rightMargin: Theme.spacing
            visible: root.grid
            itemCount: root.shownList.length
            revision: root.shownList
            letterStarts: root.letters ? HostedController.allLetterStarts[root.tab] : null
            onLetterTapped: {
                letterGrid.starts = HostedController.letterStarts(root.tab)
                letterGrid.visible = true
            }

            tile: Component {
                LibraryTile {
                    required property var modelData
                    readonly property var item: root.shownList[modelData] ?? ({})
                    // A song: on the Songs tab, or in a folder (after its folders)
                    readonly property bool song: root.tab === HostedController.SongsTab || item.kind === "song"
                    readonly property int songIndex: root.inFolders ? modelData - (root.shownList.length - root.folderSongCount)
                                                                    : modelData
                    readonly property int songList: root.inFolders ? HostedController.FolderList : HostedController.SongsList

                    image: item.kind === "folder" && !SettingsController.folderCovers ? "" : item.thumbnail || ""
                    icon: item.kind === "folder" ? "folder" : song ? "music"
                        : root.tab === HostedController.ArtistsTab ? "user"
                        : root.tab === HostedController.PlaylistsTab ? "listMusic" : "compactDisc"
                    title: (song ? item.title : item.name) || ""
                    subtitle: (song ? item.artist : item.subtitle) || ""
                    current: song && item.path === PlayerController.source
                    showMore: song
                    onTapped: {
                        if (item.kind === "folder")
                            HostedController.openFolder(item.id, item.name)
                        else if (song)
                            HostedController.play(songList, songIndex)
                        else
                            HostedController.open(root.tab, item.id, item.name, item.thumbnail)
                    }
                    onMoreRequested: (button) => songMenu.show(button, songList, songIndex, item.favorite === true)
                }
            }
        }

        }

        // An opened album / artist / playlist
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: HostedController.detailOpen
            spacing: Theme.spacing

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacing
                Layout.rightMargin: Theme.padding
                spacing: Theme.spacing

                ControlButton {
                    iconName: "back"
                    iconSize: 13
                    iconColor: Theme.textMuted
                    onClicked: HostedController.closeDetail()
                }

                Label {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: HostedController.detailTitle
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                PillButton {
                    filled: true
                    iconName: "play"
                    iconSize: 11
                    text: qsTr("Play")
                    implicitHeight: 32
                    enabled: HostedController.detailSongs.length > 0
                    onClicked: HostedController.play(HostedController.DetailList, 0)
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: Theme.spacing
                Layout.rightMargin: Theme.spacing
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: Theme.flickDeceleration
                maximumFlickVelocity: Theme.flickVelocity
                model: HostedController.detailSongs
                ScrollBar.vertical: ScrollBar {}

                delegate: HostedRow {
                    required property var modelData
                    required property int index

                    width: ListView.view.width
                    thumbnail: modelData.thumbnail || ""
                    title: modelData.title
                    subtitle: [modelData.artist, modelData.album].filter(s => s).join("  ·  ")
                    duration: modelData.durationMs
                    playing: modelData.path === PlayerController.source
                    onTapped: HostedController.play(HostedController.DetailList, index)
                    onQueueRequested: HostedController.addToQueue(HostedController.DetailList, index)
                    favorite: modelData.favorite === true
                    onFavoriteToggled: HostedController.setFavorite(HostedController.DetailList, index, !favorite)
                    onMenuRequested: (button) => songMenu.show(button, HostedController.DetailList, index, favorite)
                }
            }
        }
    }

    LetterJumpGrid {
        id: letterGrid
        anchors.fill: parent
        visible: false
        z: 50
        onChosen: (row) => {
            if (root.grid)
                tileGrid.positionViewAtIndex(tileGrid.rowOf(row), ListView.Beginning)
            else
                list.positionViewAtIndex(row, ListView.Beginning)
            visible = false
        }
        onClosed: visible = false
    }

    // A song's menu: to a server playlist; out of the opened playlist
    ThemedMenu {
        id: songMenu

        property int list: 0
        property int index: -1
        property bool favorite: false
        property var choices: []
        readonly property int fixedCount: 5 // the items before the playlists

        // The server's playlists can arrive after the menu opened (loaded on first use)
        Connections {
            target: HostedController
            function onListsChanged() { if (songMenu.visible) songMenu.choices = HostedController.playlistChoices() }
        }

        function show(button, list, index, favorite) {
            songMenu.list = list
            songMenu.index = index
            songMenu.favorite = favorite === true
            choices = HostedController.playlistChoices()
            popup(button, 0, button.height)
        }

        Action {
            text: songMenu.favorite ? qsTr("Remove from your favourites") : qsTr("Add to your favourites")
            icon.name: "heart"
            onTriggered: HostedController.setFavorite(songMenu.list, songMenu.index, !songMenu.favorite)
        }
        Action {
            text: qsTr("Add to the Queue")
            icon.name: "plus"
            onTriggered: HostedController.addToQueue(songMenu.list, songMenu.index)
        }

        Action {
            text: qsTr("Add to a new playlist…")
            icon.name: "plus"
            onTriggered: newPlaylistDialog.ask(qsTr("New playlist on the server"), "")
        }
        // (only in an opened playlist)
        MenuItem {
            visible: songMenu.list === HostedController.DetailList && HostedController.detailIsPlaylist
            height: visible ? implicitHeight : 0
            action: Action {
                text: qsTr("Remove from this playlist")
                icon.name: "trash"
                onTriggered: HostedController.removeFromPlaylist(songMenu.index)
            }
        }
        MenuSeparator {
            visible: songMenu.choices.length > 0
            height: visible ? implicitHeight : 0
            contentItem: Rectangle {
                implicitHeight: 1
                color: Theme.border
            }
        }

        Instantiator {
            model: songMenu.choices
            delegate: Action {
                required property var modelData
                text: qsTr("Add to %1").arg(modelData.name)
                icon.name: "listMusic"
                onTriggered: HostedController.addToPlaylist(songMenu.list, songMenu.index, modelData.id, modelData.name)
            }
            onObjectAdded: (index, object) => songMenu.insertAction(index + songMenu.fixedCount, object)
            onObjectRemoved: (index, object) => songMenu.removeAction(object)
        }
    }

    NameDialog {
        id: newPlaylistDialog
        onAccepted: (name) => HostedController.addToNewPlaylist(songMenu.list, songMenu.index, name)
    }

    // The tab's ways to sort (what the server can do), the one in use checked
    ThemedMenu {
        id: sortMenu

        Instantiator {
            model: [[{ id: "name", text: qsTr("Title A–Z") }, { id: "nameDesc", text: qsTr("Title Z–A") },
                     { id: "newest", text: qsTr("Newest added") }, { id: "oldest", text: qsTr("Oldest added") },
                     { id: "artist", text: qsTr("Artist") }, { id: "album", text: qsTr("Album") }],
                    [{ id: "name", text: qsTr("Name A–Z") }, { id: "nameDesc", text: qsTr("Name Z–A") },
                     { id: "newest", text: qsTr("Newest added") }, { id: "oldest", text: qsTr("Oldest added") },
                     { id: "artist", text: qsTr("Artist") }, { id: "year", text: qsTr("Year") },
                     { id: "mostSongs", text: qsTr("Most songs") }, { id: "fewestSongs", text: qsTr("Fewest songs") }],
                    [{ id: "name", text: qsTr("Name A–Z") }, { id: "nameDesc", text: qsTr("Name Z–A") },
                     { id: "mostSongs", text: qsTr("Most songs") }, { id: "fewestSongs", text: qsTr("Fewest songs") }],
                    [{ id: "name", text: qsTr("Name A–Z") }, { id: "nameDesc", text: qsTr("Name Z–A") },
                     { id: "mostSongs", text: qsTr("Most songs") }, { id: "fewestSongs", text: qsTr("Fewest songs") }],
                    [{ id: "name", text: qsTr("Name A–Z") }, { id: "nameDesc", text: qsTr("Name Z–A") },
                     { id: "newest", text: qsTr("Newest added") }, { id: "oldest", text: qsTr("Oldest added") },
                     { id: "mostSongs", text: qsTr("Most songs") }, { id: "fewestSongs", text: qsTr("Fewest songs") }],
                    [{ id: "name", text: qsTr("Name A–Z") }, { id: "nameDesc", text: qsTr("Name Z–A") },
                     { id: "mostSongs", text: qsTr("Most items") }, { id: "fewestSongs", text: qsTr("Fewest items") }]][root.tab]

            delegate: Action {
                required property var modelData
                text: modelData.text
                icon.name: SettingsController.hostedSorts[root.tab] === modelData.id ? "check" : ""
                onTriggered: SettingsController.setHostedSort(root.tab, modelData.id)
            }

            onObjectAdded: (index, object) => sortMenu.insertAction(index, object)
            onObjectRemoved: (index, object) => sortMenu.removeAction(object)
        }
    }

    component FormField: TextField {
        id: field
        // Search (pill-shaped, as in the local library) or a sign-in field
        property bool pill: false
        Layout.fillWidth: true
        implicitHeight: pill ? 40 : 42
        color: Theme.text
        placeholderTextColor: Theme.textMuted
        font.pixelSize: Theme.fontSize
        leftPadding: Theme.padding
        background: Rectangle {
            radius: field.pill ? height / 2 : Theme.radius
            color: field.pill ? (field.activeFocus ? Theme.fillStrong : Theme.fill) : Theme.fillSoft
            border.width: field.pill && !field.activeFocus ? 0 : 1
            border.color: field.activeFocus ? Theme.accent : Theme.border
        }
    }
}
