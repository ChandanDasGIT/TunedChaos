pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel

// The app's own folder chooser (the system one can't take the app's colors):
// places on the side (home, Music, Downloads, mounted drives), a clickable
// path bar, the folders of the current one, and Cancel / "Use this folder".
// Click a folder to open it; Backspace goes up, Enter accepts, Esc cancels.
// Also picks a file (pick()'s options): { files: ["*.m3u"] } lists those files
// and a click picks one; { save: true, name: "x.m3u8" } adds a file name field.
Popup {
    id: root

    property string title: qsTr("Choose a folder")
    property string acceptText: qsTr("Use this folder")
    property url folder: home

    readonly property url home: Files.toUrl(Files.homeFolder())
    readonly property bool narrow: width < 480 // places in a row above the folders, not beside them
    // Home (on Android: the phone's storage), Music, Downloads; then the drives
    readonly property var places: [
        { icon: "home", name: Qt.platform.os === "android" ? qsTr("Phone") : qsTr("Home"), url: home },
        { icon: "music", name: qsTr("Music"), url: StandardPaths.writableLocation(StandardPaths.MusicLocation) },
        { icon: "download", name: qsTr("Downloads"), url: StandardPaths.writableLocation(StandardPaths.DownloadLocation) }
    ]

    property var onPicked: null // the function pick() was given
    property var drives: []     // mounted drives, read when opened
    property var fileFilters: [] // e.g. ["*.m3u", "*.m3u8"]: files to list (empty: folders only)
    property bool saveMode: false // choose a folder and type a file name
    readonly property bool openFileMode: fileFilters.length > 0 && !saveMode
    // Saving over a file that is already there. (count / status: checked again
    // once the folder's listing has loaded; indexOf alone doesn't notice.)
    readonly property bool nameTaken: saveMode && nameField.text.trim() !== "" && folders.status === FolderListModel.Ready
                                      && folders.count >= 0
                                      && folders.indexOf(Files.child(folder, nameField.text.trim())) >= 0

    signal accepted(string folder) // local path

    // Opens at startFolder (url; "" = home) and calls done(path) with the chosen
    // folder (or file, see options).
    function pick(dialogTitle, buttonText, startFolder, done, options) {
        title = dialogTitle
        acceptText = buttonText
        onPicked = done
        fileFilters = options && options.files ? options.files : []
        saveMode = !!(options && options.save)
        nameField.text = options && options.name ? options.name : ""
        folder = startFolder && startFolder !== "" ? startFolder : home
        drives = Files.drives()
        open()
        list.forceActiveFocus()
    }

    function goUp() {
        if (!Files.isRoot(folder))
            folder = Files.parentOf(folder)
    }

    function accept() {
        if (openFileMode)
            return // a file is picked by clicking it
        if (saveMode && nameField.text.trim() === "")
            return
        const path = Files.toPath(saveMode ? Files.child(folder, nameField.text.trim()) : folder)
        root.accepted(path)
        if (onPicked)
            onPicked(path)
        close()
    }

    // One instance, in the main window (see Main.qml), so it is centered on the window.
    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Util.dialogY(parent.height, height)
    width: Math.min(Overlay.overlay ? Overlay.overlay.width - 2 * Theme.padding : 640, 640)
    height: Math.min(Overlay.overlay ? Util.dialogRoom(Overlay.overlay.height) - 2 * Theme.padding : 520, 520)
    modal: true
    onVisibleChanged: Util.openDialogs += visible ? 1 : -1
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.anim }
        NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Theme.anim; easing.type: Theme.easing }
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

    FolderListModel {
        id: folders
        folder: root.folder
        showFiles: root.fileFilters.length > 0
        nameFilters: root.fileFilters
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: hiddenSwitch.checked
        sortCaseSensitive: false
    }

    contentItem: ColumnLayout {
        spacing: 0

        // Title
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Theme.padding * 1.5
            Layout.bottomMargin: Theme.padding
            spacing: Theme.spacing

            Icon {
                name: "folderOpen"
                size: 16
                color: Theme.accent
            }

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.title
                color: Theme.text
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            ControlButton {
                iconName: "close"
                iconSize: 13
                iconColor: Theme.textMuted
                onClicked: root.close()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Theme.padding
            Layout.rightMargin: Theme.padding
            spacing: Theme.padding

            // ---- Places
            ColumnLayout {
                Layout.preferredWidth: 160
                Layout.maximumWidth: 160
                Layout.fillWidth: false
                Layout.fillHeight: true
                visible: !root.narrow
                spacing: 2

                Repeater {
                    model: root.places
                    delegate: Place {
                        required property var modelData
                        iconName: modelData.icon
                        label: modelData.name
                        target: modelData.url
                    }
                }

                Label {
                    textFormat: Text.PlainText
                    Layout.topMargin: Theme.spacing
                    Layout.leftMargin: 10
                    visible: root.drives.length > 0
                    text: qsTr("Drives")
                    color: Theme.accent
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: contentHeight
                    Layout.maximumHeight: 4 * 38
                    clip: true
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    flickDeceleration: Theme.flickDeceleration
                    maximumFlickVelocity: Theme.flickVelocity
                    synchronousDrag: true
                    spacing: 2
                    model: root.drives

                    delegate: Place {
                        required property var modelData
                        width: ListView.view.width
                        iconName: "drive"
                        label: modelData.name
                        target: modelData.url
                    }
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.leftMargin: 10
                    spacing: Theme.spacing

                    SettingsSwitch {
                        id: hiddenSwitch
                    }

                    Label {
                        textFormat: Text.PlainText
                        text: qsTr("Hidden")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            // ---- Current folder
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.spacing

                // Narrow (phones): the places as a row of buttons
                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    visible: root.narrow
                    orientation: ListView.Horizontal
                    spacing: 6
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickDeceleration: Theme.flickDeceleration
                    maximumFlickVelocity: Theme.flickVelocity
                    synchronousDrag: true
                    model: root.places.concat(root.drives.map((d) => ({ icon: "drive", name: d.name, url: d.url })))

                    delegate: PillButton {
                        required property var modelData
                        iconName: modelData.icon
                        iconSize: 11
                        text: modelData.name
                        implicitHeight: 32
                        active: Files.toPath(root.folder) === Files.toPath(modelData.url)
                        onClicked: root.folder = modelData.url
                    }
                }

                // Path bar: up, then each part of the path (click to go there)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    PillButton {
                        iconName: "arrowUp"
                        iconSize: 11
                        implicitWidth: 34
                        implicitHeight: 32
                        enabled: !Files.isRoot(root.folder)
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Up one folder")
                        onClicked: root.goUp()
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: height / 2
                        color: Theme.fill
                        clip: true

                        ListView {
                            id: crumbs

                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            orientation: ListView.Horizontal
                            boundsBehavior: Flickable.StopAtBounds
                            flickDeceleration: Theme.flickDeceleration
                            maximumFlickVelocity: Theme.flickVelocity
                            synchronousDrag: true
                            model: Files.crumbs(root.folder) // [{ name, url }], from the root
                            onCountChanged: positionViewAtEnd()
                            onWidthChanged: positionViewAtEnd()

                            delegate: Row {
                                id: crumb

                                required property var modelData
                                required property int index
                                readonly property bool last: index === crumbs.count - 1

                                height: crumbs.height

                                Label {
                                    textFormat: Text.PlainText
                                    // "/ home" needs no "›" after the root; "C: › Music" does
                                    visible: crumb.index > 1 || (crumb.index === 1 && crumbs.model[0].name !== "/")
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: " › "
                                    color: Theme.textDim
                                    font.pixelSize: Theme.fontSize
                                }

                                Label {
                                    textFormat: Text.PlainText
                                    anchors.verticalCenter: parent.verticalCenter
                                    leftPadding: 6
                                    rightPadding: 6
                                    text: crumb.modelData.name
                                    color: crumb.last ? Theme.text : crumbHover.hovered ? Theme.accent : Theme.textMuted
                                    font.pixelSize: Theme.fontSize
                                    font.weight: crumb.last ? Font.DemiBold : Font.Normal

                                    HoverHandler { id: crumbHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        onTapped: root.folder = crumb.modelData.url
                                    }
                                }
                            }
                        }
                    }
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickDeceleration: Theme.flickDeceleration
                    maximumFlickVelocity: Theme.flickVelocity
                    synchronousDrag: true
                    spacing: 2
                    model: folders
                    keyNavigationEnabled: true
                    currentIndex: -1
                    ScrollBar.vertical: ScrollBar {}

                    Keys.onReturnPressed: root.accept()
                    Keys.onEnterPressed: root.accept()
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Backspace) {
                            root.goUp()
                            event.accepted = true
                        }
                    }

                    // The new folder's contents fade in.
                    onModelChanged: contentY = 0
                    Connections {
                        target: folders
                        function onFolderChanged() {
                            list.contentY = 0
                            listFade.restart()
                        }
                    }
                    NumberAnimation {
                        id: listFade
                        target: list
                        property: "opacity"
                        from: 0.3
                        to: 1
                        duration: Theme.anim
                    }

                    delegate: Rectangle {
                        id: row

                        required property string fileName
                        required property url fileUrl
                        required property bool fileIsDir

                        width: ListView.view.width
                        height: 40
                        radius: Theme.radius
                        color: rowHover.hovered ? Theme.hover : "transparent"

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                if (row.fileIsDir) {
                                    root.folder = row.fileUrl
                                } else if (root.saveMode) {
                                    nameField.text = row.fileName // save over it
                                } else {
                                    root.accepted(Files.toPath(row.fileUrl))
                                    if (root.onPicked)
                                        root.onPicked(Files.toPath(row.fileUrl))
                                    root.close()
                                }
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: Theme.padding

                            Icon {
                                name: row.fileIsDir ? "folder" : "listMusic"
                                size: 13
                                color: rowHover.hovered || !row.fileIsDir ? Theme.accent : Theme.textMuted
                            }

                            Label {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: row.fileName
                                color: Theme.text
                                font.pixelSize: Theme.fontSize
                                elide: Text.ElideRight
                            }

                            Icon {
                                name: "chevronRight"
                                size: 9
                                color: Theme.textDim
                                visible: row.fileIsDir
                                opacity: rowHover.hovered ? 1 : 0
                            }
                        }
                    }

                    Label {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: folders.status === FolderListModel.Ready && folders.count === 0
                        text: root.fileFilters.length > 0 ? qsTr("No folders or playlist files in here")
                                                          : qsTr("No folders in here")
                        color: Theme.textDim
                        font.pixelSize: Theme.fontSize
                    }
                }
            }
        }

        // Buttons
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Theme.padding * 1.5
            Layout.topMargin: Theme.padding
            spacing: Theme.spacing

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: !root.saveMode
                text: root.openFileMode ? qsTr("Click a playlist file to open it") : Files.displayPath(root.folder)
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideMiddle
            }

            // Saving: the file name
            TextField {
                id: nameField
                Layout.fillWidth: true
                visible: root.saveMode
                implicitHeight: 36
                leftPadding: 14
                rightPadding: 14
                placeholderText: qsTr("File name")
                placeholderTextColor: Theme.textMuted
                color: Theme.text
                font.pixelSize: Theme.fontSize
                selectByMouse: true
                onAccepted: root.accept()

                background: Rectangle {
                    radius: height / 2
                    color: nameField.activeFocus ? Theme.fillStrong : Theme.fill
                    border.width: nameField.activeFocus ? 1 : 0
                    border.color: Theme.accent
                }
            }

            PillButton {
                text: qsTr("Cancel")
                implicitHeight: 36
                onClicked: root.close()
            }

            PillButton {
                visible: !root.openFileMode
                enabled: !root.saveMode || nameField.text.trim() !== ""
                iconName: "check"
                iconSize: 11
                text: root.nameTaken ? qsTr("Replace") : root.acceptText
                implicitHeight: 36
                filled: true
                onClicked: root.accept()
            }
        }
    }

    // A shortcut in the side bar.
    component Place: Rectangle {
        id: place

        property string iconName
        property string label
        property url target
        readonly property bool current: Files.toPath(root.folder) === Files.toPath(target)

        Layout.fillWidth: true
        implicitHeight: 36
        radius: Theme.radius
        color: current ? Theme.accentSoft : placeHover.hovered ? Theme.hover : "transparent"

        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        HoverHandler { id: placeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.folder = place.target }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            spacing: 10

            Icon {
                name: place.iconName
                size: 12
                color: place.current ? Theme.accent : Theme.textMuted
            }

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: place.label
                color: place.current ? Theme.accent : Theme.text
                font.pixelSize: Theme.fontSize
                elide: Text.ElideRight
            }
        }
    }
}
