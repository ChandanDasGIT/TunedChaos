import QtQuick
import QtQuick.Controls

// A card on a shelf: a playlist / album (opens its songs; hold and drag it onto
// the Queue or the player) or an artist (round picture; opens their page).
Item {
    id: card

    required property var modelData
    readonly property bool isArtist: Util.ytIsArtist(modelData.browseId)

    width: 140
    height: 196
    scale: cardHover.hovered ? 1.03 : 1

    Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Theme.easing } }

    HoverHandler {
        id: cardHover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: Util.ytOpen(card.modelData)
    }

    // Songs are fetched on drop.
    DragSource {
        enabled: !card.isArtist
        payload: function() {
            return { browseId: card.modelData.browseId, title: card.modelData.title,
                     subtitle: card.modelData.subtitle || "", cover: card.modelData.thumbnail || "" }
        }
    }

    YtThumbnail {
        id: art
        width: 140
        height: 140
        round: card.isArtist
        source: card.modelData.thumbnail
        hue: card.modelData.title.length % 10 / 10
        iconName: card.isArtist ? "user" : "listMusic"
    }

    Label {
        textFormat: Text.PlainText
        anchors.top: art.bottom
        anchors.topMargin: 6
        width: parent.width
        horizontalAlignment: card.isArtist ? Text.AlignHCenter : Text.AlignLeft
        text: card.modelData.title
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
        horizontalAlignment: card.isArtist ? Text.AlignHCenter : Text.AlignLeft
        text: card.modelData.subtitle
        color: Theme.textMuted
        font.pixelSize: Theme.fontSizeSmall
        elide: Text.ElideRight
        maximumLineCount: 2
        wrapMode: Text.WordWrap
    }
}
