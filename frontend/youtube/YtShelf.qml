pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A titled, sideways-scrolling row of cards (YtCard).
ColumnLayout {
    id: root

    property string title
    property var items: []
    // Hovered or moving: a drawer holding it must not take a drag as a swipe.
    readonly property bool busy: shelfHover.hovered || row.dragging || row.moving

    spacing: Theme.spacing

    Label {
        textFormat: Text.PlainText
        Layout.leftMargin: Theme.padding
        Layout.topMargin: Theme.spacing
        text: root.title
        color: Theme.text
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.DemiBold
    }

    ListView {
        id: row
        Layout.fillWidth: true
        Layout.preferredHeight: 196
        orientation: ListView.Horizontal
        populate: ListPopulate { sideways: true }
        spacing: Theme.padding
        leftMargin: Theme.padding
        rightMargin: Theme.padding
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: Theme.flickDeceleration
        maximumFlickVelocity: Theme.flickVelocity
        synchronousDrag: true
        model: root.items

        HoverHandler {
            id: shelfHover
        }

        delegate: YtCard {}
    }
}
