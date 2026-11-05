pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One library song: cover, title, artist · album · length, and play / "⋮"
// buttons on hover. A click plays the list it's in from it (all songs, the
// album, the artist...) without touching the Queue; hold and drag to drop it
// on the Queue or the player. The song that is playing is tinted
// and shows bouncing bars on its cover.
Rectangle {
    id: root

    required property int index
    required property string path
    required property string title
    required property string artist
    required property string album
    required property var duration
    property int list: LocalLibraryController.SongsList // the list it's shown in (Songs tab, album / artist, folder)
    property bool showAlbum: true

    readonly property bool isCurrent: PlayerController.source === root.path
    readonly property bool isPlaying: isCurrent && PlayerController.playing
    // Hover buttons stay while the menu is open (the menu takes the hover).
    readonly property bool menuOpen: menuLoader.item !== null && (menuLoader.item as LibrarySongMenu).visible
    readonly property bool showButtons: hover.hovered || menuOpen

    signal detailsRequested(string path)
    signal editTagsRequested(string path)

    function playOrToggle() {
        if (root.isCurrent)
            PlayerController.togglePlayPause()
        else
            LocalLibraryController.play(root.list, root.index)
    }

    // Created on first use: one menu per row would be wasteful.
    Loader {
        id: menuLoader
        active: false
        sourceComponent: LibrarySongMenu {
            list: root.list
            index: root.index
            path: root.path
            onDetailsRequested: (path) => root.detailsRequested(path)
            onEditTagsRequested: (path) => root.editTagsRequested(path)
        }
    }

    implicitHeight: 56
    radius: Theme.radius
    color: isCurrent ? (hover.hovered ? Theme.currentRowHover : Theme.currentRow)
         : hover.hovered ? Theme.hover : "transparent"

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    HoverHandler {
        id: hover
    }

    TapHandler {
        // (A quick second tap doesn't pause what the first one played.)
        onTapped: if (tapCount === 1) root.playOrToggle()
    }

    // Hold and drag onto the Queue or the player
    DragSource {
        payload: function() {
            return { items: [{ path: root.path }], title: root.title, subtitle: root.artist,
                     cover: Util.coverSource(root.path, "") }
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad // (a finger's tap would count as this too)
        onTapped: {
            menuLoader.active = true
            (menuLoader.item as LibrarySongMenu).popup()
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: Theme.padding

        Rectangle {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            radius: Theme.radius
            color: Theme.surfaceAlt
            clip: true

            Icon {
                anchors.centerIn: parent
                name: "music"
                size: 13
                color: Theme.textDim
            }

            Image {
                anchors.fill: parent
                source: Util.coverSource(root.path, "")
                sourceSize: Qt.size(80, 80)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: status === Image.Ready ? 1 : 0
            }

            // "Now playing" overlay
            Rectangle {
                anchors.fill: parent
                color: "#99000000"
                opacity: root.isCurrent ? 1 : 0
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: Theme.anim } }

                PlayingBars {
                    anchors.centerIn: parent
                    playing: root.isPlaying
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.title
                color: root.isCurrent ? Theme.accent : Theme.text
                font.pixelSize: Theme.fontSize
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: [root.artist, root.showAlbum ? root.album : ""].filter(s => s !== "").join("  ·  ")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }
        }

        Label {
            textFormat: Text.PlainText
            visible: !root.showButtons && !root.isCurrent
            text: Util.formatTime(root.duration)
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
            font.features: { "tnum": 1 }
        }

        // The playing song keeps its pause button visible; the rest show on hover.
        PillButton {
            iconName: root.isPlaying ? "pause" : "play"
            iconSize: 11
            implicitWidth: 32
            implicitHeight: 32
            transparentIdle: !root.isCurrent
            active: root.isCurrent
            visible: root.showButtons || root.isCurrent
            ToolTip.visible: hovered
            ToolTip.text: root.isPlaying ? qsTr("Pause") : qsTr("Play")
            onClicked: root.playOrToggle()
        }

        PillButton {
            id: moreButton
            iconName: "more"
            iconSize: 12
            implicitWidth: 32
            implicitHeight: 32
            transparentIdle: true
            visible: root.showButtons || Theme.touchOnly
            ToolTip.visible: hovered
            ToolTip.text: qsTr("More")
            onClicked: {
                menuLoader.active = true
                // Parent the menu to the row: the button may hide while it is open.
                const pos = moreButton.mapToItem(root, 0, moreButton.height)
                const menu = menuLoader.item as LibrarySongMenu
                menu.popup(root, pos.x, pos.y)
            }
        }
    }
}
