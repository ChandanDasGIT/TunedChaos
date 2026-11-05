pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Home: a greeting for the time of day, "Your Mix" (your most played songs,
// shuffled), and what you've been listening to: recently played, most played
// this month, albums to jump back into, albums recently added to the library,
// a YouTube Mix recommended from the YouTube song you play most, the whole
// history ("See all", by day) and your stats. Most of it comes from the private
// listening history.
Rectangle {
    id: root

    property bool showPinButton: true
    property bool pinned: false
    property bool showCloseButton: false
    property string page: "" // "": the overview; "history" / "stats" / "mood": that page instead
    property var mood: ({ id: "", name: "" }) // the mood open on the "mood" page
    // (Read again whenever a mood changes.)
    readonly property var moodSongs: MoodsController.moods.length >= 0 ? MoodsController.songs(mood.id) : []
    // Back / Esc: from a page to the overview (false: already there).
    readonly property bool canGoBack: page !== ""
    function back() {
        if (page === "")
            return false
        page = ""
        return true
    }

    signal pinToggled()
    signal closeRequested()

    readonly property bool hasHistory: HistoryController.count > 0

    // The greeting follows the clock.
    property int hour: new Date().getHours()
    readonly property string greeting: hour >= 5 && hour < 12 ? qsTr("Good morning")
                                     : hour >= 12 && hour < 17 ? qsTr("Good afternoon")
                                     : qsTr("Good evening")
    Timer {
        interval: 60 * 1000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.hour = new Date().getHours()
    }

    color: Theme.panelShade // softens the cover tint behind it

    // The solid card this panel sits on (Main): the strip behind the pin / close
    // buttons matches it, so scrolled content passes under them.
    property color backdrop: "transparent"
    readonly property bool scrolled: (root.page === "" && overview.contentY > 4)
                                     || (root.page === "history" && historyList.contentY > historyList.originY + 4)
                                     || (root.page === "stats" && statsPage.contentY > 4)
                                     || (root.page === "mood" && moodList.contentY > 4)

    Rectangle {
        z: 2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 1
        height: Theme.headerHeight
        topLeftRadius: Theme.radiusCard - 1
        topRightRadius: Theme.radiusCard - 1
        color: Qt.tint(root.backdrop, Theme.panelShade)
        visible: opacity > 0
        opacity: root.scrolled && (root.showPinButton || root.showCloseButton) ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }
    radius: Theme.radiusCard
    border.color: Theme.border

    // Pin / close, top right
    Row {
        z: 3
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacing
        spacing: 2

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

    // ---- The overview
    Flickable {
        id: overview
        anchors.fill: parent
        anchors.margins: 1
        anchors.bottomMargin: 6
        clip: true
        contentHeight: sections.implicitHeight + 2 * Theme.padding
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: Theme.flickDeceleration
        maximumFlickVelocity: Theme.flickVelocity
        synchronousDrag: true
        opacity: root.page === "" ? 1 : 0
        visible: opacity > 0
        ScrollBar.vertical: ScrollBar {}

        Behavior on opacity { NumberAnimation { duration: Theme.anim } }

        ColumnLayout {
            id: sections
            x: Theme.padding + 4
            y: Theme.padding
            width: overview.width - 2 * (Theme.padding + 4)
            spacing: Theme.padding

            // Greeting
            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.topMargin: Theme.padding * 2
                Layout.rightMargin: 60 // clear of the pin / close buttons
                text: root.greeting
                color: Theme.text
                font.pixelSize: 38
                font.weight: Font.Bold
                font.letterSpacing: -0.5
                wrapMode: Text.WordWrap
            }

            // "Your Mix": a big round shuffle button
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing
                Layout.bottomMargin: Theme.spacing
                spacing: Theme.padding

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Label {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Your Mix")
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeTitle
                        font.weight: Font.DemiBold
                    }

                    Label {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: root.hasHistory ? qsTr("The songs you play most, shuffled")
                            : LocalLibraryController.songCount > 0 ? qsTr("Songs from your library, shuffled")
                            : qsTr("Play some music, and what you love shows up here")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize
                        wrapMode: Text.WordWrap
                    }
                }

                AbstractButton {
                    id: mixButton
                    implicitWidth: 72
                    implicitHeight: 72
                    enabled: root.hasHistory || LocalLibraryController.songCount > 0
                    opacity: enabled || Util.openDialogs > 0 ? 1 : 0.4
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    scale: pressed ? 0.92 : hovered ? 1.05 : 1
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Play Your Mix")
                    onClicked: HistoryController.playMix()

                    Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Theme.easingBack } }

                    background: Rectangle {
                        radius: width / 2
                        color: Theme.accent
                    }
                    contentItem: Item {
                        Icon {
                            anchors.centerIn: parent
                            name: "shuffle"
                            size: 22
                            color: Theme.background
                        }
                    }
                }
            }

            // Moods: filled from the player's heart button
            GridLayout {
                Layout.fillWidth: true
                columns: 3
                columnSpacing: Theme.spacing
                rowSpacing: Theme.spacing

                Repeater {
                    model: MoodsController.moods

                    delegate: Rectangle {
                        id: moodTile

                        required property var modelData
                        required property int index
                        readonly property var look: [
                            { icon: "moodHappy", hue: 0.13 }, { icon: "moodSad", hue: 0.6 },
                            { icon: "moodBored", hue: 0.3 }, { icon: "moodSuspense", hue: 0.78 },
                            { icon: "moodMetal", hue: 0.0 }, { icon: "moodDance", hue: 0.9 }
                        ][index]

                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 84
                        radius: Theme.radiusLarge
                        color: Qt.hsla(look.hue, 0.55, 0.5, moodHover.hovered ? 0.26 : 0.16)

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        HoverHandler { id: moodHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                root.mood = moodTile.modelData
                                root.page = "mood"
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 4

                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                name: moodTile.look.icon
                                size: 18
                                color: Qt.hsla(moodTile.look.hue, 0.75, 0.72, 1)
                            }

                            Label {
                                textFormat: Text.PlainText
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: moodTile.modelData.name
                                color: Theme.text
                                font.pixelSize: Theme.fontSize
                                font.weight: Font.DemiBold
                            }

                            Label {
                                textFormat: Text.PlainText
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Util.songCount(moodTile.modelData.count)
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }
                    }
                }
            }

            // Recently played
            SectionTitle {
                visible: root.hasHistory
                text: qsTr("Recently played")
            }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: 172
                visible: root.hasHistory
                orientation: ListView.Horizontal
                populate: ListPopulate { sideways: true }
                spacing: Theme.padding
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: Theme.flickDeceleration
                maximumFlickVelocity: Theme.flickVelocity
                synchronousDrag: true
                model: HistoryController.recent

                delegate: CoverCard {
                    required property var modelData
                    required property int index

                    title: modelData.title
                    subtitle: modelData.artist
                    cover: Util.coverSource(modelData.path, modelData.thumbnail)
                    dragItems: [modelData.item]
                    onClicked: HistoryController.playList("recent", index)
                }
            }

            // Most played this month
            SectionTitle {
                visible: HistoryController.mostPlayed.length > 0
                text: qsTr("Most played this month")
            }
            Column {
                Layout.fillWidth: true
                visible: HistoryController.mostPlayed.length > 0
                spacing: 2

                Repeater {
                    model: HistoryController.mostPlayed.slice(0, 5)

                    delegate: HomeSongRow {
                        required property var modelData
                        required property int index

                        width: parent.width
                        song: modelData
                        note: modelData.plays === 1 ? qsTr("1 play") : qsTr("%1 plays").arg(modelData.plays)
                        onClicked: HistoryController.playList("mostPlayed", index)
                    }
                }
            }

            // Albums to jump back into
            SectionTitle {
                visible: HistoryController.recentAlbums.length > 0
                text: qsTr("Jump back in")
            }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: 172
                visible: HistoryController.recentAlbums.length > 0
                orientation: ListView.Horizontal
                populate: ListPopulate { sideways: true }
                spacing: Theme.padding
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: Theme.flickDeceleration
                maximumFlickVelocity: Theme.flickVelocity
                synchronousDrag: true
                model: HistoryController.recentAlbums

                delegate: CoverCard {
                    required property var modelData

                    title: modelData.album
                    subtitle: modelData.artist
                    cover: Util.coverSource(modelData.path, "")
                    iconName: "compactDisc"
                    onClicked: LocalLibraryController.playAlbumOf(modelData.path)
                }
            }

            // Albums newest in the library
            SectionTitle {
                visible: LocalLibraryController.recentlyAdded.length > 0
                text: qsTr("Recently added")
            }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: 172
                visible: LocalLibraryController.recentlyAdded.length > 0
                orientation: ListView.Horizontal
                populate: ListPopulate { sideways: true }
                spacing: Theme.padding
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: Theme.flickDeceleration
                maximumFlickVelocity: Theme.flickVelocity
                synchronousDrag: true
                model: LocalLibraryController.recentlyAdded

                delegate: CoverCard {
                    required property var modelData

                    title: modelData.album
                    subtitle: modelData.artist
                    cover: Util.coverSource(modelData.coverPath, "")
                    iconName: "compactDisc"
                    dragItems: LocalLibraryController.albumItems(modelData.key)
                    onClicked: LocalLibraryController.playAlbum(modelData.key)
                }
            }

            // Smart playlists: they fill themselves (right-click or ⋮ to change one)
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing

                Label {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Smart playlists")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.DemiBold
                }

                PillButton {
                    text: qsTr("New")
                    iconName: "plus"
                    iconSize: 10
                    implicitHeight: 30
                    transparentIdle: true
                    onClicked: smartDialog.edit(null)
                }
            }
            // Two even columns; an odd last card takes the whole row.
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Theme.spacing
                rowSpacing: Theme.spacing

                Repeater {
                    id: smartCards
                    model: SmartPlaylistsController.playlists

                    delegate: SmartCard {
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 78
                        Layout.columnSpan: index === smartCards.count - 1 && smartCards.count % 2 === 1 ? 2 : 1
                        playlist: modelData
                        hue: (0.72 + index * 0.17) % 1
                    }
                }
            }

            // Recommended: the Mix of the YouTube song played most
            SectionTitle {
                visible: recommended.visible
                text: qsTr("Recommended for you")
            }
            Rectangle {
                id: recommended
                Layout.fillWidth: true
                implicitHeight: 84
                visible: HistoryController.favoriteYouTube.videoId !== undefined
                radius: Theme.radiusLarge
                color: recommendedHover.hovered ? Theme.hover : Theme.fillSoft

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                HoverHandler {
                    id: recommendedHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: YouTubeController.play(HistoryController.favoriteYouTube)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: Theme.padding

                    YtThumbnail {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 64
                        source: HistoryController.favoriteYouTube.thumbnail || ""
                        hue: (HistoryController.favoriteYouTube.title || "").length % 10 / 10
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: qsTr("Mix – %1").arg(HistoryController.favoriteYouTube.title || "")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Label {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: qsTr("What YouTube Music plays after the song you play most")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                        }
                    }

                    Icon {
                        name: "play"
                        size: 14
                        color: Theme.accent
                    }
                }
            }

            // History: the latest few, and the whole of it
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing
                visible: root.hasHistory

                Label {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("History")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.DemiBold
                }

                PillButton {
                    text: qsTr("See all")
                    iconName: "chevronRight"
                    iconSize: 10
                    implicitHeight: 30
                    transparentIdle: true
                    onClicked: root.page = "history"
                }
            }
            Column {
                Layout.fillWidth: true
                visible: root.hasHistory
                spacing: 2

                Repeater {
                    model: HistoryController.entries.slice(0, 4)

                    delegate: HomeSongRow {
                        required property var modelData
                        required property int index

                        width: parent.width
                        song: modelData
                        note: modelData.day === qsTr("Today") ? modelData.clock : modelData.day
                        removable: true
                        onClicked: HistoryController.playList("entries", index)
                        onRemoveRequested: HistoryController.removeEntry(index)
                    }
                }
            }

            // Your stats: three numbers, and the rest on their own page
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing
                visible: root.hasHistory || LocalLibraryController.songCount > 0

                Label {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Your stats")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.DemiBold
                }

                PillButton {
                    text: qsTr("More")
                    iconName: "chevronRight"
                    iconSize: 10
                    implicitHeight: 30
                    transparentIdle: true
                    onClicked: root.page = "stats"
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: root.hasHistory || LocalLibraryController.songCount > 0
                spacing: Theme.spacing

                StatTile {
                    value: HistoryController.stats.plays ?? 0
                    label: qsTr("plays")
                }
                StatTile {
                    value: root.length(HistoryController.stats.listenedMs ?? 0)
                    label: qsTr("of music played")
                }
                StatTile {
                    value: HistoryController.stats.songs ?? 0
                    label: qsTr("songs in your library folders")
                }
            }

            // Nothing listened to yet
            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.topMargin: Theme.padding
                visible: !root.hasHistory
                text: SettingsController.historyEnabled
                      ? qsTr("Songs you listen to show up here: recently played, your most played, albums to jump back into and recommendations.")
                      : qsTr("The listening history is off (Settings → General), so Home has nothing to show yet.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize
                wrapMode: Text.WordWrap
            }
        }
    }

    // ---- One mood's songs
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 1
        anchors.bottomMargin: 6
        spacing: Theme.spacing
        opacity: root.page === "mood" ? 1 : 0
        visible: opacity > 0
        transform: PageShift { shown: root.page === "mood" }

        Behavior on opacity { NumberAnimation { duration: Theme.anim } }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing
            Layout.topMargin: Theme.spacing
            Layout.rightMargin: 90 // clear of the pin / close buttons
            spacing: Theme.padding

            PillButton {
                iconName: "back"
                iconSize: 12
                implicitWidth: 36
                implicitHeight: 36
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Back to Home")
                onClicked: root.page = ""
            }

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.mood.name
                color: Theme.text
                font.pixelSize: Theme.fontSizeTitle
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            PillButton {
                visible: root.moodSongs.length > 0
                iconName: "play"
                iconSize: 11
                text: qsTr("Play all")
                implicitHeight: 36
                filled: true
                onClicked: MoodsController.play(root.mood.id, 0)
            }
        }

        ListView {
            id: moodList
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
            model: root.moodSongs
            ScrollBar.vertical: ScrollBar {}

            delegate: HomeSongRow {
                required property var modelData
                required property int index

                width: moodList.width
                song: modelData
                note: Util.formatTime(modelData.durationMs)
                removable: true
                removeTip: qsTr("Remove from this mood")
                onClicked: MoodsController.play(root.mood.id, index)
                onRemoveRequested: MoodsController.removeSong(root.mood.id, index)
            }

            Label {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                width: parent.width - 4 * Theme.padding
                visible: root.moodSongs.length === 0
                text: qsTr("No songs here yet. While a song plays, tap the heart on the player to add it.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }

    // ---- The whole history, by day
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 1
        anchors.bottomMargin: 6
        spacing: Theme.spacing
        opacity: root.page === "history" ? 1 : 0
        visible: opacity > 0
        transform: PageShift { shown: root.page === "history" }

        Behavior on opacity { NumberAnimation { duration: Theme.anim } }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing
            Layout.topMargin: Theme.spacing
            Layout.rightMargin: 90 // clear of the pin / close buttons
            spacing: Theme.padding

            PillButton {
                iconName: "back"
                iconSize: 12
                implicitWidth: 36
                implicitHeight: 36
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Back to Home")
                onClicked: root.page = ""
            }

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("History")
                color: Theme.text
                font.pixelSize: Theme.fontSizeTitle
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        ListView {
            id: historyList
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
            model: HistoryController.entries
            ScrollBar.vertical: ScrollBar {}

            // A day's heading above its first play.
            delegate: Column {
                id: entry

                required property var modelData
                required property int index
                readonly property bool firstOfDay: index === 0 || HistoryController.entries[index - 1].day !== modelData.day

                width: historyList.width

                Label {
                    textFormat: Text.PlainText
                    visible: entry.firstOfDay
                    leftPadding: 8
                    topPadding: entry.index === 0 ? 4 : Theme.padding
                    bottomPadding: 4
                    text: entry.modelData.day
                    color: Theme.accent
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                }

                HomeSongRow {
                    width: parent.width
                    song: entry.modelData
                    note: entry.modelData.clock
                    removable: true
                    onClicked: HistoryController.playList("entries", entry.index)
                    onRemoveRequested: HistoryController.removeEntry(entry.index)
                }
            }

            Label {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: historyList.count === 0
                text: qsTr("No songs listened to yet.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize
            }
        }
    }

    // ---- Your stats
    Flickable {
        id: statsPage
        anchors.fill: parent
        anchors.margins: 1
        anchors.bottomMargin: 6
        clip: true
        contentHeight: statsColumn.implicitHeight + 2 * Theme.padding
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: Theme.flickDeceleration
        maximumFlickVelocity: Theme.flickVelocity
        synchronousDrag: true
        opacity: root.page === "stats" ? 1 : 0
        visible: opacity > 0
        transform: PageShift { shown: root.page === "stats" }
        ScrollBar.vertical: ScrollBar {}

        Behavior on opacity { NumberAnimation { duration: Theme.anim } }

        ColumnLayout {
            id: statsColumn
            x: Theme.padding
            y: Theme.spacing
            width: statsPage.width - 2 * Theme.padding
            spacing: Theme.spacing

            RowLayout {
                Layout.fillWidth: true
                Layout.rightMargin: 80 // clear of the pin / close buttons
                spacing: Theme.padding

                PillButton {
                    iconName: "back"
                    iconSize: 12
                    implicitWidth: 36
                    implicitHeight: 36
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Back to Home")
                    onClicked: root.page = ""
                }

                Label {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Your stats")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeTitle
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }

            SectionTitle { text: qsTr("Your library") }
            GridLayout {
                Layout.fillWidth: true
                columns: width >= 4 * 96 ? 4 : 2 // two by two when narrow
                rowSpacing: Theme.spacing
                columnSpacing: Theme.spacing

                StatTile { value: HistoryController.stats.songs ?? 0; label: qsTr("songs") }
                StatTile { value: HistoryController.stats.albums ?? 0; label: qsTr("albums") }
                StatTile { value: HistoryController.stats.artists ?? 0; label: qsTr("artists") }
                StatTile { value: root.length(HistoryController.stats.libraryMs ?? 0); label: qsTr("of music") }
            }

            SectionTitle { text: qsTr("Your listening") }
            GridLayout {
                Layout.fillWidth: true
                columns: width >= 4 * 96 ? 4 : 2 // two by two when narrow
                rowSpacing: Theme.spacing
                columnSpacing: Theme.spacing

                StatTile { value: HistoryController.stats.plays ?? 0; label: qsTr("plays") }
                StatTile { value: HistoryController.stats.playsThisMonth ?? 0; label: qsTr("this month") }
                StatTile { value: root.length(HistoryController.stats.listenedMs ?? 0); label: qsTr("played") }
                StatTile { value: HistoryController.stats.youTubePlays ?? 0; label: qsTr("from YouTube") }
            }

            TopList { title: qsTr("Top artists"); entries: HistoryController.stats.topArtists ?? [] }
            TopList { title: qsTr("Top albums"); entries: HistoryController.stats.topAlbums ?? [] }
            TopList { title: qsTr("Top songs"); entries: HistoryController.stats.topSongs ?? [] }

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing
                text: qsTr("All time, from your listening history (kept on this computer only).")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }
        }
    }

    // A length for a stat tile: "25 min" under an hour, then "2.5 h", then "12 h".
    function length(ms) {
        const minutes = Math.round(ms / 60000)
        if (minutes < 60)
            return qsTr("%1 min").arg(minutes)
        const h = ms / 3600000
        return qsTr("%1 h").arg(h >= 10 ? Math.round(h) : Math.round(h * 10) / 10)
    }

    // A page slides in from the right over the overview.
    component PageShift: Translate {
        property bool shown
        x: shown ? 0 : 48
        Behavior on x { NumberAnimation { duration: Theme.animSlow; easing.type: Theme.easingPanel } }
    }

    // A big number over what it counts.
    component StatTile: Rectangle {
        id: tile

        property var value
        property string label

        Layout.fillWidth: true
        Layout.preferredWidth: 1 // tiles share the row equally
        implicitHeight: 76
        radius: Theme.radiusLarge
        color: Theme.fillSoft

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            spacing: 2

            Label {
                textFormat: Text.PlainText
                width: parent.width
                text: String(tile.value)
                color: Theme.accent
                font.pixelSize: 24
                font.weight: Font.Bold
                // Shrinks to fit (e.g. "3 h 12 min") before it is cut
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 14
                elide: Text.ElideRight
            }
            Label {
                textFormat: Text.PlainText
                width: parent.width
                text: tile.label
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                maximumLineCount: 2
            }
        }
    }

    // "Top artists": a ranked list with play counts.
    component TopList: ColumnLayout {
        id: topList

        property string title
        property var entries: []

        Layout.fillWidth: true
        visible: entries.length > 0
        spacing: 2

        SectionTitle { text: topList.title }

        Repeater {
            model: topList.entries

            delegate: RowLayout {
                required property var modelData
                required property int index

                Layout.fillWidth: true
                Layout.preferredHeight: 34
                spacing: Theme.padding

                Label {
                    textFormat: Text.PlainText
                    Layout.preferredWidth: 22
                    text: index + 1
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSize
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignRight
                }
                Label {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: modelData.name
                    color: Theme.text
                    font.pixelSize: Theme.fontSize
                    elide: Text.ElideRight
                }
                Label {
                    textFormat: Text.PlainText
                    text: modelData.plays === 1 ? qsTr("1 play") : qsTr("%1 plays").arg(modelData.plays)
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }
    }

    SmartPlaylistDialog {
        id: smartDialog
    }

    // A smart playlist: its name and how many songs it has now. A click plays
    // it; right-click or ⋮ edits it; hold and drag to drop its songs on the Queue.
    component SmartCard: Rectangle {
        id: smart

        property var playlist
        property real hue: 0.72

        radius: Theme.radiusLarge
        color: Qt.hsla(hue, 0.55, 0.5, smartHover.hovered ? 0.26 : 0.16)
        opacity: playlist.count > 0 ? 1 : 0.6

        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        HoverHandler {
            id: smartHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: SmartPlaylistsController.play(smart.playlist.id)
        }
        TapHandler {
            acceptedButtons: Qt.RightButton
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad // (a finger's tap would count as this too)
            onTapped: smartDialog.edit(smart.playlist)
        }
        DragSource {
            payload: function() {
                return { items: SmartPlaylistsController.items(smart.playlist.id), title: smart.playlist.name,
                         subtitle: Util.songCount(smart.playlist.count) }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 0
            spacing: 8

            Rectangle {
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                radius: 12
                color: Qt.hsla(smart.hue, 0.6, 0.55, 0.25)

                Icon {
                    anchors.centerIn: parent
                    name: "sparkles"
                    size: 15
                    color: Qt.hsla(smart.hue, 0.75, 0.75, 1)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: smart.playlist.name
                    color: Theme.text
                    font.pixelSize: Theme.fontSize
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    lineHeight: 0.95
                }
                Label {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: Util.songCount(smart.playlist.count)
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            ControlButton {
                iconName: "more"
                iconSize: 12
                iconColor: Theme.textMuted
                opacity: smartHover.hovered || Theme.touchOnly ? 1 : 0 // (no hovering on a phone)
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Edit")
                onClicked: smartDialog.edit(smart.playlist)
            }
        }
    }

    component SectionTitle: Label {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        Layout.topMargin: Theme.spacing
        color: Theme.text
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.DemiBold
    }

    // A cover with a title and subtitle under it (songs, albums). Hold and
    // drag to drop it on the Queue or the player (when it has `dragItems`).
    component CoverCard: Item {
        id: card

        property string title
        property string subtitle
        property string cover
        property string iconName: "music"
        property var dragItems: null
        signal clicked()

        width: 128
        height: 172
        scale: cardHover.hovered ? 1.03 : 1

        Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Theme.easing } }

        HoverHandler {
            id: cardHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: card.clicked()
        }
        DragSource {
            enabled: card.dragItems !== null
            payload: function() {
                return { items: card.dragItems, title: card.title, subtitle: card.subtitle, cover: card.cover }
            }
        }

        Rectangle {
            id: art
            width: 128
            height: 128
            radius: Theme.radiusLarge
            color: Theme.surfaceAlt
            clip: true

            Icon {
                anchors.centerIn: parent
                name: card.iconName
                size: 26
                color: Theme.textDim
            }

            Image {
                anchors.fill: parent
                source: card.cover
                sourceSize: Qt.size(256, 256)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: status === Image.Ready ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: Theme.anim } }
            }
        }

        Label {
            textFormat: Text.PlainText
            anchors.top: art.bottom
            anchors.topMargin: 6
            width: parent.width
            text: card.title
            color: Theme.text
            font.pixelSize: Theme.fontSize
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Label {
            textFormat: Text.PlainText
            anchors.top: art.bottom
            anchors.topMargin: 24
            width: parent.width
            text: card.subtitle
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
        }
    }
}
