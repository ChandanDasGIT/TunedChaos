pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Lyrics of the playing track.
//   Synced: the current line is bright and bold, lines further away fade; the
//           list glides to keep the current line in view; click a line to seek.
//   Static: plain text you can scroll.
Item {
    id: root

    property bool showSynced: SettingsController.lyricsSyncedByDefault
    readonly property bool syncedView: showSynced && LyricsController.synced
    // Japanese / Korean lyrics in a Japanese / Korean font (see Util.cjkFamily)
    readonly property string lyricsFamily: LyricsController.status === LyricsController.Found
        ? Util.cjkFamily(LyricsController.lines.slice(0, 40).map((l) => l.text).join("")) : ""
    readonly property bool following: syncedView && LyricsController.currentLine >= 0
    // 0 = closed .. 1 = open: the parts come in one after another (see phase()).
    property real progress: 1
    property bool covered: false // a panel lies over this (see NowPlayingPanel)
    // Where the big cover lands when the lyrics open (NowPlayingPanel flies it here).
    readonly property Item coverSlot: capsuleCover

    signal closeRequested()

    // 0 before `from`, 1 after `to`, smooth in between.
    function phase(from, to) {
        const t = Math.max(0, Math.min(1, (progress - from) / (to - from)))
        return t * t * (3 - 2 * t)
    }

    // ---- Mini "now playing" capsule ---------------------------------------
    Rectangle {
        id: capsule
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width, capsuleRow.implicitWidth + 28)
        height: 52
        radius: height / 2
        color: Theme.capsule
        opacity: root.phase(0.45, 1)

        RowLayout {
            id: capsuleRow
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 18
            spacing: 10

            Rectangle {
                id: capsuleCover
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 20
                color: Theme.surfaceAlt
                clip: true
                opacity: root.phase(0.85, 1) // takes over from the flying cover at the end

                Icon {
                    anchors.centerIn: parent
                    name: "music"
                    size: 14
                    color: Theme.textMuted
                }

                Image {
                    anchors.fill: parent
                    source: Util.coverSource(PlayerController.source, PlaylistController.currentThumbnail)
                    sourceSize: Qt.size(80, 80)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }
            }

            ColumnLayout {
                spacing: 0

                Label {
                    textFormat: Text.PlainText
                    Layout.maximumWidth: 260
                    text: PlaylistController.currentTitle !== "" ? PlaylistController.currentTitle : PlayerController.title
                    color: Theme.text
                    font.pixelSize: Theme.fontSize
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Label {
                    textFormat: Text.PlainText
                    Layout.maximumWidth: 260
                    visible: text !== ""
                    text: PlaylistController.currentSubtitle
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Plain text found, but no source had timed lyrics: say so (otherwise it
    // looks like the highlighting is broken).
    Label {
        id: untimedNote
        textFormat: Text.PlainText
        opacity: root.phase(0.35, 1)
        anchors.top: capsule.bottom
        anchors.topMargin: Theme.spacing
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width, implicitWidth)
        visible: LyricsController.status === LyricsController.Found && !LyricsController.synced
        text: qsTr("These lyrics have no timing, so they can't follow the song.")
        color: Theme.textDim
        font.pixelSize: Theme.fontSizeSmall
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }

    // ---- Lines -------------------------------------------------------------
    ListView {
        id: list
        opacity: root.phase(0.35, 1)
        transform: Translate { y: 32 * (1 - root.phase(0.2, 1)) } // rises into place
        anchors.top: untimedNote.visible ? untimedNote.bottom : capsule.bottom
        anchors.topMargin: Theme.padding
        anchors.bottom: footer.top
        anchors.bottomMargin: Theme.spacing
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        spacing: 14
        model: LyricsController.status === LyricsController.Found ? LyricsController.lines : []
        currentIndex: root.following ? LyricsController.currentLine : -1
        highlightRangeMode: root.following ? ListView.StrictlyEnforceRange : ListView.NoHighlightRange
        preferredHighlightBegin: height * 0.38
        preferredHighlightEnd: height * 0.38 + 30
        highlightMoveDuration: 450
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: Theme.flickDeceleration
        maximumFlickVelocity: Theme.flickVelocity
        synchronousDrag: true
        ScrollBar.vertical: ScrollBar { policy: root.syncedView ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded }

        delegate: Label {
            id: line
            textFormat: Text.PlainText

            required property var modelData
            required property int index

            readonly property bool isCurrent: root.following && index === LyricsController.currentLine
            readonly property int distance: root.following ? Math.abs(index - LyricsController.currentLine) : 0

            width: ListView.view.width
            leftPadding: 4
            rightPadding: 12
            text: modelData.text !== "" ? modelData.text : (root.syncedView ? "♪" : " ")
            font.family: root.lyricsFamily !== "" ? root.lyricsFamily : Qt.application.font.family
            wrapMode: Text.WordWrap
            font.pixelSize: root.syncedView ? 22 : 17
            font.weight: isCurrent ? Font.Bold : Font.Medium
            color: isCurrent ? Theme.text : Theme.textMuted
            opacity: root.syncedView ? Math.max(0.28, 1 - distance * 0.17) : 0.92
            scale: isCurrent ? 1.0 : 0.96
            transformOrigin: Item.Left

            Behavior on color { ColorAnimation { duration: Theme.anim } }
            Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }
            Behavior on scale { NumberAnimation { duration: Theme.animSlow; easing.type: Theme.easing } }

            HoverHandler {
                enabled: root.syncedView && !root.covered && line.modelData.time >= 0
                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                enabled: root.syncedView && !root.covered && line.modelData.time >= 0
                onTapped: PlayerController.seek(line.modelData.time)
            }
        }
    }

    // ---- Loading / nothing found -------------------------------------------
    Column {
        anchors.centerIn: list
        width: list.width - 2 * Theme.padding
        spacing: Theme.spacing
        opacity: (LyricsController.status === LyricsController.Found ? 0 : 1) * root.phase(0.35, 1)
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: Theme.anim } }

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "lyrics"
            size: 30
            color: Theme.textMuted

            SequentialAnimation on opacity {
                running: LyricsController.status === LyricsController.Loading
                loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
            }
        }

        Label {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: LyricsController.status === LyricsController.Loading ? qsTr("Looking for lyrics…")
                : LyricsController.status === LyricsController.NotFound ? qsTr("No lyrics found")
                : qsTr("Nothing playing")
            color: Theme.text
            font.pixelSize: Theme.fontSizeLarge
        }

        Label {
            textFormat: Text.PlainText
            width: parent.width
            visible: LyricsController.status === LyricsController.NotFound
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: qsTr("Add a .lrc file next to the song, or turn on more sources in Settings.")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // ---- Footer: back | Synced / Static, the source below ------------------
    // (The source under the buttons: a long name never pushes them out of a narrow window.)
    ColumnLayout {
        id: footer
        opacity: root.phase(0.5, 1)
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 4

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.spacing

            PillButton {
                iconName: "back"
                iconSize: 13
                implicitWidth: 44
                implicitHeight: 36
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Back to the cover")
                onClicked: root.closeRequested()
            }

            Rectangle {
                visible: LyricsController.synced
                implicitWidth: modeRow.implicitWidth + 8
                implicitHeight: modeRow.implicitHeight + 8
                radius: height / 2
                color: Theme.fill

                RowLayout {
                    id: modeRow
                    anchors.centerIn: parent
                    spacing: 2

                    PillButton {
                        text: qsTr("Synced")
                        implicitHeight: 30
                        transparentIdle: true
                        active: root.showSynced
                        onClicked: root.showSynced = true
                    }

                    PillButton {
                        text: qsTr("Static")
                        implicitHeight: 30
                        transparentIdle: true
                        active: !root.showSynced
                        onClicked: root.showSynced = false
                    }
                }
            }
        }

        Label {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: LyricsController.status === LyricsController.Found
            text: qsTr("from %1").arg(LyricsController.sourceName)
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
