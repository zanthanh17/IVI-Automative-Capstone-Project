import QtQuick 2.12
import Style 1.0
import MediaPlayerModel 1.0
import NormalModeModel 1.0

NormalModeContentItem {
    id: playerRoot
    readonly property int textAreaWidth: 330


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
            font.pixelSize: 18
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
        y: 158
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
            font.pixelSize: 13
            color: Style.textSecondary

            onTextChanged: artistViewport.marqueeOffset = 0

            Behavior on text { enabled: false }
        }
    }

    /* === Transport Controls === */
    Row {
        id: controls
        anchors.horizontalCenter: parent.horizontalCenter
        y: 206
        spacing: 36

        /* Previous button */
        Canvas {
            width: 28; height: 28
            anchors.verticalCenter: parent.verticalCenter

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = Style.lightPeriwinkle
                // Left-pointing double triangle
                ctx.beginPath()
                ctx.moveTo(14, 4); ctx.lineTo(2, 14); ctx.lineTo(14, 24)
                ctx.fill()
                ctx.beginPath()
                ctx.moveTo(24, 4); ctx.lineTo(12, 14); ctx.lineTo(24, 24)
                ctx.fill()
            }

            MouseArea {
                anchors.fill: parent
                onClicked: MediaPlayerModel.previousSong()
            }
        }

        /* Play / Pause button */
        Canvas {
            id: playPauseBtn
            width: 40; height: 40
            anchors.verticalCenter: parent.verticalCenter

            property bool isPlaying: MediaPlayerModel.mediaPlayback
            onIsPlayingChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()

                // Circle outline
                ctx.strokeStyle = Style.brightBlue
                ctx.lineWidth = 2
                ctx.beginPath()
                ctx.arc(20, 20, 18, 0, Math.PI * 2)
                ctx.stroke()

                ctx.fillStyle = Style.brightBlue
                if (isPlaying) {
                    // Pause icon (two bars)
                    ctx.fillRect(13, 12, 4, 16)
                    ctx.fillRect(23, 12, 4, 16)
                } else {
                    // Play icon (triangle)
                    ctx.beginPath()
                    ctx.moveTo(15, 10)
                    ctx.lineTo(30, 20)
                    ctx.lineTo(15, 30)
                    ctx.fill()
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: MediaPlayerModel.togglePlayback()
            }
        }

        /* Next button */
        Canvas {
            width: 28; height: 28
            anchors.verticalCenter: parent.verticalCenter

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = Style.lightPeriwinkle
                // Right-pointing double triangle
                ctx.beginPath()
                ctx.moveTo(4, 4); ctx.lineTo(16, 14); ctx.lineTo(4, 24)
                ctx.fill()
                ctx.beginPath()
                ctx.moveTo(14, 4); ctx.lineTo(26, 14); ctx.lineTo(14, 24)
                ctx.fill()
            }

            MouseArea {
                anchors.fill: parent
                onClicked: MediaPlayerModel.nextSong()
            }
        }
    }

    /* === Bluetooth status hint === */
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 298
        spacing: 5
        opacity: 0.4

        Text {
            text: "♪"
            font.pixelSize: 11
            color: Style.brightBlue
        }
        Text {
            text: MediaPlayerModel.modeLabel
            font.pixelSize: 10
            color: "#657080"
        }
    }
}
