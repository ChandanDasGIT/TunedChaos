import QtQuick
import QtQuick.Controls

// A panel's tabs on one line: they share its width evenly and scroll sideways
// where they don't fit, with an arrow on each side that has more to show.
// Phones: compact tabs sized to their labels; instead of arrows (which covered
// a tab), tabs fade out toward an edge with more beyond it.
Item {
    id: root

    property var tabs: [] // [{ icon, label }]
    property int current: -1
    // Hovered or moving: a drawer holding it must not take a drag as a swipe.
    readonly property bool busy: hover.hovered || list.dragging || list.moving

    signal tabPicked(int index)

    readonly property bool compact: Theme.touchOnly
    readonly property real fadeWidth: 28

    implicitHeight: 34

    ListView {
        id: list
        anchors.fill: parent
        orientation: ListView.Horizontal
        spacing: 6
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: Theme.flickDeceleration
        maximumFlickVelocity: Theme.flickVelocity
        synchronousDrag: true
        currentIndex: root.current
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
        model: root.tabs

        HoverHandler {
            id: hover
        }

        delegate: PillButton {
            id: tab

            required property var modelData
            required property int index
            // Phones: how close it is to an edge with more beyond it (fades there)
            readonly property real fromLeft: x - list.contentX
            readonly property real fromRight: list.width - (x - list.contentX + width)
            readonly property real edgeFade: !root.compact ? 1
                : Math.min(list.atXBeginning ? 1 : Math.max(0.15, Math.min(1, (fromLeft + root.fadeWidth) / (2 * root.fadeWidth))),
                           list.atXEnd ? 1 : Math.max(0.15, Math.min(1, (fromRight + root.fadeWidth) / (2 * root.fadeWidth))))

            width: root.compact ? implicitWidth
                 : Math.max(implicitWidth, (list.width - (list.count - 1) * list.spacing) / list.count)
            opacity: edgeFade
            sidePadding: root.compact ? 12 : 16
            iconName: modelData.icon
            iconSize: root.compact ? 10 : 11
            text: modelData.label
            implicitHeight: 34
            active: root.current === index
            onClicked: root.tabPicked(index)
        }
    }

    ScrollHint {
        anchors.left: parent.left
        iconName: "chevronLeftSmall"
        shown: !root.compact && !list.atXBeginning
        onClicked: list.positionViewAtBeginning()
    }

    ScrollHint {
        anchors.right: parent.right
        iconName: "chevronRight"
        shown: !root.compact && !list.atXEnd
        onClicked: list.positionViewAtEnd()
    }

    component ScrollHint: AbstractButton {
        id: hint

        property string iconName
        property bool shown: false

        anchors.verticalCenter: parent.verticalCenter
        width: 26
        height: 26
        focusPolicy: Qt.NoFocus
        enabled: shown
        opacity: shown ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

        background: Rectangle {
            radius: width / 2
            color: Theme.surfaceAlt
            border.color: Theme.border
        }

        contentItem: Item {
            Icon {
                anchors.centerIn: parent
                name: hint.iconName
                size: 10
                color: Theme.text
            }
        }
    }
}
