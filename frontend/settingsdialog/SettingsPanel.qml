pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// App settings as a panel in the right-hand column (a sheet above the
// navigation bar at phone size), like a phone's settings app: a list of
// categories; one opens its page (slides in from the right, back returns).
// The search bar at the bottom finds any setting: picking a result opens its
// page, scrolls to it and highlights it. Every change is saved immediately
// (SettingsController).
Rectangle {
    id: root

    property bool showCloseButton: true
    property int page: -1 // -1: the list of categories
    property int shownPage: 0 // the page in the stack (kept while sliding back to the list)
    readonly property string query: searchField.text.trim()
    readonly property bool searching: query !== ""

    readonly property var pages: [
        { name: qsTr("General"), icon: "sliders", hue: 0.62, summary: qsTr("Startup, notifications, listening history") },
        { name: qsTr("Playback"), icon: "play", hue: 0.36, summary: qsTr("Output device, fades, ReplayGain, controls") },
        { name: qsTr("Equalizer"), icon: "equalizer", hue: 0.08, summary: qsTr("Bands and presets") },
        { name: qsTr("Appearance"), icon: "palette", hue: 0.83, summary: qsTr("Theme, background, visualizer") },
        { name: qsTr("Library"), icon: "compactDisc", hue: 0.55, summary: qsTr("Music folders, excluded folders") },
        { name: qsTr("Album art"), icon: "image", hue: 0.95, summary: qsTr("Missing covers and where to find them") },
        { name: qsTr("Lyrics"), icon: "lyrics", hue: 0.13, summary: qsTr("Sources, synced lyrics, script") },
        { name: qsTr("YouTube Music"), icon: "cloud", hue: 0.0, summary: qsTr("Account, autoplay, audio quality") },
        { name: qsTr("Keyboard shortcuts"), icon: "keyboard", hue: 0.7, summary: qsTr("Every key the app knows") },
        { name: qsTr("About"), icon: "info", hue: 0.5, summary: qsTr("Version and your data") },
        { name: qsTr("Layout Customisation"), icon: "layout", hue: 0.75,
          summary: android ? qsTr("Bottom bar, default panel")
                  : qsTr("Bottom bar, what opens on start") },
        { name: qsTr("Seekbar"), icon: "wave", hue: 0.3, summary: qsTr("Animation and thumb style") },
        { name: qsTr("Sleep timer"), icon: "moon", hue: 0.68, summary: qsTr("Pause the music after a while") }
    ]
    // Android has no keyboard to speak of: no Keyboard shortcuts page there
    readonly property bool android: Qt.platform.os === "android"
    readonly property int shortcutsPage: 8
    // The categories in groups, like a phone's settings
    readonly property var groups: [[0, 1, 12, 2, 10], [3, 11, 5, 6], [4, 7], android ? [9] : [8, 9]]

    readonly property int equalizerPage: 2
    readonly property int libraryPage: 4

    // Layout Customisation
    readonly property var panelNames: ({ youtube: qsTr("YouTube"), queue: qsTr("Queue"), home: qsTr("Home"),
                                         library: qsTr("Library"), player: qsTr("Player") })
    readonly property var startChoices: ["player"].concat(SettingsController.panelOrder.filter(
        (panel) => !android || !SettingsController.hiddenPanels.includes(panel)))
    readonly property string startShown: startChoices.includes(SettingsController.startPanel)
                                         ? SettingsController.startPanel : "player"
    // Phones: the panel in the player's place
    readonly property var defaultChoices: ["player"].concat(SettingsController.panelOrder.filter(
        (panel) => !SettingsController.hiddenPanels.includes(panel)))
    readonly property string defaultShown: defaultChoices.includes(SettingsController.defaultPanel)
                                           ? SettingsController.defaultPanel : "player"

    // Shown: the category groups rise in, one after another.
    function intro() {
        introRun++
    }
    property int introRun: 0

    signal closeRequested()
    // Ask Main for the folder picker (it lives in the main window).
    signal addFolderRequested()
    signal clearHistoryRequested() // asks first (the confirmation lives in the main window)
    signal excludeFolderRequested(string startFolder)

    // Opens that page (-1: the list), e.g. the Library's music folders.
    function openPage(index) {
        searchField.clear()
        if (index >= 0)
            shownPage = index
        page = index
    }
    // The panel closed: the search bar would keep its focus, and so the keyboard, open.
    function dropKeyboard() {
        searchField.focus = false
        Qt.inputMethod.hide()
    }
    // Esc: clears the search, else back to the list; false at the list (nothing left to do).
    readonly property bool canGoBack: searching || page >= 0
    function back() {
        if (searching) {
            searchField.clear()
            return true
        }
        if (page >= 0) {
            page = -1
            return true
        }
        return false
    }

    // ---- Search: every setting (row) of every page, found by its words
    function collect(item, pageIndex, card, out) {
        for (const child of item.children) {
            if (child.hiddenHere === true) // (not on this platform)
                continue
            if (child.settingsCard === true) {
                collect(child, pageIndex, child.title, out)
                continue
            }
            if (child.settingsRow === true && child.title !== "")
                out.push({ page: pageIndex, card: card, title: child.title, description: child.description, item: child })
            collect(child, pageIndex, card, out)
        }
    }
    function search(text) {
        const words = text.toLowerCase().split(/\s+/).filter((w) => w !== "")
        const matches = (s) => words.every((w) => s.toLowerCase().includes(w))
        const out = []
        pages.forEach((p, i) => {
            if (android && i === shortcutsPage)
                return
            if (matches(p.name + " " + p.summary))
                out.push({ page: i, card: "", title: p.name, description: p.summary, item: null })
        })
        const rows = []
        for (let i = 0; i < stack.children.length; ++i)
            if (!(android && i === shortcutsPage))
                collect(stack.children[i], i, "", rows)
        const titled = rows.filter((r) => matches(r.title + " " + r.card))
        const described = rows.filter((r) => !matches(r.title + " " + r.card)
                                       && matches(r.title + " " + r.card + " " + r.description + " " + pages[r.page].name))
        return out.concat(titled, described).slice(0, 60)
    }
    function reveal(result) {
        openPage(result.page)
        searchField.focus = false // Esc goes back again
        root.forceActiveFocus()
        revealing = result.item
        if (revealing)
            revealTimer.restart()
    }
    // Scrolled to once the page has been laid out
    property Item revealing: null
    Timer {
        id: revealTimer
        interval: 60
        onTriggered: {
            if (root.revealing)
                stack.children[root.page].reveal(root.revealing)
            root.revealing = null
        }
    }

    color: Theme.panelShade // softens the cover tint behind it
    radius: Theme.radiusCard
    border.color: Theme.border

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 1 // inside the border
        spacing: 0

        // ---- Header: "Settings", or a page's name with a back button
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.headerHeight
            color: Theme.fillSoft
            topLeftRadius: Theme.radiusCard - 1
            topRightRadius: Theme.radiusCard - 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.page >= 0 && !root.searching ? Theme.spacing : Theme.padding
                anchors.rightMargin: Theme.spacing
                spacing: Theme.spacing

                ControlButton {
                    visible: root.page >= 0 && !root.searching
                    iconName: "back"
                    iconSize: 13
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("All settings")
                    onClicked: root.page = -1
                }

                Icon {
                    visible: root.page < 0 || root.searching
                    name: "settings"
                    size: 14
                    color: Theme.accent
                }

                Label {
                    Layout.fillWidth: true
                    text: root.searching ? qsTr("Search settings")
                          : root.page >= 0 ? root.pages[root.page].name : qsTr("Settings")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeLarge
                    elide: Text.ElideRight
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

        // ---- The list, the pages and the search results
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            // The categories
            Flickable {
                id: categories
                width: parent.width
                height: parent.height
                x: root.page < 0 ? 0 : -width * 0.3
                opacity: root.page < 0 && !root.searching ? 1 : 0
                visible: opacity > 0
                contentHeight: groupColumn.implicitHeight + 2 * Theme.padding
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: Theme.flickDeceleration
                maximumFlickVelocity: Theme.flickVelocity
                synchronousDrag: true
                ScrollBar.vertical: ScrollBar {}

                Behavior on x { NumberAnimation { duration: Theme.animSlow; easing.type: Theme.easingPanel } }
                Behavior on opacity { NumberAnimation { duration: Theme.anim } }

                ColumnLayout {
                    id: groupColumn
                    x: Theme.padding
                    y: Theme.padding
                    width: categories.width - 2 * Theme.padding
                    spacing: Theme.padding

                    Repeater {
                        model: root.groups

                        delegate: Rectangle {
                            id: group

                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            implicitHeight: groupRows.implicitHeight
                            radius: Theme.radiusLarge
                            color: Theme.fillSoft
                            transform: Translate { id: rise }

                            Connections {
                                target: root
                                function onIntroRunChanged() { groupIntro.restart() }
                            }
                            SequentialAnimation {
                                id: groupIntro
                                PropertyAction { target: group; property: "opacity"; value: 0 }
                                PropertyAction { target: rise; property: "y"; value: 24 }
                                PauseAnimation { duration: 60 + group.index * 45 }
                                ParallelAnimation {
                                    NumberAnimation { target: group; property: "opacity"; to: 1; duration: Theme.anim; easing.type: Theme.easing }
                                    NumberAnimation { target: rise; property: "y"; to: 0; duration: Theme.animSlow; easing.type: Theme.easing }
                                }
                            }

                            ColumnLayout {
                                id: groupRows
                                width: parent.width
                                spacing: 0

                                Repeater {
                                    model: group.modelData

                                    delegate: CategoryRow {
                                        required property int modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        pageIndex: modelData
                                        first: index === 0
                                        last: index === group.modelData.length - 1
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // The pages (one at a time), sliding in from the right
            Item {
                width: parent.width
                height: parent.height
                x: root.page >= 0 ? 0 : width
                opacity: root.page >= 0 && !root.searching ? 1 : 0
                visible: x < width && opacity > 0

                Behavior on x { NumberAnimation { duration: Theme.animSlow; easing.type: Theme.easingPanel } }
                Behavior on opacity { NumberAnimation { duration: Theme.anim } }

                StackLayout {
                    id: stack
                    anchors.fill: parent
                    anchors.topMargin: Theme.padding
                    currentIndex: root.shownPage

                    // ------------------------------------------------------------ General
                    SettingsPage {
                        title: qsTr("General")

                        SettingsCard {
                            title: qsTr("Startup and closing")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Restore the Queue on startup")
                                description: qsTr("Start with the songs you had last time. Off: start empty.")

                                SettingsSwitch {
                                    checked: SettingsController.restorePlaylist
                                    onToggled: SettingsController.restorePlaylist = checked
                                }
                            }

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Resume where you left off")
                                description: qsTr("Reopen on the last song, paused where it was.")

                                SettingsSwitch {
                                    checked: SettingsController.resumeSession
                                    onToggled: SettingsController.resumeSession = checked
                                }
                            }

                            SettingsRow {
                                Layout.fillWidth: true
                                readonly property bool hiddenHere: root.android
                                visible: !hiddenHere // (Android keeps playing by itself)
                                title: qsTr("Keep playing after closing the window")
                                description: qsTr("Closing hides the window; open the app again to bring it back. Quit with the power button or Ctrl+Q.")

                                SettingsSwitch {
                                    checked: SettingsController.backgroundPlayback
                                    onToggled: SettingsController.backgroundPlayback = checked
                                }
                            }
                        }

                        SettingsCard {
                            readonly property bool hiddenHere: root.android
                            visible: !hiddenHere // (Android: the media notification shows the song)
                            title: qsTr("Notifications")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Show the song when it changes")
                                description: qsTr("A desktop notification with the title, artist and cover, while the app's window isn't in front.")

                                SettingsSwitch {
                                    checked: SettingsController.notificationsEnabled
                                    onToggled: SettingsController.notificationsEnabled = checked
                                }
                            }
                        }

                        SettingsCard {
                            title: qsTr("Listening history")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Keep a listening history")
                                description: qsTr("Remember the songs you listen to (half a song, or 4 minutes, counts) for Home. It stays on this computer.")

                                SettingsSwitch {
                                    checked: SettingsController.historyEnabled
                                    onToggled: SettingsController.historyEnabled = checked
                                }
                            }

                            SettingsRow {
                                Layout.fillWidth: true
                                enabled: SettingsController.historyEnabled
                                opacity: enabled || Util.openDialogs > 0 ? 1 : 0.5
                                title: qsTr("Include YouTube Music songs")
                                description: qsTr("Off: only songs from your library and your files are remembered.")

                                SettingsSwitch {
                                    checked: SettingsController.historyYouTube
                                    onToggled: SettingsController.historyYouTube = checked
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true

                                Label {
                                    Layout.fillWidth: true
                                    text: HistoryController.count === 1 ? qsTr("1 song listened to so far.")
                                                                        : qsTr("%1 songs listened to so far.").arg(HistoryController.count)
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                PillButton {
                                    iconName: "trash"
                                    iconSize: 11
                                    text: qsTr("Clear history…")
                                    implicitHeight: 32
                                    enabled: HistoryController.count > 0
                                    onClicked: root.clearHistoryRequested()
                                }
                            }
                        }
                    }

                    // ------------------------------------------------------------ Playback
                    SettingsPage {
                        title: qsTr("Playback")

                        SettingsCard {
                            title: qsTr("Output device")

                            SettingsRow {
                                Layout.fillWidth: true
                                description: qsTr("Where the music plays. Switching takes effect immediately.")

                                PillButton {
                                    iconName: "refresh"
                                    iconSize: 12
                                    implicitWidth: 34
                                    implicitHeight: 30
                                    ToolTip.visible: hovered
                                    ToolTip.text: qsTr("Refresh the list")
                                    onClicked: PlayerController.refreshOutputDevices()
                                }
                            }

                            Repeater {
                                model: PlayerController.outputDevices

                                delegate: Rectangle {
                                    id: deviceRow

                                    required property var modelData
                                    readonly property bool current: modelData.id === PlayerController.outputDevice

                                    Layout.fillWidth: true
                                    implicitHeight: 40
                                    radius: Theme.radius
                                    color: current ? Theme.accentSoft : deviceHover.hovered ? Theme.hover : Theme.fillSoft

                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                    HoverHandler {
                                        id: deviceHover
                                        cursorShape: Qt.PointingHandCursor
                                    }

                                    TapHandler {
                                        onTapped: PlayerController.outputDevice = deviceRow.modelData.id
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.padding
                                        anchors.rightMargin: Theme.padding
                                        spacing: Theme.spacing

                                        Icon {
                                            name: deviceRow.modelData.id === "" ? "settings" : "volume"
                                            size: 12
                                            color: deviceRow.current ? Theme.accent : Theme.textMuted
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: deviceRow.modelData.name
                                            color: deviceRow.current ? Theme.accent : Theme.text
                                            font.pixelSize: Theme.fontSize
                                            elide: Text.ElideRight
                                        }

                                        Icon {
                                            name: "check"
                                            size: 12
                                            color: Theme.accent
                                            scale: deviceRow.current ? 1 : 0
                                            visible: scale > 0

                                            Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Theme.easingBack } }
                                        }
                                    }
                                }
                            }
                        }

                        SettingsCard {
                            title: qsTr("Between songs")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Fade between songs")
                                description: qsTr("Each song fades out at its end and the next fades in from its start: nothing overlaps or is cut. Skipping fades briefly too. Songs that run into each other on an album stay gapless.")

                                Stepper {
                                    text: SettingsController.fadeSeconds > 0
                                          ? qsTr("%1 s").arg(SettingsController.fadeSeconds) : qsTr("Off")
                                    canDecrease: SettingsController.fadeSeconds > 0
                                    canIncrease: SettingsController.fadeSeconds < 12
                                    onDecreased: SettingsController.fadeSeconds -= 1
                                    onIncreased: SettingsController.fadeSeconds += 1
                                }
                            }

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("ReplayGain")
                                description: SettingsController.replayGain === 0
                                    ? qsTr("Off: songs play as loud as they were made.")
                                    : SettingsController.replayGain === 1
                                      ? qsTr("Track: every song about equally loud. Uses the loudness stored in your files; songs without it are measured once, in the background.")
                                      : qsTr("Album: albums keep their own ups and downs, while albums are about equally loud. Songs without stored loudness are measured once, in the background.")
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: [qsTr("Off"), qsTr("Track"), qsTr("Album")]

                                    delegate: PillButton {
                                        required property string modelData
                                        required property int index

                                        text: modelData
                                        implicitHeight: 32
                                        active: SettingsController.replayGain === index
                                        onClicked: SettingsController.replayGain = index
                                    }
                                }
                            }

                            // Measuring the library's songs (LoudnessController)
                            Label {
                                Layout.fillWidth: true
                                visible: SettingsController.replayGain !== 0 && LoudnessController.songCount > 0
                                text: LoudnessController.doneCount < LoudnessController.songCount
                                      ? qsTr("Measuring loudness: %1 of %2 songs done").arg(LoudnessController.doneCount)
                                                                                     .arg(LoudnessController.songCount)
                                      : qsTr("All %1 library songs are levelled").arg(LoudnessController.songCount)
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.WordWrap
                            }

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Play lists in the Queue")
                                description: SettingsController.listsToQueue
                                    ? qsTr("Playing an album, artist, playlist or YouTube song adds it to the end of the Queue, so you always see what plays next. A YouTube Mix keeps adding to the Queue.")
                                    : qsTr("Playing an album, artist, playlist or YouTube song plays it on its own; the Queue stays as it is.")

                                SettingsSwitch {
                                    checked: SettingsController.listsToQueue
                                    onToggled: SettingsController.listsToQueue = checked
                                }
                            }
                        }

                        SettingsCard {
                            title: qsTr("Controls")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Volume step")
                                description: qsTr("How much one mouse-wheel notch or Ctrl+↑ / ↓ changes the volume.")

                                Stepper {
                                    text: SettingsController.volumeStep + "%"
                                    canDecrease: SettingsController.volumeStep > 1
                                    canIncrease: SettingsController.volumeStep < 25
                                    onDecreased: SettingsController.volumeStep -= 1
                                    onIncreased: SettingsController.volumeStep += 1
                                }
                            }

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Show remaining time")
                                description: qsTr("The time right of the seek bar counts down instead of showing the length.")

                                SettingsSwitch {
                                    checked: SettingsController.showRemainingTime
                                    onToggled: SettingsController.showRemainingTime = checked
                                }
                            }
                        }
                    }

                    // ------------------------------------------------------------ Equalizer
                    SettingsPage {
                        id: eqPage
                        title: qsTr("Equalizer")

                        // dB for the bands 31 Hz ... 16 kHz
                        readonly property var presets: [
                            { id: "flat", name: qsTr("Flat"), gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
                            { id: "bass", name: qsTr("Bass boost"), gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0] },
                            { id: "treble", name: qsTr("Treble boost"), gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6] },
                            { id: "vocal", name: qsTr("Vocal"), gains: [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1] },
                            { id: "rock", name: qsTr("Rock"), gains: [4, 3, 2, 0, -1, -1, 1, 2, 3, 4] },
                            { id: "pop", name: qsTr("Pop"), gains: [-1, 0, 2, 3, 4, 3, 1, 0, -1, -1] },
                            { id: "electronic", name: qsTr("Electronic"), gains: [5, 4, 1, 0, -2, 1, 0, 1, 4, 5] },
                            { id: "hiphop", name: qsTr("Hip-hop"), gains: [5, 4, 2, 3, -1, -1, 1, 0, 2, 3] },
                            { id: "jazz", name: qsTr("Jazz"), gains: [3, 2, 1, 2, -1, -1, 0, 1, 2, 3] },
                            { id: "classical", name: qsTr("Classical"), gains: [4, 3, 2, 1, -1, -1, 0, 2, 3, 4] },
                            { id: "acoustic", name: qsTr("Acoustic"), gains: [4, 3, 2, 1, 1, 1, 2, 2, 3, 2] }
                        ]
                        readonly property var bandLabels: ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

                        SettingsCard {
                            title: qsTr("Equalizer")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Equalizer")
                                description: qsTr("Shape the sound with 10 bands. Boosting doesn't lower the volume: only peaks that would distort are turned down for a moment. Changes are heard at once.")

                                SettingsSwitch {
                                    checked: SettingsController.eqEnabled
                                    onToggled: SettingsController.eqEnabled = checked
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: eqPage.presets

                                    delegate: PillButton {
                                        required property var modelData

                                        text: modelData.name
                                        implicitHeight: 32
                                        active: SettingsController.eqPreset === modelData.id
                                        onClicked: {
                                            SettingsController.setEqPreset(modelData.id, modelData.gains)
                                            SettingsController.eqEnabled = true
                                        }
                                    }
                                }

                                PillButton {
                                    visible: SettingsController.eqPreset === "custom"
                                    text: qsTr("Custom")
                                    implicitHeight: 32
                                    active: true
                                }
                            }

                            // The 10 bands. Double-click a slider to set it back to 0.
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: Theme.spacing
                                spacing: 0
                                opacity: SettingsController.eqEnabled ? 1 : 0.5

                                Behavior on opacity { NumberAnimation { duration: Theme.anim } }

                                Repeater {
                                    model: 10

                                    delegate: EqBand {
                                        required property int index

                                        Layout.fillWidth: true
                                        label: eqPage.bandLabels[index]
                                        value: SettingsController.eqGains[index]
                                        onMoved: (db) => {
                                            SettingsController.setEqGain(index, db)
                                            SettingsController.eqEnabled = true
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true

                                Label {
                                    Layout.fillWidth: true
                                    text: qsTr("Hz · ±12 dB. Double-click a slider to set it back to 0.")
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.WordWrap
                                }

                                PillButton {
                                    iconName: "refresh"
                                    iconSize: 11
                                    text: qsTr("Reset")
                                    implicitHeight: 32
                                    onClicked: SettingsController.setEqPreset("flat", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
                                }
                            }
                        }
                    }

                    // ------------------------------------------------------------ Appearance
                    SettingsPage {
                        title: qsTr("Appearance")

                        SettingsCard {
                            title: qsTr("Theme")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Colors")
                                description: qsTr("System follows your desktop's light or dark setting.")
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: [
                                        { id: "system", name: qsTr("System"), icon: "settings" },
                                        { id: "dark", name: qsTr("Dark"), icon: "moon" },
                                        { id: "light", name: qsTr("Light"), icon: "sun" }
                                    ]

                                    delegate: PillButton {
                                        required property var modelData

                                        iconName: modelData.icon
                                        iconSize: 11
                                        text: modelData.name
                                        implicitHeight: 32
                                        active: SettingsController.themeMode === modelData.id
                                        onClicked: SettingsController.themeMode = modelData.id
                                    }
                                }
                            }

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Interface size")
                                description: qsTr("Makes everything bigger or smaller: text, buttons, panels. Takes effect when the app starts again.")
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: [0.9, 1.0, 1.1, 1.25, 1.5]

                                    delegate: PillButton {
                                        required property real modelData

                                        text: Math.round(modelData * 100) + "%"
                                        implicitHeight: 32
                                        active: Math.abs(SettingsController.interfaceScale - modelData) < 0.01
                                        onClicked: SettingsController.interfaceScale = modelData
                                    }
                                }
                            }

                            // Shown once the chosen size differs from the one in use
                            RowLayout {
                                Layout.fillWidth: true
                                visible: Math.abs(SettingsController.interfaceScale - SettingsController.activeInterfaceScale) > 0.01
                                spacing: Theme.spacing

                                Label {
                                    Layout.fillWidth: true
                                    text: SettingsController.resumeSession
                                          ? qsTr("Restart the app to use the new size. The song you're playing picks up where it was.")
                                          : qsTr("Restart the app to use the new size.")
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.WordWrap
                                }

                                PillButton {
                                    filled: true
                                    iconName: "refresh"
                                    iconSize: 11
                                    text: qsTr("Restart now")
                                    implicitHeight: 32
                                    onClicked: SettingsController.restartApp()
                                }
                            }
                        }

                        SettingsCard {
                            title: qsTr("Background")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Cover color strength")
                                description: qsTr("How strongly the background takes the album cover's color.")

                                RowLayout {
                                    spacing: Theme.spacing

                                    ThemedSlider {
                                        implicitWidth: 140
                                        from: 0
                                        to: 1
                                        value: SettingsController.coverTintStrength
                                        onMoved: SettingsController.coverTintStrength = value
                                    }

                                    Label {
                                        Layout.preferredWidth: 38
                                        horizontalAlignment: Text.AlignRight
                                        text: Math.round(SettingsController.coverTintStrength * 100) + "%"
                                        color: Theme.text
                                        font.pixelSize: Theme.fontSize
                                        font.features: { "tnum": 1 }
                                    }
                                }
                            }
                        }

                        SettingsCard {
                            title: qsTr("Visualizer")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Show the visualizer")
                                description: qsTr("The music's frequencies, under the volume bar.")

                                SettingsSwitch {
                                    checked: SettingsController.visualizerEnabled
                                    onToggled: SettingsController.visualizerEnabled = checked
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                enabled: SettingsController.visualizerEnabled
                                opacity: enabled || Util.openDialogs > 0 ? 1 : 0.4

                                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

                                Repeater {
                                    model: [qsTr("Bars"), qsTr("Mirrored bars"), qsTr("Wave")]

                                    delegate: PillButton {
                                        required property string modelData
                                        required property int index

                                        text: modelData
                                        implicitHeight: 32
                                        active: SettingsController.visualizerStyle === index
                                        onClicked: SettingsController.visualizerStyle = index
                                    }
                                }
                            }
                        }
                    }

                    // ------------------------------------------------------------ Library
                    SettingsPage {
                        title: qsTr("Library")

                        SettingsCard {
                            title: qsTr("Browsing")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Letter groups")
                                description: qsTr("Songs, artists and genres sorted by name (A–Z or Z–A) get a header for each letter. Tap a letter to jump to another one.")

                                SettingsSwitch {
                                    checked: SettingsController.letterGroups
                                    onToggled: SettingsController.letterGroups = checked
                                }
                            }
                        }

                        SettingsCard {
                            title: qsTr("Hosted library")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: HostedController.signedIn ? HostedController.serverName : qsTr("No server")
                                description: HostedController.signedIn
                                             ? qsTr("Signed in as %1 (Jellyfin). Its songs are in Library > Hosted library.")
                                               .arg(HostedController.userName)
                                             : qsTr("Sign in to a Jellyfin server from Library > Hosted library.")

                                PillButton {
                                    visible: HostedController.signedIn
                                    text: qsTr("Sign out")
                                    implicitHeight: 32
                                    onClicked: HostedController.signOut()
                                }
                            }
                        }

                        SettingsCard {
                            title: qsTr("Music folders")

                            SettingsRow {
                                Layout.fillWidth: true
                                description: qsTr("Your library is every song in these folders (and the folders inside them). Removing a folder leaves the files where they are.")
                            }

                            Repeater {
                                model: SettingsController.libraryFolders

                                delegate: Rectangle {
                                    id: folderRow

                                    required property string modelData

                                    Layout.fillWidth: true
                                    implicitHeight: 40
                                    radius: Theme.radius
                                    color: Theme.fill

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 4
                                        spacing: Theme.spacing

                                        Icon {
                                            name: "folder"
                                            size: 12
                                            color: Theme.accent
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: folderRow.modelData
                                            color: Theme.text
                                            font.pixelSize: Theme.fontSize
                                            elide: Text.ElideMiddle
                                        }

                                        PillButton {
                                            iconName: "close"
                                            iconSize: 11
                                            implicitWidth: 30
                                            implicitHeight: 30
                                            transparentIdle: true
                                            ToolTip.visible: hovered
                                            ToolTip.text: qsTr("Remove from the library (the files stay)")
                                            onClicked: LocalLibraryController.removeFolder(folderRow.modelData)
                                        }
                                    }
                                }
                            }

                            PillButton {
                                iconName: "folderPlus"
                                iconSize: 12
                                text: qsTr("Add folder…")
                                implicitHeight: 32
                                filled: SettingsController.libraryFolders.length === 0
                                onClicked: root.addFolderRequested()
                            }
                        }

                        SettingsCard {
                            title: qsTr("Excluded folders")

                            SettingsRow {
                                Layout.fillWidth: true
                                description: qsTr("Folders inside your music folders that are left out (e.g. ringtones, recordings).")
                            }

                            Repeater {
                                model: SettingsController.libraryExcluded

                                delegate: Rectangle {
                                    id: excludedRow

                                    required property string modelData

                                    Layout.fillWidth: true
                                    implicitHeight: 40
                                    radius: Theme.radius
                                    color: Theme.fill

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 4
                                        spacing: Theme.spacing

                                        Icon {
                                            name: "eyeSlash"
                                            size: 12
                                            color: Theme.textMuted
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: excludedRow.modelData
                                            color: Theme.text
                                            font.pixelSize: Theme.fontSize
                                            elide: Text.ElideMiddle
                                        }

                                        PillButton {
                                            iconName: "close"
                                            iconSize: 11
                                            implicitWidth: 30
                                            implicitHeight: 30
                                            transparentIdle: true
                                            ToolTip.visible: hovered
                                            ToolTip.text: qsTr("Include it again")
                                            onClicked: SettingsController.removeLibraryExcluded(excludedRow.modelData)
                                        }
                                    }
                                }
                            }

                            PillButton {
                                iconName: "eyeSlash"
                                iconSize: 12
                                text: qsTr("Exclude a folder…")
                                implicitHeight: 32
                                onClicked: root.excludeFolderRequested(SettingsController.libraryFolders.length > 0
                                                                       ? Files.toUrl(SettingsController.libraryFolders[0]) : "")
                            }
                        }
                    }

                    // ------------------------------------------------------------ Album art
                    SettingsPage {
                        title: qsTr("Album art")

                        SettingsCard {
                            title: qsTr("Size")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Album art size")
                                description: qsTr("On the player. At 100% it reaches the edges of the screen, above the song's title, and stays still.")
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacing

                                ThemedSlider {
                                    Layout.fillWidth: true
                                    from: 60
                                    to: 100
                                    stepSize: 5
                                    snapMode: Slider.SnapAlways
                                    value: SettingsController.coverSize
                                    onMoved: SettingsController.coverSize = Math.round(value)
                                }

                                Label {
                                    Layout.preferredWidth: 44
                                    horizontalAlignment: Text.AlignRight
                                    text: SettingsController.coverSize + "%"
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSize
                                    font.features: { "tnum": 1 }
                                }
                            }
                        }

                        SettingsCard {
                            title: qsTr("Missing covers")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Find missing covers online")
                                description: qsTr("For songs without a cover, ask the sources below and show the sharpest match. Covers are cached; your files are not changed.")

                                SettingsSwitch {
                                    checked: SettingsController.coversOnline
                                    onToggled: SettingsController.coversOnline = checked
                                }
                            }
                        }

                        SettingsCard {
                            title: qsTr("Sources")

                            Repeater {
                                model: SettingsController.coverSources

                                delegate: SettingsRow {
                                    id: coverSourceRow

                                    required property var modelData

                                    Layout.fillWidth: true
                                    title: modelData.name
                                    opacity: SettingsController.coversOnline || modelData.id === "folder" ? 1 : 0.4

                                    SettingsSwitch {
                                        checked: coverSourceRow.modelData.enabled
                                        onToggled: SettingsController.setCoverSourceEnabled(coverSourceRow.modelData.id, checked)
                                    }
                                }
                            }
                        }
                    }

                    // ------------------------------------------------------------ Lyrics
                    SettingsPage {
                        title: qsTr("Lyrics")

                        SettingsCard {
                            title: qsTr("Sources")

                            SettingsRow {
                                Layout.fillWidth: true
                                description: qsTr("Tried from top to bottom until one has lyrics. Switch off the ones you don't want.")
                            }

                            Repeater {
                                model: SettingsController.lyricsSources

                                delegate: Rectangle {
                                    id: sourceRow

                                    required property var modelData
                                    required property int index

                                    Layout.fillWidth: true
                                    implicitHeight: 44
                                    radius: Theme.radius
                                    color: Theme.fillSoft

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.padding
                                        anchors.rightMargin: Theme.spacing
                                        spacing: Theme.spacing

                                        Label {
                                            text: (sourceRow.index + 1) + "."
                                            color: Theme.textMuted
                                            font.pixelSize: Theme.fontSize
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: sourceRow.modelData.name
                                            color: sourceRow.modelData.enabled ? Theme.text : Theme.textMuted
                                            font.pixelSize: Theme.fontSize
                                            elide: Text.ElideRight
                                        }

                                        PillButton {
                                            iconName: "arrowUp"
                                            iconSize: 11
                                            implicitWidth: 32
                                            implicitHeight: 28
                                            transparentIdle: true
                                            enabled: sourceRow.index > 0
                                            onClicked: SettingsController.moveLyricsSource(sourceRow.index, -1)
                                        }

                                        PillButton {
                                            iconName: "arrowDown"
                                            iconSize: 11
                                            implicitWidth: 32
                                            implicitHeight: 28
                                            transparentIdle: true
                                            enabled: sourceRow.index < SettingsController.lyricsSources.length - 1
                                            onClicked: SettingsController.moveLyricsSource(sourceRow.index, 1)
                                        }

                                        SettingsSwitch {
                                            checked: sourceRow.modelData.enabled
                                            onToggled: SettingsController.setLyricsSourceEnabled(sourceRow.index, checked)
                                        }
                                    }
                                }
                            }
                        }

                        SettingsCard {
                            title: qsTr("Display")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Synced lyrics by default")
                                description: qsTr("Highlight lines in time with the music when timing is available.")

                                SettingsSwitch {
                                    checked: SettingsController.lyricsSyncedByDefault
                                    onToggled: SettingsController.lyricsSyncedByDefault = checked
                                }
                            }

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Script")
                                description: qsTr("English letters: the song's own words written in English letters (e.g. “Aankhen band kar ke”), not a translation.")
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: [qsTr("Original script"), qsTr("English letters")]

                                    delegate: PillButton {
                                        required property string modelData
                                        required property int index

                                        text: modelData
                                        implicitHeight: 32
                                        active: SettingsController.lyricsLatinScript === (index === 1)
                                        onClicked: SettingsController.lyricsLatinScript = index === 1
                                    }
                                }
                            }
                        }
                    }

                    // ------------------------------------------------------------ YouTube Music
                    SettingsPage {
                        title: qsTr("YouTube Music")

                        SettingsCard {
                            readonly property bool hiddenHere: root.android
                            visible: !hiddenHere // (yt-dlp can't read a phone browser's session)
                            title: qsTr("Your account")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Sign in through your browser")
                                description: qsTr("Pick the browser where you're signed in; yt-dlp reads your library through it. The app never sees your password. Close that browser if reading fails.")
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: [
                                        { id: "", name: qsTr("Not signed in") },
                                        { id: "firefox", name: "Firefox" },
                                        { id: "chrome", name: "Chrome" },
                                        { id: "chromium", name: "Chromium" },
                                        { id: "brave", name: "Brave" },
                                        { id: "edge", name: "Edge" },
                                        { id: "vivaldi", name: "Vivaldi" },
                                        { id: "opera", name: "Opera" }
                                    ]

                                    delegate: PillButton {
                                        required property var modelData

                                        text: modelData.name
                                        implicitHeight: 32
                                        active: SettingsController.ytCookiesBrowser === modelData.id
                                        onClicked: SettingsController.ytCookiesBrowser = modelData.id
                                    }
                                }
                            }
                        }

                        SettingsCard {
                            title: qsTr("Your local songs")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Look up track info in the background")
                                description: qsTr("Find your songs on YouTube Music and show that info in Track details.")

                                SettingsSwitch {
                                    checked: SettingsController.ytBackgroundLookup
                                    onToggled: SettingsController.ytBackgroundLookup = checked
                                }
                            }
                        }

                        SettingsCard {
                            title: qsTr("Playback")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Autoplay similar songs")
                                description: qsTr("After a song, an album or a playlist, keep playing what YouTube Music plays next (a Mix). Playing YouTube songs never adds them to the Queue.")

                                SettingsSwitch {
                                    checked: SettingsController.ytAutoplay
                                    onToggled: SettingsController.ytAutoplay = checked
                                }
                            }

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Continue with a Mix when the Queue ends")
                                description: qsTr("If the Queue's last song is from YouTube, its Mix plays after it. The Queue itself stays as it is.")

                                SettingsSwitch {
                                    checked: SettingsController.ytQueueMix
                                    onToggled: SettingsController.ytQueueMix = checked
                                }
                            }

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Audio quality")
                                description: SettingsController.ytQuality === SettingsController.YtAuto
                                             ? qsTr("The best sound, but the smallest streams on a metered connection (e.g. a phone hotspot).")
                                             : SettingsController.ytQuality === SettingsController.YtBest
                                               ? qsTr("Always the best sound YouTube Music has (up to 256 kbps with Premium).")
                                               : qsTr("Always the smallest streams, to save data.")
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: [
                                        { value: SettingsController.YtAuto, name: qsTr("Auto") },
                                        { value: SettingsController.YtBest, name: qsTr("Best") },
                                        { value: SettingsController.YtLowest, name: qsTr("Lowest") }
                                    ]

                                    delegate: PillButton {
                                        required property var modelData

                                        text: modelData.name
                                        implicitHeight: 32
                                        active: SettingsController.ytQuality === modelData.value
                                        onClicked: SettingsController.ytQuality = modelData.value
                                    }
                                }
                            }

                            // yt-dlp plays YouTube songs; the app keeps it up to date (YtDlpManager)
                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("yt-dlp")
                                description: {
                                    const where = YouTubeController.ytDlpSource === "app" ? qsTr("the app's own copy")
                                                : YouTubeController.ytDlpSource === "bundled" ? qsTr("the copy that came with the app")
                                                : qsTr("installed on this computer")
                                    const what = YouTubeController.available
                                                 ? qsTr("Version %1, %2. It plays YouTube songs.").arg(YouTubeController.ytDlpVersion).arg(where)
                                                 : YouTubeController.ytDlpCanUpdate
                                                   ? qsTr("Not found yet. It plays YouTube songs; the app gets it when online.")
                                                   : qsTr("Not found. Install yt-dlp to play YouTube songs.")
                                    const checked = YouTubeController.ytDlpCanUpdate
                                                    ? " " + qsTr("Checked for updates at every start.") : ""
                                    return what + checked + (YouTubeController.ytDlpStatus !== "" ? "\n" + YouTubeController.ytDlpStatus : "")
                                }

                                PillButton {
                                    visible: YouTubeController.ytDlpCanUpdate
                                    enabled: !YouTubeController.ytDlpBusy
                                    iconName: "refresh"
                                    iconSize: 11
                                    text: YouTubeController.ytDlpBusy ? qsTr("Checking…") : qsTr("Update yt-dlp")
                                    implicitHeight: 32
                                    onClicked: YouTubeController.updateYtDlp()
                                }
                            }
                        }
                    }

                    // ------------------------------------------------------------ Keyboard shortcuts
                    SettingsPage {
                        title: qsTr("Keyboard shortcuts")

                        // Both lists mirror frontend/layout/AppShortcuts.qml.
                        SettingsCard {
                            title: qsTr("Playback")

                            ShortcutList {
                                model: [
                                    [qsTr("Play / pause"), "Space"],
                                    [qsTr("Next / previous song"), "Ctrl+→  /  Ctrl+←"],
                                    [qsTr("Seek 5 s forward / back"), "→  /  ←"],
                                    [qsTr("Seek 30 s forward / back"), "Shift+→  /  Shift+←"],
                                    [qsTr("Volume up / down"), "Ctrl+↑  /  Ctrl+↓"],
                                    [qsTr("Mute"), "M"],
                                    [qsTr("Shuffle"), "Ctrl+S"],
                                    [qsTr("Repeat (cycles)"), "Ctrl+R"]
                                ]
                            }
                        }

                        SettingsCard {
                            title: qsTr("Window")

                            ShortcutList {
                                model: [
                                    [qsTr("Lyrics"), "Ctrl+L"],
                                    [qsTr("Search (Library if open, else YouTube Music)"), "Ctrl+F"],
                                    [qsTr("Queue / YouTube Music / Library"), "Ctrl+1  /  2  /  3"],
                                    [qsTr("Settings"), "Ctrl+,"],
                                    [qsTr("Close lyrics, panel or dialog"), "Esc"],
                                    [qsTr("Quit"), "Ctrl+Q"]
                                ]
                            }
                        }
                    }

                    // ------------------------------------------------------------ About
                    SettingsPage {
                        title: qsTr("About")

                        SettingsCard {
                            title: qsTr("Tuned Chaos")

                            Label {
                                Layout.fillWidth: true
                                text: qsTr("Version %1").arg(Qt.application.version)
                                color: Theme.text
                                font.pixelSize: Theme.fontSize
                            }

                            Label {
                                Layout.fillWidth: true
                                // The sound system differs: PipeWire on Linux, miniaudio elsewhere
                                text: qsTr("A music player for your local music and YouTube Music. Built with Qt, FFmpeg, %1 and TagLib.")
                                      .arg(Qt.platform.os === "linux" ? "PipeWire" : "miniaudio")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.WordWrap
                            }

                            PillButton {
                                iconName: "link"
                                iconSize: 12
                                text: qsTr("Source code on GitHub")
                                implicitHeight: 32
                                onClicked: Qt.openUrlExternally("https://github.com/ChandanDasGIT/TunedChaos")
                            }

                            // (Android only: the other systems update through their own packages)
                            SettingsRow {
                                Layout.fillWidth: true
                                readonly property bool hiddenHere: !root.android
                                visible: !hiddenHere
                                title: qsTr("Check for updates")
                                description: qsTr("Look for a new version of the app at startup.")

                                SettingsSwitch {
                                    checked: SettingsController.appUpdateCheck
                                    onToggled: SettingsController.appUpdateCheck = checked
                                }
                            }
                        }

                        SettingsCard {
                            title: qsTr("Your data")

                            Repeater {
                                model: [
                                    { name: qsTr("Settings"), kind: "config" },
                                    { name: qsTr("Queue, playlists, library"), kind: "data" },
                                    { name: qsTr("Covers, lyrics, YouTube matches"), kind: "cache" }
                                ]

                                delegate: SettingsRow {
                                    id: dataRow

                                    required property var modelData
                                    readonly property url folder: Files.toUrl(Files.appFolder(modelData.kind))

                                    Layout.fillWidth: true
                                    title: modelData.name
                                    description: Files.displayPath(folder)

                                    PillButton {
                                        iconName: "folderOpen"
                                        iconSize: 12
                                        implicitWidth: 34
                                        implicitHeight: 30
                                        ToolTip.visible: hovered
                                        ToolTip.text: qsTr("Open the folder")
                                        onClicked: Qt.openUrlExternally(dataRow.folder)
                                    }
                                }
                            }
                        }
                    }

                    // ------------------------------------------------------------ Layout Customisation
                    SettingsPage {
                        title: qsTr("Layout Customisation")

                        SettingsCard {
                            title: qsTr("Bottom bar")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Lines between icons")
                                description: qsTr("A thin line separates each icon from the next.")

                                SettingsSwitch {
                                    checked: SettingsController.navDividers
                                    onToggled: SettingsController.navDividers = checked
                                }
                            }

                            SettingsRow {
                                readonly property bool hiddenHere: !root.android
                                visible: !hiddenHere // (phones only)
                                Layout.fillWidth: true
                                title: qsTr("Panels")
                                description: qsTr("Choose which panels you can open and their order. A panel turned off can't be opened; your music and its settings stay. Settings is always there.")
                            }

                            Repeater {
                                model: root.android ? SettingsController.panelOrder : []

                                delegate: Rectangle {
                                    id: panelRow

                                    required property string modelData
                                    required property int index
                                    readonly property bool shownInBar: !SettingsController.hiddenPanels.includes(modelData)

                                    Layout.fillWidth: true
                                    implicitHeight: 44
                                    radius: Theme.radius
                                    color: Theme.fillSoft

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.padding
                                        anchors.rightMargin: Theme.spacing
                                        spacing: Theme.spacing

                                        Label {
                                            Layout.fillWidth: true
                                            text: root.panelNames[panelRow.modelData]
                                            color: panelRow.shownInBar ? Theme.text : Theme.textMuted
                                            font.pixelSize: Theme.fontSize
                                            elide: Text.ElideRight
                                        }

                                        PillButton {
                                            iconName: "arrowUp"
                                            iconSize: 11
                                            implicitWidth: 32
                                            implicitHeight: 28
                                            transparentIdle: true
                                            enabled: panelRow.index > 0
                                            onClicked: SettingsController.movePanel(panelRow.index, -1)
                                        }

                                        PillButton {
                                            iconName: "arrowDown"
                                            iconSize: 11
                                            implicitWidth: 32
                                            implicitHeight: 28
                                            transparentIdle: true
                                            enabled: panelRow.index < SettingsController.panelOrder.length - 1
                                            onClicked: SettingsController.movePanel(panelRow.index, 1)
                                        }

                                        SettingsSwitch {
                                            checked: panelRow.shownInBar
                                            onToggled: SettingsController.setPanelHidden(panelRow.modelData, !checked)
                                        }
                                    }
                                }
                            }
                        }

                        SettingsCard {
                            readonly property bool hiddenHere: !root.android
                            visible: !hiddenHere // (phones only)
                            title: qsTr("Default panel")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Choose default")
                                description: qsTr("What opens when the app starts and what you come back to when a panel closes. On the bottom bar the player takes its place.")
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: root.android ? root.defaultChoices : []

                                    delegate: PillButton {
                                        required property string modelData

                                        text: root.panelNames[modelData]
                                        implicitHeight: 32
                                        active: root.defaultShown === modelData
                                        onClicked: SettingsController.defaultPanel = modelData
                                    }
                                }
                            }
                        }

                        SettingsCard {
                            readonly property bool hiddenHere: root.android // (phones: the default panel opens)
                            visible: !hiddenHere
                            title: qsTr("Startup")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Open on start")
                                description: qsTr("What you see when the app opens.")
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: root.startChoices

                                    delegate: PillButton {
                                        required property string modelData

                                        text: root.panelNames[modelData]
                                        implicitHeight: 32
                                        active: root.startShown === modelData
                                        onClicked: SettingsController.startPanel = modelData
                                    }
                                }
                            }
                        }
                    }

                    // ------------------------------------------------------------ Seekbar
                    SettingsPage {
                        title: qsTr("Seekbar")

                        SettingsCard {
                            title: qsTr("Player seekbar")

                            SeekbarOptions {
                                Layout.fillWidth: true
                                styleSetting: "seekbarStyle"
                                thumbSetting: "seekbarThumb"
                                styleDescription: qsTr("While a song plays: the whole bar flows, or only the part around the thumb.")
                                thumbDescription: qsTr("The marker that shows where you are in the song.")
                            }
                        }

                        SettingsCard {
                            readonly property bool hiddenHere: !root.android
                            visible: !hiddenHere // (phones only)
                            title: qsTr("Bottom bar seekbar")

                            SeekbarOptions {
                                Layout.fillWidth: true
                                styleSetting: "fidgetStyle"
                                thumbSetting: "fidgetThumb"
                                styleDescription: qsTr("While you drag it: the whole bar moves, or only the part around the thumb. It shows when the bottom bar has one panel or none.")
                                thumbDescription: qsTr("Just for fun: it has nothing to do with the music.")
                            }
                        }
                    }

                    // ------------------------------------------------------------ Sleep timer
                    SettingsPage {
                        title: qsTr("Sleep timer")

                        SettingsCard {
                            title: qsTr("Sleep timer")

                            SettingsRow {
                                Layout.fillWidth: true
                                title: qsTr("Pause the music")
                                description: !SleepTimerController.active ? qsTr("Off. The music fades out at the end.")
                                           : SleepTimerController.endOfSong ? qsTr("Pausing at the end of this song")
                                           : qsTr("Pausing in %1").arg(Util.formatTime(SleepTimerController.remainingMs))
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: [15, 30, 45, 60, 90]

                                    delegate: PillButton {
                                        required property int modelData

                                        text: qsTr("%1 min").arg(modelData)
                                        implicitHeight: 32
                                        onClicked: SleepTimerController.start(modelData)
                                    }
                                }

                                PillButton {
                                    text: qsTr("End of this song")
                                    implicitHeight: 32
                                    enabled: PlayerController.hasTrack
                                    active: SleepTimerController.endOfSong
                                    onClicked: SleepTimerController.startEndOfSong()
                                }

                                PillButton {
                                    text: qsTr("Turn off")
                                    implicitHeight: 32
                                    enabled: SleepTimerController.active
                                    onClicked: SleepTimerController.cancel()
                                }
                            }
                        }
                    }
                }
            }

            // Search results: a setting's name, where it is, and what it does
            ListView {
                id: results
                anchors.fill: parent
                anchors.topMargin: Theme.spacing
                opacity: root.searching ? 1 : 0
                visible: opacity > 0
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: Theme.flickDeceleration
                maximumFlickVelocity: Theme.flickVelocity
                synchronousDrag: true
                model: root.searching ? root.search(root.query) : []
                ScrollBar.vertical: ScrollBar {}

                Behavior on opacity { NumberAnimation { duration: Theme.anim } }

                delegate: Rectangle {
                    id: result

                    required property var modelData

                    x: Theme.spacing
                    width: ListView.view.width - 2 * Theme.spacing
                    implicitHeight: resultColumn.implicitHeight + 16
                    radius: Theme.radius
                    color: resultHover.hovered ? Theme.hover : "transparent"

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    HoverHandler {
                        id: resultHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: root.reveal(result.modelData)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 12
                        spacing: 12

                        CategoryIcon {
                            pageIndex: result.modelData.page
                            size: 28
                        }

                        ColumnLayout {
                            id: resultColumn
                            Layout.fillWidth: true
                            spacing: 1

                            Label {
                                Layout.fillWidth: true
                                text: result.modelData.title
                                color: Theme.text
                                font.pixelSize: Theme.fontSize
                                elide: Text.ElideRight
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: result.modelData.item !== null
                                text: root.pages[result.modelData.page].name
                                      + (result.modelData.card !== "" ? "  ›  " + result.modelData.card : "")
                                color: Theme.accent
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideRight
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: result.modelData.description
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                            }
                        }

                        Icon {
                            name: "chevronRight"
                            size: 10
                            color: Theme.textMuted
                        }
                    }
                }

                Label {
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.padding
                    visible: root.searching && results.count === 0
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: qsTr("No settings match “%1”").arg(root.query)
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize
                }
            }
        }

        // ---- Search bar, at the bottom
        TextField {
            id: searchField
            Layout.fillWidth: true
            Layout.margins: Theme.spacing + 2
            implicitHeight: 40
            leftPadding: 40
            rightPadding: text !== "" ? 40 : 16
            placeholderText: qsTr("Search settings")
            placeholderTextColor: Theme.textMuted
            color: Theme.text
            font.pixelSize: Theme.fontSize
            selectByMouse: true
            // Esc: clears the search, else back to the list, else closes
            Keys.onEscapePressed: {
                if (text !== "")
                    clear()
                else if (!root.back())
                    root.closeRequested()
            }
            onAccepted: if (results.count > 0) root.reveal(results.model[0])

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
                color: searchField.activeFocus ? Theme.accent : Theme.textMuted
            }

            ControlButton {
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                visible: searchField.text !== ""
                iconName: "close"
                iconSize: 10
                iconColor: Theme.textMuted
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Clear")
                onClicked: searchField.clear()
            }
        }
    }

    // A category's icon: a colored rounded square, like a phone's settings.
    component CategoryIcon: Rectangle {
        id: categoryIcon

        required property int pageIndex
        property real size: 30

        implicitWidth: size
        implicitHeight: size
        radius: size * 0.28
        color: Qt.hsla(root.pages[pageIndex].hue, 0.55, Theme.isDark ? 0.5 : 0.55, 1)

        Icon {
            anchors.centerIn: parent
            name: root.pages[categoryIcon.pageIndex].icon
            size: categoryIcon.size * 0.45
            color: "white"
        }
    }

    // One category in the list: icon, name, a line about it, and a chevron.
    component CategoryRow: Rectangle {
        id: row

        required property int pageIndex
        property bool first: false
        property bool last: false

        implicitHeight: 58
        topLeftRadius: first ? Theme.radiusLarge : 0
        topRightRadius: first ? Theme.radiusLarge : 0
        bottomLeftRadius: last ? Theme.radiusLarge : 0
        bottomRightRadius: last ? Theme.radiusLarge : 0
        color: rowTap.pressed ? Theme.fillStrong : rowHover.hovered ? Theme.hover : "transparent"

        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        HoverHandler {
            id: rowHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: rowTap
            onTapped: root.openPage(row.pageIndex)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 14
            spacing: 14

            CategoryIcon {
                pageIndex: row.pageIndex
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    Layout.fillWidth: true
                    text: root.pages[row.pageIndex].name
                    color: Theme.text
                    font.pixelSize: Theme.fontSize
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    text: root.pages[row.pageIndex].summary
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                }
            }

            Icon {
                name: "chevronRight"
                size: 10
                color: Theme.textMuted
            }
        }

        // Divider to the next row, from under the text
        Rectangle {
            visible: !row.last
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.leftMargin: 56
            anchors.right: parent.right
            height: 1
            color: Theme.border
        }
    }

    // One page: its cards, scrolling (the header shows its name); fades in when shown.
    component SettingsPage: ScrollView {
        id: settingsPage

        Component.onCompleted: {
            const flick = contentItem as Flickable
            flick.flickDeceleration = Theme.flickDeceleration
            flick.maximumFlickVelocity = Theme.flickVelocity
            flick.synchronousDrag = true
        }

        property string title
        default property alias content: pageColumn.data

        // Scrolls to a setting (a search result) and highlights it for a moment.
        function reveal(item) {
            const at = item.mapToItem(pageColumn, 0, 0)
            const flick = settingsPage.contentItem as Flickable
            flick.contentY = Math.max(0, Math.min(at.y - 48, pageColumn.implicitHeight - flick.height))
            highlight.x = at.x - 8
            highlight.y = at.y - 6
            highlight.width = item.width + 16
            highlight.height = item.height + 12
            highlightPulse.restart()
        }

        contentWidth: availableWidth
        contentHeight: pageColumn.implicitHeight
        clip: true

        onVisibleChanged: if (visible) pageFade.restart()

        NumberAnimation {
            id: pageFade
            target: settingsPage
            property: "opacity"
            from: 0
            to: 1
            duration: Theme.anim
            easing.type: Theme.easing
        }

        ColumnLayout {
            id: pageColumn
            width: settingsPage.availableWidth
            spacing: Theme.padding
        }

        Rectangle {
            id: highlight
            radius: Theme.radius
            color: Theme.accent
            opacity: 0

            SequentialAnimation {
                id: highlightPulse
                NumberAnimation { target: highlight; property: "opacity"; to: 0.28; duration: Theme.anim }
                PauseAnimation { duration: 700 }
                NumberAnimation { target: highlight; property: "opacity"; to: 0; duration: 900; easing.type: Easing.InOutQuad }
            }
        }
    }

    // One equalizer band: its value (dB), a vertical slider filled from 0 dB
    // up or down, and its frequency. Double-click: back to 0.
    component EqBand: ColumnLayout {
        id: band

        property string label
        property real value: 0
        signal moved(real db)

        spacing: 6

        // (Labels fill the column, so the bands can share the row's width.)
        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: (band.value > 0 ? "+" : "") + Math.round(band.value)
            color: band.value !== 0 ? Theme.accent : Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.DemiBold
        }

        Slider {
            id: slider
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 160
            Layout.preferredWidth: 28
            orientation: Qt.Vertical
            from: -12
            to: 12
            stepSize: 1
            snapMode: Slider.SnapAlways
            value: band.value
            hoverEnabled: true
            focusPolicy: Qt.NoFocus
            onMoved: band.moved(value)

            TapHandler {
                onDoubleTapped: band.moved(0)
            }

            background: Item {
                x: slider.leftPadding + slider.availableWidth / 2 - 3
                y: slider.topPadding
                width: 6
                height: slider.availableHeight

                Rectangle {
                    anchors.fill: parent
                    radius: 3
                    color: Theme.border
                }

                // From the 0 dB mark to the handle
                Rectangle {
                    readonly property real zero: parent.height / 2
                    readonly property real at: slider.visualPosition * parent.height
                    width: parent.width
                    y: Math.min(zero, at)
                    height: Math.abs(at - zero)
                    radius: 3
                    color: slider.hovered || slider.pressed ? Theme.accent : Theme.text
                    opacity: 0.85

                    Behavior on color { ColorAnimation { duration: Theme.anim } }
                }

                // 0 dB mark
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 - 1
                    width: 14
                    height: 2
                    radius: 1
                    color: Theme.textDim
                }
            }

            handle: Rectangle {
                readonly property real size: slider.pressed ? 16 : slider.hovered ? 14 : 12

                x: slider.leftPadding + slider.availableWidth / 2 - width / 2
                y: slider.topPadding + slider.visualPosition * (slider.availableHeight - height)
                implicitWidth: size
                implicitHeight: size
                radius: width / 2
                color: Theme.text

                Behavior on implicitWidth { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easing } }
                Behavior on implicitHeight { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easing } }
            }
        }

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: band.label
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // A rounded card with a small accent heading.
    // One seek bar's choices: its animation and its thumb.
    component SeekbarOptions: ColumnLayout {
        id: options

        property string styleSetting
        property string thumbSetting
        property string styleDescription
        property string thumbDescription

        spacing: Theme.spacing

        SettingsRow {
            Layout.fillWidth: true
            title: qsTr("Animation")
            description: options.styleDescription
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [
                    { id: "wave", name: qsTr("Full wave") },
                    { id: "dot", name: qsTr("Around the thumb") }
                ]

                delegate: PillButton {
                    required property var modelData

                    text: modelData.name
                    implicitHeight: 32
                    active: SettingsController[options.styleSetting] === modelData.id
                    onClicked: SettingsController[options.styleSetting] = modelData.id
                }
            }
        }

        SettingsRow {
            Layout.fillWidth: true
            title: qsTr("Thumb")
            description: options.thumbDescription
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [
                    { id: "circle", name: qsTr("Circle") },
                    { id: "ring", name: qsTr("Ring") },
                    { id: "pill", name: qsTr("Pill") },
                    { id: "diamond", name: qsTr("Diamond") },
                    { id: "heart", name: qsTr("Heart") },
                    { id: "star", name: qsTr("Star") },
                    { id: "note", name: qsTr("Music note") },
                    { id: "disc", name: qsTr("Disc") },
                    { id: "play", name: qsTr("Play") },
                    { id: "arrow", name: qsTr("Wave arrow") }
                ]

                delegate: AbstractButton {
                    id: thumbChoice

                    required property var modelData
                    readonly property bool chosen: SettingsController[options.thumbSetting] === modelData.id

                    implicitWidth: 52
                    implicitHeight: 44
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    ToolTip.visible: hovered
                    ToolTip.text: modelData.name
                    onClicked: SettingsController[options.thumbSetting] = modelData.id

                    background: Rectangle {
                        radius: Theme.radius
                        color: thumbChoice.chosen ? Theme.accentSoft
                             : thumbChoice.hovered ? Theme.hover : Theme.fillSoft
                    }

                    contentItem: Item {
                        SeekThumb {
                            anchors.centerIn: parent
                            kind: thumbChoice.modelData.id
                            size: 12
                            color: thumbChoice.chosen ? Theme.accent : Theme.text
                        }
                    }
                }
            }
        }
    }

    component SettingsCard: Rectangle {
        id: card

        readonly property bool settingsCard: true // (search)
        property string title
        default property alias content: cardColumn.data

        Layout.fillWidth: true
        Layout.leftMargin: Theme.padding
        Layout.rightMargin: Theme.padding
        Layout.bottomMargin: 2
        implicitHeight: cardColumn.implicitHeight + 2 * Theme.padding
        radius: Theme.radiusLarge
        color: Theme.fillSoft

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: Theme.padding
            spacing: Theme.padding

            Label {
                text: card.title.toUpperCase()
                color: Theme.accent
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                font.letterSpacing: 1
            }
        }
    }

    // "−  value  +" for small numbers.
    component Stepper: RowLayout {
        id: stepper

        property string text
        property bool canDecrease: true
        property bool canIncrease: true

        signal decreased()
        signal increased()

        spacing: 4

        PillButton {
            iconName: "minus"
            iconSize: 11
            implicitWidth: 34
            implicitHeight: 30
            enabled: stepper.canDecrease
            onClicked: stepper.decreased()
        }

        Label {
            Layout.preferredWidth: 44
            horizontalAlignment: Text.AlignHCenter
            text: stepper.text
            color: Theme.text
            font.pixelSize: Theme.fontSize
            font.features: { "tnum": 1 }
        }

        PillButton {
            iconName: "plus"
            iconSize: 11
            implicitWidth: 34
            implicitHeight: 30
            enabled: stepper.canIncrease
            onClicked: stepper.increased()
        }
    }

    // Rows of "what it does ............ [keys]".
    component ShortcutList: ColumnLayout {
        id: shortcutList

        property var model: []

        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: shortcutList.model

            delegate: Item {
                id: shortcutRow

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 26

                Label {
                    anchors.left: parent.left
                    anchors.right: keys.left
                    anchors.rightMargin: Theme.padding
                    anchors.verticalCenter: parent.verticalCenter
                    text: shortcutRow.modelData[0]
                    color: Theme.text
                    font.pixelSize: Theme.fontSize
                    elide: Text.ElideRight
                }

                Rectangle {
                    id: keys
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: keysLabel.implicitWidth + 16
                    height: 24
                    radius: 6
                    color: Theme.surfaceAlt

                    Label {
                        id: keysLabel
                        anchors.centerIn: parent
                        text: shortcutRow.modelData[1]
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }
}
