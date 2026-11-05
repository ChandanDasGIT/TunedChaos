import QtQuick
import QtQuick.Controls

// Small pill with the track's format, e.g. "44.1 kHz · 941 kbps · FLAC".
// A click asks for the track's details.
Rectangle {
    id: root

    property string text: PlayerController.qualityText
    property bool covered: false // a panel lies over this (see NowPlayingPanel)

    signal clicked()

    implicitWidth: label.implicitWidth + 20
    implicitHeight: label.implicitHeight + 6
    radius: height / 2
    color: chipHover.hovered ? Theme.hover : Theme.fill
    opacity: text !== "" ? 1 : 0
    visible: opacity > 0

    Behavior on opacity { NumberAnimation { duration: Theme.anim } }
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    HoverHandler {
        id: chipHover
        enabled: !root.covered
        cursorShape: Qt.PointingHandCursor
    }
    // Small to look at, so a finger needn't land exactly on it. Never reaches
    // upward: the seek bar is right above, and a tap there would do both.
    Item {
        anchors.fill: parent
        anchors.leftMargin: Theme.touchOnly ? -18 : 0
        anchors.rightMargin: Theme.touchOnly ? -18 : 0
        anchors.bottomMargin: Theme.touchOnly ? -18 : 0

        TapHandler {
            enabled: !root.covered
            onTapped: root.clicked()
        }
    }

    ToolTip.visible: chipHover.hovered
    ToolTip.text: qsTr("Track details")

    Label {
        id: label
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: root.text
        color: chipHover.hovered ? Theme.text : Theme.textMuted
        font.pixelSize: Theme.fontSizeSmall
        font.features: { "tnum": 1 }
    }
}
