pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: window

    // ---- Layout -------------------------------------------------------------------
    // Picked by how much of the screen the window covers, so a full-screen
    // window behaves the same on any monitor:
    //  "wide" (most of the screen): columns Queue or Home | Player | YouTube, Library or Settings;
    //  "half": two columns at most, so an opened panel can push the player out
    //          (a floating mini player then stands in for it);
    //  "compact" (phone size): the player alone, panels slide over it as drawers.
    // The columns share the width equally. Queue and Home take turns in the
    // left-hand one (Home slides up over the Queue), YouTube and Library in the
    // right-hand one. A pinned panel stays open (also after a restart).
    property real screenWidthOverride: 0 // tests: pretend the screen is this wide
    readonly property real screenWidth: screenWidthOverride > 0 ? screenWidthOverride : Screen.width > 0 ? Screen.width : width
    readonly property real minimumColumn: 300
    readonly property string layout: {
        const share = width / screenWidth
        if (width < Theme.compactBreakpoint || share < 0.4 || width < 2 * minimumColumn + 3 * Theme.cardGap)
            return "compact"
        return share >= 0.7 && width >= 3 * minimumColumn + 4 * Theme.cardGap ? "wide" : "half"
    }
    readonly property bool compact: layout === "compact"

    // Opened without being pinned (wide / half layouts; compact uses the drawers).
    property string leftOpen: ""       // "queue" / "home", shown over a pinned one
    property string rightOpen: ""      // "youtube" / "library" / "settings", shown over a pinned one
    property bool playerRecalled: false // half: the player in place of two pinned panels
    property string lastOpened: ""     // the panel opened last pushes the player away from its side
    // Phones: a panel turned off in Layout Customisation is gone, with every way to
    // open it (only the panel: what it shows keeps working).
    readonly property var hiddenPanels: Theme.touchOnly ? SettingsController.hiddenPanels : []
    function panelHidden(name) {
        return hiddenPanels.includes(name)
    }
    onHiddenPanelsChanged: {
        if (panelHidden(leftOpen))
            leftOpen = ""
        if (panelHidden(rightOpen))
            rightOpen = ""
        if (panelHidden("queue"))
            playlistDrawer.close()
        if (panelHidden("youtube"))
            youtubeDrawer.close()
        if (panelHidden("library"))
            libraryDrawer.close()
        if (panelHidden("home"))
            homeSheet.shown = false
    }

    // Which column each panel uses (Layout Customisation, desktop); Settings is never pinned
    readonly property var allPanels: ["queue", "home", "youtube", "library", "settings"]
    readonly property var pinnablePanels: ["queue", "home", "youtube", "library"]
    readonly property var leftPanels: SettingsController.leftPanels
    function pinnedFlag(name) {
        return name === "queue" ? SettingsController.playlistPinned
             : name === "home" ? SettingsController.homePanelPinned
             : name === "youtube" ? SettingsController.youtubePanelPinned
             : name === "library" ? SettingsController.libraryPanelPinned : false
    }
    function setPinnedFlag(name, pinned) {
        if (name === "queue")
            SettingsController.playlistPinned = pinned
        else if (name === "home")
            SettingsController.homePanelPinned = pinned
        else if (name === "youtube")
            SettingsController.youtubePanelPinned = pinned
        else if (name === "library")
            SettingsController.libraryPanelPinned = pinned
    }
    function pinnedOn(left) {
        return pinnablePanels.find((name) => isLeft(name) === left && pinnedFlag(name) && !panelHidden(name)) ?? ""
    }
    // The panels of one column that can be opened
    function sidePanels(left) {
        return allPanels.filter((name) => isLeft(name) === left && !panelHidden(name))
    }
    readonly property string leftPinned: { leftPanels; return pinnedOn(true) }
    readonly property string rightPinned: { leftPanels; return pinnedOn(false) }
    // What the columns show
    readonly property string leftShown: compact ? "" : leftOpen !== "" ? leftOpen : leftPinned
    readonly property string rightShown: compact || playerRecalled ? "" : rightOpen !== "" ? rightOpen : rightPinned
    function docked(name) {
        return leftShown === name || rightShown === name
    }
    readonly property bool playlistDocked: docked("queue")
    readonly property bool homeDocked: docked("home")
    readonly property bool youtubeDocked: docked("youtube")
    readonly property bool libraryDocked: docked("library")
    // Settings: in its column (never pinned), or a sheet at phone size
    readonly property bool settingsDocked: docked("settings")
    readonly property bool settingsShown: settingsDocked || settingsSheet.shown
    onSettingsShownChanged: {
        if (!settingsShown)
            settingsPanel.dropKeyboard()
        else if (settingsPanel.page < 0)
            settingsPanel.intro()
    }
    readonly property bool playerShown: layout !== "half" || !(leftShown !== "" && rightShown !== "")

    function isLeft(name) {
        return leftPanels.includes(name)
    }
    // A panel moved to the other column: the open panels move to their columns
    // (Settings, where the change was made, wins a shared one), and a column keeps
    // one pinned panel at most.
    readonly property string leftKey: leftPanels.join() // (changes only when the sides do)
    onLeftKeyChanged: {
        const open = [leftOpen, rightOpen].filter((name) => name !== "")
                                          .sort((a, b) => (a === "settings") - (b === "settings"))
        leftOpen = ""
        rightOpen = ""
        fixPins()
        for (const name of open)
            setOpen(name)
        if (layout === "half" && leftOpen !== "" && rightOpen !== "") {
            if (leftOpen === "settings")
                rightOpen = ""
            else
                leftOpen = ""
        }
    }
    function fixPins() {
        for (const left of [true, false]) {
            const pinned = pinnablePanels.filter((name) => isLeft(name) === left && pinnedFlag(name))
            pinned.slice(1).forEach((name) => setPinnedFlag(name, false))
        }
    }
    // Shown in its column (unpinned over a pinned one), without the half layout's rules
    function setOpen(name) {
        if (isLeft(name))
            leftOpen = name === leftPinned ? "" : name
        else
            rightOpen = name === rightPinned ? "" : name
    }
    function openPanel(name) {
        if (panelHidden(name))
            return
        playerRecalled = false
        lastOpened = name
        if (isLeft(name)) {
            leftOpen = name === leftPinned ? "" : name
            if (layout === "half")
                rightOpen = "" // only one unpinned panel at a time
        } else {
            rightOpen = name === rightPinned ? "" : name
            if (layout === "half")
                leftOpen = ""
        }
    }
    // Closing a pinned panel unpins it.
    function closePanel(name) {
        if (isLeft(name) && leftOpen === name)
            leftOpen = "" // a pinned panel under it comes back
        else if (isLeft(name))
            setPinned(name, false)
        else if (rightOpen === name)
            rightOpen = ""
        else
            setPinned(name, false)
    }
    // Pinning a panel unpins the other one of its column (the one pinned last wins).
    function setPinned(name, pinned) {
        if (!pinnablePanels.includes(name))
            return
        if (pinned)
            pinnablePanels.filter((other) => other !== name && isLeft(other) === isLeft(name))
                          .forEach((other) => setPinnedFlag(other, false))
        setPinnedFlag(name, pinned)
    }
    // A column's pin button: the panel stays open either way.
    function togglePin(name) {
        const left = isLeft(name)
        const wasPinned = (left ? leftPinned : rightPinned) === name
        if (left)
            leftOpen = wasPinned ? name : ""
        else
            rightOpen = wasPinned ? name : ""
        setPinned(name, !wasPinned)
    }
    // Half layout, the floating mini player tapped: make room for the player.
    function showPlayer() {
        if (rightOpen !== "")
            rightOpen = ""
        else if (leftOpen !== "")
            leftOpen = ""
        else
            playerRecalled = true
    }
    // Queue and Home used to sit in different columns, so both could be pinned.
    Component.onCompleted: {
        fixPins()
        Qt.callLater(() => { // (once the window has its size)
            openStartPanel()
            restoreBase("")
            screenSettle.restart() // (the first screen, for Back)
        })
    }
    // What Layout Customisation says to open at start (the player needs nothing).
    function openStartPanel() {
        const name = SettingsController.startPanel
        if (Theme.touchOnly) // phones: the default panel opens instead (restoreBase)
            return
        if (name === "player" || panelHidden(name))
            return
        if (!compact)
            openPanel(name)
        else if (name === "queue")
            toggleQueue()
        else if (name === "youtube")
            toggleYoutube()
        else if (name === "library")
            toggleLibrary()
        else if (name === "home")
            toggleHome()
    }

    // ---- Phones: the default panel (Layout Customisation) ---------------------------
    // The chosen panel takes the player's place: it opens on start, and whenever
    // every drawer and sheet is closed it slides back up. The bottom bar shows a
    // Player button in its place; the player shows only when asked for (that
    // button, the mini player, or the default panel itself put away), and Back
    // from there goes back to the default panel.
    readonly property string basePanel: Theme.touchOnly && compact
                                        && !panelHidden(SettingsController.defaultPanel)
                                        ? SettingsController.defaultPanel : "player"
    property bool playerUp: false // the player asked for, over the default panel
    function openBaseScreen() {
        if (basePanel === "home")
            homeSheet.shown = true
        else if (basePanel === "queue")
            playlistDrawer.open()
        else if (basePanel === "youtube")
            youtubeDrawer.open()
        else if (basePanel === "library")
            libraryDrawer.open()
    }
    function nothingOpen() {
        return !playlistDrawer.visible && !youtubeDrawer.visible && !libraryDrawer.visible
               && !homeSheet.shown && !settingsSheet.shown
    }
    // Something closed (`closed`: which one, "" if unknown); runs once the others have opened.
    function restoreBase(closed) {
        if (basePanel === "player" || !nothingOpen())
            return
        if (closed === basePanel) // the default panel itself put away: the player
            playerUp = true
        if (!playerUp)
            openBaseScreen()
    }
    // The bottom bar's Player button (in the default panel's place)
    readonly property bool playerInFront: basePanel !== "player" && playerUp && !anyDrawerOpen
    function togglePlayer() {
        if (playerInFront) {
            showBase()
        } else {
            playerUp = true
            closeDrawers()
        }
    }
    function showBase() {
        playerUp = false
        restoreBase("")
    }
    onBasePanelChanged: {
        playerUp = false
        Qt.callLater(restoreBase, "")
    }

    // ---- Phones: Back returns to the screen you came from -------------------------
    // Every screen change (a panel, Home, Settings or the player in front), however
    // it happened, remembers the screen left. A screen only counts once it has
    // stayed a moment, so the in-between steps of a change (a panel closing while
    // the next opens, the default panel coming back) are never remembered.
    // Back forgets the screen it leaves, except when it lands on the default panel:
    // then Back once more returns to that screen (only once, so Back can't bounce
    // between the two for ever).
    readonly property bool historyOn: Theme.touchOnly && compact
    readonly property string screenNow: settingsSheet.shown ? "settings"
                                      : homeSheet.shown ? "home"
                                      : playlistDrawer.visible ? "queue"
                                      : youtubeDrawer.visible ? "youtube"
                                      : libraryDrawer.visible ? "library" : "player"
    property string screenSettled: ""
    property var screenHistory: [] // oldest first, each screen once
    property double backAt: 0 // when Back was last pressed: the change after it is Back's
    property bool settledByBack: false // the screen in front was reached by Back
    onScreenNowChanged: if (historyOn) screenSettle.restart()
    onHistoryOnChanged: if (!historyOn) screenHistory = []
    Timer {
        id: screenSettle
        interval: 350
        onTriggered: {
            const now = window.screenNow
            const left = window.screenSettled
            if (now === left)
                return
            window.screenSettled = now
            const leftByBack = window.settledByBack
            const byBack = Date.now() - window.backAt < 1500
            window.settledByBack = byBack
            window.backAt = 0
            if (left === "" || (byBack && (now !== window.basePanel || leftByBack)))
                return
            const list = window.screenHistory.filter((name) => name !== left && name !== now)
            list.push(left)
            window.screenHistory = list.slice(-20)
        }
    }
    function previousScreen() {
        if (!historyOn)
            return ""
        for (let i = screenHistory.length - 1; i >= 0; --i) {
            const name = screenHistory[i]
            if (name !== screenNow && !panelHidden(name))
                return name
        }
        return ""
    }
    function goToPrevious() {
        const name = previousScreen()
        screenHistory = screenHistory.slice(0, screenHistory.lastIndexOf(name))
        closeDrawers()
        if (name === "player")
            playerUp = true
        else if (name === "settings")
            settingsSheet.shown = true
        else if (name === "home")
            homeSheet.shown = true
        else if (name === "queue")
            playlistDrawer.open()
        else if (name === "youtube")
            youtubeDrawer.open()
        else if (name === "library")
            libraryDrawer.open()
    }

    // Panels opened in one layout stay open in the next.
    onLayoutChanged: {
        playerRecalled = false
        if (compact) {
            settingsSheet.shown = leftOpen === "settings" || rightOpen === "settings"
            homeSheet.shown = leftOpen === "home" || rightOpen === "home"
            leftOpen = ""
            rightOpen = ""
            return
        }
        // Drawers first, then Home and Settings (they slide up over a column's panel)
        if (playlistDrawer.opened)
            setOpen("queue")
        if (youtubeDrawer.opened)
            setOpen("youtube")
        else if (libraryDrawer.opened)
            setOpen("library")
        if (homeSheet.shown)
            setOpen("home")
        if (settingsSheet.shown) {
            settingsSheet.shown = false
            setOpen("settings")
        }
        closeDrawers()
        if (layout === "half" && leftOpen !== "" && rightOpen !== "")
            leftOpen = ""
    }

    // Background tone from the playing track's cover (blended by the strength
    // set in Settings); fades on track change. Light mode blends a pastel of
    // the cover's color (same hue, kept light), so dark covers can't muddy it.
    readonly property color coverTone: Theme.isDark ? CoverPalette.color
                                       : Qt.hsla(CoverPalette.color.hslHue, CoverPalette.color.hslSaturation, 0.86, 1)
    property color tint: CoverPalette.hasColor
                         ? Qt.tint(Theme.background, Qt.rgba(coverTone.r, coverTone.g, coverTone.b,
                                                             SettingsController.coverTintStrength))
                         : Theme.background
    Behavior on tint { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }

    // The tooltip style (frontend/style) can't read Theme: it takes these.
    palette.toolTipBase: Theme.tooltip
    palette.toolTipText: Theme.text

    width: 1100
    height: 680
    minimumWidth: 360
    minimumHeight: 480
    visible: true
    title: "Tuned Chaos"
    color: Theme.background

    // Phones: the app fills the whole screen, its background behind the status
    // and navigation bars. Everything else keeps clear of them with these
    // margins (0 on the desktop).
    flags: Theme.touchOnly ? Qt.Window | Qt.ExpandedClientAreaHint | Qt.NoTitleBarBackgroundHint : Qt.Window
    topPadding: 0
    bottomPadding: 0
    leftPadding: 0
    rightPadding: 0
    readonly property real safeTop: contentItem.SafeArea.margins.top
    readonly property real safeBottom: contentItem.SafeArea.margins.bottom
    readonly property real safeLeft: contentItem.SafeArea.margins.left
    readonly property real safeRight: contentItem.SafeArea.margins.right

    Binding {
        target: Util
        property: "safeTop"
        value: window.safeTop
    }
    // Android reports the keyboard in physical pixels.
    Binding {
        target: Util
        property: "keyboardHeight"
        value: {
            const keyboard = Qt.inputMethod.keyboardRectangle
            if (!Theme.touchOnly || !Qt.inputMethod.visible || keyboard.height <= 0)
                return 0
            return Math.max(0, window.height - keyboard.y / Screen.devicePixelRatio)
        }
    }

    // How much of an item the open keyboard covers, from the item's bottom up.
    function keyboardOverlap(item) {
        if (Util.keyboardHeight <= 0)
            return 0
        return Math.max(0, item.mapToItem(null, 0, item.height).y - (height - Util.keyboardHeight))
    }

    // Background playing: closing only hides the window while a song is loaded
    // (launching the app again or the desktop's media controls bring it back).
    // Quitting closes the windows too, so a real quit is flagged first.
    property bool quitting: false

    function quitApp() {
        quitting = true
        Qt.quit()
    }

    // Closing the window: to the tray (desktop, when there is one), else, with
    // "Keep playing" on, hidden while a song is loaded; otherwise the app quits.
    readonly property bool trayOn: !Theme.touchOnly && typeof Tray !== "undefined" && Tray.available
                                   && SettingsController.closeToTray
    onClosing: (close) => {
        if (quitting)
            return
        if (trayOn || (SettingsController.backgroundPlayback && PlayerController.hasTrack)) {
            close.accepted = false
            window.hide()
        }
    }
    function hideToTray() {
        if (trayOn)
            window.hide()
    }
    onVisibleChanged: if (typeof Tray !== "undefined") Tray.windowShown = visible

    // The Now Playing buttons and the keyboard shortcuts (Ctrl+1 / 2 / 3) share these.
    // Phone size shows one panel at a time: opening one closes the others.
    function closeDrawers() {
        settingsSheet.shown = false
        homeSheet.shown = false
        playlistDrawer.close()
        youtubeDrawer.close()
        libraryDrawer.close()
    }
    function toggleDrawer(drawer) {
        if (drawer.opened) {
            drawer.close()
        } else {
            closeDrawers()
            drawer.open()
        }
    }
    function toggleQueue() {
        if (panelHidden("queue"))
            return
        if (compact)
            toggleDrawer(playlistDrawer)
        else
            playlistDocked ? closePanel("queue") : openPanel("queue")
    }
    function toggleYoutube() {
        if (panelHidden("youtube"))
            return
        if (compact)
            toggleDrawer(youtubeDrawer)
        else
            youtubeDocked ? closePanel("youtube") : openPanel("youtube")
    }
    function toggleLibrary() {
        if (panelHidden("library"))
            return
        if (compact)
            toggleDrawer(libraryDrawer)
        else
            libraryDocked ? closePanel("library") : openPanel("library")
    }
    // Settings, on a page (-1: the list; left out: where it was last).
    function openSettings(page) {
        if (page !== undefined)
            settingsPanel.openPage(page)
        if (compact) {
            closeDrawers()
            settingsSheet.shown = true
        } else {
            openPanel("settings")
        }
    }
    function closeSettings() {
        settingsSheet.shown = false
        if (leftOpen === "settings")
            leftOpen = ""
        if (rightOpen === "settings")
            rightOpen = ""
    }
    function toggleSettings() {
        settingsShown ? closeSettings() : openSettings()
    }
    function toggleHome() {
        if (panelHidden("home"))
            return
        if (compact) {
            const show = !homeSheet.shown
            closeDrawers()
            homeSheet.shown = show
        } else {
            homeDocked ? closePanel("home") : openPanel("home")
        }
    }
    // Ctrl+F: the Library's search if the Library is showing, else YouTube Music's.
    // A drawer takes the focus itself once it has opened, so a drawer that is
    // still opening gets the search focused then (searchOnOpen).
    property bool searchOnOpen: false
    function focusSearch() {
        if (libraryDocked) {
            dockedLibrary.focusSearch()
        } else if (libraryDrawer.visible) {
            drawerLibrary.focusSearch()
            searchOnOpen = !libraryDrawer.opened
        } else if (panelHidden("youtube")) {
            return
        } else if (youtubeDocked) {
            dockedYoutube.focusSearch()
        } else if (!compact) {
            openPanel("youtube")
            dockedYoutube.focusSearch()
        } else {
            if (!youtubeDrawer.visible)
                toggleYoutube()
            drawerYoutube.focusSearch()
            searchOnOpen = !youtubeDrawer.opened
        }
    }

    // Esc / Android's Back: one step back in what is in front (a page inside a
    // panel first, then the drawer or sheet closes), else the lyrics close.
    // Wide layouts: Settings, the lyrics, then the right and left panels' pages
    // (their columns stay open). Nothing to go back from: Back leaves the app.
    function backTarget() {
        if (compact) {
            // Phones: after a page inside, back to the screen you came from.
            const previous = previousScreen() !== "" ? () => goToPrevious() : null
            // The default panel (phones) is the bottom: Back only goes back inside it.
            const drawers = [[playlistDrawer, drawerPlaylist, "queue"], [youtubeDrawer, drawerYoutube, "youtube"],
                             [libraryDrawer, drawerLibrary, "library"]]
            for (const [drawer, panel, name] of drawers) {
                if (!drawer.opened)
                    continue
                if (previous)
                    return { panel: panel, close: previous }
                if (name !== basePanel)
                    return { panel: panel, close: () => drawer.close() }
                if (panel.canGoBack)
                    return { panel: panel, close: null }
                return null
            }
            if (homeSheet.shown && previous)
                return { panel: sheetHome, close: previous }
            if (settingsSheet.shown && previous)
                return { panel: settingsPanel, close: previous }
            if (homeSheet.shown && basePanel === "home") // the bottom, as above
                return sheetHome.canGoBack ? { panel: sheetHome, close: null } : null
            if (homeSheet.shown)
                return { panel: sheetHome, close: () => homeSheet.shown = false }
        }
        if (settingsShown)
            return { panel: settingsPanel, close: () => closeSettings() }
        if (nowPlaying.lyricsOpen)
            return { panel: null, close: () => nowPlaying.lyricsOpen = false }
        if (compact && !anyDrawerOpen && previousScreen() !== "")
            return { panel: null, close: () => goToPrevious() }
        if (compact && basePanel !== "player" && playerUp)
            return { panel: null, close: () => showBase() }
        if (!compact) {
            const docked = { queue: dockedPlaylist, home: dockedHome, youtube: dockedYoutube, library: dockedLibrary }
            for (const name of [rightShown, leftShown]) {
                const panel = docked[name]
                if (panel && panel.canGoBack)
                    return { panel: panel, close: null }
            }
        }
        return null
    }
    readonly property bool canGoBack: backTarget() !== null
    function goBack() {
        const target = backTarget()
        if (!target) { // phones: Back at the bottom puts the app in the background
            if (Theme.touchOnly)
                Files.minimizeApp()
            return
        }
        backAt = Date.now()
        if (target.panel && target.panel.back())
            return
        if (target.close)
            target.close()
    }

    readonly property bool dialogOpen: Util.openDialogs > 0

    AppShortcuts {
        dialogOpen: window.dialogOpen
        // (Phones: always, so Back never reaches Android, which would close the app.)
        escapeEnabled: !dialogOpen && Util.openMenus === 0
                       && (window.canGoBack || Theme.touchOnly)
        onEscapePressed: window.goBack()
        onToggleLyrics: nowPlaying.lyricsOpen = !nowPlaying.lyricsOpen
        onFocusSearch: window.focusSearch()
        onToggleQueue: window.toggleQueue()
        onToggleYoutube: window.toggleYoutube()
        onToggleLibrary: window.toggleLibrary()
        onOpenSettings: window.toggleSettings()
        onQuit: window.quitApp()
    }

    onPlaylistDockedChanged: if (playlistDocked) playlistDrawer.close()
    onYoutubeDockedChanged: if (youtubeDocked) youtubeDrawer.close()
    onLibraryDockedChanged: if (libraryDocked) libraryDrawer.close()
    onHomeDockedChanged: if (homeDocked) homeSheet.shown = false

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: window.tint }
            // Dark mode: deepens to near black; light mode: only a slight shade.
            GradientStop { position: 1.0; color: Qt.darker(window.tint, Theme.isDark ? 2.2 : 1.12) }
        }
    }

    // Panels float as rounded cards over the tinted background.
    SplitView {
        id: split
        enabled: !window.dialogOpen // (everything behind a dialog: see Util.openDialogs)

        // Equal widths for every open column (fractional while one docks / undocks).
        readonly property real openColumns: Math.max(1, playlistSlot.openness + playerSlot.openness
                                                     + rightSlot.openness)
        readonly property real share: (width - (openColumns - 1) * Theme.cardGap) / openColumns
        // A column opened or closed: back to equal widths, even after the dividers were dragged.
        readonly property string columns: [window.leftShown !== "", window.playerShown, window.rightShown].join()
        onColumnsChanged: [playlistSlot, playerSlot, rightSlot].forEach((slot) => slot.equalize())

        anchors.fill: parent
        anchors.topMargin: Theme.cardGap + window.safeTop
        anchors.leftMargin: Theme.cardGap + window.safeLeft
        anchors.rightMargin: Theme.cardGap + window.safeRight
        // Room for the navigation bar and the floating mini player under the columns.
        // The gap above the mini player grows with it, so the columns shrink and
        // grow smoothly as it slides in and out.
        anchors.bottomMargin: window.height - navBar.y + Theme.cardGap
                              + floatingMini.height * (1 + Theme.cardGap / floatingMini.fullHeight)
        orientation: Qt.Horizontal

        // The gap between cards; a small bar appears while hovered or dragged.
        handle: Item {
            implicitWidth: Theme.cardGap

            Rectangle {
                anchors.centerIn: parent
                width: 4
                height: Math.min(parent.height * 0.3, 72)
                radius: 2
                color: Theme.accent
                opacity: parent.SplitHandle.pressed ? 1 : parent.SplitHandle.hovered ? 0.6 : 0

                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
            }
        }

        // The left-hand column; the right-hand one is the same (see SideSlot).
        SideSlot {
            id: playlistSlot
            leftColumn: true
            minimumWidth: 240
            SplitView.fillWidth: !window.playerShown && window.rightShown === ""
        }

        // The player, pushed out by the panel opened last when there's no room (half layout)
        DockSlot {
            id: playerSlot
            docked: window.playerShown
            share: split.share
            minimumWidth: 280
            leftSide: !window.isLeft(window.lastOpened)
            SplitView.fillWidth: window.playerShown

            NowPlayingPanel {
                id: nowPlaying
                objectName: "nowPlaying"
                anchors.fill: parent
                edgeTop: window.compact ? Theme.cardGap + window.safeTop : 0
                edgeSide: window.compact ? Theme.cardGap + Math.max(window.safeLeft, window.safeRight) : 0
                covered: window.compact && window.anyDrawerOpen
                onDetailsRequested: detailsDialog.show(PlayerController.source)
                onEqualizerRequested: window.openSettings(settingsPanel.equalizerPage)
                onQuitRequested: window.quitApp()
            }

            // Songs dragged from the Library or YouTube: dropped here, they join the Queue.
            // (Phone size: the drawers' mini players take them instead.)
            DropHint {
                accepts: !window.compact
                onDropped: SongDrag.deliver("", -1)
            }
        }

        SideSlot {
            id: rightSlot
            leftColumn: false
            minimumWidth: 320
            SplitView.fillWidth: !window.playerShown && docked
        }
    }

    // A column beside the player. The Queue, YouTube and Library take turns in it
    // (swapping cross-fades in place); Home and Settings slide up from the bottom
    // over what it shows, and back down. Which panels use which column is set in
    // Layout Customisation; the panels move into their column's places (faces,
    // homeCard, settingsCard).
    component SideSlot: DockSlot {
        id: sideSlot

        property bool leftColumn: true
        readonly property string shown: leftColumn ? window.leftShown : window.rightShown
        // The panel opened last (the edge swipe brings it back)
        property string lastPanel: ""
        // The panel showing under Home / Settings ("": none; kept while they close)
        property string face: ""
        property string previous: ""
        readonly property alias faces: facesItem
        readonly property Item homeCard: homeCardItem.card
        readonly property Item settingsCard: settingsCardItem.card
        // Under Home or Settings, clicks would reach the panel's rows (see NowPlayingPanel.covered)
        readonly property bool faceEnabled: homeCardItem.down > 0 && settingsCardItem.down > 0

        function isFace(name) {
            return name === "queue" || name === "youtube" || name === "library"
        }
        onShownChanged: {
            if (isFace(shown))
                face = shown
            else if (shown !== "" && !(previous === "home" || previous === "settings"))
                face = isFace(previous) ? previous : "" // Home over nothing shows nothing under it
            if (shown !== "")
                lastPanel = shown
            previous = shown
        }

        docked: shown !== ""
        share: split.share
        leftSide: leftColumn
        // (Song rows keep their own swipe, delete: there only the header and empty space swipe)
        swipeEnabled: window.layout === "half" && !(face === "youtube" && shown === "youtube" && dockedYoutube.swipeBlocked)
                      && !(face === "library" && shown === "library" && dockedLibrary.swipeBlocked)
        swipeAnywhere: shown !== "queue" && shown !== "home"
        onSwipedAway: window.closePanel(shown !== "" ? shown : lastPanel)

        Item {
            id: facesItem
            anchors.fill: parent
        }

        // Home, then Settings over it: solid cards in the window's tint
        SlideCard {
            id: homeCardItem
            z: 3
            up: sideSlot.shown === "home"
            keyboardAware: true
        }
        SlideCard {
            id: settingsCardItem
            z: 4
            up: sideSlot.shown === "settings"
        }
    }

    // A card that slides up from the bottom of a column over its panel, and back down.
    // Panels go in `card` (the host clips it while it slides).
    component SlideCard: Item {
        id: slide

        property bool up: false
        property bool keyboardAware: false
        readonly property alias card: cardRect
        readonly property alias down: cardRect.down
        readonly property alias color: cardRect.color

        anchors.fill: parent
        clip: true
        visible: cardRect.y < height

        Rectangle {
            id: cardRect
            // 0: in place, 1: below the column. Animated as a fraction, so the
            // column changing size (opening, resizing) doesn't move it.
            property real down: slide.up ? 0 : 1
            width: parent.width
            height: parent.height - (slide.keyboardAware ? window.keyboardOverlap(parent) : 0)
            y: down * (height + Theme.cardGap)
            radius: Theme.radiusCard
            color: Theme.isDark ? Qt.darker(window.tint, 1.6) : Qt.tint(window.tint, "#b3ffffff")
            Behavior on down { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingPanel } }
        }
    }

    function slotFor(name) {
        return isLeft(name) ? playlistSlot : rightSlot
    }

    // The column panels (each in its column's place, see SideSlot)
    PlaylistPanel {
        id: dockedPlaylist
        readonly property var slot: window.slotFor("queue")
        readonly property bool current: slot.face === "queue"
        parent: slot.faces
        anchors.fill: parent
        acceptsDrops: true
        showPinButton: true
        pinned: window.leftPinned === "queue" || window.rightPinned === "queue"
        showCloseButton: !pinned
        enabled: slot.faceEnabled
        onPinToggled: window.togglePin("queue")
        onCloseRequested: window.closePanel("queue")
        onDetailsRequested: (path) => detailsDialog.show(path)
        onImportM3uRequested: window.importM3u()
        onExportM3uRequested: (id, name) => window.exportM3u(id, name)
        // Swapping: the outgoing panel fades out while this one fades and slides in.
        opacity: current ? 1 : 0
        visible: current || opacity > 0
        z: current ? 1 : 0
        transform: Translate { x: (1 - dockedPlaylist.opacity) * 24 * (dockedPlaylist.slot.leftColumn ? -1 : 1) }
        Behavior on opacity { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingPanel } }
    }
    YouTubePanel {
        id: dockedYoutube
        readonly property var slot: window.slotFor("youtube")
        readonly property bool current: slot.face === "youtube"
        parent: slot.faces
        anchors.fill: parent
        enabled: slot.faceEnabled
        pinned: window.leftPinned === "youtube" || window.rightPinned === "youtube"
        showCloseButton: !pinned
        onPinToggled: window.togglePin("youtube")
        onCloseRequested: window.closePanel("youtube")
        onSettingsRequested: window.openSettings()
        opacity: current ? 1 : 0
        visible: current || opacity > 0
        z: current ? 1 : 0
        transform: Translate { x: (1 - dockedYoutube.opacity) * 24 * (dockedYoutube.slot.leftColumn ? -1 : 1) }
        Behavior on opacity { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingPanel } }
    }
    LibraryPanel {
        id: dockedLibrary
        readonly property var slot: window.slotFor("library")
        readonly property bool current: slot.face === "library"
        parent: slot.faces
        anchors.fill: parent
        enabled: slot.faceEnabled
        pinned: window.leftPinned === "library" || window.rightPinned === "library"
        showCloseButton: !pinned
        onPinToggled: window.togglePin("library")
        onCloseRequested: window.closePanel("library")
        onDetailsRequested: (path) => detailsDialog.show(path)
        onEditTagsRequested: (path) => detailsDialog.show(path, true)
        onSettingsRequested: window.openSettings()
        onFoldersSettingsRequested: window.openSettings(settingsPanel.libraryPage)
        onCurrentChanged: if (current) chooseSource() // opened: the choice between the libraries
        opacity: current ? 1 : 0
        visible: current || opacity > 0
        z: current ? 1 : 0
        transform: Translate { x: (1 - dockedLibrary.opacity) * 24 * (dockedLibrary.slot.leftColumn ? -1 : 1) }
        Behavior on opacity { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingPanel } }
    }
    HomePanel {
        id: dockedHome
        parent: window.slotFor("home").homeCard
        anchors.fill: parent
        backdrop: parent ? parent.color : "transparent"
        pinned: window.leftPinned === "home" || window.rightPinned === "home"
        showCloseButton: !pinned
        onPinToggled: window.togglePin("home")
        onCloseRequested: window.closePanel("home")
    }

    // Half layout: drag in from an empty window edge to bring that side's panel back.
    EdgeSwipe {
        anchors.left: parent.left
        enabled: window.layout === "half" && window.leftShown === "" && window.sidePanels(true).length > 0
        inward: 1
        onTriggered: window.openPanel(window.edgePanel(true))
    }
    EdgeSwipe {
        anchors.right: parent.right
        enabled: window.layout === "half" && window.rightShown === "" && window.sidePanels(false).length > 0
        inward: -1
        onTriggered: window.openPanel(window.edgePanel(false))
    }
    // The column's panel opened last, else its first one
    function edgePanel(left) {
        const panels = sidePanels(left)
        const last = (left ? playlistSlot : rightSlot).lastPanel
        return panels.includes(last) ? last : panels[0]
    }

    // Whenever the player is out of sight (pushed out in the half layout, or
    // covered by a panel at phone size), a floating mini player above the
    // navigation bar stands in for it; tap the cover or title to bring it back.
    // (A panel let go to close counts as closed: what it covered shouldn't wait for it.)
    readonly property bool queueDrawerOpen: playlistDrawer.visible && !playlistPull.closing
    readonly property bool youtubeDrawerOpen: youtubeDrawer.visible && !youtubePull.closing
    readonly property bool libraryDrawerOpen: libraryDrawer.visible && !libraryPull.closing
    readonly property bool homeSheetOpen: homeSheet.shown && !homePull.closing
    readonly property bool settingsSheetOpen: settingsSheet.shown && !settingsPull.closing
    readonly property bool anyDrawerOpen: queueDrawerOpen || youtubeDrawerOpen || libraryDrawerOpen
                                          || homeSheetOpen || settingsSheetOpen
    MiniPlayer {
        id: floatingMini
        objectName: "floatingMini"
        enabled: !window.dialogOpen
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: navBar.top
        anchors.leftMargin: Theme.cardGap + window.safeLeft
        anchors.rightMargin: Theme.cardGap + window.safeRight
        anchors.bottomMargin: Theme.cardGap
        height: implicitHeight
        radius: Theme.radiusCard
        z: 5
        active: (window.layout === "half" && !window.playerShown) || (window.compact && window.anyDrawerOpen)
        acceptsDrops: true
        onOpenPlayerRequested: {
            if (window.compact) {
                window.playerUp = true
                window.closeDrawers()
            } else {
                window.showPlayer()
            }
        }
    }

    // The way around: YouTube Music, Queue, Home, Library and Settings, always at the bottom.
    NavBar {
        id: navBar
        objectName: "navBar"
        enabled: !window.dialogOpen
        readonly property real room: parent.width - 2 * Theme.cardGap - window.safeLeft - window.safeRight

        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.cardGap + window.safeBottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: (window.safeLeft - window.safeRight) / 2
        width: window.compact ? room : Math.min(room, 560)
        height: implicitHeight
        z: 5
        // Phones: the default panel's button gives way to the player's
        panels: SettingsController.panelOrder.filter((panel) => !window.panelHidden(panel))
                .map((panel) => panel === window.basePanel ? "player" : panel)
        playerOpen: window.playerInFront
        homeOpen: window.homeDocked || window.homeSheetOpen
        queueOpen: window.playlistDocked || window.queueDrawerOpen
        youtubeOpen: window.youtubeDocked || window.youtubeDrawerOpen
        libraryOpen: window.libraryDocked || window.libraryDrawerOpen
        settingsOpen: window.settingsDocked || window.settingsSheetOpen
        onPlayerClicked: window.togglePlayer()
        onHomeClicked: window.toggleHome()
        onQueueClicked: window.toggleQueue()
        onYoutubeClicked: window.toggleYoutube()
        onLibraryClicked: window.toggleLibrary()
        onSettingsClicked: window.toggleSettings()
    }

    // Phone size: the panels end above the mini player and the navigation bar.
    readonly property real drawerHeight: navBar.y - (PlayerController.hasTrack ? floatingMini.fullHeight + Theme.cardGap : 0)

    // Phone size: the Queue slides up over the player, like every panel here.
    SlidePanel {
        id: playlistDrawer
        objectName: "playlistDrawer"
        onAboutToShow: { playlistPull.reset(); window.playerUp = false }
        onClosed: Qt.callLater(window.restoreBase, "queue")

        DrawerCard {
            drawer: playlistDrawer
            pull: playlistPull.pull

            PullToClose {
                id: playlistPull
                onPulledDown: playlistDrawer.close()

                PlaylistPanel {
                    id: drawerPlaylist
                    anchors.fill: parent
                    showCloseButton: true
                    onCloseRequested: playlistDrawer.close()
                    onDetailsRequested: (path) => detailsDialog.show(path)
                    onImportM3uRequested: window.importM3u()
                    onExportM3uRequested: (id, name) => window.exportM3u(id, name)
                }
            }
        }
    }

    // The YouTube Music card, sliding up.
    SlidePanel {
        id: youtubeDrawer
        objectName: "youtubeDrawer"
        onAboutToShow: { youtubePull.reset(); window.playerUp = false }
        onOpened: if (window.searchOnOpen) { window.searchOnOpen = false; drawerYoutube.focusSearch() }
        onClosed: {
            window.searchOnOpen = false
            Qt.callLater(window.restoreBase, "youtube")
        }

        DrawerCard {
            drawer: youtubeDrawer
            pull: youtubePull.pull

            PullToClose {
                id: youtubePull
                onPulledDown: youtubeDrawer.close()

                YouTubePanel {
                    id: drawerYoutube
                    objectName: "youtubePanel"
                    anchors.fill: parent
                    showPinButton: false
                    showCloseButton: true
                    onCloseRequested: youtubeDrawer.close()
                    onSettingsRequested: window.openSettings()
                }
            }
        }
    }

    // The local library, sliding up.
    SlidePanel {
        id: libraryDrawer
        objectName: "libraryDrawer"
        onAboutToShow: { libraryPull.reset(); window.playerUp = false; drawerLibrary.chooseSource() }
        onOpened: if (window.searchOnOpen) { window.searchOnOpen = false; drawerLibrary.focusSearch() }
        onClosed: {
            window.searchOnOpen = false
            Qt.callLater(window.restoreBase, "library")
        }

        DrawerCard {
            drawer: libraryDrawer
            pull: libraryPull.pull

            PullToClose {
                id: libraryPull
                onPulledDown: libraryDrawer.close()

                LibraryPanel {
                    id: drawerLibrary
                    objectName: "libraryPanel"
                    anchors.fill: parent
                    showPinButton: false
                    onCloseRequested: libraryDrawer.close()
                    onDetailsRequested: (path) => detailsDialog.show(path)
                    onEditTagsRequested: (path) => detailsDialog.show(path, true)
                    onSettingsRequested: window.openSettings()
                    onFoldersSettingsRequested: window.openSettings(settingsPanel.libraryPage)
                }
            }
        }
    }

    // Phone size: Settings as a sheet sliding up above the mini player and the
    // navigation bar (the drawers' height).
    Item {
        width: window.width
        height: window.drawerHeight
        clip: true
        z: 4
        enabled: !window.dialogOpen
        visible: settingsSheet.y < height

        Rectangle {
            id: settingsSheet
            property bool shown: false
            onShownChanged: {
                if (shown) {
                    settingsPull.reset()
                    window.playerUp = false
                } else {
                    Qt.callLater(window.restoreBase, "settings")
                }
            }
            property real down: shown ? 0 : 1 // as for settingsCard
            x: Theme.cardGap + window.safeLeft
            width: parent.width - 2 * Theme.cardGap - window.safeLeft - window.safeRight
            height: parent.height - 2 * Theme.cardGap - window.safeTop - window.keyboardOverlap(parent)
            y: Theme.cardGap + window.safeTop + down * (parent.height - Theme.cardGap - window.safeTop) + settingsPull.pull
            radius: Theme.radiusCard
            color: Theme.isDark ? Qt.darker(window.tint, 1.6) : Qt.tint(window.tint, "#b3ffffff")

            Behavior on down { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingPanel } }

            PullToClose {
                id: settingsPull
                onPulledDown: window.closeSettings()
            }
        }
    }

    // Phone size: Home as a sheet sliding up, like Settings.
    Item {
        width: window.width
        height: window.drawerHeight
        clip: true
        z: 4
        enabled: !window.dialogOpen
        visible: homeSheet.y < height

        Rectangle {
            id: homeSheet
            property bool shown: false
            onShownChanged: {
                if (shown) {
                    homePull.reset()
                    window.playerUp = false
                } else {
                    Qt.callLater(window.restoreBase, "home")
                }
            }
            property real down: shown ? 0 : 1 // as for settingsCard
            x: Theme.cardGap + window.safeLeft
            width: parent.width - 2 * Theme.cardGap - window.safeLeft - window.safeRight
            height: parent.height - 2 * Theme.cardGap - window.safeTop
            y: Theme.cardGap + window.safeTop + down * (parent.height - Theme.cardGap - window.safeTop) + homePull.pull
            radius: Theme.radiusCard
            color: Theme.isDark ? Qt.darker(window.tint, 1.6) : Qt.tint(window.tint, "#b3ffffff")

            Behavior on down { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingPanel } }

            PullToClose {
                id: homePull
                onPulledDown: homeSheet.shown = false

                HomePanel {
                    id: sheetHome
                    objectName: "homePanel"
                    anchors.fill: parent
                    backdrop: homeSheet.color
                    showPinButton: false
                    showCloseButton: true
                    onCloseRequested: homeSheet.shown = false
                }
            }
        }
    }

    // One Settings panel: in the right-hand column, or the sheet at phone size.
    SettingsPanel {
        id: settingsPanel
        objectName: "settingsPanel"
        parent: window.compact ? settingsPull.contentItem : window.slotFor("settings").settingsCard
        anchors.fill: parent
        onCloseRequested: window.closeSettings()
        onClearHistoryRequested: clearHistoryDialog.ask(qsTr("Clear your listening history?"),
                                                        qsTr("Every song remembered so far is forgotten. Your music itself stays."))
        onAddFolderRequested: folderPicker.pick(qsTr("Add a music folder"), qsTr("Add this folder"), "",
                                                (folder) => LocalLibraryController.addFolder(folder))
        onExcludeFolderRequested: (startFolder) => folderPicker.pick(
            qsTr("Leave a folder out of the library"), qsTr("Exclude this folder"), startFolder,
            (folder) => SettingsController.addLibraryExcluded(folder))
    }

    // A strip along a window edge: dragging inward from it opens that side's panel.
    component EdgeSwipe: Item {
        property int inward: 1 // +1: drag right (left edge), -1: drag left (right edge)
        signal triggered()

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Theme.cardGap + 6
        z: 2

        DragHandler {
            property bool done: false

            enabled: !SongDrag.active

            target: null
            xAxis.enabled: true
            yAxis.enabled: false
            onActiveChanged: done = false
            onTranslationChanged: {
                if (active && !done && translation.x * parent.inward > 40) {
                    done = true
                    parent.triggered()
                }
            }
        }
    }

    // Phone size: a panel sliding up from the bottom, ending above the mini player
    // and the navigation bar (which stay usable). Esc, Back, a drag down or the bar
    // closes it: nothing around it does.
    component SlidePanel: Popup {
        property real position: 0 // 0 closed, 1 open
        enabled: !window.dialogOpen

        x: 0
        y: 0
        width: window.width
        height: window.drawerHeight
        padding: 0
        modal: false
        dim: false
        focus: true
        clip: true // the card comes from under the mini player
        closePolicy: Popup.NoAutoClose // Esc / Back: window.goBack()
        background: Item {}
        enter: Transition {
            NumberAnimation { property: "position"; to: 1.0; duration: Theme.animPanel; easing.type: Theme.easingPanel }
        }
        exit: Transition {
            NumberAnimation { property: "position"; to: 0.0; duration: Theme.anim; easing.type: Easing.OutCubic }
        }
    }

    // Phone size: drag a panel down from anywhere to put it away, as DockSlot does
    // sideways. Lists inside scroll first; at their top they let go of a downward
    // drag and this takes it. Its content stays put; the overshoot (`pull`) moves
    // the card instead, and springs back by itself unless pulled far or fast enough.
    component PullToClose: Flickable {
        id: pullFlick

        signal pulledDown()

        // Dragged past its edge, a Flickable reports half the distance.
        readonly property real flickPull: Math.max(0, -2 * verticalOvershoot)
        property real closingPull: -1 // on its way out; -1: following the finger
        readonly property bool closing: closingPull >= 0
        readonly property real pull: closingPull >= 0 ? closingPull : flickPull

        function reset() {
            away.stop()
            closingPull = -1
        }

        anchors.fill: parent
        contentWidth: width
        contentHeight: height
        interactive: window.compact && !SongDrag.active
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.DragOverBounds
        boundsMovement: Flickable.StopAtBounds
        // While it settles a Flickable keeps the next touch for itself: quickly, then.
        rebound: Transition {
            NumberAnimation { properties: "x,y"; duration: 100; easing.type: Easing.OutCubic }
        }
        onDraggingChanged: {
            if (!dragging && flickPull > 0 && !away.running
                    && (flickPull > height * 0.2 || -verticalVelocity > 800)) {
                closingPull = flickPull
                away.start()
            }
        }

        NumberAnimation {
            id: away
            target: pullFlick
            property: "closingPull"
            to: pullFlick.height + 2 * Theme.cardGap
            duration: Theme.anim
            easing.type: Theme.easing
            onFinished: pullFlick.pulledDown()
        }
    }

    // A drawer's panel: an inset rounded card on a solid tinted background that
    // grows slightly and brightens as the drawer opens.
    component DrawerCard: Rectangle {
        required property SlidePanel drawer
        property real pull: 0 // dragged down (PullToClose)

        transformOrigin: Item.Bottom
        transform: Translate { y: pull + (1 - drawer.position) * (height + 2 * Theme.cardGap) }
        anchors.fill: parent
        anchors.margins: Theme.cardGap
        anchors.topMargin: Theme.cardGap + window.safeTop
        anchors.leftMargin: Theme.cardGap + window.safeLeft
        anchors.rightMargin: Theme.cardGap + window.safeRight
        radius: Theme.radiusCard
        color: Theme.isDark ? Qt.darker(window.tint, 1.6) : Qt.tint(window.tint, "#b3ffffff")
        scale: 0.96 + 0.04 * drawer.position
        opacity: 0.4 + 0.6 * drawer.position
    }

    // Drag & drop folders anywhere on the window, also over open drawers and
    // dialogs (it sits in the popup layer, above them; it only takes drags, so
    // clicks still reach what is underneath). Songs always go to the Queue.
    DropOverlay {
        parent: Overlay.overlay
        anchors.fill: parent
        z: 1000
        onUrlsDropped: {
            PlaylistsController.view("") // show the Queue, whatever list was open
            window.showPlaylistPanel()
        }
        onPlaylistsDropped: window.showPlaylistPanel() // the import opens the new playlist
    }

    // The card following the pointer while songs are dragged (over drawers too)
    DragCard {
        parent: Overlay.overlay
        z: 2000
    }

    function showPlaylistPanel() {
        if (panelHidden("queue"))
            return
        if (!compact) {
            if (!playlistDocked)
                openPanel("queue")
        } else {
            closeDrawers()
            playlistDrawer.open()
        }
    }

    // M3U playlists through the app's own file picker.
    function importM3u() {
        folderPicker.pick(qsTr("Import an M3U playlist"), "", "", (file) => PlaylistsController.importM3u(file),
                          { files: ["*.m3u", "*.m3u8"] })
    }
    function exportM3u(id, name) {
        folderPicker.pick(qsTr("Export as M3U"), qsTr("Save"), "", (file) => PlaylistsController.exportM3u(id, file),
                          { save: true, files: ["*.m3u", "*.m3u8"], name: name.replace(/[\/]/g, "-") + ".m3u8" })
    }

    TrackDetailsDialog {
        id: detailsDialog
        objectName: "detailsDialog"
    }

    // Playlist naming / deleting (asked for by PlaylistsController)
    NameDialog {
        id: nameDialog
        onAccepted: (name) => PlaylistsController.submitName(name)
    }

    ConfirmDialog {
        id: confirmDialog
        onConfirmed: PlaylistsController.confirmDelete()
    }

    Connections {
        target: PlaylistsController
        function onNamePrompt(title, initialName) { nameDialog.ask(title, initialName) }
        function onDeletePrompt(name) {
            confirmDialog.ask(qsTr("Delete “%1”?").arg(name),
                              qsTr("The playlist is removed. The songs themselves stay where they are."))
        }
        function onNotice(text) { toast.show(text) }
    }

    Connections {
        target: LocalLibraryController
        function onNotice(text) { toast.show(text) }
    }

    Connections {
        target: HostedController
        function onNotice(text) { toast.show(text) }
    }

    Toast {
        id: toast
        bottomOffset: Theme.padding * 1.5 + window.safeBottom
    }

    // The app's folder chooser (Library: add folder; Settings: exclude folder)
    FolderPicker {
        id: folderPicker
        objectName: "folderPicker"
    }

    // Playback problems (e.g. YouTube limiting requests) in full; the line
    // under the title only has room for the start.
    Connections {
        target: PlayerController
        function onErrorStringChanged() {
            if (PlayerController.errorString !== "")
                toast.show(PlayerController.errorString)
        }
    }

    ConfirmDialog {
        id: clearHistoryDialog
        confirmText: qsTr("Clear")
        onConfirmed: HistoryController.clear()
    }

    // A new version of the app
    UpdateDialog {
        id: updateDialog
        objectName: "updateDialog"
        updater: typeof AppUpdater !== "undefined" ? AppUpdater : null
    }
}
