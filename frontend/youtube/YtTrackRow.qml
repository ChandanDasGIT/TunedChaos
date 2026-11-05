pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One YouTube song: thumbnail, title, artists · duration, and play /
// add-to-playlist / save buttons that appear on hover. A tap plays
// (phones: only "⋮" and the playing song's pause show);
// hold and drag to drop it on the Queue or the player.
// The song that is playing is tinted, shows bouncing bars on its thumbnail,
// and its play button becomes pause (always visible).
// `song` is a YouTubeController song map.
Rectangle {
    id: root

    required property var song
    property bool showSave: true
    property bool showRemove: false
    // In an album / playlist: playing the song plays that list from it
    // (otherwise the song plays alone, followed by its Mix).
    property var listSongs: null
    property int listIndex: -1
    property string listTitle: ""

    readonly property bool isCurrent: (root.song.videoId || "") !== ""
                                      && PlayerController.source === "ytmusic:" + root.song.videoId
    readonly property bool isPlaying: isCurrent && PlayerController.playing
    // Hover buttons stay while the menu is open (the menu takes the hover).
    readonly property bool menuOpen: menuLoader.item !== null && (menuLoader.item as YtSongMenu).visible
    readonly property bool showButtons: !Theme.touchOnly && (hover.hovered || menuOpen)

    signal removeRequested()

    // Created on first use: one menu per row would be wasteful.
    Loader {
        id: menuLoader
        active: false
        sourceComponent: YtSongMenu {
            song: root.song
        }
    }

    // Play this song, or pause / resume it if it is the one playing.
    function playOrToggle() {
        if (root.isCurrent)
            PlayerController.togglePlayPause()
        else if (root.listSongs)
            YouTubeController.playList(root.listSongs, root.listIndex, root.listTitle)
        else
            YouTubeController.play(root.song)
    }

    implicitHeight: 60
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
            return { items: [root.song], title: root.song.title || "", subtitle: root.song.artists || "",
                     cover: root.song.thumbnail || "" }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: Theme.padding

        YtThumbnail {
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            source: root.song.thumbnail || ""
            hue: (root.song.title || "").length % 10 / 10

            // "Now playing" overlay
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
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
                text: root.song.title || ""
                color: root.isCurrent ? Theme.accent : Theme.text
                font.pixelSize: Theme.fontSize
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: (root.song.artists || "")
                      + (root.song.duration > 0 ? "  ·  " + Util.formatTime(root.song.duration) : "")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }
        }

        // The playing song keeps its pause button visible; the rest show on hover.
        PillButton {
            iconName: root.isPlaying ? "pause" : "play"
            iconSize: 11
            implicitWidth: 32
            implicitHeight: 32
            transparentIdle: !root.isCurrent
            active: root.isCurrent
            opacity: root.showButtons || root.isCurrent ? 1 : 0
            visible: opacity > 0
            ToolTip.visible: hovered
            ToolTip.text: root.isPlaying ? qsTr("Pause") : qsTr("Play")
            onClicked: root.playOrToggle()

            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        }

        Row {
            spacing: 2
            opacity: root.showButtons || Theme.touchOnly ? 1 : 0
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

            PillButton {
                visible: root.showButtons
                iconName: "plus"
                iconSize: 12
                implicitWidth: 32
                implicitHeight: 32
                transparentIdle: true
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Add to playlist")
                onClicked: YouTubeController.enqueue(root.song)
            }

            PillButton {
                id: moreButton
                iconName: "more"
                iconSize: 12
                implicitWidth: 32
                implicitHeight: 32
                transparentIdle: true
                ToolTip.visible: hovered
                ToolTip.text: qsTr("More")
                onClicked: {
                    menuLoader.active = true
                    // Parent the menu to the row: the button may hide while it is open.
                    const pos = moreButton.mapToItem(root, 0, moreButton.height)
                    const menu = menuLoader.item as YtSongMenu
                    menu.popup(root, pos.x, pos.y)
                }
            }

            PillButton {
                visible: root.showRemove
                iconName: "trash"
                iconSize: 11
                implicitWidth: 32
                implicitHeight: 32
                transparentIdle: true
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Remove")
                onClicked: root.removeRequested()
            }
        }
    }
}
