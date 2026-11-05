pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The YouTube Music panel: Home / Search / Library / Saved tabs.
// Playback goes through yt-dlp; without it the panel explains what is missing.
Rectangle {
    id: root

    property bool showPinButton: true
    property bool pinned: false
    property bool showCloseButton: false
    property int tab: 0
    // A drag inside must not close the drawer holding this panel (see YtHomeView).
    readonly property bool swipeBlocked: homeView.swipeBlocked || artistView.swipeBlocked || tabRow.busy
    // An artist's page or an album / playlist is open over the tabs.
    readonly property bool overlayOpen: YouTubeController.artistOpen || YouTubeController.collectionOpen

    // A tab picked (or Ctrl+F): back from any open artist / album first.
    function showTab(index) {
        YouTubeController.closeCollection()
        YouTubeController.closeArtist()
        tab = index
    }
    // Back / Esc: out of the album, then the artist (false: nothing open).
    readonly property bool canGoBack: overlayOpen
    function back() {
        if (YouTubeController.collectionOpen)
            YouTubeController.closeCollection()
        else if (YouTubeController.artistOpen)
            YouTubeController.closeArtist()
        else
            return false
        return true
    }
    // Ctrl+F: the Search tab, ready to type.
    function focusSearch() {
        showTab(1)
        searchView.focusField()
    }

    signal pinToggled()
    signal closeRequested()
    signal settingsRequested()

    function notice(text) {
        toastLabel.text = text
        toast.shown = true
        toastTimer.restart()
    }

    color: Theme.panelShade // softens the cover tint behind it
    radius: Theme.radiusCard
    border.color: Theme.border

    Connections {
        target: YouTubeController
        function onNotice(text) { root.notice(text) }
    }

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

                Icon {
                    name: "cloud"
                    size: 14
                    color: Theme.accent
                }

                Label {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("YouTube Music")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeLarge
                    elide: Text.ElideRight
                }

                // Shown only when playback can't work
                Rectangle {
                    visible: !YouTubeController.available
                    implicitWidth: warningLabel.implicitWidth + 16
                    implicitHeight: warningLabel.implicitHeight + 6
                    radius: height / 2
                    color: Theme.errorSoft

                    Label {
                        id: warningLabel
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: qsTr("yt-dlp not found")
                        color: Theme.error
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    HoverHandler { id: warningHover }
                    ToolTip.visible: warningHover.hovered
                    ToolTip.text: qsTr("Install yt-dlp to play YouTube songs (search and browsing still work).")
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
                    onClicked: root.closeRequested()
                }
            }
        }

        // Tabs
        TabRow {
            id: tabRow
            Layout.fillWidth: true
            Layout.margins: Theme.padding
            Layout.bottomMargin: 4
            current: root.overlayOpen ? -1 : root.tab
            tabs: [
                { icon: "compass", label: qsTr("Home") },
                { icon: "search", label: qsTr("Search") },
                { icon: "listMusic", label: qsTr("Library") },
                { icon: "bookmark", label: qsTr("Saved") }
            ]
            onTabPicked: (index) => root.showTab(index)
        }

        // Tab contents: the new tab slides in from the side it is on, the old one
        // slides out the other way; both fade.
        Item {
            id: pages
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            // The tabs; they step back while an artist / album is open over them.
            Item {
                anchors.fill: parent
                opacity: root.overlayOpen ? 0 : 1
                visible: opacity > 0
                scale: root.overlayOpen ? 0.97 : 1

                Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                Behavior on scale { NumberAnimation { duration: Theme.animSlow; easing.type: Theme.easingPanel } }

                YtHomeView {
                    id: homeView
                    anchors.fill: parent
                    opacity: root.tab === 0 ? 1 : 0
                    visible: opacity > 0
                    transform: PageShift { page: 0 }
                    Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                }

                YtSearchView {
                    id: searchView
                    anchors.fill: parent
                    opacity: root.tab === 1 ? 1 : 0
                    visible: opacity > 0
                    transform: PageShift { page: 1 }
                    Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                }

                YtLibraryView {
                    anchors.fill: parent
                    onSettingsRequested: root.settingsRequested()
                    opacity: root.tab === 2 ? 1 : 0
                    visible: opacity > 0
                    transform: PageShift { page: 2 }
                    Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                }

                YtSavedLinksView {
                    anchors.fill: parent
                    opacity: root.tab === 3 ? 1 : 0
                    visible: opacity > 0
                    transform: PageShift { page: 3 }
                    Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                }
            }

            YtOverlay {
                shown: YouTubeController.artistOpen && !YouTubeController.collectionOpen
                YtArtistView {
                    id: artistView
                    anchors.fill: parent
                }
            }

            // Above the artist's page: going back from an album returns to the artist.
            YtOverlay {
                shown: YouTubeController.collectionOpen
                YtCollectionView {
                    anchors.fill: parent
                }
            }
        }
    }

    // Horizontal offset of a tab page: 0 when shown, else off to its side.
    component PageShift: Translate {
        required property int page
        x: root.tab === page ? 0 : (page < root.tab ? -48 : 48)
        Behavior on x { NumberAnimation { duration: Theme.animSlow; easing.type: Theme.easingPanel } }
    }

    // A page over the tabs (an artist, an album): slides in from the right.
    component YtOverlay: Item {
        id: overlay
        required property bool shown
        anchors.fill: parent
        opacity: shown ? 1 : 0
        visible: opacity > 0
        transform: Translate {
            x: overlay.shown ? 0 : 56
            Behavior on x { NumberAnimation { duration: Theme.animSlow; easing.type: Theme.easingPanel } }
        }
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
    }

    // Small notice at the bottom ("coming in a later phase", ...)
    Rectangle {
        id: toast

        property bool shown: false

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: shown ? Theme.padding * 1.5 : -height
        width: Math.min(parent.width - 2 * Theme.padding, toastLabel.implicitWidth + 32)
        height: toastLabel.implicitHeight + 18
        radius: height / 2
        color: Theme.surfaceAlt
        border.color: Theme.border
        opacity: shown ? 1 : 0

        Behavior on anchors.bottomMargin { NumberAnimation { duration: Theme.anim; easing.type: Theme.easing } }
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }

        Label {
            id: toastLabel
            textFormat: Text.PlainText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, toast.width - 24)
            color: Theme.text
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
        }

        Timer {
            id: toastTimer
            interval: 2600
            onTriggered: toast.shown = false
        }
    }
}
