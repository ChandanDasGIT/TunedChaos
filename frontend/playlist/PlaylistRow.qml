import QtQuick
import QtQuick.Controls

// One playlist row: [cover] | Title | Artist - Album | Track | Duration.
// Rounded and inset; the playing row is tinted and shows play/pause over its
// cover. Column widths come from PlaylistPanel so they line up with PlaylistHeader.
// Swipe left (mouse drag, touch, or two-finger touchpad swipe) to reveal Delete.
// The handle at the left moves the song when dragged up / down (so does
// pressing and holding the row). "⋮" opens the menu.
Item {
    id: root

    required property int index
    required property string path
    required property string title
    required property string artistAlbum
    required property string trackLabel
    required property real durationMs
    required property bool isCurrent
    required property string thumbnail
    required property bool isYouTube

    property bool selected: false
    property bool menuOpen: false // this row's menu is open: keep "⋮" shown
    property bool editable: true  // false: no swipe to delete, no hold to reorder
    property real indicatorWidth: 70
    property real titleWidth: 200
    property real artistAlbumWidth: 200
    property real trackWidth: 52
    property real durationWidth: 60

    // Horizontal inset of the rounded row (PlaylistHeader uses the same).
    readonly property real inset: 6

    signal clicked()
    signal activated() // tapped: play this track
    signal contextMenuRequested() // right-click
    signal menuButtonClicked(real x, real y) // "⋮": open the menu at this point of the row
    signal deleteRequested()      // the revealed Delete button was pressed
    signal swipeOpened()          // so the list can close the row that was open before
    signal moveRequested(int from, int to) // while dragging a held row

    // ---- Hold and drag to reorder -------------------------------------------------
    property Flickable list: null // the ListView holding the row (positions, auto-scroll)
    property int rowCount: 0
    property bool reordering: false
    property real dragOffset: 0   // how far the row is lifted from its slot while dragging
    property real grabOffset: 0
    property point lastScenePos

    // Follow the pointer; swap with a neighbour once the row's middle passes it.
    function updateReorder(scenePos) {
        if (!list)
            return
        lastScenePos = scenePos
        const pointer = list.contentItem.mapFromItem(null, scenePos.x, scenePos.y).y
        dragOffset = pointer - (y + height / 2) - grabOffset
        const target = Math.max(0, Math.min(rowCount - 1, Math.floor((y + height / 2 + dragOffset) / height)))
        if (target !== index)
            moveRequested(index, target)
    }

    // Held long enough: the row lifts and follows the pointer. The list stops
    // scrolling meanwhile, so the drag moves the row instead.
    function startReorder(scenePos) {
        if (!list || !editable)
            return
        closeSwipe()
        const pointer = list.contentItem.mapFromItem(null, scenePos.x, scenePos.y).y
        grabOffset = pointer - (y + height / 2)
        dragOffset = 0
        lastScenePos = scenePos
        list.interactive = false
        reordering = true
    }
    function endReorder() {
        if (!reordering)
            return
        reordering = false
        dragOffset = 0
        if (list)
            list.interactive = true
    }

    z: reordering ? 10 : 0
    transform: Translate { y: root.dragOffset }

    Behavior on dragOffset {
        enabled: !root.reordering // settle back into the slot when released
        NumberAnimation { duration: Theme.anim; easing.type: Theme.easing }
    }

    // ---- Swipe to delete --------------------------------------------------------
    property int openRowIndex: -1 // the list's currently open row
    readonly property real revealWidth: 96
    property real swipeX: 0       // <= 0: how far the row content is slid left
    property bool wheelSwiping: false

    function closeSwipe() {
        swipeX = 0
    }
    // Past halfway it snaps open, otherwise it springs back.
    function settleSwipe() {
        swipeX = swipeX < -revealWidth / 2 ? -revealWidth : 0
        if (swipeX < 0)
            swipeOpened()
    }
    function swipeBy(dx) {
        if (!editable)
            return
        swipeX = Math.max(-revealWidth * 1.3, Math.min(0, swipeX + dx))
    }

    onOpenRowIndexChanged: if (openRowIndex !== index && swipeX !== 0) closeSwipe()

    Behavior on swipeX {
        enabled: !swipeDrag.active && !root.wheelSwiping
        SpringAnimation { spring: 5; damping: 0.38; epsilon: 0.5 }
    }

    implicitHeight: 48

    // Delete button behind the row, growing with the swipe
    Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: root.inset
        y: 2
        width: Math.max(0, -root.swipeX - 4)
        height: root.height - 4
        radius: Theme.radius
        color: deleteTap.pressed ? Qt.darker(Theme.error, 1.25) : Theme.error
        visible: width > 1
        opacity: Math.min(1, -root.swipeX / (root.revealWidth * 0.6))
        clip: true

        Row {
            anchors.centerIn: parent
            spacing: 6

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "trash"
                size: 12
                color: "white"
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: -root.swipeX > 80
                text: qsTr("Delete")
                color: "white"
                font.pixelSize: Theme.fontSize
                font.weight: Font.DemiBold
            }
        }

        TapHandler {
            id: deleteTap
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: root.deleteRequested()
        }
    }

    DragHandler {
        id: swipeDrag

        property real startX: 0

        enabled: !root.reordering && root.editable
        target: null
        xAxis.enabled: true
        yAxis.enabled: false // vertical drags still scroll the list
        onActiveChanged: active ? (startX = root.swipeX) : root.settleSwipe()
        onTranslationChanged: {
            if (active)
                root.swipeX = Math.max(-root.revealWidth * 1.3, Math.min(0, startX + translation.x))
        }
    }

    // Two-finger horizontal touchpad swipe
    WheelHandler {
        acceptedDevices: PointerDevice.TouchPad
        target: null
        onWheel: (event) => {
            const dx = event.pixelDelta.x !== 0 ? event.pixelDelta.x : event.angleDelta.x / 8
            const dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 8
            if (Math.abs(dx) <= Math.abs(dy)) {
                // Mostly vertical: scroll the list. (Declining the event with
                // event.accepted = false does not reach the list: it would never scroll.)
                const view = root.list
                if (view) {
                    const top = view.originY
                    const bottom = Math.max(top, top + view.contentHeight - view.height)
                    view.contentY = Math.max(top, Math.min(bottom, view.contentY - dy))
                }
                return
            }
            root.wheelSwiping = true
            root.swipeBy(dx)
            wheelSettle.restart()
        }
    }

    Timer {
        id: wheelSettle
        interval: 160
        onTriggered: {
            root.wheelSwiping = false
            root.settleSwipe()
        }
    }

    Rectangle {
        id: card
        x: root.inset + root.swipeX
        width: root.width - 2 * root.inset
        height: root.height - 4
        y: 2
        radius: Theme.radius
        border.width: root.reordering ? 1 : 0
        border.color: Theme.accent
        color: root.reordering ? Theme.surfaceAlt
             : root.selected ? Theme.selection
             : root.isCurrent ? (hover.hovered ? Theme.currentRowHover : Theme.currentRow)
             : hover.hovered ? Theme.hover : "transparent"

        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    HoverHandler {
        id: hover
        cursorShape: root.reordering ? Qt.ClosedHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        id: tap
        longPressThreshold: 0.4
        // An open row closes on tap instead of playing.
        // (A quick second tap doesn't undo what the first one did.)
        onTapped: {
            if (root.swipeX < 0) {
                root.closeSwipe()
                return
            }
            root.clicked()
            if (tapCount === 1)
                root.activated()
        }
        onLongPressed: {
            root.clicked()
            root.startReorder(tap.point.scenePosition)
        }
    }

    // Follows the held pointer (a passive grab: it sees every move) and drops the row on release.
    PointHandler {
        id: holdTracker
        onTranslationChanged: if (root.reordering) root.updateReorder(holdTracker.point.scenePosition)
        onActiveChanged: if (!active) root.endReorder()
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad // (a finger's tap would count as this too)
        onTapped: {
            root.clicked()
            root.contextMenuRequested()
        }
    }

    Row {
        x: root.inset + root.swipeX
        width: card.width
        height: root.height

        // Grab handle, then the cover thumbnail; the playing track shows
        // play/pause on top of it.
        Item {
            width: root.indicatorWidth
            height: parent.height

            Item {
                id: grip
                width: 26
                height: parent.height
                visible: root.editable

                Icon {
                    anchors.centerIn: parent
                    name: "grip"
                    size: 12
                    color: root.reordering ? Theme.accent : Theme.textMuted
                }

                // The press takes over at once, and keeps the list from scrolling.
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                    cursorShape: root.reordering ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    onPressed: (mouse) => {
                        root.clicked()
                        root.startReorder(mapToItem(null, mouse.x, mouse.y))
                    }
                    onPositionChanged: (mouse) => root.updateReorder(mapToItem(null, mouse.x, mouse.y))
                    onReleased: root.endReorder()
                    onCanceled: root.endReorder()
                }
            }

            Rectangle {
                id: thumb
                anchors.left: grip.right
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 34
                radius: 6
                color: Theme.surfaceAlt
                clip: true

                Icon {
                    anchors.centerIn: parent
                    visible: cover.status !== Image.Ready || cover.implicitWidth <= 1
                    name: "music"
                    size: 12
                    color: Theme.textMuted
                }

                Image {
                    id: cover
                    anchors.fill: parent
                    // The provider returns a 1x1 transparent image when there is no cover.
                    source: Util.coverSource(root.path, root.thumbnail)
                    sourceSize: Qt.size(68, 68)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: status === Image.Ready ? 1 : 0

                    Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                }

                // YouTube badge
                Rectangle {
                    visible: root.isYouTube && !root.isCurrent
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: 14
                    height: 14
                    radius: 7
                    color: "#cc000000"

                    Icon {
                        anchors.centerIn: parent
                        name: "cloud"
                        size: 7
                        color: Theme.text
                    }
                }

                // Playing overlay
                Rectangle {
                    anchors.fill: parent
                    color: "#99000000"
                    opacity: root.isCurrent ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity { NumberAnimation { duration: Theme.anim } }

                    Icon {
                        id: indicator
                        anchors.centerIn: parent
                        name: PlayerController.playing ? "pause" : "play"
                        size: 12
                        color: Theme.accent
                        scale: root.isCurrent ? 1 : 0

                        Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Theme.easingBack } }

                        // Gentle pulse while this track plays.
                        SequentialAnimation on opacity {
                            running: root.isCurrent && PlayerController.playing
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.45; duration: 800; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                            onRunningChanged: if (!running) indicator.opacity = 1
                        }
                    }
                }
            }
        }

        Label {
            width: root.titleWidth
            height: parent.height
            leftPadding: 6
            rightPadding: 6
            verticalAlignment: Text.AlignVCenter
            text: root.title
            color: root.isCurrent ? Theme.accent : Theme.text
            font.pixelSize: Theme.fontSize
            font.weight: root.isCurrent ? Font.DemiBold : Font.Medium
            elide: Text.ElideRight

            Behavior on color { ColorAnimation { duration: Theme.anim } }
        }

        Label {
            width: root.artistAlbumWidth
            height: parent.height
            leftPadding: 6
            rightPadding: 6
            verticalAlignment: Text.AlignVCenter
            text: root.artistAlbum
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize
            elide: Text.ElideRight
        }

        Label {
            width: root.trackWidth
            height: parent.height
            leftPadding: 6
            rightPadding: 6
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            text: root.trackLabel
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
            font.features: { "tnum": 1 }
            elide: Text.ElideRight
        }

        Label {
            width: root.durationWidth
            height: parent.height
            leftPadding: 6
            rightPadding: moreButton.opacity > 0 ? 6 + 26 * moreButton.opacity : 6 // makes room for "⋮"
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            text: root.durationMs > 0 ? Util.formatTime(root.durationMs) : ""
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
            font.features: { "tnum": 1 }
            elide: Text.ElideRight
        }
    }

    // "⋮": the same menu as right-click.
    PillButton {
        id: moreButton
        anchors.right: parent.right
        anchors.rightMargin: root.inset + 2 - root.swipeX
        anchors.verticalCenter: parent.verticalCenter
        iconName: "more"
        iconSize: 12
        implicitWidth: 26
        implicitHeight: 26
        transparentIdle: true
        opacity: (hover.hovered || root.selected || root.menuOpen) && !root.reordering ? 1 : 0
        visible: opacity > 0
        ToolTip.visible: hovered
        ToolTip.text: qsTr("More")
        onClicked: {
            root.clicked()
            const pos = moreButton.mapToItem(root, 0, moreButton.height)
            root.menuButtonClicked(pos.x, pos.y)
        }

        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    // Auto-scroll while dragging near the top / bottom of the list.
    Timer {
        interval: 16
        repeat: true
        running: root.reordering && root.list !== null
        onTriggered: {
            const view = root.list
            const pointer = view.contentItem.mapFromItem(null, root.lastScenePos.x, root.lastScenePos.y).y - view.contentY
            const edge = 44
            let step = 0
            if (pointer < edge)
                step = -Math.ceil((edge - pointer) / 4)
            else if (pointer > view.height - edge)
                step = Math.ceil((pointer - (view.height - edge)) / 4)
            if (step === 0)
                return
            view.contentY = Math.max(0, Math.min(view.contentHeight - view.height, view.contentY + step))
            root.updateReorder(root.lastScenePos)
        }
    }
}
