pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Details of a music file: tags, audio properties, file info, what YouTube
// Music knows about it, and (collapsed) every raw tag. Values can be selected
// and copied. For local files, "Edit tags" turns the tags into a form; the file
// changes only when Save is pressed.
Popup {
    id: root

    // [{ title, collapsible, fields: [{ label, value }] }]
    property var sections: []
    property string path
    property var ytInfo: ({})

    // editTags: open with the tags ready to edit
    function show(filePath, editTags) {
        path = filePath
        sections = LibraryController.trackDetails(filePath)
        YtMetadataController.prioritize(filePath)
        ytInfo = YtMetadataController.infoFor(filePath)
        editing = false
        saving = false
        pipelineOpen = false
        if (editTags && canEdit)
            startEditing()
        open()
    }

    // ---- The audio pipeline: what happens to the song playing, in the engine's order
    property bool pipelineOpen: false
    readonly property bool pipelineKnown: path === PlayerController.source
                                          && PlayerController.sourceInfo.sampleRate !== undefined
    function kHz(rate) {
        return (rate / 1000).toLocaleString(Qt.locale("C"), "f", rate % 1000 === 0 ? 0 : 1) + " kHz"
    }
    // [{ name, icon, status, on, rows: [[label, value], ...] }]
    readonly property var pipeline: {
        if (!pipelineKnown)
            return []
        const s = PlayerController.sourceInfo
        const rate = kHz(s.outputRate)
        const resampling = s.sampleRate !== s.outputRate
        const channelNames = { 1: qsTr("Mono"), 2: qsTr("Stereo") }
        const channels = channelNames[s.channels] ?? s.channelLayout
        const formats = { u8: "8-bit integer", s16: "16-bit integer", s32: "32-bit integer", s64: "64-bit integer",
                          flt: "32-bit float", dbl: "64-bit float" }
        const decoded = formats[(s.sampleFormat || "").replace(/p$/, "")] ?? s.sampleFormat

        const source = [[qsTr("Type"), s.stream ? qsTr("YouTube stream") : qsTr("Local file")],
                        [qsTr("Container"), s.container],
                        [qsTr("Sample rate"), kHz(s.sampleRate)]]
        if (s.bitsPerSample > 0) {
            source.push([qsTr("Bit depth"), qsTr("%1-bit").arg(s.bitsPerSample)])
            source.push([qsTr("PCM data rate"),
                         qsTr("%1 kbps").arg(Math.round(s.sampleRate * s.bitsPerSample * s.channels / 1000))])
        }
        if (s.bitrate > 0)
            source.push([qsTr("Bitrate"), qsTr("%1 kbps").arg(Math.round(s.bitrate / 1000))])
        source.push([qsTr("Channels"), channels])

        const convert = [[qsTr("Rate"), resampling ? kHz(s.sampleRate) + " → " + rate : rate],
                         [qsTr("Channels"), s.channels === 2 ? qsTr("Stereo") : channels + " → " + qsTr("Stereo")],
                         [qsTr("Sample format"), decoded + " → 32-bit float"]]
        if (resampling) {
            convert.splice(1, 0, [qsTr("Ratio"), (s.outputRate / s.sampleRate).toFixed(4) + " : 1"],
                           [qsTr("Filter"), qsTr("%1 taps · cutoff %2").arg(s.filterSize)
                            .arg(kHz(Math.round(s.cutoff * Math.min(s.sampleRate, s.outputRate) / 2)))])
        }

        const mode = SettingsController.replayGain
        const album = mode === 2 && s.gainAlbumDb !== undefined
        const db = album ? s.gainAlbumDb : s.gainTrackDb
        const gainOn = mode !== 0 && db !== undefined

        const fade = SettingsController.fadeSeconds
        const eqGains = SettingsController.eqGains.filter((g) => g !== 0)
        const eqOn = SettingsController.eqEnabled
        const volume = PlayerController.volume
        const volumeDb = volume > 0 ? 60 * Math.log10(volume) : -Infinity // (the slider is cubic)
        const devices = PlayerController.outputDevices.filter((d) => d.id === PlayerController.outputDevice)
        const android = Qt.platform.os === "android"
        const backend = android ? "AAudio" : Qt.platform.os === "windows" ? "WASAPI" : "PipeWire"

        return [
            { name: qsTr("Source"), icon: s.stream ? "cloud" : "folder", status: s.codecName, on: true, rows: source },
            { name: qsTr("Decoder"), icon: "compactDisc", status: qsTr("Active"), on: true,
              rows: [[qsTr("Library"), "FFmpeg " + s.ffmpeg], [qsTr("Codec"), s.codec], [qsTr("Decodes to"), decoded]] },
            { name: qsTr("Converter"), icon: "wave", status: resampling ? qsTr("Resampling") : qsTr("Rate kept"),
              on: true, rows: convert },
            { name: qsTr("ReplayGain"), icon: "sliders", status: gainOn ? qsTr("Active") : qsTr("Off"), on: gainOn,
              rows: [[qsTr("Mode"), mode === 0 ? qsTr("Off") : mode === 2 ? qsTr("Album") : qsTr("Track")],
                     [qsTr("This song"), db !== undefined ? (db > 0 ? "+" : "") + db.toFixed(1) + " dB"
                                         : s.gainSource === "pending" ? qsTr("Not measured yet")
                                         : s.gainSource === "failed" ? qsTr("Couldn't be measured")
                                         : qsTr("Plays as it is")],
                     [qsTr("From"), s.gainSource === "server" ? qsTr("Measured by your server")
                                  : s.stream && s.gainSource === "pending" ? qsTr("Your server hasn't measured it")
                                  : s.stream ? qsTr("YouTube songs aren't levelled")
                                  : s.gainSource === "measured" ? qsTr("Measured by the app")
                                  : s.gainSource === "tags" ? qsTr("The file's tags")
                                  : qsTr("Nothing yet")]] },
            { name: qsTr("Fades"), icon: "wave", status: fade > 0 ? qsTr("Crossfade") : qsTr("Gapless"), on: fade > 0,
              rows: [[qsTr("Between songs"), fade > 0 ? qsTr("%1 s").arg(fade) : qsTr("None")],
                     [qsTr("Curve"), qsTr("Quarter sine")]] },
            { name: qsTr("Buffer"), icon: "listMusic", status: qsTr("Active"), on: true,
              rows: [[qsTr("Holds"), qsTr("About %1 s of audio").arg((s.bufferMs / 1000).toFixed(1))]] },
            { name: qsTr("Equalizer"), icon: "equalizer", status: eqOn ? qsTr("Active") : qsTr("Off"), on: eqOn,
              rows: [[qsTr("Preset"), eqOn ? SettingsController.eqPreset : qsTr("Off")],
                     [qsTr("Bands changed"), qsTr("%1 of 10").arg(eqGains.length)],
                     [qsTr("Limiter"), eqOn ? qsTr("Guards against clipping") : qsTr("Off")]] },
            { name: qsTr("Volume"), icon: "volume", status: PlayerController.muted ? qsTr("Muted") : qsTr("Active"),
              on: !PlayerController.muted,
              rows: [[qsTr("Slider"), Math.round(volume * 100) + "%"],
                     [qsTr("Gain"), volume >= 1 ? "0.0 dB" : volume > 0 ? volumeDb.toFixed(1) + " dB" : qsTr("Silent")],
                     [qsTr("Curve"), qsTr("Cubic")]] },
            { name: qsTr("Output"), icon: "drive", status: backend, on: true,
              rows: [[qsTr("Device"), devices.length > 0 ? devices[0].name : qsTr("System default")],
                     [qsTr("Sent as"), rate + " · 32-bit float · " + qsTr("stereo")]] }
        ]
    }
    readonly property string pipelineSummary: {
        if (!pipelineKnown)
            return ""
        const s = PlayerController.sourceInfo
        return s.codecName + " · " + (s.sampleRate !== s.outputRate ? kHz(s.sampleRate) + " → " : "") + kHz(s.outputRate)
    }

    // ---- Editing the tags
    readonly property bool canEdit: path !== "" && !path.startsWith("ytmusic:") && !path.startsWith("hosted:")
    property bool editing: false
    onEditingChanged: if (!editing) Qt.inputMethod.hide()
    property bool saving: false
    readonly property var tagFields: [
        { key: "title", label: qsTr("Title") }, { key: "artist", label: qsTr("Artist") },
        { key: "album", label: qsTr("Album") }, { key: "albumArtist", label: qsTr("Album artist") },
        { key: "track", label: qsTr("Track") }, { key: "disc", label: qsTr("Disc") },
        { key: "year", label: qsTr("Year") }, { key: "genre", label: qsTr("Genre") }
    ]
    property var tags: ({})

    function startEditing() {
        tags = LocalLibraryController.tagsOf(path)
        editing = Object.keys(tags).length > 0
    }

    Connections {
        target: LocalLibraryController
        function onTagsSaved(savedPath, ok) {
            if (savedPath !== root.path)
                return
            root.saving = false
            if (ok) {
                root.editing = false
                root.sections = LibraryController.trackDetails(root.path)
            }
        }
    }

    Connections {
        target: YtMetadataController
        function onInfoChanged(changedPath) {
            if (changedPath === root.path)
                root.ytInfo = YtMetadataController.infoFor(root.path)
        }
    }

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Util.dialogY(parent.height, height)
    width: Math.min(Overlay.overlay ? Overlay.overlay.width - 2 * Theme.padding : 560, 560)
    height: Math.min(Overlay.overlay ? Util.dialogRoom(Overlay.overlay.height) - 2 * Theme.padding : 640, 640)
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
        radius: Theme.radiusLarge
        border.color: Theme.border
    }

    Overlay.modal: Rectangle {
        color: Theme.scrim
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
    }

    contentItem: ColumnLayout {
        spacing: 0

        // Title bar
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Theme.padding
            Layout.rightMargin: Theme.spacing

            Icon {
                name: "info"
                size: 16
                color: Theme.accent
            }

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Track details")
                color: Theme.text
                font.pixelSize: Theme.fontSizeLarge
            }

            PillButton {
                visible: root.canEdit && !root.editing
                iconName: "sliders"
                iconSize: 11
                text: qsTr("Edit tags")
                implicitHeight: 30
                transparentIdle: true
                onClicked: root.startEditing()
            }

            ControlButton {
                iconName: "close"
                iconSize: 13
                onClicked: root.close()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.border
        }

        // The tags as a form (Edit tags)
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Theme.padding
            visible: root.editing
            spacing: Theme.spacing

            ColumnLayout {
                id: tagForm
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.tagFields

                    delegate: Item {
                        id: tagRow

                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        implicitHeight: 34

                        Label {
                            id: tagLabel
                            textFormat: Text.PlainText
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 96
                            text: tagRow.modelData.label
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize
                        }

                        TextField {
                            id: tagField
                            anchors.left: tagLabel.right
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            implicitHeight: 32
                            leftPadding: 12
                            rightPadding: 12
                            enabled: !root.saving
                            text: root.tags[tagRow.modelData.key] || ""
                            color: Theme.text
                            font.pixelSize: Theme.fontSize
                            selectByMouse: true
                            inputMethodHints: ["track", "disc", "year"].includes(tagRow.modelData.key) ? Qt.ImhDigitsOnly : Qt.ImhNone
                            onTextEdited: root.tags[tagRow.modelData.key] = text

                            background: Rectangle {
                                radius: height / 2
                                color: Theme.fillStrong
                                border.width: tagField.activeFocus ? 1 : 0
                                border.color: Theme.accent
                            }
                        }
                    }
                }
            }

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Saving changes the file itself (a safety copy is kept until it is done). Other tags, the cover and the audio stay as they are.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Theme.spacing

                PillButton {
                    text: qsTr("Cancel")
                    implicitHeight: 36
                    enabled: !root.saving
                    onClicked: root.editing = false
                }

                PillButton {
                    filled: true
                    text: root.saving ? qsTr("Saving…") : qsTr("Save")
                    implicitHeight: 36
                    enabled: !root.saving
                    onClicked: {
                        root.saving = true
                        LocalLibraryController.saveTags(root.path, root.tags)
                    }
                }
            }
        }

        ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.editing
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: scroll.availableWidth
                spacing: Theme.padding

                Item { implicitHeight: 1 }

                PipelineSection {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.padding
                    Layout.rightMargin: Theme.padding
                }

                // Tags, Audio, File
                Repeater {
                    model: root.sections.slice(0, 3)
                    delegate: DetailsSection {
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.padding
                        Layout.rightMargin: Theme.padding
                    }
                }

                YouTubeSection {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.padding
                    Layout.rightMargin: Theme.padding
                }

                // All tags
                Repeater {
                    model: root.sections.slice(3)
                    delegate: DetailsSection {
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.padding
                        Layout.rightMargin: Theme.padding
                    }
                }

                Item { implicitHeight: Theme.spacing }
            }
        }
    }

    // Collapsed at first (the heading sums it up): a card for each stage, in order.
    component PipelineSection: ColumnLayout {
        spacing: 6

        Item {
            Layout.fillWidth: true
            implicitHeight: 24

            RowLayout {
                anchors.fill: parent
                spacing: 6

                Icon {
                    name: root.pipelineOpen ? "chevronDown" : "chevronRight"
                    size: 10
                    color: Theme.accent
                }

                Label {
                    textFormat: Text.PlainText
                    text: qsTr("Audio pipeline").toUpperCase()
                    color: Theme.accent
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                    font.letterSpacing: 1
                }

                Label {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: root.pipelineSummary
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pipelineOpen = !root.pipelineOpen
            }
        }

        Label {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: root.pipelineOpen && !root.pipelineKnown
            text: qsTr("Play this song to see how it reaches your speakers.")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.pipelineOpen ? root.pipeline : []

            delegate: ColumnLayout {
                id: stage

                required property var modelData
                required property int index

                Layout.fillWidth: true
                spacing: 0

                // Flows on from the stage above
                Icon {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 4
                    visible: stage.index > 0
                    name: "chevronDown"
                    size: 9
                    color: Theme.textDim
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: stageColumn.implicitHeight + 2 * Theme.spacing
                    radius: Theme.radius
                    color: Theme.fillSoft
                    opacity: stage.modelData.on ? 1 : 0.6

                    ColumnLayout {
                        id: stageColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacing
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 2
                            spacing: Theme.spacing

                            Icon {
                                name: stage.modelData.icon
                                size: 12
                                color: stage.modelData.on ? Theme.accent : Theme.textMuted
                            }

                            Label {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: stage.modelData.name
                                color: Theme.text
                                font.pixelSize: Theme.fontSize
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                implicitWidth: statusLabel.implicitWidth + 16
                                implicitHeight: statusLabel.implicitHeight + 4
                                radius: height / 2
                                color: stage.modelData.on ? Theme.accentSoft : Theme.fill

                                Label {
                                    id: statusLabel
                                    textFormat: Text.PlainText
                                    anchors.centerIn: parent
                                    text: stage.modelData.status
                                    color: stage.modelData.on ? Theme.accent : Theme.textMuted
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        Repeater {
                            model: stage.modelData.rows

                            delegate: RowLayout {
                                id: stageRow

                                required property var modelData

                                Layout.fillWidth: true
                                spacing: Theme.padding

                                Label {
                                    textFormat: Text.PlainText
                                    text: stageRow.modelData[0]
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                Label {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                    text: stageRow.modelData[1]
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component DetailsSection: ColumnLayout {
        id: section

        required property var modelData
        property bool expanded: !modelData.collapsible

        visible: modelData.fields.length > 0
        spacing: 6

        // Section heading (click to expand/collapse "All tags")
        Item {
            Layout.fillWidth: true
            implicitHeight: 24

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Icon {
                    visible: section.modelData.collapsible
                    name: section.expanded ? "chevronDown" : "chevronRight"
                    size: 10
                    color: Theme.accent
                    height: parent.height
                }

                Label {
                    textFormat: Text.PlainText
                    text: section.modelData.title.toUpperCase()
                    color: Theme.accent
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                    font.letterSpacing: 1
                }

                Label {
                    textFormat: Text.PlainText
                    visible: section.modelData.collapsible
                    text: "(" + section.modelData.fields.length + ")"
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: section.modelData.collapsible
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: section.expanded = !section.expanded
            }
        }

        Repeater {
            model: section.expanded ? section.modelData.fields : []

            delegate: RowLayout {
                id: field

                required property var modelData

                Layout.fillWidth: true
                spacing: Theme.padding

                Label {
                    textFormat: Text.PlainText
                    Layout.preferredWidth: 130
                    Layout.alignment: Qt.AlignTop
                    text: field.modelData.label
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize
                    wrapMode: Text.WrapAnywhere
                }

                TextEdit {
                    Layout.fillWidth: true
                    text: field.modelData.value
                    readOnly: true
                    selectByMouse: !Theme.touchOnly // (on a phone, a drag here must scroll)
                    wrapMode: TextEdit.WrapAnywhere
                    color: Theme.text
                    selectionColor: Theme.selection
                    selectedTextColor: Theme.text
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }

    // "From YouTube Music": the matched song, or why there is none (yet).
    component YouTubeSection: ColumnLayout {
        id: yt

        readonly property string lookupState: root.ytInfo.state !== undefined ? root.ytInfo.state : ""

        spacing: 6

        Item {
            Layout.fillWidth: true
            implicitHeight: 24

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Icon {
                    name: "cloud"
                    size: 10
                    color: Theme.accent
                    height: parent.height
                }

                Label {
                    textFormat: Text.PlainText
                    text: qsTr("From YouTube Music").toUpperCase()
                    color: Theme.accent
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                    font.letterSpacing: 1
                }

                Label {
                    textFormat: Text.PlainText
                    visible: yt.lookupState === "matched" && root.ytInfo.close === true
                    text: qsTr("(close match)")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        // Not matched (yet)
        Label {
            id: statusLabel
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: yt.lookupState !== "matched"
            wrapMode: Text.WordWrap
            text: yt.lookupState === "pending" ? qsTr("Looking it up on YouTube Music…")
                : yt.lookupState === "nomatch" ? qsTr("No match on YouTube Music. The title and the album or an artist must match.")
                : yt.lookupState === "error" ? qsTr("Couldn't reach YouTube Music. It will try again.")
                : yt.lookupState === "off" ? qsTr("Turned off in Settings.")
                : ""
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize

            SequentialAnimation on opacity {
                running: yt.lookupState === "pending"
                loops: Animation.Infinite
                NumberAnimation { to: 0.4; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                onRunningChanged: if (!running) statusLabel.opacity = 1
            }
        }

        // Matched
        RowLayout {
            Layout.fillWidth: true
            visible: yt.lookupState === "matched"
            spacing: Theme.padding

            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 76
                implicitHeight: 76
                radius: Theme.radius
                color: Theme.surfaceAlt
                clip: true

                Icon {
                    anchors.centerIn: parent
                    name: "music"
                    size: 18
                    color: Theme.textMuted
                }

                Image {
                    anchors.fill: parent
                    source: yt.lookupState === "matched" ? root.ytInfo.thumbnail : ""
                    sourceSize: Qt.size(152, 152)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: status === Image.Ready ? 1 : 0

                    Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                YtField { label: qsTr("Title"); value: root.ytInfo.title || "" }
                YtField { label: qsTr("Artists"); value: root.ytInfo.artists || "" }
                YtField { label: qsTr("Album"); value: root.ytInfo.album || "" }
                YtField { label: qsTr("Year"); value: root.ytInfo.year || "" }
                YtField {
                    label: qsTr("Duration")
                    value: root.ytInfo.duration > 0 ? Util.formatTime(root.ytInfo.duration) : ""
                }
                YtField { label: qsTr("Link"); value: root.ytInfo.url || "" }
            }
        }
    }

    component YtField: RowLayout {
        id: ytField

        property string label
        property string value

        Layout.fillWidth: true
        visible: value !== ""
        spacing: Theme.padding

        Label {
            textFormat: Text.PlainText
            Layout.preferredWidth: 70
            Layout.alignment: Qt.AlignTop
            text: ytField.label
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize
        }

        TextEdit {
            Layout.fillWidth: true
            text: ytField.value
            readOnly: true
            selectByMouse: !Theme.touchOnly // (on a phone, a drag here must scroll)
            wrapMode: TextEdit.WrapAnywhere
            color: Theme.text
            selectionColor: Theme.selection
            selectedTextColor: Theme.text
            font.pixelSize: Theme.fontSize
        }
    }
}
