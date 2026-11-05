import QtQuick
import QtQuick.Controls

// A grid of tiles for the Library's grid views (local and hosted): rows of as
// many tiles as fit, with letter headers between them when the list is grouped
// by letter. It knows only how many items there are and where each letter's
// first item is; each tile is made by `tile` with `modelData`: the item's
// index in the list (the tile looks up its own data).
ListView {
    id: grid

    property int itemCount: 0
    // { letter: first index } when grouped by letter, else null
    property var letterStarts: null
    property Component tile
    property real tileMinWidth: 150
    property real textHeight: 46 // under the square picture: two lines
    // Anything that changes when the list's contents do (same count, new order): the tiles are made again
    property var revision: null

    signal letterTapped()

    readonly property int columns: Math.max(2, Math.floor(width / tileMinWidth))
    readonly property real cellWidth: width / columns
    readonly property real cellHeight: cellWidth + textHeight
    // Each row: a letter header ({ header }) or a run of items ({ first, count })
    readonly property var rows: {
        const out = []
        out.revision = revision // (read so the rows are made again when it changes)
        const runs = [] // [first, end) of each letter group (or the whole list)
        if (letterStarts && Object.keys(letterStarts).length > 0) {
            const starts = Object.keys(letterStarts).map((letter) => ({ letter: letter, first: letterStarts[letter] }))
                                                     .sort((a, b) => a.first - b.first)
            for (let i = 0; i < starts.length; ++i)
                runs.push({ header: starts[i].letter, first: starts[i].first,
                            end: i + 1 < starts.length ? starts[i + 1].first : itemCount })
        } else {
            runs.push({ header: "", first: 0, end: itemCount })
        }
        for (const run of runs) {
            if (run.header !== "")
                out.push({ header: run.header, first: run.first, count: 0 })
            for (let first = run.first; first < run.end; first += columns)
                out.push({ header: "", first: first, count: Math.min(columns, run.end - first) })
        }
        return out
    }
    // The row showing item `index` (its letter's header if it starts one): for the letter grid
    function rowOf(index) {
        for (let r = 0; r < rows.length; ++r) {
            const row = rows[r]
            if (row.header !== "" && row.first === index)
                return r
            if (row.header === "" && index >= row.first && index < row.first + row.count)
                return r
        }
        return 0
    }

    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickDeceleration: Theme.flickDeceleration
    maximumFlickVelocity: Theme.flickVelocity
    synchronousDrag: true
    model: rows
    ScrollBar.vertical: ScrollBar {}

    delegate: Item {
        id: gridRow

        required property var modelData

        width: ListView.view.width
        height: modelData.header !== "" ? header.implicitHeight : grid.cellHeight

        LetterHeader {
            id: header
            width: parent.width
            visible: gridRow.modelData.header !== ""
            letter: gridRow.modelData.header
            onTapped: grid.letterTapped()
        }

        Row {
            visible: gridRow.modelData.header === ""

            Repeater {
                // The items' indexes in the list
                model: Array.from({ length: gridRow.modelData.count }, (_, i) => gridRow.modelData.first + i)

                delegate: Item {
                    id: cell

                    required property var modelData

                    width: grid.cellWidth
                    height: grid.cellHeight

                    // Made with its index already set (see ReorderList)
                    Component.onCompleted: if (grid.tile) grid.tile.createObject(cell, {
                        modelData: cell.modelData,
                        width: Qt.binding(() => cell.width), height: Qt.binding(() => cell.height) })
                }
            }
        }
    }
}
