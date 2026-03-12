import QtQuick 2.12
import Style 1.0
import MediaPlayerModel 1.0
import NormalModeModel 1.0

NormalModeContentItem {
    id: playerRoot
    readonly property int textAreaWidth: 330


    // Beautiful Glassmorphism Background
    Rectangle {
        anchors.fill: parent
        anchors.margins: 10
        anchors.topMargin: 100
        anchors.bottomMargin: 20
        radius: 20
        color: Qt.rgba(0.05, 0.05, 0.08, 0.6)
        border.color: Qt.rgba(1, 1, 1, 0.15)
        border.width: 1
    }

    /* === Song Title === */
    Item {
        id: songTitleViewport
        width: playerRoot.textAreaWidth
        height: 26
        anchors.horizontalCenter: parent.horizontalCenter
        y: 124
        clip: true

        property real marqueeOffset: 0
        readonly property bool marqueeNeeded: songTitle.implicitWidth > width

        onMarqueeNeededChanged: if (!marqueeNeeded) marqueeOffset = 0

        SequentialAnimation {
            id: songTitleMarqueeAnim
            loops: Animation.Infinite
            running: songTitleViewport.marqueeNeeded && playerRoot.selected && playerRoot.visible

            PauseAnimation { duration: 900 }
            NumberAnimation {
                target: songTitleViewport
                property: "marqueeOffset"
                from: 0
                to: songTitle.implicitWidth - songTitleViewport.width
                duration: Math.max(2600, (songTitle.implicitWidth - songTitleViewport.width) * 18)
                easing.type: Easing.Linear
            }
            PauseAnimation { duration: 500 }
            ScriptAction { script: songTitleViewport.marqueeOffset = 0 }
            PauseAnimation { duration: 400 }
        }

        Text {
            id: songTitle
            y: 0
            x: songTitleViewport.marqueeNeeded
               ? -songTitleViewport.marqueeOffset
               : (songTitleViewport.width - implicitWidth) / 2
            text: MediaPlayerModel.currentSong
            font.pixelSize: 20
            font.bold: true
            color: Style.textPrimary

            onTextChanged: songTitleViewport.marqueeOffset = 0

            Behavior on text { enabled: false }
            Behavior on opacity { NumberAnimation { duration: MediaPlayerModel.changeSongDuration } }
        }
    }

    /* === Artist Name === */
    Item {
        id: artistViewport
        width: playerRoot.textAreaWidth
        height: 20
        anchors.horizontalCenter: parent.horizontalCenter
        y: 160
        clip: true

        property real marqueeOffset: 0
        readonly property bool marqueeNeeded: artistName.implicitWidth > width

        onMarqueeNeededChanged: if (!marqueeNeeded) marqueeOffset = 0

        SequentialAnimation {
            id: artistMarqueeAnim
            loops: Animation.Infinite
            running: artistViewport.marqueeNeeded && playerRoot.selected && playerRoot.visible

            PauseAnimation { duration: 1200 }
            NumberAnimation {
                target: artistViewport
                property: "marqueeOffset"
                from: 0
                to: artistName.implicitWidth - artistViewport.width
                duration: Math.max(2600, (artistName.implicitWidth - artistViewport.width) * 20)
                easing.type: Easing.Linear
            }
            PauseAnimation { duration: 500 }
            ScriptAction { script: artistViewport.marqueeOffset = 0 }
            PauseAnimation { duration: 500 }
        }

        Text {
            id: artistName
            y: 0
            x: artistViewport.marqueeNeeded
               ? -artistViewport.marqueeOffset
               : (artistViewport.width - implicitWidth) / 2
            text: MediaPlayerModel.currentArtist
            font.pixelSize: 14
            color: Style.textSecondary

            onTextChanged: artistViewport.marqueeOffset = 0

            Behavior on text { enabled: false }
        }
    }

    /* === Transport Controls === */
    Row {
        id: controls
        anchors.horizontalCenter: parent.horizontalCenter
        y: 204
        spacing: 30

        /* Previous button */
        Item {
            width: 44; height: 44
            anchors.verticalCenter: parent.verticalCenter
            Image {
                anchors.centerIn: parent
                source: "qrc:/images/media/skip-previous.svg"
                width: 32; height: 32
                opacity: prevMouseArea.pressed ? 0.6 : 1.0
                Behavior on opacity { NumberAnimation { duration: 100 } }
            }
            MouseArea {
                id: prevMouseArea
                anchors.fill: parent
                onClicked: MediaPlayerModel.previousSong()
            }
        }

        /* Play / Pause button */
        Item {
            id: playPauseBtn
            width: 56; height: 56
            anchors.verticalCenter: parent.verticalCenter
            
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: playMouseArea.pressed ? Qt.rgba(Style.brightBlue.r, Style.brightBlue.g, Style.brightBlue.b, 0.7) : Style.brightBlue
                Behavior on color { ColorAnimation { duration: 100 } }
            }

            Image {
                property bool isPlaying: MediaPlayerModel.mediaPlayback
                anchors.centerIn: parent
                source: isPlaying ? "qrc:/images/media/pause.svg" : "qrc:/images/media/play.svg"
                width: 36; height: 36
            }

            MouseArea {
                id: playMouseArea
                anchors.fill: parent
                onClicked: MediaPlayerModel.togglePlayback()
            }
        }

        /* Next button */
        Item {
            width: 44; height: 44
            anchors.verticalCenter: parent.verticalCenter
            Image {
                anchors.centerIn: parent
                source: "qrc:/images/media/skip-next.svg"
                width: 32; height: 32
                opacity: nextMouseArea.pressed ? 0.6 : 1.0
                Behavior on opacity { NumberAnimation { duration: 100 } }
            }
            MouseArea {
                id: nextMouseArea
                anchors.fill: parent
                onClicked: MediaPlayerModel.nextSong()
            }
        }
    }

    /* === Bluetooth status hint === */
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 284
        spacing: 6
        opacity: 0.6

        Text {
            text: "♪"
            font.pixelSize: 12
            color: Style.brightBlue
        }
        Text {
            text: MediaPlayerModel.modeLabel
            font.pixelSize: 11
            color: Style.textSecondary
            font.bold: true
        }
    }
}
