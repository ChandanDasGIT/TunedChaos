pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Making or changing a smart playlist: its name, its rules (each a field, a
// comparison and a value), whether all or any rule must match, its order and
// how many songs it keeps. The number of songs it would have updates as you go.
Popup {
    id: root

    // The playlist being edited (see SmartPlaylistsController); "" id = a new one.
    property string playlistId: ""
    property var rules: []
    property bool matchAll: true
    property string order: "plays"
    property int revision: 0 // a rule's value was typed (changed in place, so the rows keep the focus)

    readonly property var fields: [
        { id: "title", name: qsTr("Title"), kind: "text" },
        { id: "artist", name: qsTr("Artist"), kind: "text" },
        { id: "album", name: qsTr("Album"), kind: "text" },
        { id: "plays", name: qsTr("Plays"), kind: "number" },
        { id: "duration", name: qsTr("Length (minutes)"), kind: "number" },
        { id: "lastPlayed", name: qsTr("Last played"), kind: "days" },
        { id: "added", name: qsTr("Added to the library"), kind: "days" },
        { id: "source", name: qsTr("Source"), kind: "source" }
    ]
    readonly property var ops: ({
        text: [{ id: "contains", name: qsTr("contains") }, { id: "notContains", name: qsTr("doesn't contain") },
               { id: "is", name: qsTr("is") }, { id: "isNot", name: qsTr("isn't") }],
        number: [{ id: "greater", name: qsTr("more than") }, { id: "less", name: qsTr("less than") },
                 { id: "equals", name: qsTr("exactly") }],
        days: [{ id: "inLast", name: qsTr("in the last … days") }, { id: "notInLast", name: qsTr("not in the last … days") }],
        source: [{ id: "is", name: qsTr("is") }]
    })
    readonly property var orders: [
        { id: "plays", name: qsTr("Most played") }, { id: "lastPlayed", name: qsTr("Recently played") },
        { id: "added", name: qsTr("Recently added") }, { id: "title", name: qsTr("Title") },
        { id: "artist", name: qsTr("Artist") }, { id: "random", name: qsTr("Random") }
    ]

    function kindOf(field) {
        for (const f of fields)
            if (f.id === field)
                return f.kind
        return "text"
    }
    function nameIn(list, id) {
        for (const item of list)
            if (item.id === id)
                return item.name
        return id
    }

    // A playlist map to edit, or nothing for a new one.
    function edit(playlist) {
        playlistId = playlist ? playlist.id : ""
        nameField.text = playlist ? playlist.name : ""
        matchAll = playlist ? playlist.matchAll : true
        order = playlist ? playlist.order : "plays"
        limitField.text = playlist && playlist.limit > 0 ? String(playlist.limit) : ""
        rules = playlist ? playlist.rules.map((r) => ({ field: r.field, op: r.op, value: r.value }))
                         : [{ field: "plays", op: "greater", value: "5" }]
        revision = 0
        open()
        nameField.forceActiveFocus()
    }

    function current() {
        return { id: playlistId, name: nameField.text.trim(), matchAll: matchAll, rules: rules, order: order,
                 limit: parseInt(limitField.text) || 0 }
    }
    function setRule(index, change) {
        const list = rules.slice()
        list[index] = Object.assign({}, list[index], change)
        rules = list
    }

    readonly property int count: visible && revision >= 0 ? SmartPlaylistsController.preview(current()) : 0

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Util.dialogY(parent.height, height)
    width: Math.min(Overlay.overlay ? Overlay.overlay.width - 2 * Theme.padding : 520, 520)
    height: Math.min(Overlay.overlay ? Util.dialogRoom(Overlay.overlay.height) - 2 * Theme.padding : 600, implicitHeight)
    modal: true
    onVisibleChanged: Util.openDialogs += visible ? 1 : -1
    focus: true
    padding: Theme.padding * 1.5
    closePolicy: Popup.CloseOnEscape

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.anim }
        NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: Theme.anim; easing.type: Theme.easingBack }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: Theme.animFast }
        NumberAnimation { property: "scale"; to: 0.96; duration: Theme.animFast }
    }

    background: Rectangle {
        color: Theme.surface
        radius: Theme.radiusLarge * 1.5
        border.color: Theme.border
    }

    Overlay.modal: Rectangle {
        color: Theme.scrim
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
    }

    contentItem: ColumnLayout {
        spacing: Theme.padding

        Label {
            textFormat: Text.PlainText
            text: root.playlistId === "" ? qsTr("New smart playlist") : qsTr("Edit smart playlist")
            color: Theme.text
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.DemiBold
        }

        Field {
            id: nameField
            Layout.fillWidth: true
            placeholderText: qsTr("Name")
        }

        // All or any
        Flow {
            Layout.fillWidth: true
            spacing: 6

            PillButton {
                text: qsTr("All rules match")
                implicitHeight: 30
                active: root.matchAll
                onClicked: root.matchAll = true
            }
            PillButton {
                text: qsTr("Any rule matches")
                implicitHeight: 30
                active: !root.matchAll
                onClicked: root.matchAll = false
            }
        }

        // The rules
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: Math.min(ruleColumn.implicitHeight, 220)
            Layout.minimumHeight: Math.min(ruleColumn.implicitHeight, 90)
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                id: ruleColumn
                width: parent.width
                spacing: 6

                Repeater {
                    model: root.rules

                    delegate: Rectangle {
                        id: ruleRow

                        required property var modelData
                        required property int index
                        readonly property string kind: root.kindOf(modelData.field)

                        Layout.fillWidth: true
                        implicitHeight: ruleFlow.implicitHeight + 12
                        radius: Theme.radius
                        color: Theme.fillSoft

                        Flow {
                            id: ruleFlow
                            anchors.left: parent.left
                            anchors.right: removeRule.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 6
                            spacing: 6

                            Picker {
                                options: root.fields
                                value: ruleRow.modelData.field
                                onPicked: (id) => {
                                    const kind = root.kindOf(id)
                                    root.setRule(ruleRow.index, { field: id, op: root.ops[kind][0].id,
                                                                  value: kind === "source" ? "local" : kind === "text" ? "" : "1" })
                                }
                            }
                            Picker {
                                visible: ruleRow.kind !== "source"
                                options: root.ops[ruleRow.kind]
                                value: ruleRow.modelData.op
                                onPicked: (id) => root.setRule(ruleRow.index, { op: id })
                            }
                            Field {
                                visible: ruleRow.kind !== "source"
                                width: ruleRow.kind === "text" ? 160 : 70
                                text: ruleRow.modelData.value
                                inputMethodHints: ruleRow.kind === "text" ? Qt.ImhNone : Qt.ImhDigitsOnly
                                onTextEdited: {
                                    root.rules[ruleRow.index].value = text
                                    root.revision++
                                }
                            }
                            PillButton {
                                visible: ruleRow.kind === "source"
                                text: qsTr("your library")
                                implicitHeight: 30
                                active: ruleRow.modelData.value === "local"
                                onClicked: root.setRule(ruleRow.index, { value: "local" })
                            }
                            PillButton {
                                visible: ruleRow.kind === "source"
                                text: qsTr("YouTube Music")
                                implicitHeight: 30
                                active: ruleRow.modelData.value === "youtube"
                                onClicked: root.setRule(ruleRow.index, { value: "youtube" })
                            }
                        }

                        PillButton {
                            id: removeRule
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "close"
                            iconSize: 10
                            implicitWidth: 28
                            implicitHeight: 28
                            transparentIdle: true
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Remove this rule")
                            onClicked: root.rules = root.rules.filter((r, i) => i !== ruleRow.index)
                        }
                    }
                }

                PillButton {
                    iconName: "plus"
                    iconSize: 10
                    text: qsTr("Add a rule")
                    implicitHeight: 30
                    transparentIdle: true
                    onClicked: root.rules = root.rules.concat([{ field: "artist", op: "contains", value: "" }])
                }
            }
        }

        // Order and limit
        Flow {
            Layout.fillWidth: true
            spacing: 6

            Label {
                textFormat: Text.PlainText
                height: 30
                verticalAlignment: Text.AlignVCenter
                text: qsTr("Order:")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize
            }
            Picker {
                options: root.orders
                value: root.order
                onPicked: (id) => root.order = id
            }
            Label {
                textFormat: Text.PlainText
                height: 30
                leftPadding: Theme.spacing
                verticalAlignment: Text.AlignVCenter
                text: qsTr("At most")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize
            }
            Field {
                id: limitField
                width: 70
                placeholderText: qsTr("all")
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 0; top: 100000 }
            }
            Label {
                textFormat: Text.PlainText
                height: 30
                verticalAlignment: Text.AlignVCenter
                text: qsTr("songs")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing

            PillButton {
                visible: root.playlistId !== ""
                iconName: "trash"
                iconSize: 11
                text: qsTr("Delete")
                implicitHeight: 36
                transparentIdle: true
                onClicked: {
                    SmartPlaylistsController.remove(root.playlistId)
                    root.close()
                }
            }

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.count === 1 ? qsTr("1 song right now") : qsTr("%1 songs right now").arg(root.count)
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignRight
            }

            PillButton {
                text: qsTr("Cancel")
                implicitHeight: 36
                onClicked: root.close()
            }

            PillButton {
                filled: true
                text: qsTr("Save")
                implicitHeight: 36
                enabled: nameField.text.trim() !== ""
                onClicked: {
                    SmartPlaylistsController.save(root.current())
                    root.close()
                }
            }
        }
    }

    // A rounded text field.
    component Field: TextField {
        id: field

        implicitHeight: 30
        leftPadding: 12
        rightPadding: 12
        color: Theme.text
        placeholderTextColor: Theme.textMuted
        font.pixelSize: Theme.fontSize
        selectByMouse: true

        background: Rectangle {
            radius: height / 2
            color: Theme.fillStrong
            border.width: field.activeFocus ? 1 : 0
            border.color: Theme.accent
        }
    }

    // A pill showing the chosen option; a click opens the list of options.
    component Picker: PillButton {
        id: picker

        property var options: []
        property string value
        signal picked(string id)

        text: root.nameIn(options, value)
        iconName: "chevronDown"
        iconSize: 9
        iconAfter: true
        implicitHeight: 30
        onClicked: menu.popup(picker, 0, picker.height + 4)

        ThemedMenu {
            id: menu

            Instantiator {
                model: picker.options

                delegate: Action {
                    required property var modelData

                    text: modelData.name
                    checkable: true
                    checked: modelData.id === picker.value
                    onTriggered: picker.picked(modelData.id)
                }

                onObjectAdded: (index, object) => menu.insertAction(index, object)
                onObjectRemoved: (index, object) => menu.removeAction(object)
            }
        }
    }
}
