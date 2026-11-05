pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The local library panel: Songs / Albums / Artists / Folders. Opening an
// album or an artist shows its songs, with a back button; Folders is browsed
// like a file manager. Clicking a song plays the list it's in (never adding it
// to the Queue). The header has Refresh, Pin and Close. The music folders (and
// the ones left out) are chosen in Settings.
Rectangle {
    id: root

    property bool showPinButton: true
    property bool pinned: false
    property bool showCloseButton: true
    property int tab: 0
    // What the panel shows: "" = the choice between the two libraries, "local" = the
    // songs on this device (tabs below), "hosted" = a music server (frontend/hosted)
    property string source: SettingsController.librarySource
    readonly property bool hasFolders: SettingsController.libraryFolders.length > 0
    readonly property bool inDetail: LocalLibraryController.detailKind !== 0 && (tab >= 1 && tab <= 3)

    // A drag on the tabs must not close the drawer holding this panel (see YtHomeView).
    readonly property bool swipeBlocked: tabRow.busy

    signal pinToggled()
    signal closeRequested()
    signal settingsRequested()
    signal detailsRequested(string path)
    signal editTagsRequested(string path)
    signal foldersSettingsRequested() // the music folders are chosen in Settings

    onTabChanged: {
        LocalLibraryController.closeDetail()
        letterGrid.visible = false
    }

    // Library opened: the library picked last (the choice if none yet)
    function chooseSource() {
        letterGrid.visible = false
        source = SettingsController.librarySource
    }

    // The letter grid over a list (a letter header was tapped)
    function openLetters(tab, view) {
        letterGrid.starts = LocalLibraryController.letterStarts(tab)
        letterGrid.view = view
        letterGrid.visible = true
    }

    // Back / Esc: the letter grid, out of the album / artist, or up one folder (false: nothing to go back from).
    readonly property bool canGoBack: letterGrid.visible || inDetail
                                      || (tab === 4 && hasFolders && LocalLibraryController.folder !== "")
                                      || source !== ""
    function back() {
        if (letterGrid.visible)
            letterGrid.visible = false
        else if (source === "hosted" && hostedView.back())
            return true // out of an album / artist / playlist, or up one folder
        else if (inDetail)
            LocalLibraryController.closeDetail()
        else if (source === "local" && tab === 4 && hasFolders && LocalLibraryController.folder !== "")
            LocalLibraryController.folderUp()
        else if (source !== "")
            source = "" // back to the choice
        else
            return false
        return true
    }
    // Ctrl+F: the search of the open tab, ready to type.
    function focusSearch() {
        source = "local"
        LocalLibraryController.closeDetail()
        searchField.forceActiveFocus()
        searchField.selectAll()
    }

    color: Theme.panelShade // softens the cover tint behind it

    LibraryAddAllMenu {
        id: addAllMenu
    }

    // The tabs in the order shown (their numbers stay: sorts and views are kept by them)
    readonly property var tabOrder: [0, 1, 4, 2, 3]
    function tabPosition(t) { return tabOrder.indexOf(t) }
    // Each tab shown as a list or a grid of tiles (Settings: library.view.local.<tab>)
    readonly property var viewKeys: ["local.songs", "local.albums", "local.artists", "local.genres", "local.folders"]
    function gridView(t) { return SettingsController.libraryViews[viewKeys[t]] === true }

    // A grid tile's song menu (one for all of them)
    LibrarySongMenu {
        id: gridSongMenu
        onDetailsRequested: (path) => root.detailsRequested(path)
        onEditTagsRequested: (path) => root.editTagsRequested(path)
    }
    function openSongMenu(button, list, index, path) {
        gridSongMenu.list = list
        gridSongMenu.index = index
        gridSongMenu.path = path
        gridSongMenu.popup(button, 0, button.height)
    }

    // Which setting the sort button changes: each tab remembers its own.
    readonly property string sortSetting: ["librarySort", "albumSort", "artistSort", "genreSort", "folderSort"][tab]

    ThemedMenu {
        id: songSortMenu

        SortAction { sort: "title"; text: qsTr("Title A–Z") }
        SortAction { sort: "titleDesc"; text: qsTr("Title Z–A") }
        SortAction { sort: "newest"; text: qsTr("Newest added") }
        SortAction { sort: "oldest"; text: qsTr("Oldest added") }
        SortAction { sort: "modifiedNew"; text: qsTr("Newly-modified date") }
        SortAction { sort: "modifiedOld"; text: qsTr("Last-modified date") }
        SortAction { sort: "artist"; text: qsTr("Artist") }
        SortAction { sort: "album"; text: qsTr("Album") }
    }

    ThemedMenu {
        id: albumSortMenu

        SortAction { setting: "albumSort"; sort: "name"; text: qsTr("Name A–Z") }
        SortAction { setting: "albumSort"; sort: "nameDesc"; text: qsTr("Name Z–A") }
        SortAction { setting: "albumSort"; sort: "newest"; text: qsTr("Newest added") }
        SortAction { setting: "albumSort"; sort: "oldest"; text: qsTr("Oldest added") }
        SortAction { setting: "albumSort"; sort: "modifiedNew"; text: qsTr("Newly-modified date") }
        SortAction { setting: "albumSort"; sort: "modifiedOld"; text: qsTr("Last-modified date") }
        SortAction { setting: "albumSort"; sort: "artist"; text: qsTr("Artist") }
        SortAction { setting: "albumSort"; sort: "mostSongs"; text: qsTr("Most songs") }
    }

    ThemedMenu {
        id: artistSortMenu

        SortAction { setting: "artistSort"; sort: "name"; text: qsTr("Name A–Z") }
        SortAction { setting: "artistSort"; sort: "nameDesc"; text: qsTr("Name Z–A") }
        SortAction { setting: "artistSort"; sort: "mostSongs"; text: qsTr("Most songs") }
        SortAction { setting: "artistSort"; sort: "fewestSongs"; text: qsTr("Fewest songs") }
    }

    ThemedMenu {
        id: genreSortMenu

        SortAction { setting: "genreSort"; sort: "name"; text: qsTr("Name A–Z") }
        SortAction { setting: "genreSort"; sort: "nameDesc"; text: qsTr("Name Z–A") }
        SortAction { setting: "genreSort"; sort: "mostSongs"; text: qsTr("Most songs") }
        SortAction { setting: "genreSort"; sort: "fewestSongs"; text: qsTr("Fewest songs") }
    }

    ThemedMenu {
        id: folderSortMenu

        SortAction { setting: "folderSort"; sort: "name"; text: qsTr("Name A–Z") }
        SortAction { setting: "folderSort"; sort: "nameDesc"; text: qsTr("Name Z–A") }
        SortAction { setting: "folderSort"; sort: "mostSongs"; text: qsTr("Most songs") }
        SortAction { setting: "folderSort"; sort: "fewestSongs"; text: qsTr("Fewest songs") }
        SortAction { setting: "folderSort"; sort: "modifiedNew"; text: qsTr("Newly-modified date") }
        SortAction { setting: "folderSort"; sort: "modifiedOld"; text: qsTr("Last-modified date") }
    }
    radius: Theme.radiusCard
    border.color: Theme.border


    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 1 // inside the border
        anchors.bottomMargin: 6 // scrolling rows stay clear of the rounded corners
        spacing: 0

        // Header
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.headerHeight
            color: Theme.fillSoft
            topLeftRadius: Theme.radiusCard - 1
            topRightRadius: Theme.radiusCard - 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.padding
                anchors.rightMargin: Theme.spacing
                spacing: Theme.spacing

                ControlButton {
                    visible: root.source !== ""
                    iconName: "back"
                    iconSize: 13
                    iconColor: Theme.textMuted
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Both libraries")
                    onClicked: root.source = ""
                }

                Icon {
                    visible: root.source === ""
                    name: "compactDisc"
                    size: 14
                    color: Theme.accent
                }

                Label {
                    text: root.source === "local" ? qsTr("Local library")
                        : root.source === "hosted" ? qsTr("Hosted library") : qsTr("Library")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeLarge
                }

                // Local: how many songs; hosted: which server
                Label {
                    Layout.fillWidth: true
                    text: root.source === "local" && LocalLibraryController.songCount > 0
                          ? Util.songCount(LocalLibraryController.songCount)
                          : root.source === "hosted" && HostedController.signedIn ? HostedController.serverName : ""
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                }

                ControlButton {
                    id: refreshButton
                    readonly property bool hosted: root.source === "hosted"
                    readonly property bool working: hosted ? HostedController.busy : LocalLibraryController.scanning
                    visible: root.source === "local" || (hosted && HostedController.signedIn)
                    iconName: "refresh"
                    iconSize: 13
                    enabled: !working && (hosted || root.hasFolders)
                    iconColor: working ? Theme.accent : Theme.textMuted
                    ToolTip.visible: hovered
                    ToolTip.text: hosted ? qsTr("Load again from the server") : qsTr("Look for new and changed songs")
                    onClicked: hosted ? HostedController.refresh(hostedView.tab) : LocalLibraryController.refresh()

                    RotationAnimation on rotation {
                        running: refreshButton.working
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 1000
                        onRunningChanged: if (!running) refreshButton.rotation = 0
                    }
                }

                ControlButton {
                    visible: root.showPinButton
                    iconName: "thumbtack"
                    iconSize: 14
                    active: root.pinned
                    iconColor: root.pinned ? Theme.accent : Theme.textMuted
                    rotation: root.pinned ? 0 : 45
                    ToolTip.visible: hovered
                    ToolTip.text: root.pinned ? qsTr("Unpin panel") : qsTr("Pin panel")
                    onClicked: root.pinToggled()

                    Behavior on rotation { NumberAnimation { duration: Theme.anim; easing.type: Theme.easing } }
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

        // Tabs
        // ---- The choice between the two libraries
        LibrarySourceChooser {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.source === ""
            onChosen: (source) => {
                root.source = source
                SettingsController.librarySource = source // opens there next time
            }
        }

        // ---- Hosted library (a music server)
        HostedLibraryView {
            id: hostedView
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.source === "hosted"
        }

        // ---- Local library: tabs, search and the lists
        TabRow {
            id: tabRow
            visible: root.source === "local"
            Layout.fillWidth: true
            Layout.margins: Theme.padding
            Layout.bottomMargin: 4
            current: root.tabPosition(root.tab)
            tabs: [
                { icon: "music", label: qsTr("Songs") },
                { icon: "compactDisc", label: qsTr("Albums") },
                { icon: "folder", label: qsTr("Folders") },
                { icon: "user", label: qsTr("Artists") },
                { icon: "music", label: qsTr("Genres") }
            ]
            onTabPicked: (index) => root.tab = root.tabOrder[index]
        }

        // Scan progress
        Label {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.padding
            Layout.rightMargin: Theme.padding
            visible: root.source === "local" && LocalLibraryController.scanning
            text: LocalLibraryController.scanTotal > 0
                  ? qsTr("Reading songs… %1 / %2").arg(LocalLibraryController.scanDone).arg(LocalLibraryController.scanTotal)
                  : qsTr("Looking for songs…")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
        }

        // Search and sort, for whichever tab is open
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.padding
            Layout.rightMargin: Theme.padding
            Layout.topMargin: 4
            Layout.bottomMargin: Theme.spacing
            visible: root.source === "local" && LocalLibraryController.songCount > 0 && !root.inDetail
            spacing: Theme.spacing

            TextField {
                id: searchField
                Layout.fillWidth: true
                implicitHeight: 40
                leftPadding: 40
                rightPadding: LocalLibraryController.search !== "" ? 40 : 16
                placeholderText: [qsTr("Search your library"), qsTr("Search albums"), qsTr("Search artists"), qsTr("Search genres"),
                                  qsTr("Search this folder")][root.tab]
                placeholderTextColor: Theme.textMuted
                color: Theme.text
                font.pixelSize: Theme.fontSize
                selectByMouse: true
                text: LocalLibraryController.search
                onTextEdited: LocalLibraryController.search = text

                background: Rectangle {
                    radius: height / 2
                    color: searchField.activeFocus ? Theme.fillStrong : Theme.fill
                    border.width: searchField.activeFocus ? 1 : 0
                    border.color: Theme.accent

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }

                Icon {
                    anchors.left: parent.left
                    anchors.leftMargin: 15
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 12
                    color: Theme.textMuted
                }

                ControlButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    visible: LocalLibraryController.search !== ""
                    iconName: "close"
                    iconSize: 12
                    iconColor: Theme.textMuted
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Clear")
                    onClicked: LocalLibraryController.search = ""
                }
            }

            // List or grid, for this tab
            ControlButton {
                readonly property bool grid: root.gridView(root.tab)
                iconName: grid ? "list" : "grid"
                iconSize: 14
                iconColor: Theme.textMuted
                ToolTip.visible: hovered
                ToolTip.text: grid ? qsTr("Show as a list") : qsTr("Show as a grid")
                onClicked: SettingsController.setGridView(root.viewKeys[root.tab], !grid)
            }

            ControlButton {
                id: sortButton
                iconName: "sortList"
                iconSize: 14
                active: SettingsController[root.sortSetting] !== (root.tab === 0 ? "title" : "name")
                iconColor: active ? Theme.accent : Theme.textMuted
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Sort")
                onClicked: [songSortMenu, albumSortMenu, artistSortMenu, genreSortMenu, folderSortMenu][root.tab]
                           .popup(sortButton, 0, sortButton.height)
            }
        }

        // Pages: the new one slides in from its side, the old one out the other way.
        Item {
            id: pages
            visible: root.source === "local"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            // ---- Songs
            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.spacing
                opacity: root.tab === 0 ? 1 : 0
                visible: opacity > 0
                transform: PageShift { page: 0 }
                Behavior on opacity { NumberAnimation { duration: Theme.anim } }

                SongList {
                    id: songsList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !root.gridView(0)
                    model: LocalLibraryController.songs
                    list: LocalLibraryController.SongsList
                    letters: LocalLibraryController.songLetters
                }

                SongGrid {
                    id: songsGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.gridView(0)
                    songs: LocalLibraryController.songs
                    list: LocalLibraryController.SongsList
                    letterStarts: LocalLibraryController.songLetters
                                  ? LocalLibraryController.allLetterStarts[0] : null
                    onLetterTapped: root.openLetters(0, songsGrid)
                }
            }

            // ---- Albums: a grid of covers or a list (letter headers when sorted by name)
            TileGrid {
                id: albumGrid
                anchors.fill: parent
                anchors.leftMargin: Theme.spacing
                anchors.rightMargin: Theme.spacing
                opacity: root.tab === 1 && !root.inDetail && root.gridView(1) ? 1 : 0
                visible: opacity > 0
                transform: PageShift { page: 1 }
                Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                itemCount: LocalLibraryController.albums.length
                letterStarts: LocalLibraryController.albumLetters
                              ? LocalLibraryController.allLetterStarts[1] : null
                onLetterTapped: root.openLetters(1, albumGrid)

                tile: Component {
                    LibraryTile {
                        required property var modelData
                        readonly property var album: LocalLibraryController.albums[modelData] ?? ({})

                        image: Util.coverSource(album.coverPath || "", "")
                        icon: "compactDisc"
                        title: album.album || ""
                        subtitle: album.artist || ""
                        onTapped: LocalLibraryController.showAlbum(album.key)
                        dragPayload: function() {
                            return { items: LocalLibraryController.albumItems(album.key), title: album.album,
                                     subtitle: Util.songCount(album.count), cover: Util.coverSource(album.coverPath, "") }
                        }
                    }
                }
            }

            EntryList {
                page: 1
                shown: !root.gridView(1)
                albums: true
                letters: LocalLibraryController.albumLetters
                model: LocalLibraryController.albums
                onEntryOpened: (key) => LocalLibraryController.showAlbum(key)
            }

            // ---- Artists
            EntryGrid {
                page: 2
                icon: "user"
                entries: LocalLibraryController.artists
                letters: LocalLibraryController.artistLetters
                onEntryOpened: (name) => LocalLibraryController.showArtist(name)
            }

            EntryList {
                page: 2
                shown: !root.gridView(2)
                letters: LocalLibraryController.artistLetters
                model: LocalLibraryController.artists
                onEntryOpened: (name) => LocalLibraryController.showArtist(name)
            }

            // ---- Genres
            EntryGrid {
                page: 3
                icon: "music"
                entries: LocalLibraryController.genres
                letters: LocalLibraryController.genreLetters
                onEntryOpened: (name) => LocalLibraryController.showGenre(name)
            }

            EntryList {
                page: 3
                shown: !root.gridView(3)
                letters: LocalLibraryController.genreLetters
                model: LocalLibraryController.genres
                note: LocalLibraryController.songsWithoutGenre > 0
                      ? qsTr("Not shown: %1 without a genre tag").arg(Util.songCount(LocalLibraryController.songsWithoutGenre)) : ""
                onEntryOpened: (name) => LocalLibraryController.showGenre(name)
            }

            // ---- An opened album / artist
            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.spacing
                opacity: root.inDetail ? 1 : 0
                visible: opacity > 0
                transform: DetailShift {}
                Behavior on opacity { NumberAnimation { duration: Theme.anim } }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.spacing
                    Layout.rightMargin: Theme.padding
                    spacing: Theme.padding

                    PillButton {
                        iconName: "back"
                        iconSize: 12
                        implicitWidth: 36
                        implicitHeight: 36
                        ToolTip.visible: hovered
                        ToolTip.text: [qsTr("Back to albums"), qsTr("Back to artists"), qsTr("Back to genres")][root.tab - 1] ?? ""
                        onClicked: LocalLibraryController.closeDetail()
                    }

                    Rectangle {
                        visible: LocalLibraryController.detailKind === 1
                        Layout.preferredWidth: 56
                        Layout.preferredHeight: 56
                        radius: Theme.radius
                        color: Theme.surfaceAlt
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: Util.coverSource(LocalLibraryController.detailCoverPath, "")
                            sourceSize: Qt.size(112, 112)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            Layout.fillWidth: true
                            text: LocalLibraryController.detailTitle
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: LocalLibraryController.detailSubtitle
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                    }
                }

                RowLayout {
                    Layout.leftMargin: Theme.padding
                    spacing: 6

                    PillButton {
                        iconName: "play"
                        iconSize: 11
                        text: qsTr("Play all")
                        implicitHeight: 32
                        filled: true
                        onClicked: LocalLibraryController.play(LocalLibraryController.DetailList, -1)
                    }

                    PillButton {
                        id: addAllButton
                        iconName: "chevronDown"
                        iconSize: 11
                        text: qsTr("Add all")
                        implicitHeight: 32
                        onClicked: addAllMenu.openAt(
                            addAllButton, LocalLibraryController.items(LocalLibraryController.DetailList, -1),
                            () => LocalLibraryController.addToQueue(LocalLibraryController.DetailList, -1))
                    }
                }

                SongList {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: LocalLibraryController.detailSongs
                    list: LocalLibraryController.DetailList
                    showAlbum: LocalLibraryController.detailKind !== 1
                }
            }

            // ---- Folders, browsed like a file manager: a path bar, then the
            // folder's subfolders and its songs. At the top, the music folders
            // (added and removed in Settings).
            ColumnLayout {
                anchors.fill: parent
                spacing: 4
                opacity: root.tab === 4 && root.hasFolders ? 1 : 0
                visible: opacity > 0
                transform: PageShift { page: 4 }
                Behavior on opacity { NumberAnimation { duration: Theme.anim } }

                readonly property bool atTop: LocalLibraryController.folder === ""

                // Path bar: up, then where we are (each part opens that folder)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.spacing
                    Layout.rightMargin: Theme.padding
                    spacing: 2

                    PillButton {
                        iconName: "back"
                        iconSize: 12
                        implicitWidth: 36
                        implicitHeight: 36
                        enabled: !parent.parent.atTop
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Up one folder")
                        onClicked: LocalLibraryController.folderUp()
                    }

                    Flickable {
                        id: pathBar
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        clip: true
                        contentWidth: crumbs.width
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        flickDeceleration: Theme.flickDeceleration
                        maximumFlickVelocity: Theme.flickVelocity
                        synchronousDrag: true
                        // The deepest part stays in view.
                        onContentWidthChanged: contentX = Math.max(0, contentWidth - width)

                        Row {
                            id: crumbs
                            height: parent.height
                            spacing: 0

                            Repeater {
                                model: [{ name: qsTr("Folders"), path: "" }].concat(LocalLibraryController.folderCrumbs)

                                delegate: Row {
                                    id: crumb

                                    required property var modelData
                                    required property int index
                                    readonly property bool last: index === LocalLibraryController.folderCrumbs.length

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
                                        iconName: crumb.index === 0 ? "home" : ""
                                        iconSize: 11
                                        text: crumb.modelData.name
                                        implicitHeight: 30
                                        sidePadding: 10
                                        transparentIdle: true
                                        active: crumb.last
                                        onClicked: if (!crumb.last) LocalLibraryController.openFolder(crumb.modelData.path)
                                    }
                                }
                            }
                        }
                    }

                    PillButton {
                        visible: !parent.parent.atTop
                        iconName: "play"
                        iconSize: 11
                        implicitWidth: 36
                        implicitHeight: 36
                        filled: true
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Play all (subfolders too)")
                        onClicked: LocalLibraryController.playFolder()
                    }

                    PillButton {
                        id: addFolderButton
                        visible: !parent.parent.atTop
                        iconName: "chevronDown"
                        iconSize: 11
                        implicitWidth: 36
                        implicitHeight: 36
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Add all (subfolders too)")
                        onClicked: addAllMenu.openAt(addFolderButton,
                                                     LocalLibraryController.folderItems(LocalLibraryController.folder),
                                                     () => LocalLibraryController.addFolderToQueue())
                    }
                }

                // Subfolders first, then the songs, in one scrolling list
                // As a grid: the subfolders' tiles, then the songs'
                TileGrid {
                    id: folderGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: Theme.spacing
                    Layout.rightMargin: Theme.spacing
                    visible: root.gridView(4)
                    readonly property int folderCount: LocalLibraryController.subfolders.length
                    itemCount: folderCount + LocalLibraryController.folderSongs.count
                    revision: LocalLibraryController.subfolders

                    tile: Component {
                        Loader {
                            id: folderCell
                            required property var modelData
                            readonly property bool isFolder: modelData < folderGrid.folderCount
                            sourceComponent: isFolder ? folderTile : songTile

                            Component {
                                id: folderTile
                                LibraryTile {
                                    readonly property var folder: LocalLibraryController.subfolders[folderCell.modelData] ?? ({})
                                    icon: "folder"
                                    image: SettingsController.folderCovers && folder.coverPath ? Util.coverSource(folder.coverPath, "") : ""
                                    title: folder.name || ""
                                    subtitle: folder.location || Util.songCount(folder.count || 0)
                                    onTapped: {
                                        LocalLibraryController.openFolder(folder.path)
                                        folderGrid.positionViewAtBeginning()
                                    }
                                }
                            }
                            Component {
                                id: songTile
                                SongTile {
                                    songs: LocalLibraryController.folderSongs
                                    list: LocalLibraryController.FolderList
                                    index: folderCell.modelData - folderGrid.folderCount
                                }
                            }
                        }
                    }
                }

                ListView {
                    id: folderView
                    visible: !root.gridView(4)
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: Theme.spacing
                    Layout.rightMargin: Theme.spacing
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickDeceleration: Theme.flickDeceleration
                    maximumFlickVelocity: Theme.flickVelocity
                    synchronousDrag: true
                    spacing: 2
                    ScrollBar.vertical: ScrollBar {}
                    model: LocalLibraryController.folderSongs

                    header: Column {
                        width: folderView.width
                        spacing: 2
                        bottomPadding: LocalLibraryController.subfolders.length > 0 && folderView.count > 0 ? 6 : 0

                        Repeater {
                            model: LocalLibraryController.subfolders

                            delegate: LibraryFolderRow {
                                required property var modelData

                                width: folderView.width
                                name: modelData.name
                                path: modelData.path
                                count: modelData.count
                                coverPath: SettingsController.folderCovers ? modelData.coverPath || "" : ""
                                location: modelData.location || ""
                                onOpened: {
                                    LocalLibraryController.openFolder(path)
                                    folderView.positionViewAtBeginning()
                                }
                            }
                        }
                    }

                    delegate: LibrarySongRow {
                        width: ListView.view.width
                        list: LocalLibraryController.FolderList
                        onDetailsRequested: (path) => root.detailsRequested(path)
                        onEditTagsRequested: (path) => root.editTagsRequested(path)
                    }

                    Label {
                        anchors.centerIn: parent
                        width: parent.width - 4 * Theme.padding
                        visible: folderView.count === 0 && LocalLibraryController.subfolders.length === 0
                                 && LocalLibraryController.search === ""
                        text: qsTr("No songs in this folder.")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ---- No music folders yet (they're chosen in Settings)
            Column {
                anchors.centerIn: parent
                width: parent.width - 4 * Theme.padding
                spacing: Theme.spacing
                visible: !root.hasFolders

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 76
                    height: 76
                    radius: 38
                    color: Theme.accentSoft

                    Icon {
                        anchors.centerIn: parent
                        name: "compactDisc"
                        size: 28
                        color: Theme.accent
                    }
                }

                Item { width: 1; height: 4 }

                Label {
                    width: parent.width
                    text: qsTr("Build your library")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                }

                Label {
                    width: parent.width
                    text: qsTr("Choose the folders where your music is. Every song in them shows up here, sorted into albums, artists and folders.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                Item { width: 1; height: 4 }

                PillButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    iconName: "folderPlus"
                    iconSize: 12
                    text: qsTr("Choose music folders")
                    implicitHeight: 36
                    filled: true
                    onClicked: root.foldersSettingsRequested()
                }
            }

            // A search that found nothing
            Label {
                anchors.centerIn: parent
                width: parent.width - 4 * Theme.padding
                visible: LocalLibraryController.search !== "" && !root.inDetail
                         && [LocalLibraryController.songs.count, LocalLibraryController.albums.length,
                             LocalLibraryController.artists.length, LocalLibraryController.genres.length,
                             LocalLibraryController.subfolders.length + LocalLibraryController.folderSongs.count][root.tab] === 0
                text: qsTr("Nothing matches your search.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            // Folders added, nothing found (yet)
            Label {
                anchors.centerIn: parent
                width: parent.width - 4 * Theme.padding
                visible: root.hasFolders && root.tab !== 4 && LocalLibraryController.songCount === 0
                         && !LocalLibraryController.scanning
                text: qsTr("No songs found in your library folders.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }

    }

    // A list of library songs.
    // One way to sort a tab; a check marks the one in use.
    component SortAction: Action {
        property string setting: "librarySort"
        property string sort

        icon.name: SettingsController[setting] === sort ? "check" : ""
        onTriggered: SettingsController[setting] = sort
    }

    LetterJumpGrid {
        id: letterGrid

        property Item view: null

        anchors.fill: parent
        visible: false
        z: 50
        onChosen: (row) => {
            if (view)
                view.positionViewAtIndex(view.rowOf ? view.rowOf(row) : row, ListView.Beginning)
            visible = false
        }
        onClosed: visible = false
    }

    // A song's tile in a grid: tap plays the list it's in from it, "⋮" opens its menu.
    component SongTile: LibraryTile {
        id: songTileRoot
        required property var songs // a LibrarySongsModel
        property int list: LocalLibraryController.SongsList
        required property int index
        readonly property var song: (songs.count, songs.get(index))
        current: PlayerController.source === (song.path || "")
        image: Util.coverSource(song.path || "", "")
        icon: "music"
        title: song.title || ""
        subtitle: song.artist || ""
        showMore: true
        onTapped: current ? PlayerController.togglePlayPause() : LocalLibraryController.play(list, index)
        onMoreRequested: (button) => root.openSongMenu(button, list, index, song.path)
        dragPayload: function() {
            return { items: [{ path: song.path }], title: song.title, subtitle: song.artist,
                     cover: Util.coverSource(song.path, "") }
        }
    }

    // Songs as a grid of covers
    component SongGrid: TileGrid {
        id: songGridRoot
        required property var songs
        property int list: LocalLibraryController.SongsList
        itemCount: songs.count
        revision: LocalLibraryController.allLetterStarts // (changes with every search / sort)
        tile: Component {
            SongTile {
                required property var modelData
                songs: songGridRoot.songs
                list: songGridRoot.list
                index: modelData
            }
        }
    }

    // Artists / genres as a grid of icon tiles (shown instead of their EntryList)
    component EntryGrid: TileGrid {
        id: entryGridRoot
        required property int page
        required property var entries
        property string icon: "user"
        property bool letters: false
        signal entryOpened(string name)

        anchors.fill: parent
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacing
        opacity: root.tab === page && !root.inDetail && root.gridView(page) ? 1 : 0
        visible: opacity > 0
        transform: PageShift { page: entryGridRoot.page }
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
        itemCount: entries.length
        letterStarts: letters ? LocalLibraryController.allLetterStarts[page] : null
        onLetterTapped: root.openLetters(page, entryGridRoot)
        tile: Component {
            LibraryTile {
                required property var modelData
                readonly property var entry: entryGridRoot.entries[modelData] ?? ({})
                icon: entryGridRoot.icon
                title: entry.name || ""
                subtitle: Util.songCount(entry.count || 0)
                onTapped: entryGridRoot.entryOpened(entry.name)
            }
        }
    }

    component SongList: ListView {
        id: songList
        populate: ListPopulate {}

        property int list: LocalLibraryController.SongsList
        property bool showAlbum: true
        property bool letters: false // letter headers (the Songs tab sorted by title)

        section.property: letters ? "letter" : ""
        section.criteria: ViewSection.FullString
        section.delegate: LetterHeader {
            required property string section
            width: songList.width
            letter: section
            onTapped: root.openLetters(0, songList)
        }

        Layout.leftMargin: Theme.spacing
        Layout.rightMargin: Theme.spacing
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: Theme.flickDeceleration
        maximumFlickVelocity: Theme.flickVelocity
        synchronousDrag: true
        spacing: 2
        ScrollBar.vertical: ScrollBar {}

        delegate: LibrarySongRow {
            width: ListView.view.width
            list: songList.list
            showAlbum: songList.showAlbum
            onDetailsRequested: (path) => root.detailsRequested(path)
            onEditTagsRequested: (path) => root.editTagsRequested(path)
        }
    }

    // The opened album / artist slides in from the right.
    component DetailShift: Translate {
        x: root.inDetail ? 0 : 48
        Behavior on x { NumberAnimation { duration: Theme.animSlow; easing.type: Theme.easingPanel } }
    }

    // Horizontal offset of a tab page: 0 when shown, else off to its side.
    // A list of names with their song counts (Artists, Genres).
    component EntryList: ListView {
        id: entries

        required property int page
        property string note // a line above the list
        property bool letters: false // letter headers (sorted by name)
        property bool shown: true    // (false: the tab shows its grid instead)
        property bool albums: false  // albums: their covers, names and artists (opened by key)

        signal entryOpened(string name)

        populate: ListPopulate {}
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacing
        opacity: root.tab === page && !root.inDetail && shown ? 1 : 0
        visible: opacity > 0
        transform: PageShift { page: entries.page }
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: Theme.flickDeceleration
        maximumFlickVelocity: Theme.flickVelocity
        synchronousDrag: true
        spacing: 2
        ScrollBar.vertical: ScrollBar {}

        header: Item {
            width: entries.width
            height: entries.note !== "" ? noteLabel.implicitHeight + Theme.spacing : 0

            Label {
                id: noteLabel
                width: parent.width
                visible: entries.note !== ""
                leftPadding: 8
                rightPadding: 8
                text: entries.note
                color: Theme.text
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }
        }

        delegate: Column {
            id: entry

            required property var modelData
            required property int index

            width: ListView.view.width

            // The first of its letter: the letter's header above it
            LetterHeader {
                width: parent.width
                visible: entries.letters && (entry.index === 0
                                             || entries.model[entry.index - 1].letter !== entry.modelData.letter)
                letter: entry.modelData.letter || ""
                onTapped: root.openLetters(entries.page, entries)
            }

            Rectangle {
                id: artistRow

                readonly property var modelData: entry.modelData

                width: parent.width
                height: 52
                radius: Theme.radius
                color: artistHover.hovered ? Theme.hover : "transparent"

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                HoverHandler { id: artistHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: entries.entryOpened(entries.albums ? artistRow.modelData.key : artistRow.modelData.name) }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 12
                    spacing: Theme.padding

                    Rectangle {
                        Layout.preferredWidth: entries.albums ? 40 : 36
                        Layout.preferredHeight: entries.albums ? 40 : 36
                        radius: entries.albums ? Theme.radius : 18
                        color: entries.albums ? Theme.surfaceAlt : Theme.accentSoft
                        clip: true

                        Image {
                            anchors.fill: parent
                            visible: entries.albums
                            source: entries.albums ? Util.coverSource(artistRow.modelData.coverPath || "", "") : ""
                            sourceSize: Qt.size(80, 80)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }

                        Label {
                            anchors.centerIn: parent
                            visible: !entries.albums
                            text: (artistRow.modelData.name || "").charAt(0).toUpperCase()
                            color: Theme.accent
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.DemiBold
                        }
                    }

                    Column {
                        Layout.fillWidth: true

                        Label {
                            width: parent.width
                            text: entries.albums ? artistRow.modelData.album : artistRow.modelData.name
                            color: Theme.text
                            font.pixelSize: Theme.fontSize
                            elide: Text.ElideRight
                        }
                        Label {
                            width: parent.width
                            visible: entries.albums
                            text: artistRow.modelData.artist || ""
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                    }

                    Label {
                        text: Util.songCount(artistRow.modelData.count)
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    Icon {
                        name: "chevronRight"
                        size: 10
                        color: Theme.textDim
                    }
                }
            }
        }
    }

    component PageShift: Translate {
        required property int page
        x: root.tab === page ? 0 : (root.tabPosition(page) < root.tabPosition(root.tab) ? -48 : 48)
        Behavior on x { NumberAnimation { duration: Theme.animSlow; easing.type: Theme.easingPanel } }
    }
}
