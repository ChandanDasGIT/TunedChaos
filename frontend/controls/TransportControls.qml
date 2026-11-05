import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Big stadium buttons (previous | play/pause | next) and, below them, a
// grouped row of toggles (shuffle | repeat | lyrics), and autoplay (YouTube
// Mix) in a pill of its own beside it.
ColumnLayout {
    id: root

    property bool lyricsOpen: false

    signal lyricsToggled()

    spacing: Theme.padding

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 10

        PillButton {
            iconName: "prev"
            iconSize: 18
            implicitWidth: 78
            implicitHeight: 56
            enabled: PlayerController.hasTrack
            // Restarts the track if it has played > 3 s, otherwise goes to the previous one.
            onClicked: PlaylistController.previous()
        }

        PillButton {
            filled: true
            implicitWidth: 104
            implicitHeight: 64
            enabled: PlayerController.hasTrack || PlaylistController.count > 0
            onClicked: PlaylistController.playPause()

            // Play and pause icons turn and crossfade into each other.
            contentItem: Item {
                Icon {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 2 // the play triangle looks centered this way
                    name: "play"
                    size: 22
                    color: Theme.background
                    opacity: PlayerController.playing ? 0 : 1
                    rotation: PlayerController.playing ? 90 : 0
                    scale: PlayerController.playing ? 0.6 : 1

                    Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                    Behavior on rotation { NumberAnimation { duration: Theme.anim; easing.type: Theme.easing } }
                    Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Theme.easing } }
                }

                Icon {
                    anchors.centerIn: parent
                    name: "pause"
                    size: 22
                    color: Theme.background
                    opacity: PlayerController.playing ? 1 : 0
                    rotation: PlayerController.playing ? 0 : -90
                    scale: PlayerController.playing ? 1 : 0.6

                    Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                    Behavior on rotation { NumberAnimation { duration: Theme.anim; easing.type: Theme.easing } }
                    Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Theme.easing } }
                }
            }
        }

        PillButton {
            iconName: "next"
            iconSize: 18
            implicitWidth: 78
            implicitHeight: 56
            enabled: PlaylistController.hasNext
            onClicked: PlaylistController.next()
        }
    }

    // The toggles, and autoplay in a pill of its own next to them
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Theme.spacing

        // Shuffle | repeat | lyrics
        Rectangle {
            implicitWidth: toggles.implicitWidth + 10
            implicitHeight: toggles.implicitHeight + 10
            radius: height / 2
            color: Theme.fill

            RowLayout {
                id: toggles
                anchors.centerIn: parent
                spacing: 4

                PillButton {
                    iconName: "shuffle"
                    iconSize: 14
                    implicitWidth: 60
                    implicitHeight: 38
                    transparentIdle: true
                    active: PlaylistController.shuffle
                    onClicked: PlaylistController.shuffle = !PlaylistController.shuffle
                    ToolTip.visible: hovered
                    ToolTip.text: PlaylistController.shuffle ? qsTr("Shuffle: on") : qsTr("Shuffle: off")
                }

                PillButton {
                    iconName: "repeat"
                    iconSize: 14
                    implicitWidth: 60
                    implicitHeight: 38
                    transparentIdle: true
                    active: PlaylistController.repeatMode !== PlaylistController.RepeatOff
                    onClicked: PlaylistController.cycleRepeatMode()
                    ToolTip.visible: hovered
                    ToolTip.text: PlaylistController.repeatMode === PlaylistController.RepeatOne ? qsTr("Repeat: this track")
                                : PlaylistController.repeatMode === PlaylistController.RepeatAll ? qsTr("Repeat: playlist")
                                : qsTr("Repeat: off")

                    // "1" badge for repeat-one (pops in)
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: 10
                        anchors.topMargin: 4
                        width: 13
                        height: 13
                        radius: width / 2
                        color: Theme.accent
                        scale: PlaylistController.repeatMode === PlaylistController.RepeatOne ? 1 : 0
                        visible: scale > 0

                        Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Theme.easingBack } }

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: "1"
                            color: Theme.background
                            font.pixelSize: 9
                            font.bold: true
                        }
                    }
                }

                PillButton {
                    iconName: "lyrics"
                    iconSize: 14
                    implicitWidth: 60
                    implicitHeight: 38
                    transparentIdle: true
                    enabled: PlayerController.hasTrack
                    active: root.lyricsOpen
                    onClicked: root.lyricsToggled()
                    ToolTip.visible: hovered
                    ToolTip.text: root.lyricsOpen ? qsTr("Hide lyrics") : qsTr("Show lyrics")
                }
            }
        }

        // Autoplay: after a YouTube song, album or playlist, keep going with its Mix
        Rectangle {
            implicitWidth: autoplay.implicitWidth + 10
            implicitHeight: autoplay.implicitHeight + 10
            radius: height / 2
            color: Theme.fill

            PillButton {
                id: autoplay
                anchors.centerIn: parent
                iconName: "infinity"
                iconSize: 14
                implicitWidth: 60
                implicitHeight: 38
                transparentIdle: true
                active: SettingsController.ytAutoplay
                onClicked: SettingsController.ytAutoplay = !SettingsController.ytAutoplay
                ToolTip.visible: hovered
                ToolTip.text: SettingsController.ytAutoplay ? qsTr("Autoplay similar songs: on") : qsTr("Autoplay similar songs: off")
            }
        }
    }
}
