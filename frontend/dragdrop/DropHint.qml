import QtQuick

// A drop target for songs dragged with SongDrag, covering its parent. While a
// drag is on it shows a soft accent wash, an outline and a pill saying what a
// drop does, brighter with the pointer over it; `dropped` when released there.
// Never takes the pointer itself.
Rectangle {
    id: root

    property bool accepts: true // this target takes drops right now
    property bool showLabel: true
    property string text: qsTr("Drop to add to the Queue")

    readonly property bool shown: accepts && SongDrag.active && parent.visible
    readonly property bool over: shown && contains(mapFromItem(null, SongDrag.scenePos.x, SongDrag.scenePos.y))

    signal dropped()

    anchors.fill: parent
    radius: Theme.radiusCard
    z: 10
    color: Theme.withAlpha(Theme.accent, over ? 0.18 : 0.06)
    border.width: over ? 2 : 1
    border.color: Theme.withAlpha(Theme.accent, over ? 1 : 0.5)
    opacity: shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity { NumberAnimation { duration: Theme.anim } }
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Connections {
        target: SongDrag
        function onDropped() {
            if (root.over)
                root.dropped()
        }
    }

    Rectangle {
        anchors.centerIn: parent
        visible: root.showLabel
        width: label.implicitWidth + 2 * Theme.padding
        height: label.implicitHeight + Theme.spacing
        radius: height / 2
        color: root.over ? Theme.accent : Theme.surfaceAlt
        scale: root.over ? 1.05 : 1

        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Theme.easing } }

        Text {
            id: label
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: root.text
            color: root.over ? Theme.background : Theme.text
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.DemiBold
        }
    }
}
