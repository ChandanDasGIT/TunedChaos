import QtQuick
import QtQuick.Controls

// A SplitView column for a dockable panel. Docking opens its width smoothly
// (the panel slides in from its outer side and fades in, the player glides
// aside); undocking closes it the same way. The panel keeps its full width
// while the column opens or closes, so its content doesn't squeeze (nor
// shrink in height: a leaving panel keeps its height, a coming one has its
// final height at once). The gap to the next card is part of the column
// (gapBefore / gapAfter: the dividers take no room), so it opens and closes
// with it instead of appearing all at once.
Item {
    id: slot

    property bool docked: false
    property real share: 300      // card width when docked (until the user drags the divider)
    property real targetShare: share   // the card width once every column has finished opening / closing
    property real targetHeight: height // the height once the columns have settled
    property real gapBefore: 0    // room left of the card / right of it (the gaps between cards)
    property real gapAfter: 0
    readonly property real gaps: gapBefore + gapAfter
    property real minimumWidth: 240
    property bool leftSide: true  // slides in from the left edge (else from the right)
    default property alias content: swipeFlick.flickableData

    // Swipe the panel toward its outer edge to put it away (like a phone drawer):
    // it follows the pointer and springs back unless swiped far or fast enough.
    // swipeAnywhere: also over the panel's lists (they keep vertical scrolling and
    // clicks: only a sideways drag swipes). Otherwise only where nothing below
    // takes the press, e.g. the header, so rows can keep their own swipes.
    property bool swipeEnabled: false
    property bool swipeAnywhere: true
    signal swipedAway()

    readonly property int outward: leftSide ? -1 : 1
    // How far the panel is pulled toward its edge: by a drag over the lists
    // (swipeFlick's overshoot: dragged past its edge, a Flickable reports half
    // the distance) or by a drag / touchpad swipe elsewhere (swipeOffset).
    property real swipeOffset: 0
    readonly property real flickPull: outward < 0 ? Math.min(0, -2 * swipeFlick.horizontalOvershoot)
                                                  : Math.max(0, -2 * swipeFlick.horizontalOvershoot)
    readonly property real pulled: swipeOffset + flickPull
    readonly property bool swiping: swipeDrag.active || wheelSwipe.swiping

    function swipeTo(dx) {
        swipeOffset = outward < 0 ? Math.min(0, dx) : Math.max(0, dx)
    }
    function settleSwipe(fast) {
        if (fast || Math.abs(pulled) > width * 0.3)
            swipedAway()
        swipeOffset = 0
    }

    Behavior on swipeOffset {
        enabled: !slot.swiping
        NumberAnimation { duration: Theme.anim; easing.type: Theme.easing }
    }

    property real openness: docked ? 1 : 0
    property real fullWidth: targetShare // the panel's width while opening / closing
    property real closingHeight: 0       // its height when it began to close

    Behavior on openness {
        NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingPanel }
    }

    visible: docked || openness > 0 // at once when docking, so its content can take the focus
    opacity: openness

    SplitView.minimumWidth: openness < 1 ? 0 : minimumWidth + gaps
    SplitView.preferredWidth: (share + gaps) * openness

    // Back to the shared width. Dragging the divider replaces the width binding;
    // this sets it again.
    function equalize() {
        if (!docked)
            return
        fullWidth = Qt.binding(() => slot.targetShare)
        SplitView.preferredWidth = Qt.binding(() => (slot.share + slot.gaps) * slot.openness)
    }

    onDockedChanged: {
        if (docked) {
            equalize()
        } else {
            const closingFrom = width
            fullWidth = Math.max(0, closingFrom - gaps)
            closingHeight = height
            SplitView.preferredWidth = Qt.binding(() => closingFrom * slot.openness)
        }
    }

    // The card's place: the column without its gaps
    Item {
        id: area
        x: slot.gapBefore
        width: Math.max(0, slot.width - slot.gaps)
        height: slot.height
        clip: slot.openness < 1 || slot.pulled !== 0


        Item {
            id: holder
            width: slot.openness < 1 ? Math.max(area.width, slot.fullWidth) : area.width
            height: slot.openness < 1 ? Math.max(area.height, slot.docked ? slot.targetHeight : slot.closingHeight)
                                      : area.height
            x: (slot.leftSide ? area.width - width : 0) + slot.pulled
            opacity: 1 - 0.6 * Math.min(1, Math.abs(slot.pulled) / Math.max(1, area.width))

            // Sideways-only: lists inside keep their presses and vertical scrolling;
            // once a drag goes sideways it takes over. Its content stays put; the
            // overshoot pulls the whole panel along instead (and springs back by
            // itself). Like the pages of a SwipeView.
            Flickable {
                id: swipeFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: height
                interactive: slot.swipeEnabled && slot.swipeAnywhere && !SongDrag.active
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.DragOverBounds
                boundsMovement: Flickable.StopAtBounds
                onDraggingChanged: {
                    if (!dragging && slot.swipeEnabled)
                        slot.settleSwipe(-horizontalVelocity * slot.outward > 800)
                }

                // Two-finger touchpad swipe. Here (on the content) it comes before
                // the Flickable itself; lists keep vertical scrolling, as they take
                // those wheel events before they get here.
                WheelHandler {
                    id: wheelSwipe

                    property bool swiping: false
                    property real total: 0

                    enabled: slot.swipeEnabled && !SongDrag.active
                    acceptedDevices: PointerDevice.TouchPad
                    target: null
                    onWheel: (event) => {
                        const dx = event.pixelDelta.x !== 0 ? event.pixelDelta.x : event.angleDelta.x / 8
                        const dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 8
                        if (Math.abs(dx) <= Math.abs(dy))
                            return
                        if (!swiping)
                            total = 0
                        swiping = true
                        total += dx
                        slot.swipeTo(total)
                        wheelSettle.restart()
                    }
                }
            }

            Timer {
                id: wheelSettle
                interval: 160
                onTriggered: {
                    wheelSwipe.swiping = false
                    slot.settleSwipe(false)
                }
            }

            // Mouse / touch swipe where swipeFlick doesn't take it: below the
            // content, so only presses nothing else takes arrive (e.g. the header).
            Item {
                anchors.fill: parent
                z: -1

                DragHandler {
                    id: swipeDrag

                    enabled: slot.swipeEnabled && !slot.swipeAnywhere && !SongDrag.active
                    grabPermissions: PointerHandler.TakeOverForbidden // rows' own swipes and presses win
                    target: null
                    xAxis.enabled: true
                    yAxis.enabled: false
                    onTranslationChanged: if (active) slot.swipeTo(translation.x)
                    onActiveChanged: if (!active) slot.settleSwipe(centroid.velocity.x * slot.outward > 800)
                }
            }
        }
    }
}
