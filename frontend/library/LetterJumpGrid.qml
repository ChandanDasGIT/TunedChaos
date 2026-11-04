import QtQuick
import QtQuick.Controls

// Every letter group in a grid over the Library list: letters with songs can be
// tapped to jump there, the others are dimmed. Tapping outside closes it.
Rectangle {
    id: root

    property var starts: ({}) // letter -> first row, from LocalLibraryController.letterStarts()
    readonly property var letters: ["#"].concat("ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("")).concat(["…"])

    signal chosen(int row)
    signal closed()

    color: Theme.withAlpha(Theme.background, 0.94)
    opacity: visible ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.anim } }

    TapHandler { onTapped: root.closed() } // outside the letters

    Grid {
        id: grid

        readonly property real cell: Math.min(72, (root.width - 2 * Theme.padding) / columns)

        anchors.centerIn: parent
        columns: 4
        spacing: 0

        Repeater {
            model: root.letters

            delegate: Item {
                id: cellItem

                required property string modelData
                readonly property bool present: root.starts[modelData] !== undefined

                width: grid.cell
                height: grid.cell

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: Theme.radius
                    color: !cellItem.present ? "transparent"
                         : letterHover.hovered ? Theme.accentSoftHover : Theme.accentSoft
                    border.width: cellItem.present ? 0 : 1
                    border.color: Theme.border

                    Label {
                        anchors.centerIn: parent
                        text: cellItem.modelData
                        color: cellItem.present ? Theme.accent : Theme.textDim
                        font.pixelSize: Theme.fontSizeTitle
                        font.weight: Font.DemiBold
                    }

                    HoverHandler { id: letterHover; enabled: cellItem.present; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        enabled: cellItem.present
                        onTapped: root.chosen(root.starts[cellItem.modelData])
                    }
                }
            }
        }
    }
}
